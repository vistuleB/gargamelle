import test from 'node:test';
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {compileOracle} from '../oracle.mjs';
import {compileSupplementary} from '../supplementary-oracle.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));

test('static record helpers preserve schema, acceptance, output, and errors on both targets',async t=>{
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-record-helpers-'));
  try{
    for(const name of ['src','priv','build/packages'])cpSync(join(root,name),join(directory,name),{recursive:true});
    for(const name of ['gleam.toml','manifest.toml'])cpSync(join(root,name),join(directory,name));
    mkdirSync(join(directory,'test'));
    for(const name of ['shared_record.gleam','record_helpers_example.gleam','record_helpers_test.gleam'])
      cpSync(new URL(name,import.meta.url),join(directory,'test',name));
    writeFileSync(join(directory,'test/gargamelle_test.gleam'),'import gleeunit\npub fn main() { gleeunit.main() }\n');
    const run=(command,args)=>spawnSync(command,args,{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
    const helper=run('make',['-C','priv/regex-src']);assert.equal(helper.status,0,helper.stdout+helper.stderr);
    for(const target of ['javascript','erlang']){
      const tests=run('gleam',['test','--target',target]);assert.equal(tests.status,0,tests.stdout+tests.stderr);assert.match(tests.stdout,/7 passed, no failures/);
      const example=run('gleam',['run','--target',target,'--module','record_helpers_example']);assert.equal(example.status,0,example.stdout+example.stderr);
      assert.equal(example.stdout.trim(),'{"active":true,"age":3,"name":"Azrael"}');
      t.diagnostic(`${target}: seven comparison tests and the record example passed`);
    }
    const load=name=>import(pathToFileURL(join(directory,'build/dev/javascript/gargamelle',name+'.mjs')));
    const s=await load('gargamelle'),e=await load('gargamelle/encoding'),shared=await load('shared_record'),fixture=await load('record_helpers_example');
    const unwrap=result=>{assert.ok(result.isOk(),JSON.stringify(result));return result[0];};
    const [baseline,encoder]=fixture.baseline(),[combined,combinedEncoder]=unwrap(fixture.shared());
    const schema=JSON.parse(s.schema_string(baseline,s.JsonFormat$Compact$const));
    const oracles=[compileOracle(schema),await compileSupplementary(schema)];
    let accepted=0,rejected=0;
    // Fixed exhaustive product rather than probabilistic sampling.
    for(const name of ['Azrael','',false])for(const age of [0,3,-1,1.5,'3'])for(const nickname of [undefined,'A',null])for(const active of [undefined,true,'yes'])for(const extra of [false,true]){
      const raw={name,age};if(nickname!==undefined)raw.nickname=nickname;if(active!==undefined)raw.active=active;if(extra)raw.extra=true;
      const json=unwrap(s.parse(JSON.stringify(raw))),expected=s.validate(baseline,json);
      for(const oracle of oracles)assert.equal(oracle(raw).accepted,expected.isOk());
      for(const def of [combined]){assert.deepEqual(s.validate(def,json),expected);assert.deepEqual(s.decode(def,json),s.decode(baseline,json));}
      if(expected.isOk()){
        accepted++;const value=unwrap(s.decode(combined,json));
        const left=unwrap(e.encode_json(encoder,value)),right=unwrap(e.encode_json(combinedEncoder,value));
        assert.equal(s.to_string(left,s.JsonFormat$Compact$const),s.to_string(right,s.JsonFormat$Compact$const));
        assert.ok(s.validate(combined,right).isOk());
      }else rejected++;
    }
    assert.ok(accepted>0&&rejected>0);t.diagnostic(`${accepted+rejected} cases: ${accepted} accepted, ${rejected} rejected; both schema oracles agree`);
    const original=s.required(s.record(x=>x),'\ud800',s.text());
    const invalid=shared.required(shared.start(x=>x),'\ud800',s.text(),e.text(),x=>x);
    assert.ok(!invalid.isOk());assert.deepEqual(invalid[0][0],original[0]);
    const key='a/b~',baselineFields=unwrap(s.required(s.record(x=>x),key,s.text()));
    const combinedFields=unwrap(shared.finish(shared.required(shared.start(x=>x),key,s.text(),e.text(),x=>x),s.RecordPolicy$Strict$const));
    const originalDef=s.finish(baselineFields,s.RecordPolicy$Strict$const);
    const badInput=unwrap(s.parse(JSON.stringify({[key]:false})));
    assert.deepEqual(s.decode(combinedFields[0],badInput),s.decode(originalDef,badInput));
    const encoderFields=unwrap(e.field(e.record(),key,e.text(),x=>x));
    const badValue='\ud800';
    assert.deepEqual(e.encode_json(combinedFields[1],badValue),e.encode_json(e.finish(encoderFields),badValue));
    assert.equal(e.encode_json(combinedFields[1],badValue)[0].path,'/a~1b~0');
    const imports='import gargamelle as s\nimport gargamelle/encoding as e\nimport shared_record as r\n';
    const cases=[
      ['unfinished constructor', 'pub fn main() { r.start(fn(name) { fn(age) { #(name, age) } }) |> r.required("name",s.text(),e.text(),fn(value: #(String, Int)) { value.0 }) |> r.finish(s.Strict) }'],
      ['wrong getter', 'pub fn main() { r.start(fn(value) { value }) |> r.required("name",s.text(),e.text(),fn(_: String) { 1 }) |> r.finish(s.Strict) }'],
      ['wrong encoder', 'pub fn main() { r.start(fn(value) { value }) |> r.required("name",s.text(),e.safe_integer(),fn(value) { value }) |> r.finish(s.Strict) }'],
    ];
    const negative=join(directory,'test/negative.gleam');
    for(const [name,body] of cases){
      writeFileSync(negative,imports+body+'\n');
      for(const target of ['javascript','erlang']){const result=run('gleam',['check','--target',target]);assert.notEqual(result.status,0,name);assert.match(result.stdout+result.stderr,/Type mismatch/,name);}
    }
    rmSync(negative);
    const source=join(directory,'test/shared_record.gleam'),originalSource=readFileSync(source,'utf8');
    const mutation=originalSource.replace('gargamelle_encoding.field(encoder, name, encode, get)','gargamelle_encoding.field(encoder, name <> "_wrong", encode, get)');
    assert.notEqual(mutation,originalSource);writeFileSync(source,mutation);
    const mutated=run('gleam',['test']);assert.notEqual(mutated.status,0);assert.match(mutated.stdout,/failures/);assert.doesNotMatch(mutated.stderr,/error:/);
    writeFileSync(source,originalSource);
    t.diagnostic('Three forbidden declarations reject on both targets; an encoder-name drift mutation is detected');
  }finally{rmSync(directory,{recursive:true,force:true});}
});
