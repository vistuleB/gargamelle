import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

test('isolated typed encoder prototype works on both targets',async(t)=>{
  const root=fileURLToPath(new URL('../',import.meta.url));
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-encoder-'));
  try{
    const library=join(directory,'library');
    for(const name of ['src','priv'])cpSync(join(root,name),join(library,name),{recursive:true});
    cpSync(join(root,'gleam.toml'),join(library,'gleam.toml'));
    const helper=spawnSync('make',['-C','priv/regex-src'],{cwd:library,encoding:'utf8',timeout:60000});
    assert.equal(helper.status,0,helper.stdout+helper.stderr);
    for(const name of ['src','test'])mkdirSync(join(directory,name));
    cpSync(join(root,'verification/encoder/encoder.gleam'),join(directory,'src/encoder.gleam'));
    cpSync(join(root,'verification/encoder/encoder_test.gleam'),join(directory,'test/encoder_test.gleam'));
    for(const name of ['recursion_support.erl','recursion_support.mjs'])cpSync(join(root,'test',name),join(directory,'test',name));
    const dependency=(name,path)=>`${name} = { path = ${JSON.stringify(path)} }\n`;
    writeFileSync(join(directory,'gleam.toml'),'name = "encoder_probe"\nversion = "0.1.0"\n[dependencies]\n'+dependency('gargamelle',library)+dependency('gleam_stdlib',join(root,'build/packages/gleam_stdlib'))+dependency('gleam_json',join(root,'build/packages/gleam_json'))+'\n[dev-dependencies]\n'+dependency('gleeunit',join(root,'build/packages/gleeunit')));
    writeFileSync(join(directory,'test/encoder_probe_test.gleam'),'import gleeunit\npub fn main() { gleeunit.main() }\n');
    const run=(args)=>spawnSync('gleam',args,{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
    const guide=readFileSync(join(root,'docs/encoder-prototype.md'),'utf8');
    writeFileSync(join(directory,'src/encoder_example.gleam'),guide.match(/```gleam\n([\s\S]*?)\n```/)[1]+'\n');
    for(const target of ['javascript','erlang']){
      const result=run(['test','--target',target]);
      assert.equal(result.status,0,target+'\n'+result.stdout+result.stderr);
      assert.match(result.stdout,/12 passed, no failures/);
      const example=run(['run','--target',target,'-m','encoder_example']);
      assert.equal(example.status,0,target+' guide example\n'+example.stdout+example.stderr);
      t.diagnostic(`${target}: 12 typed encoder tests passed`);
    }
    const e=await import(pathToFileURL(join(directory,'build/dev/javascript/encoder_probe/encoder.mjs')));
    const s=await import(pathToFileURL(join(directory,'build/dev/javascript/gargamelle/gargamelle.mjs')));
    const examples=await import(pathToFileURL(join(directory,'build/dev/javascript/encoder_probe/encoder_test.mjs')));
    const {toList}=await import(pathToFileURL(join(directory,'build/dev/javascript/encoder_probe/gleam.mjs')));
    const {Some,Option$None$const:None}=await import(pathToFileURL(join(directory,'build/dev/javascript/gleam_stdlib/gleam/option.mjs')));
    const unwrap=result=>{assert.equal(result.isOk(),true);return result[0];};
    for(const [name,encoder,definition,value,accepted] of [
      ['text',e.text(),s.text(),'Brainy',true],
      ['nullable array',e.array(e.nullable(e.text())),s.array(s.nullable(s.text())),toList([new Some('Jokey'),None]),true],
      ['record absent',examples.person_encoder(),examples.person_definition(),new examples.Person('Brainy',None,None),true],
      ['record present',examples.person_encoder(),examples.person_definition(),new examples.Person('Jokey',new Some(100),new Some('J')),true],
      ['recursive record',unwrap(examples.tree_encoder()),unwrap(examples.tree_definition()),new examples.Tree('Brainy',toList([new examples.Tree('Jokey',toList([]))])),true],
      ['rejected constraint',e.text(),s.string_constant('Brainy'),'Jokey',false],
    ]){
      const json=unwrap(e.encode_json(encoder,value));
      const wire=JSON.parse(s.to_string(json,s.JsonFormat$Compact$const));
      const schema=JSON.parse(s.schema_string(definition,s.JsonFormat$Compact$const));
      for(const check of [compileOracle(schema),await compileSupplementary(schema)])assert.equal(check(wire).accepted,accepted,name);
      assert.equal(e.encode(e.codec(encoder,definition),value).isOk(),accepted,name);
    }
    t.diagnostic('6 output cases agree with both independent schema validators');
    for(const value of [Infinity,-Infinity,NaN])assert.equal(e.encode_json(e.number(),value).isOk(),false,'Nonfinite number must not silently become null');
    assert.equal(e.encode_json(e.text(),'\ud800').isOk(),false,'Unpaired surrogate must not be admitted');
    const key=e.field(e.record(),'\ud800',e.text(),x=>x);
    assert.equal(key.isOk(),false,'Unpaired surrogate key must be rejected');
    const failure=new Error('getter failed');
    assert.throws(()=>e.encode_json(e.contramap(e.text(),()=>{throw failure;}),'Brainy'),error=>error===failure);
    const cases=[
      ['unfinished_encode','pub fn main() { e.recursive(fn(self) { e.encode_json(self, "x") Ok(self) }) }','Type mismatch'],
      ['opaque_encoder','pub fn main() { e.Plan(fn(_,_) { Ok(Nil) }) }','Unknown module value'],
      ['opaque_recursion','pub fn main() { e.Recursive(fn(_) { Ok(Nil) }) }','Unknown module value'],
      ['mismatched_codec','pub fn main() { e.codec(e.text(), s.number()) }','Type mismatch'],
      ['wrong_getter','pub fn main() { e.field(e.record(), "age", e.safe_integer(), fn(_: String) { "x" }) }','Type mismatch'],
    ];
    for(const [name,body,diagnostic] of cases){
      writeFileSync(join(directory,'src/negative.gleam'),'import encoder as e\nimport gargamelle as s\n'+body+'\n');
      for(const target of ['javascript','erlang']){
        const result=run(['build','--target',target]);
        assert.notEqual(result.status,0,target+': '+name);
        assert.match(result.stdout+result.stderr,new RegExp(diagnostic),target+': '+name);
      }
    }
    t.diagnostic('5 JavaScript admission checks and 5 compile-negative programs on both targets passed');
  }finally{rmSync(directory,{recursive:true,force:true});}
});
