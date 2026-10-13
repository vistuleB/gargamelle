import test from 'node:test';
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import * as e from '../build/dev/javascript/gargamelle/gargamelle/encoding.mjs';
import {Error as GleamError} from '../build/dev/javascript/gargamelle/gleam.mjs';
import {s,unwrap} from './generated-api.mjs';

test('main paired API retains contract identity and encoding error identity',()=>{
  let checks=0,handled=0;
  const contract=s.require(s.contract(s.text()),'Observe checks',()=>{checks++;throw Error('must not check');});
  const failure=new e.InvalidValue('/score',e.ValueProblem$UnsafeInteger$const);
  const pair=s.paired_boundary(contract,()=>new GleamError(failure),()=>{handled++;},()=>{handled++;});
  assert.equal(s.paired_boundary_contract(pair),contract);
  const result=s.save(pair,'Brainy');
  assert.equal(result.isOk(),false);
  assert.ok(result[0] instanceof s.EncodingFailed);
  assert.equal(result[0][0],failure);
  assert.equal(checks,0);assert.equal(handled,0);
});

test('paired callbacks propagate operational failures without invoking later handlers',()=>{
  const marker=new Error('application failure');let handled=0;
  const contract=s.contract(s.text()),json=unwrap(s.parse('"Brainy"'));
  const encode=text=>e.encode_json(e.text(),text);
  const badEncoder=s.paired_boundary(contract,()=>{throw marker;},()=>{handled++;},()=>{handled++;});
  assert.throws(()=>s.save(badEncoder,'Brainy'),error=>error===marker);
  const badConversion=s.paired_boundary(s.contract(s.map(s.text(),()=>{throw marker;})),encode,()=>{handled++;},()=>{handled++;});
  assert.throws(()=>s.load(badConversion,json),error=>error===marker);
  const badCheck=s.paired_boundary(s.require(contract,'Throws',()=>{throw marker;}),encode,()=>{handled++;},()=>{handled++;});
  assert.throws(()=>s.save(badCheck,'Brainy'),error=>error===marker);
  assert.equal(handled,0);
  const badHandler=s.paired_boundary(contract,encode,()=>{throw marker;},()=>{throw marker;});
  assert.throws(()=>s.save(badHandler,'Brainy'),error=>error===marker);
});

test('paired guide continuation runs on both targets and invalid constructions fail compilation',()=>{
  const root=fileURLToPath(new URL('../',import.meta.url)),directory=mkdtempSync(join(tmpdir(),'gargamelle-paired-main-'));
  try{
    for(const name of ['src','priv','build/packages'])cpSync(join(root,name),join(directory,name),{recursive:true});
    for(const name of ['gleam.toml','manifest.toml'])cpSync(join(root,name),join(directory,name));
    const helper=readFileSync(join(root,'test/provider_roundtrip.gleam'),'utf8').split('pub fn main()')[0];
    const guide=readFileSync(join(root,'docs/boundaries.md'),'utf8').split('## Paired loading and saving')[1].split('## Semantic requirements')[0];
    const main=guide.match(/```gleam\n([\s\S]*?)\n```/)[1],expected=guide.match(/```text\n([\s\S]*?)\n```/)[1];
    const consumer=join(directory,'src/paired_consumer.gleam');writeFileSync(consumer,helper+main+'\n');
    const make=spawn('make',['-C','priv/regex-src']);assert.equal(make.status,0,make.output);
    for(const target of ['javascript','erlang']){
      const run=spawn('gleam',['run','--target',target,'--module','paired_consumer']);
      assert.equal(run.status,0,run.output);assert.equal(run.stdout.trim(),expected);
    }
    const core=join(directory,'src/gargamelle.gleam'),original=readFileSync(core,'utf8');
    const mutant=original.replace('json_boundary(contract, save_handler),',
      'json_boundary(gargamelle_contract_for_mutation(contract), save_handler),')+
      '\nfn gargamelle_contract_for_mutation(c) { contract(contract_definition(c)) }\n';
    assert.ok(mutant.includes('json_boundary(gargamelle_contract_for_mutation'));
    writeFileSync(core,mutant);
    assert.equal(spawn('gleam',['check']).status,0,'Egress semantic mutant must compile');
    const mutated=spawn('gleam',['run','--module','paired_consumer']);
    assert.notEqual(mutated.status,0,'Dropping egress semantic requirements escaped the example');
    assert.equal(mutated.stdout.trim(),expected.split('\n')[0],'Mutation must preserve successful loading and saving');
    writeFileSync(core,original);
    assert.equal(spawn('gleam',['run','--module','paired_consumer']).stdout.trim(),expected);
    const imports='import gargamelle as s\nimport gargamelle/encoding as e\n';
    const cases=[
      ['opaque',imports+'pub fn main() { s.PairedBoundary(Nil, Nil, Nil) }',/Unknown module value/],
      ['certificate',imports+'pub fn main() { let c = s.contract(s.text()) let p = s.paired_boundary(c, e.encode_json(e.text(), _), fn(x, _) { x }, fn(_) { Nil }) let assert Ok(j) = s.parse("\\\"Brainy\\\"") let assert Ok(v) = s.verify(c, j) s.load(p, v) }',/Type mismatch/],
      ['checked encoder',imports+'pub fn main() { let c = s.contract(s.text()) let codec = e.codec(e.text(), c) s.paired_boundary(c, e.encode(codec, _), fn(x, _) { x }, fn(_) { Nil }) }',/Type mismatch/],
      ['raw output',imports+'pub fn main() { s.paired_boundary(s.contract(s.text()), fn(x) { Ok(x) }, fn(x, _) { x }, fn(_) { Nil }) }',/Type mismatch/],
    ];
    for(const [name,source,diagnostic] of cases){
      writeFileSync(consumer,source+'\n');
      for(const target of ['javascript','erlang']){
        const result=spawn('gleam',['check','--target',target]);
        assert.notEqual(result.status,0,name);assert.match(result.output,diagnostic,name);
      }
    }
    writeFileSync(consumer,helper+main+'\n');
    assert.equal(spawn('gleam',['check']).status,0);
    function spawn(command,args){
      const result=spawnSync(command,args,{cwd:directory,encoding:'utf8',timeout:60000,env:{...process.env,GIT_DIR:'',GIT_WORK_TREE:''}});
      return {...result,output:result.stdout+'\n'+result.stderr};
    }
  }finally{rmSync(directory,{recursive:true,force:true});}
});
