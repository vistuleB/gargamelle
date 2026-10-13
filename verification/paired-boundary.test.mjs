import * as b from '../build/dev/javascript/gargamelle/gargamelle/boundary.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import * as e from '../build/dev/javascript/gargamelle/gargamelle/encoding.mjs';
import {s,unwrap} from './generated-api.mjs';

test('boundary paired API retains contract identity and typed encoding diagnostics',()=>{
  let checks=0,handled=0;
  const contract=s.require(s.contract(s.safe_integer()),'Observe checks',()=>{checks++;throw Error('must not check');});
  const pair=b.paired_boundary(contract,e.safe_integer(),()=>{handled++;},()=>{handled++;});
  assert.equal(b.paired_boundary_contract(pair),contract);
  const result=b.save(pair,9007199254740992);
  assert.equal(result.isOk(),false);
  assert.ok(result[0] instanceof e.InvalidValue);
  assert.equal(result[0].path,'');
  assert.equal(result[0].problem,e.ValueProblem$UnsafeInteger$const);
  assert.equal(checks,0);assert.equal(handled,0);
});

test('paired callbacks propagate operational failures without invoking later handlers',()=>{
  const marker=new Error('application failure');let handled=0;
  const contract=s.contract(s.text()),json=unwrap(s.parse('"Brainy"'));
  const encoder=e.text();
  const badEncoder=b.paired_boundary(contract,e.contramap(encoder,()=>{throw marker;}),()=>{handled++;},()=>{handled++;});
  assert.throws(()=>b.save(badEncoder,'Brainy'),error=>error===marker);
  const badConversion=b.paired_boundary(s.contract(s.map(s.text(),()=>{throw marker;})),encoder,()=>{handled++;},()=>{handled++;});
  assert.throws(()=>b.load(badConversion,json),error=>error===marker);
  const badCheck=b.paired_boundary(s.require(contract,'Throws',()=>{throw marker;}),encoder,()=>{handled++;},()=>{handled++;});
  assert.throws(()=>b.save(badCheck,'Brainy'),error=>error===marker);
  assert.equal(handled,0);
  const badHandler=b.paired_boundary(contract,encoder,()=>{throw marker;},()=>{throw marker;});
  assert.throws(()=>b.save(badHandler,'Brainy'),error=>error===marker);
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
    const core=join(directory,'src/gargamelle/boundary.gleam'),original=readFileSync(core,'utf8');
    const mutant=original.replace('json_boundary(boundary_contract(loader), save_handler)',
      'json_boundary(gargamelle_contract_for_mutation(boundary_contract(loader)), save_handler)')+
      '\nfn gargamelle_contract_for_mutation(c) { gargamelle.contract(gargamelle.contract_definition(c)) }\n';
    assert.ok(mutant.includes('json_boundary(gargamelle_contract_for_mutation'));
    writeFileSync(core,mutant);
    assert.equal(spawn('gleam',['check']).status,0,'Egress semantic mutant must compile');
    const mutated=spawn('gleam',['run','--module','paired_consumer']);
    assert.notEqual(mutated.status,0,'Dropping egress semantic requirements escaped the example');
    assert.equal(mutated.stdout.trim(),expected.split('\n')[0],'Mutation must preserve successful loading and saving');
    writeFileSync(core,original);
    assert.equal(spawn('gleam',['run','--module','paired_consumer']).stdout.trim(),expected);
    const imports='import gargamelle as s\nimport gargamelle/boundary as b\nimport gargamelle/encoding as e\n';
    const cases=[
      ['opaque',imports+'pub fn main() { b.PairedBoundary(Nil, Nil) }',/Unknown module value/],
      ['certificate',imports+'pub fn main() { let c = s.contract(s.text()) let p = b.paired_boundary(c, e.text(), fn(x, _) { x }, fn(_) { Nil }) let assert Ok(j) = s.parse("\\\"Brainy\\\"") let assert Ok(v) = s.verify(c, j) b.load(p, v) }',/Type mismatch/],
      ['checked encoder',imports+'pub fn main() { let c = s.contract(s.text()) let codec = e.codec(e.text(), c) b.paired_boundary(c, e.encode(codec, _), fn(x, _) { x }, fn(_) { Nil }) }',/Type mismatch/],
      ['raw output',imports+'pub fn main() { b.paired_boundary(s.contract(s.text()), fn(x) { Ok(x) }, fn(x, _) { x }, fn(_) { Nil }) }',/Type mismatch/],
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
