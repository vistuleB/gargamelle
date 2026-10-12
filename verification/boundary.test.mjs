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
  const boundary=s.boundary(s.map(s.text(),()=>{throw failure;}),(_data,_json)=>{handled++;});
  assert.throws(()=>s.forward(boundary,unwrap(s.parse('"Brainy"'))),error=>error===failure);
  assert.equal(handled,0);
});

test('boundary propagates handler exceptions without rerunning conversion',()=>{
  const failure=new Error('handler failed');
  let converted=0,handled=0;
  const boundary=s.boundary(s.map(s.text(),text=>{converted++;return text;}),(_data,_json)=>{handled++;throw failure;});
  assert.throws(()=>s.forward(boundary,unwrap(s.parse('"Brainy"'))),error=>error===failure);
  assert.equal(converted,1);
  assert.equal(handled,1);
});

test('verification succeeds without constructing decoded data',()=>{
  let converted=0;
  const definition=s.map(s.string_constant('Brainy'),()=>{converted++;throw new Error('must not convert');});
  const json=unwrap(s.parse('"Brainy"'));
  const verified=unwrap(s.verify(definition,json));
  assert.equal(s.verified_json(verified),json);
  assert.equal(s.verified_definition(verified),definition);
  assert.equal(converted,0);
  assert.equal(s.verify(definition,unwrap(s.parse('"Jokey"'))).isOk(),false);
  assert.equal(converted,0);
});

test('JSON receiving boundary retains its exact contract and propagates handler failures',()=>{
  const failure=new Error('storage failed');
  let handled=0;
  const definition=s.map(s.string_constant('Brainy'),()=>{throw new Error('must not decode');});
  const receiver=s.json_boundary(definition,verified=>{
    handled++;
    assert.equal(s.verified_definition(verified),definition);
    throw failure;
  });
  assert.equal(s.json_boundary_definition(receiver),definition);
  const other=unwrap(s.verify(s.text(),unwrap(s.parse('"Jokey"'))));
  assert.equal(s.forward_json(receiver,s.verified_json(other)).isOk(),false);
  assert.equal(handled,0);
  assert.throws(()=>s.forward_json(receiver,unwrap(s.parse('"Brainy"'))),error=>error===failure);
  assert.equal(handled,1);
});

test('boundary guide example compiles and runs on both targets',()=>{
  const root=fileURLToPath(new URL('../',import.meta.url));
  const guide=readFileSync(join(root,'docs/boundaries.md'),'utf8');
  const examples=[...guide.matchAll(/```gleam\n([\s\S]*?)\n```/g)].map(match=>match[1]);
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-boundary-guide-'));
  try{
    mkdirSync(join(directory,'src'));
    writeFileSync(join(directory,'gleam.toml'),`name = "boundary_guide"\nversion = "0.1.0"\n[dependencies]\ngargamelle = { path = ${JSON.stringify(root)} }\ngleam_stdlib = { path = ${JSON.stringify(join(root,'build/packages/gleam_stdlib'))} }\ngleam_json = { path = ${JSON.stringify(join(root,'build/packages/gleam_json'))} }\n`);
    const outputs=[s.schema_string(s.array(s.text()),s.JsonFormat$Pretty$const)+'\nBrainy, Jokey\n','["Brainy","Jokey"]\n'];
    assert.equal(examples.length,outputs.length);
    for(const [index,code] of examples.entries()){
    writeFileSync(join(directory,'src/boundary_guide.gleam'),code+'\n');
    for(const target of ['javascript','erlang']){
      const run=spawnSync('gleam',['run','--target',target],{cwd:directory,encoding:'utf8',timeout:60000});
      assert.equal(run.status,0,target+'\n'+run.stdout+run.stderr);
      assert.equal(run.stdout,outputs[index],target);
    }
    }
  }finally{rmSync(directory,{recursive:true,force:true});}
});
