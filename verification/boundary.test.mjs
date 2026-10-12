import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {s,unwrap} from './generated-api.mjs';

test('boundary propagates converter exceptions without invoking the handler',()=>{
  const failure=new Error('converter failed');
  let handled=0;
  const boundary=s.boundary(s.map(s.text(),()=>{throw failure;}),()=>{handled++;});
  assert.throws(()=>s.forward(boundary,unwrap(s.parse('"Brainy"'))),error=>error===failure);
  assert.equal(handled,0);
});

test('boundary propagates handler exceptions without rerunning conversion',()=>{
  const failure=new Error('handler failed');
  let converted=0,handled=0;
  const boundary=s.boundary(s.map(s.text(),text=>{converted++;return text;}),()=>{handled++;throw failure;});
  assert.throws(()=>s.forward(boundary,unwrap(s.parse('"Brainy"'))),error=>error===failure);
  assert.equal(converted,1);
  assert.equal(handled,1);
});

test('boundary guide example compiles and runs on both targets',()=>{
  const root=fileURLToPath(new URL('../',import.meta.url));
  const guide=readFileSync(join(root,'docs/boundaries.md'),'utf8');
  const code=guide.match(/```gleam\n([\s\S]*?)\n```/)[1];
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-boundary-guide-'));
  try{
    mkdirSync(join(directory,'src'));
    writeFileSync(join(directory,'src/boundary_guide.gleam'),code+'\n');
    writeFileSync(join(directory,'gleam.toml'),`name = "boundary_guide"\nversion = "0.1.0"\n[dependencies]\ngargamelle = { path = ${JSON.stringify(root)} }\ngleam_stdlib = { path = ${JSON.stringify(join(root,'build/packages/gleam_stdlib'))} }\ngleam_json = { path = ${JSON.stringify(join(root,'build/packages/gleam_json'))} }\n`);
    const expected=''+s.schema_string(s.array(s.text()),s.JsonFormat$Pretty$const)+'\nBrainy, Jokey\n';
    for(const target of ['javascript','erlang']){
      const run=spawnSync('gleam',['run','--target',target],{cwd:directory,encoding:'utf8',timeout:60000});
      assert.equal(run.status,0,target+'\n'+run.stdout+run.stderr);
      assert.equal(run.stdout,expected,target);
    }
  }finally{rmSync(directory,{recursive:true,force:true});}
});
