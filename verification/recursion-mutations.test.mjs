import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const mutations=[
 ['unguarded-cycle-admitted','gargamelle.mjs','function guard_same_input(n, state) {','function guard_same_input(n, state) { return new Ok(undefined);',`assert.equal(s.recursive('loop',self=>new Ok(self)) instanceof Ok,false);`],
 ['wrong-recursive-ref','gargamelle.mjs','} else if (n instanceof ReferenceNode) {\n      let name = n[0];\n      return obj(toList([["$ref", new JString("#/$defs/" + name)]]));','} else if (n instanceof ReferenceNode) {\n      let name = n[0];\n      return obj(toList([["$ref", new JString("#/missing/" + name)]]));',`const d=unwrap(s.recursive('tree',self=>new Ok(s.array(self)))); assert.equal(JSON.parse(s.schema_string(d)).$defs.tree.items.$ref,'#/$defs/tree');`],
 ['binding-scope-ignored','runtime.mjs','walkState(scopes, scope(value)), id = key(value);\n    const seen','walkState(scopes, undefined), id = key(value);\n    const seen',`const completed=unwrap(s.recursive('captured',self=>s.any_of(toList([s.map(s.text(),()=>()=>self),s.map(s.array(self),()=>()=>self)])))); const get=unwrap(s.decode(completed,unwrap(s.parse('"capture"')))); assert.equal(s.recursive('inner',inner=>s.any_of(toList([s.lift(completed),s.map(s.array(get()),()=>()=>inner)]))) instanceof Ok,false);`],
];
test('recursive guard, reference emission, and binding-scope mutants fail behavioral assertions',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gargamelle-recursion-mutants-'));
 try{
  cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
  const header=`import assert from 'node:assert/strict';\nimport * as s from './gargamelle/gargamelle.mjs';\nimport {Ok,toList} from './gargamelle/gleam.mjs';\nconst unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};\n`;
  for(const [name,file,from,to,assertion] of mutations){
   const target=join(dir,'gargamelle',file),original=readFileSync(target,'utf8');
   assert.equal(original.split(from).length-1,1,name+' mutation target must be unique');
   writeFileSync(join(dir,'check.mjs'),header+assertion+'\n');
   const run=()=>{const r=spawnSync(process.execPath,['check.mjs'],{cwd:dir,encoding:'utf8',timeout:10000});if(r.error)throw r.error;return r;};
   const baseline=run();assert.equal(baseline.status,0,name+' baseline\n'+baseline.stderr);
   writeFileSync(target,original.replace(from,to));const mutant=run();writeFileSync(target,original);
   assert.notEqual(mutant.status,0,name+' survived');assert.match(mutant.stderr,/AssertionError/,name+' must fail behavioral assertion');
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
