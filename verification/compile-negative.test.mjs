import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync,mkdirSync,writeFileSync,rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const cases=[
 ['opaque_definition','pub fn main() { s.Definition(Nil, fn(x) {x}) }','Unknown module value'],
 ['opaque_input','pub fn main() { s.JString("unadmitted") }','Unknown module value'],
 ['wrapped_tagged_branch','pub fn main() { let wrapped = s.description(s.finish(s.record(Nil),s.Closed),"x") s.variant("x",wrapped,s.Closed) }','Type mismatch'],
 ['mapped_tagged_branch','pub fn main() { let wrapped = s.map(s.finish(s.record(Nil),s.Closed),fn(x){x}) s.variant("x",wrapped,s.Closed) }','Type mismatch'],
 ['nonrecord_tagged_branch','pub fn main() { s.variant("x",s.text(),s.Closed) }','Type mismatch'],
 ['optional_is_option','pub fn main() { s.optional(s.record(fn(x: String){x}),"x",s.text()) }','Type mismatch'],
 ['no_predicate_escape','pub fn main() { s.predicate(s.text(),fn(_){False}) }','Unknown module value'],
];
test('compile-time boundary: positive baseline and seven forbidden API programs',()=>{
 const dir=mkdtempSync(join(tmpdir(),'schema-contract-negative-'));
 try{
 mkdirSync(join(dir,'src'));
 const q=p=>JSON.stringify(p);
 writeFileSync(join(dir,'gleam.toml'),`name = "negative_probe"\nversion = "0.1.0"\ntarget = "javascript"\n[dependencies]\nconcord = { path = ${q(root)} }\ngleam_stdlib = { path = ${q(resolve(root,'build/packages/gleam_stdlib'))} }\ngleam_json = { path = ${q(resolve(root,'build/packages/gleam_json'))} }\n`);
 const compile=body=>{writeFileSync(join(dir,'src/negative_probe.gleam'),'import concord as s\n'+body+'\n');const run=spawnSync('gleam',['build'],{cwd:dir,encoding:'utf8',timeout:30000});if(run.error)throw run.error;return {status:run.status,output:run.stdout+run.stderr};};
 const positive=compile('pub fn main() { s.variant("x",s.record(Nil),s.Closed) }');
 assert.equal(positive.status,0,positive.output);
 for(const [name,body,diagnostic] of cases){const result=compile(body);assert.notEqual(result.status,0,name);assert.match(result.output,new RegExp(diagnostic),name+'\n'+result.output);}
 }finally{rmSync(dir,{recursive:true,force:true});}
});
