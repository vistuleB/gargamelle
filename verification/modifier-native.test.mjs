import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import Ajv2020 from 'ajv/dist/2020.js';
import {root} from './evidence.mjs';
import {oracleOptions} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

test('typed modifier compositions agree across targets, decoded outputs and independent schemas',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'gargamelle-modifier-native-'));
 try{
  for(const path of ['src','test','priv','build/packages','gleam.toml','manifest.toml'])cpSync(join(root,path),join(dir,path),{recursive:true});
  const run=(command,args)=>{const r=spawnSync(command,args,{cwd:dir,encoding:'utf8',timeout:60000,maxBuffer:8*1024*1024});assert.ifError(r.error);assert.equal(r.status,0,r.stdout+r.stderr);return r.stdout;};
  run('make',['-C','priv/regex-src']);
  const observations=target=>JSON.parse(run('gleam',['run','--target',target,'-m','modifier_fixture']).trim());
  const javascript=observations('javascript'),erlang=observations('erlang');
  assert.deepEqual(erlang,javascript);
  assert.equal(erlang.length,7);
  const expected={counted:[true,false,false,false,true,false],text:[true,false,false,false],integer:[true,true,false,false,false],number:[true,false,true,false,false],array:[true,true,false,false,false,false,false,false],object:[true,true,false,false,false],asserted:[true,true,false,false,false]};
  let comparisons=0;
  for(const group of erlang){
   const schema=JSON.parse(group.schema);
   const ajv=new Ajv2020({...oracleOptions,strictTypes:false,validateFormats:false});
   assert.equal(ajv.validateSchema(schema),true);
   const validate=ajv.compile(schema),hyperjump=await compileSupplementary(schema);
   assert.deepEqual(group.cases.map(x=>x.validated),expected[group.name]);
   for(const row of group.cases){
    const value=JSON.parse(row.source);
    assert.equal(row.decoded.accepted,row.validated);
    assert.equal(validate(value),row.validated,JSON.stringify({group:group.name,value,schema}));
    assert.equal(hyperjump(value).accepted,row.validated);
    comparisons++;
   }
  }
  assert.equal(comparisons,38);
 }finally{rmSync(dir,{recursive:true,force:true});}
});
