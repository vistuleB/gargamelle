import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {s,unwrap,toList,Some,None} from '../generated-api.mjs';
import {Error as GleamError} from '../../build/dev/javascript/gargamelle/gleam.mjs';
import {compileOracle} from '../oracle.mjs';
import {compileSupplementary} from '../supplementary-oracle.mjs';
import {classifySplit} from '../oracle-classification.mjs';
import * as provider from '../../build/dev/javascript/gargamelle/provider_roundtrip.mjs';
import {generate,generateContract,shrink,shrinkContract} from './definition-generation.mjs';

const raw=json=>JSON.parse(s.to_string(json,s.JsonFormat$Compact$const));
const seedOptions=seed=>({seed,attempts:200,maxDepth:5,maxNodes:60,maxWidth:4,maxStringLength:10});

test('fixed seeds replay samples and metadata exactly, including seed zero',()=>{
  const definition=s.array(s.string());
  const results=[];
  for(const seed of [0,1,42,0xffffffff]){
    const first=generate(definition,seedOptions(seed)),second=generate(definition,seedOptions(seed));
    assert.equal(first.status,'generated');
    assert.deepEqual(first.replay,second.replay);
    assert.equal(first.attemptsUsed,second.attemptsUsed);
    assert.deepEqual(raw(first.json),raw(second.json));
    results.push(JSON.stringify(raw(first.json)));
  }
  assert.ok(new Set(results).size>1);
});

test('accepted samples agree with Ajv and Hyperjump without invoking converters',async()=>{
  let converted=0;
  const required=unwrap(s.required(s.record(x=>x),'values',s.array(s.safe_integer())));
  const definitions=[
    s.string(),s.boolean(),s.null$(),s.number(),s.safe_integer(),unwrap(s.string_enum(toList(['a','b']))),
    s.array(s.nullable(s.string())),s.finish(required,s.RecordPolicy$Strict$const),
    unwrap(s.bounds(s.array(s.safe_integer()),new Some(1),new Some(3))),
    unwrap(s.bounds(s.string(),new Some(2),new Some(4))),
    unwrap(s.integer_multiple_of(s.safe_integer(),2)),
    s.exclude(s.string(),s.string_constant('a')),
    unwrap(s.unique_items(s.array(s.boolean()))),
    s.map(s.string(),()=>{converted++;throw Error('conversion must not run');}),
    unwrap(s.recursive('generated-tree',self=>s.any_of(toList([
      s.map(s.string(),()=>undefined),s.map(s.array(self),()=>undefined),
    ])))),
  ];
  let samples=0;
  for(const definition of definitions){
    const schema=JSON.parse(s.schema_string(definition,s.JsonFormat$Compact$const));
    const ajv=compileOracle(schema),hyperjump=await compileSupplementary(schema);
    for(let seed=0;seed<20;seed++){
      const result=generate(definition,seedOptions(seed));
      assert.equal(result.status,'generated',JSON.stringify({schema,result}));
      const value=raw(result.json);
      assert.equal(ajv(value).accepted,true,JSON.stringify({schema,value,oracle:ajv(value)}));
      assert.equal(hyperjump(value).accepted,true);
      samples++;
    }
  }
  assert.equal(converted,0);
  assert.equal(samples,300);
});

test('hostile object keys remain ordinary keys, with the retained Ajv discrepancy diagnosed',async()=>{
  const fields=unwrap(s.required(s.record(x=>x),'__proto__',s.string()));
  const definition=s.finish(fields,s.RecordPolicy$Strict$const);
  const result=generate(definition,seedOptions(1));
  assert.equal(result.status,'generated');
  const value=raw(result.json),schema=JSON.parse(s.schema_string(definition,s.JsonFormat$Compact$const));
  assert.equal(Object.hasOwn(value,'__proto__'),true);
  const ajv=compileOracle(schema)(value),hyperjump=(await compileSupplementary(schema))(value);
  assert.equal(hyperjump.accepted,true);
  assert.equal(classifySplit(schema,value,ajv,hyperjump),'ajv-declared-proto-key');
});

test('depth, node, width, text and attempt budgets report exhaustion rather than impossibility',()=>{
  const definitions=[
    [s.array(s.array(s.string())),{maxDepth:0,maxWidth:0}],
    [unwrap(s.bounds(s.array(s.string()),new Some(1),None)),{maxDepth:0,maxWidth:1}],
    [unwrap(s.bounds(s.array(s.string()),new Some(3),None)),{maxNodes:2,maxWidth:4}],
    [unwrap(s.bounds(s.array(s.string()),new Some(3),None)),{maxWidth:2}],
    [unwrap(s.bounds(s.string(),new Some(5),None)),{maxStringLength:4}],
  ];
  // Empty nested arrays remain valid at depth zero.
  assert.equal(generate(definitions[0][0],definitions[0][1]).status,'generated');
  for(const [definition,budget] of definitions.slice(1)){
    const result=generate(definition,{...budget,attempts:7});
    assert.equal(result.status,'exhausted');
    assert.equal(result.attemptsUsed,7);
    assert.ok(result.budgetFailures>0);
    assert.equal(Object.hasOwn(result,'impossible'),false);
  }
  assert.equal(generate(s.string(),{attempts:0}).status,'exhausted');
  assert.throws(()=>generate(s.string(),{maxDepth:-1}),/Invalid budget/);
  assert.throws(()=>generate(s.string(),{invented:1}),/Unknown budget/);
});

test('100 seeded samples are admitted and accepted by native Erlang validation',()=>{
  const definition=s.array(s.nullable(s.safe_integer()));
  const values=Array.from({length:100},(_,seed)=>{
    const result=generate(definition,seedOptions(seed));
    assert.equal(result.status,'generated');
    return s.to_string(result.json,s.JsonFormat$Compact$const);
  });
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-generation-native-'));
  const root=fileURLToPath(new URL('../../',import.meta.url));
  try{
    for(const name of ['src','test','priv','build/packages'])cpSync(join(root,name),join(directory,name),{recursive:true});
    for(const name of ['gleam.toml','manifest.toml'])cpSync(join(root,name),join(directory,name));
    cpSync(new URL('./generation_native_probe.gleam',import.meta.url),join(directory,'test/generation_native_probe.gleam'));
    writeFileSync(join(directory,'test/generation_inputs.gleam'),`pub fn values() -> List(String) { [${values.map(value=>JSON.stringify(value)).join(',')}] }\n`);
    const result=spawnSync('gleam',['run','--target','erlang','--module','generation_native_probe'],{
      cwd:directory,encoding:'utf8',timeout:60000,env:{...process.env,GIT_DIR:'',GIT_WORK_TREE:''},
    });
    assert.equal(result.status,0,result.stderr);
    assert.deepEqual(JSON.parse(result.stdout),Array(100).fill(true));
  }finally{rmSync(directory,{recursive:true,force:true});}
});

test('unsupported assertions are explicit and do not get dropped',()=>{
  const definition=unwrap(s.pattern(s.string(),'^special$'));
  const result=generate(definition);
  assert.equal(result.status,'unsupported');
  assert.deepEqual(result.keywords,['/pattern']);
});

test('overlapping oneOf and impossible conjunctions never yield an accepted sample',()=>{
  const exclusive=unwrap(s.one_of(toList([s.string(),s.string()])));
  const contradictory=s.exclude(s.string(),s.string());
  for(const definition of [exclusive,contradictory])assert.equal(generate(definition,{attempts:10}).status,'exhausted');
});

test('structural samples and semantic samples remain distinct',()=>{
  let semanticCalls=0;
  const rejected=s.require(s.contract(s.string()),'Reject all proposed strings',()=>{
    semanticCalls++;return new GleamError(toList([new s.Violation('','Rejected')]));
  });
  assert.equal(generate(s.contract_definition(rejected),{attempts:5}).status,'generated');
  assert.equal(semanticCalls,0);
  const exhausted=generateContract(rejected,{attempts:5});
  assert.equal(exhausted.status,'exhausted');
  assert.equal(exhausted.acceptance,'semantic-contract');
  assert.deepEqual(exhausted.requirements,['Reject all proposed strings']);
  assert.equal(semanticCalls,5);
  const providerContract=provider.evidence_contract();
  const result=generateContract(providerContract,{...seedOptions(42),attempts:1000});
  assert.equal(result.status,'generated');
  assert.equal(s.validate_contract(providerContract,result.json).isOk(),true);
});

test('semantic exceptions are operational failures and propagate unchanged',()=>{
  const failure=new Error('semantic callback failed');
  const contract=s.require(s.contract(s.string()),'Throws',()=>{throw failure;});
  assert.throws(()=>generateContract(contract),error=>error===failure);
});

test('structural shrinking retains admission, validity and the failing property',()=>{
  const definition=s.array(s.string());
  const start=unwrap(s.parse('["long value","another","third"]'));
  const fails=json=>raw(json).some(value=>value.length>0);
  const result=shrink(definition,start,fails);
  assert.equal(result.status,'minimal-within-proposals');
  assert.equal(s.validate(definition,result.json).isOk(),true);
  assert.equal(fails(result.json),true);
  assert.deepEqual(raw(result.json),['t']);
  assert.deepEqual(raw(start),['long value','another','third']);
  assert.deepEqual(raw(shrink(definition,start,fails).json),raw(result.json));
});

test('semantic shrinking keeps contract acceptance while reducing a counterexample',()=>{
  const contract=provider.evidence_contract();
  const start=unwrap(s.parse('{"answers":[true,true,false],"score":2}'));
  const fails=json=>raw(json).answers.some(answer=>answer===true);
  const result=shrinkContract(contract,start,fails);
  assert.equal(s.validate_contract(contract,result.json).isOk(),true);
  assert.equal(fails(result.json),true);
  assert.ok(JSON.stringify(raw(result.json)).length<=JSON.stringify(raw(start)).length);
});

test('shrink exhaustion returns a still valid counterexample, and exceptions escape',()=>{
  const definition=s.array(s.string()),start=unwrap(s.parse('["long value"]'));
  const fails=json=>raw(json).some(text=>text.length>0);
  for(const budgets of [{maxSteps:0},{maxCandidates:0}]){
    const result=shrink(definition,start,fails,budgets);
    assert.equal(result.status,'budget-exhausted');
    assert.equal(s.validate(definition,result.json).isOk(),true);
    assert.equal(fails(result.json),true);
  }
  const failure=new Error('property crashed');
  assert.throws(()=>shrink(definition,start,()=>{throw failure;}),error=>error===failure);
  assert.throws(()=>shrink(definition,start,()=>false),/Initial value/);
  assert.throws(()=>shrink(definition,start,fails,{invented:1}),/Unknown shrink budget/);
});
