import * as b from '../build/dev/javascript/gargamelle/gargamelle/boundary.mjs';
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
    ['text',e.string(),s.string(),'Brainy',true],
    ['null',e.null$(),s.null$(),undefined,true],
    ['number',e.number(),s.number(),1.25,true],
    ['safe integer',e.safe_integer(),s.safe_integer(),9007199254740991,true],
    ['record',fixtures.person_encoder(),fixtures.person_definition(),new fixtures.Person('Brainy',None,None),true],
    ['recursive',unwrap(fixtures.tree_encoder()),unwrap(fixtures.tree_definition()),new fixtures.Tree('Brainy',toList([new fixtures.Tree('Jokey',toList([]))])),true],
    ['rejected constant',e.string(),s.string_constant('Brainy'),'Jokey',false],
  ]){
    const json=unwrap(e.encode_json(encoder,value));
    const raw=JSON.parse(s.to_string(json,s.JsonLayout$Compact$const));
    const schema=JSON.parse(s.schema_string(definition,s.JsonLayout$Compact$const));
    for(const oracle of [compileOracle(schema),await compileSupplementary(schema)])assert.equal(oracle(raw).accepted,accepted,name);
    assert.equal(e.encode(e.codec(encoder,s.contract(definition)),value).isOk(),accepted,name);
  }
});

test('encoding admission rejects nonfinite numbers and non-scalar strings and keys',()=>{
  for(const value of [Infinity,-Infinity,NaN])assert.equal(e.encode_json(e.number(),value).isOk(),false);
  for(const value of [9007199254740992,-9007199254740992])assert.equal(e.encode_json(e.safe_integer(),value).isOk(),false);
  assert.equal(e.encode_json(e.string(),'\ud800').isOk(),false);
  assert.equal(e.encode_json(e.array(e.string()),toList(['Brainy','\udfff'])).isOk(),false);
  assert.equal(e.field(e.record(),'\ud800',e.string(),x=>x).isOk(),false);
  const hostile=unwrap(e.field(e.record(),'__proto__',e.string(),x=>x));
  const raw=JSON.parse(s.to_string(unwrap(e.encode_json(e.finish(hostile),'safe')),s.JsonLayout$Compact$const));
  assert.equal(Object.getPrototypeOf(raw),Object.prototype);
  assert.equal(Object.hasOwn(raw,'__proto__'),true);
  assert.equal(raw.__proto__,'safe');
});

test('primitive failures retain nested field and index locations with typed reasons',()=>{
  const child=unwrap(e.field(e.record(),'score',e.number(),value=>value));
  const root=unwrap(e.field(e.record(),'answers',e.array(e.finish(child)),value=>value));
  const encoder=e.finish(root);
  for(const value of [Infinity,-Infinity,NaN]){
    const result=e.encode_json(encoder,toList([1,2,value]));
    assert.equal(result.isOk(),false);
    assert.ok(result[0] instanceof e.InvalidValue);
    assert.equal(result[0].path,'/answers/2/score');
    assert.equal(result[0].problem,e.ValueProblem$NonFiniteNumber$const);
  }
  assert.equal(e.encode_json(encoder,toList([1,2,3])).isOk(),true);
  const strings=e.array(e.string());
  const result=e.encode_json(strings,toList(['Brainy','\ud800']));
  assert.equal(result[0].path,'/1');
  assert.equal(result[0].problem,e.ValueProblem$NonScalarString$const);
  const key=e.field(e.record(),'\ud800',e.string(),value=>value);
  assert.ok(key[0] instanceof e.InvalidField);
  assert.equal(key[0].name,'\ud800');
  assert.equal(key[0].problem,e.FieldProblem$NonScalarKey$const);
  assert.equal(e.encode_json(strings,toList(['😀',''])).isOk(),true);
});

test('nested getter exceptions preserve their identity and stop later callbacks',()=>{
  const failure=new Error('getter failed');
  let later=0;
  let fields=unwrap(e.field(e.record(),'first',e.string(),()=>{throw failure;}));
  fields=unwrap(e.field(fields,'later',e.string(),()=>{later++;return 'never';}));
  const root=unwrap(e.field(e.record(),'items',e.array(e.finish(fields)),value=>value));
  assert.throws(()=>e.encode_json(e.finish(root),toList(['Brainy'])),error=>error===failure);
  assert.equal(later,0);
});

test('getter, requirement and handler exceptions remain operational failures',()=>{
  const failure=new Error('callback failed');
  assert.throws(()=>e.encode_json(e.contramap(e.string(),()=>{throw failure;}),'Brainy'),error=>error===failure);
  let handled=0;
  const contract=s.require(s.contract(s.string()),'Throw',()=>{throw failure;});
  const receiver=b.json(contract,()=>{handled++;});
  assert.throws(()=>b.send(b.output(e.string(),receiver),'Brainy'),error=>error===failure);
  assert.equal(handled,0);
  const storage=b.json(s.contract(s.string()),()=>{handled++;throw failure;});
  assert.throws(()=>b.send(b.output(e.string(),storage),'Brainy'),error=>error===failure);
  assert.equal(handled,1);
});

test('construction invokes no getters or receiving callbacks',()=>{
  const record=unwrap(e.field(e.record(),'name',e.string(),()=>{throw Error('Getter during construction');}));
  const encoder=e.finish(record);
  const contract=s.require(s.contract(fixtures.person_definition()),'Check',()=>{throw Error('Check during construction');});
  const receiver=b.json(contract,()=>{throw Error('Handler during construction');});
  e.codec(encoder,contract);
  b.output(encoder,receiver);
});

test('public encoding guide compiles and runs on both targets',()=>{
  const root=fileURLToPath(new URL('../',import.meta.url));
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-encoding-guide-'));
  try{
    mkdirSync(join(directory,'src'));
    writeFileSync(join(directory,'gleam.toml'),`name = "encoding_guide"\nversion = "0.1.0"\n[dependencies]\ngargamelle = { path = ${JSON.stringify(root)} }\ngleam_stdlib = { path = ${JSON.stringify(join(root,'build/packages/gleam_stdlib'))} }\ngleam_json = { path = ${JSON.stringify(join(root,'build/packages/gleam_json'))} }\n`);
    const guide=readFileSync(join(root,'docs/encoding.md'),'utf8');
    const codes=[...guide.matchAll(/```gleam\n([\s\S]*?)\n```/g)].map(match=>match[1]);
    const outputs=[...guide.matchAll(/```text\n([\s\S]*?)\n```/g)].map(match=>match[1]+'\n');
    assert.equal(codes.length,outputs.length);
    for(const [index,code] of codes.entries()){
    writeFileSync(join(directory,'src/encoding_guide.gleam'),code+'\n');
    for(const target of ['javascript','erlang']){
      const run=spawnSync('gleam',['run','--target',target],{cwd:directory,encoding:'utf8',timeout:60000});
      assert.equal(run.status,0,run.stdout+run.stderr);
      assert.equal(run.stdout,outputs[index],target);
    }
    }
  }finally{rmSync(directory,{recursive:true,force:true});}
});

test('JSON passthrough preserves canonical values and does not bypass a receiving contract',()=>{
  for(const source of ['null','false','-0','1.25','1e308','"💜"','[]','{}','{"__proto__":"safe","a":[null,true,{}]}']){
    const original=unwrap(s.parse(source));
    const encoded=unwrap(e.encode_json(e.json(),original));
    assert.equal(s.to_string(encoded,s.JsonLayout$Compact$const),s.to_string(original,s.JsonLayout$Compact$const));
    const checked=e.encode(e.codec(e.json(),s.contract(s.string())),original);
    assert.equal(checked.isOk(),typeof JSON.parse(source)==='string');
  }
});
