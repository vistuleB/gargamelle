import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {s,toList,unwrap} from './generated-api.mjs';

test('direct JSON constructors retain the admitted numeric and string domains',()=>{
  for(const value of [NaN,Infinity,-Infinity])assert.equal(s.json_number(value).isOk(),false);
  for(const value of ['', 'Brainy', '\ud83d\udc9c', '\0', '\"\\\n']){
    const json=unwrap(s.json_string(value));
    assert.equal(JSON.parse(s.to_string(json,s.JsonLayout$Compact$const)),value);
  }
  for(const value of ['\ud800','\udfff','before\ud800after'])assert.equal(s.json_string(value).isOk(),false);
  for(const value of [Number.MAX_VALUE,Number.MIN_VALUE,-0,1.25,9007199254740992]){
    const json=unwrap(s.json_number(value));
    assert.deepEqual(unwrap(s.decode(s.number(),json)),value);
  }
});

test('object constructors keep own hostile keys, reject duplicates and canonicalize serialization',()=>{
  const string=unwrap(s.json_string('safe'));
  const json=unwrap(s.json_object(toList([['__proto__',string],['constructor',string],['',s.json_null()]])));
  const raw=JSON.parse(s.to_string(json,s.JsonLayout$Compact$const));
  assert.equal(Object.hasOwn(raw,'__proto__'),true);assert.equal(raw.__proto__,'safe');
  assert.equal(Object.getPrototypeOf(raw),Object.prototype);
  assert.equal(s.json_object(toList([['x',string],['x',s.json_null()]])).isOk(),false);
  assert.equal(s.json_object(toList([['\ud800',string]])).isOk(),false);
});

 test('public JSON construction and metadata encoding examples compile on both targets',()=>{
  const root=fileURLToPath(new URL('../',import.meta.url));
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-json-guide-'));
  try{
    mkdirSync(join(directory,'src'));
    writeFileSync(join(directory,'gleam.toml'),`name = "json_guide"\nversion = "0.1.0"\n[dependencies]\ngargamelle = { path = ${JSON.stringify(root)} }\ngleam_stdlib = { path = ${JSON.stringify(join(root,'build/packages/gleam_stdlib'))} }\ngleam_json = { path = ${JSON.stringify(join(root,'build/packages/gleam_json'))} }\n`);
    const guide=readFileSync(join(root,'docs/json-values.md'),'utf8');
    const codes=[...guide.matchAll(/```gleam\n([\s\S]*?)\n```/g)].map(match=>match[1]);
    const outputs=[...guide.matchAll(/```text\n([\s\S]*?)\n```/g)].map(match=>match[1]+'\n');
    assert.equal(codes.length,2);assert.equal(codes.length,outputs.length);
    for(const [index,code] of codes.entries()){
      writeFileSync(join(directory,'src/json_guide.gleam'),code+'\n');
      for(const target of ['javascript','erlang']){
        const run=spawnSync('gleam',['run','--target',target],{cwd:directory,encoding:'utf8',timeout:60000});
        assert.equal(run.status,0,run.stdout+run.stderr);assert.equal(run.stdout,outputs[index],target);
      }
    }
  }finally{rmSync(directory,{recursive:true,force:true});}
});
