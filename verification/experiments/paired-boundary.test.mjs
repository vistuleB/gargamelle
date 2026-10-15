import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,writeFileSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';

const root=fileURLToPath(new URL('../../',import.meta.url));
const run=(directory,args)=>{
  const result=spawnSync('gleam',args,{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024,
    env:{...process.env,GIT_DIR:'',GIT_WORK_TREE:''}});
  assert.equal(result.status,0,result.stderr+'\n'+result.stdout);
  return result;
};

test('private paired boundary compiles, preserves enforcement, and remains process-independent',async()=>{
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-paired-boundary-'));
  try{
    for(const name of ['src','test','priv','build/packages'])cpSync(join(root,name),join(directory,name),{recursive:true});
    for(const name of ['gleam.toml','manifest.toml'])cpSync(join(root,name),join(directory,name));
    for(const name of ['paired_boundary.gleam','paired_boundary_test.gleam','paired_boundary_example.gleam'])
      cpSync(new URL(name,import.meta.url),join(directory,'test',name==='paired_boundary.gleam'?name:'private_'+name));
    const helper=spawnSync('make',['-C','priv/regex-src'],{cwd:directory,encoding:'utf8',timeout:60000});
    assert.equal(helper.status,0,helper.stdout+'\n'+helper.stderr);
    for(const target of ['javascript','erlang']){
      const result=run(directory,['test','--target',target]);
      assert.match(result.stdout,/149 passed, no failures/);
      const example=run(directory,['run','--target',target,'--module','private_paired_boundary_example']);
      assert.equal(example.stdout.trim(),'{"answers":[true,false],"score":1}\nSave rejected: score does not match answers');
    }

    const compiled=name=>import(pathToFileURL(join(directory,'build/dev/javascript/gargamelle',name)).href);
    const [paired,s,e,b]=await Promise.all([compiled('paired_boundary.mjs'),compiled('gargamelle.mjs'),compiled('gargamelle/encoding.mjs'),compiled('gargamelle/boundary.mjs')]);
    const contract=s.contract(s.string());
    let handled=0;
    const receiver=paired.paired_boundary(contract,e.string(),x=>x,()=>{handled++;});
    assert.equal(paired.paired_contract(receiver),contract,'Inspector must return the original full contract');

    const failure=new Error('application failure');
    const converter=s.map(s.string(),()=>{throw failure;});
    const loadFailure=paired.paired_boundary(s.contract(converter),e.string(),()=>{handled++;},()=>{handled++;});
    assert.throws(()=>paired.load(loadFailure,s.parse('"Brainy"')[0]),error=>error===failure);
    const encoder=e.contramap(e.string(),()=>{throw failure;});
    const saveFailure=paired.paired_boundary(contract,encoder,()=>{handled++;},()=>{handled++;});
    assert.throws(()=>paired.save(saveFailure,'Brainy'),error=>error===failure);
    assert.equal(handled,0);
    const handlerFailure=paired.paired_boundary(contract,e.string(),()=>{throw failure;},()=>{throw failure;});
    assert.throws(()=>paired.save(handlerFailure,'Brainy'),error=>error===failure);

    // Challenge the exact failure this convenience wrapper is meant to prevent:
    // accidentally registering egress with structural checks but no semantics.
    const pairedPath=join(directory,'test/paired_boundary.gleam');
    const original=readFileSync(pairedPath,'utf8');
    const weakened=original.replace('gargamelle_boundary.contract(loader),',
      'gargamelle.contract(gargamelle.contract_definition(gargamelle_boundary.contract(loader))),' );
    assert.notEqual(weakened,original);
    writeFileSync(pairedPath,weakened);
    const mutant=spawnSync('gleam',['test','--target','javascript'],{cwd:directory,encoding:'utf8',timeout:60000});
    assert.notEqual(mutant.status,0,'Dropping egress semantic checks escaped tests');
    assert.match(mutant.stdout,/one_registered_contract_rejects_before_either_handler_test/);
    assert.match(mutant.stdout,/same_contract_does_not_imply_inverse_conversion_test/);
    assert.match(mutant.stdout,/147 passed, 2 failures/);
    writeFileSync(pairedPath,original);
    assert.match(run(directory,['test','--target','javascript']).stdout,/149 passed, no failures/);

    const declarations=`import gargamelle as s\nimport gargamelle/boundary as b\nimport gargamelle/encoding as e\nimport paired_boundary as paired\n`;
    const negatives=[
      ['certificate',declarations+`pub fn main() {\n let contract = s.contract(s.string())\n let pair = paired.paired_boundary(contract, e.string(), fn(value, _) { value }, fn(_) { Nil })\n let assert Ok(json) = s.parse("\\\"Brainy\\\"")\n let assert Ok(verified) = s.verify(contract, json)\n paired.load(pair, verified)\n}\n`,/VerifiedJson/],
      ['opaque',declarations+`pub fn main() { paired.PairedBoundary(Nil, Nil) }\n`,/PairedBoundary/],
      ['old-constructor',declarations+`pub fn main() { paired.pair(Nil, Nil, Nil, Nil) }\n`,/pair/],
      ['old-inspector',declarations+`pub fn main() { paired.contract(Nil) }\n`,/contract/],
    ];
    for(const [name,source,expected] of negatives){
      const path=join(directory,'test/paired_negative.gleam');
      writeFileSync(path,source);
      for(const target of ['javascript','erlang']){
        const result=spawnSync('gleam',['check','--target',target],{cwd:directory,encoding:'utf8',timeout:60000});
        assert.notEqual(result.status,0,`Negative ${name} compiled on ${target}`);
        assert.match(result.stderr,expected);
        assert.match(result.stderr,name==='certificate'?/Type mismatch/:/Unknown module value/);
      }
      rmSync(path);
    }
    run(directory,['check','--target','javascript']);
    assert.match(readFileSync(join(directory,'test/paired_boundary.gleam'),'utf8'),/pub opaque type PairedBoundary/);
  }finally{rmSync(directory,{recursive:true,force:true});}
});
