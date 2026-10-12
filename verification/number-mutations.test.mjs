import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const mutations=[
 ['exclusive-lower-admits-equality','gargamelle.mjs','_block = x > b;','_block = x >= b;',`const d=bound(new s.Exclusive(0),null); assert.equal(s.decode(d,unwrap(s.parse('0'))) instanceof Ok,false);`],
 ['exclusive-upper-admits-equality','gargamelle.mjs','_block$1 = x < b;','_block$1 = x <= b;',`const d=bound(null,new s.Exclusive(1)); assert.equal(s.decode(d,unwrap(s.parse('1'))) instanceof Ok,false);`],
 ['inclusive-lower-rejects-equality','gargamelle.mjs','_block = x >= b;','_block = x > b;',`const d=bound(new s.Inclusive(0.25),null); assert.equal(s.decode(d,unwrap(s.parse('0.25'))) instanceof Ok,true);`],
 ['wrong-exclusive-emission','gargamelle.mjs','"minimum", "exclusiveMinimum"','"minimum", "minimum"',`assert.equal(JSON.parse(s.schema_string(bound(new s.Exclusive(0.25),null), s.JsonFormat$Compact$const)).exclusiveMinimum,0.25);`],
 ['nonfinite-bound-admitted','runtime.mjs','export const finite = Number.isFinite;','export const finite = () => true;',`assert.equal(s.number_bounds(s.number(),new Some(new s.Inclusive(Infinity)),None) instanceof Ok,false);`],
];
test('numeric validation, emission, and construction mutants fail behavioral assertions',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gargamelle-number-mutants-'));
 try{
  cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
  const header=`import assert from 'node:assert/strict';\nimport * as s from './gargamelle/gargamelle.mjs';\nimport {Ok} from './gargamelle/gleam.mjs';\nimport {Some,Option$None$const as None} from './gleam_stdlib/gleam/option.mjs';\nconst unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};\nconst bound=(lo,hi)=>unwrap(s.number_bounds(s.number(),lo===null?None:new Some(lo),hi===null?None:new Some(hi)));\n`;
  for(const [name,file,from,to,assertion] of mutations){
   const target=join(dir,'gargamelle',file),original=readFileSync(target,'utf8');
   assert.equal(original.split(from).length-1,1,name+' target must be unique');
   writeFileSync(join(dir,'check.mjs'),header+assertion+'\n');
   const run=()=>{const r=spawnSync(process.execPath,['check.mjs'],{cwd:dir,encoding:'utf8',timeout:10000});if(r.error)throw r.error;return r;};
   const baseline=run();assert.equal(baseline.status,0,name+' baseline\n'+baseline.stderr);
   writeFileSync(target,original.replace(from,to));const mutant=run();writeFileSync(target,original);
   assert.notEqual(mutant.status,0,name+' survived');assert.match(mutant.stderr,/AssertionError/,name+' must fail an assertion');
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
