import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const mutations=[
 ['unguarded-cycle-admitted','concord.mjs','function guard_same_input(n, ancestors) {','function guard_same_input(n, ancestors) { return new Ok(undefined);',`assert.equal(s.recursive('loop',self=>new Ok(self)) instanceof Ok,false);`],
 ['wrong-recursive-ref','concord.mjs','} else if (n instanceof ReferenceNode) {\n    let name = n[0];\n    return obj(toList([["$ref", new JString("#/$defs/" + name)]]));','} else if (n instanceof ReferenceNode) {\n    let name = n[0];\n    return obj(toList([["$ref", new JString("#/missing/" + name)]]));',`const d=unwrap(s.recursive('tree',self=>new Ok(s.array(self)))); assert.equal(JSON.parse(s.emit_text(d)).$defs.tree.items.$ref,'#/$defs/tree');`],
 ['rejected-reference-remains-usable','runtime.mjs',"() => { state = 'rejected'; value = undefined; },","() => {},",`let escaped; assert.equal(s.recursive('loop',self=>{escaped=s.array(self);return new Ok(self);}) instanceof Ok,false); assert.throws(()=>s.decode(escaped,unwrap(s.parse('[]'))),/unfinalized recursive/);`],
];
test('recursive guard, reference emission, and rejected-placeholder mutants fail behavioral assertions',()=>{
 const dir=mkdtempSync(join(tmpdir(),'concord-recursion-mutants-'));
 try{
  cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
  const header=`import assert from 'node:assert/strict';\nimport * as s from './concord/concord.mjs';\nimport {Ok} from './concord/gleam.mjs';\nconst unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};\n`;
  for(const [name,file,from,to,assertion] of mutations){
   const target=join(dir,'concord',file),original=readFileSync(target,'utf8');
   assert.equal(original.split(from).length-1,1,name+' mutation target must be unique');
   writeFileSync(join(dir,'check.mjs'),header+assertion+'\n');
   const run=()=>{const r=spawnSync(process.execPath,['check.mjs'],{cwd:dir,encoding:'utf8',timeout:10000});if(r.error)throw r.error;return r;};
   const baseline=run();assert.equal(baseline.status,0,name+' baseline\n'+baseline.stderr);
   writeFileSync(target,original.replace(from,to));const mutant=run();writeFileSync(target,original);
   assert.notEqual(mutant.status,0,name+' survived');assert.match(mutant.stderr,/AssertionError/,name+' must fail behavioral assertion');
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
