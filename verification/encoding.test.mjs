import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import * as e from '../build/dev/javascript/gargamelle/gargamelle/encoding.mjs';
import * as fixtures from '../build/dev/javascript/gargamelle/encoding_test.mjs';
import {s,Ok,toList,unwrap} from './generated-api.mjs';
import {Option$None$const as None} from '../build/dev/javascript/gleam_stdlib/gleam/option.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

test('public encoders agree with independent structural schema validators',async()=>{
  for(const [name,encoder,definition,value,accepted] of [
    ['text',e.text(),s.text(),'Brainy',true],
    ['null',e.null$(),s.null$(),undefined,true],
    ['number',e.number(),s.number(),1.25,true],
    ['safe integer',e.safe_integer(),s.safe_integer(),9007199254740991,true],
    ['record',fixtures.person_encoder(),fixtures.person_definition(),new fixtures.Person('Brainy',None,None),true],
    ['recursive',unwrap(fixtures.tree_encoder()),unwrap(fixtures.tree_definition()),new fixtures.Tree('Brainy',toList([new fixtures.Tree('Jokey',toList([]))])),true],
    ['rejected constant',e.text(),s.string_constant('Brainy'),'Jokey',false],
  ]){
    const json=unwrap(e.encode_json(encoder,value));
    const raw=JSON.parse(s.to_string(json,s.JsonFormat$Compact$const));
    const schema=JSON.parse(s.schema_string(definition,s.JsonFormat$Compact$const));
    for(const oracle of [compileOracle(schema),await compileSupplementary(schema)])assert.equal(oracle(raw).accepted,accepted,name);
    assert.equal(e.encode(e.codec(encoder,s.contract(definition)),value).isOk(),accepted,name);
  }
});

test('encoding admission rejects nonfinite numbers and non-scalar strings and keys',()=>{
  for(const value of [Infinity,-Infinity,NaN])assert.equal(e.encode_json(e.number(),value).isOk(),false);
  for(const value of [9007199254740992,-9007199254740992])assert.equal(e.encode_json(e.safe_integer(),value).isOk(),false);
  assert.equal(e.encode_json(e.text(),'\ud800').isOk(),false);
  assert.equal(e.encode_json(e.array(e.text()),toList(['Brainy','\udfff'])).isOk(),false);
  assert.equal(e.field(e.record(),'\ud800',e.text(),x=>x).isOk(),false);
  const hostile=unwrap(e.field(e.record(),'__proto__',e.text(),x=>x));
  const raw=JSON.parse(s.to_string(unwrap(e.encode_json(e.finish(hostile),'safe')),s.JsonFormat$Compact$const));
  assert.equal(Object.getPrototypeOf(raw),Object.prototype);
  assert.equal(Object.hasOwn(raw,'__proto__'),true);
  assert.equal(raw.__proto__,'safe');
});

test('getter, requirement and handler exceptions remain operational failures',()=>{
  const failure=new Error('callback failed');
  assert.throws(()=>e.encode_json(e.contramap(e.text(),()=>{throw failure;}),'Brainy'),error=>error===failure);
  let handled=0;
  const contract=s.require(s.contract(s.text()),'Throw',()=>{throw failure;});
  const receiver=s.json_boundary(contract,()=>{handled++;});
  assert.throws(()=>e.send(e.output_boundary(e.text(),receiver),'Brainy'),error=>error===failure);
  assert.equal(handled,0);
  const storage=s.json_boundary(s.contract(s.text()),()=>{handled++;throw failure;});
  assert.throws(()=>e.send(e.output_boundary(e.text(),storage),'Brainy'),error=>error===failure);
  assert.equal(handled,1);
});

test('construction invokes no getters or receiving callbacks',()=>{
  const record=unwrap(e.field(e.record(),'name',e.text(),()=>{throw Error('Getter during construction');}));
  const encoder=e.finish(record);
  const contract=s.require(s.contract(fixtures.person_definition()),'Check',()=>{throw Error('Check during construction');});
  const receiver=s.json_boundary(contract,()=>{throw Error('Handler during construction');});
  e.codec(encoder,contract);
  e.output_boundary(encoder,receiver);
});

test('public encoding guide compiles and runs on both targets',()=>{
  const root=fileURLToPath(new URL('../',import.meta.url));
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-encoding-guide-'));
  try{
    mkdirSync(join(directory,'src'));
    writeFileSync(join(directory,'gleam.toml'),`name = "encoding_guide"\nversion = "0.1.0"\n[dependencies]\ngargamelle = { path = ${JSON.stringify(root)} }\ngleam_stdlib = { path = ${JSON.stringify(join(root,'build/packages/gleam_stdlib'))} }\ngleam_json = { path = ${JSON.stringify(join(root,'build/packages/gleam_json'))} }\n`);
    const guide=readFileSync(join(root,'docs/encoding.md'),'utf8');
    const code=guide.match(/```gleam\n([\s\S]*?)\n```/)[1];
    const output=guide.match(/```text\n([\s\S]*?)\n```/)[1]+'\n';
    writeFileSync(join(directory,'src/encoding_guide.gleam'),code+'\n');
    for(const target of ['javascript','erlang']){
      const run=spawnSync('gleam',['run','--target',target],{cwd:directory,encoding:'utf8',timeout:60000});
      assert.equal(run.status,0,run.stdout+run.stderr);
      assert.equal(run.stdout,output,target);
    }
  }finally{rmSync(directory,{recursive:true,force:true});}
});
