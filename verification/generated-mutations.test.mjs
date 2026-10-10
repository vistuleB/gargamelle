import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync,symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const original=readFileSync(join(root,'build/dev/javascript/gargamelle/gargamelle.mjs'),'utf8');
const variants=[
 ['first-match-one-of','return union(defs, true);','return union(defs, false);',"assert.equal(accepted('overlap','\"x\"'),false)"],
 ['null-as-missing','return new Some(x);','return x instanceof JNull ? Option$None$const : new Some(x);',"assert.equal(accepted('optional','{\"a\":null}'),false)"],
 ['disabled-extra-key','if (policy instanceof Closed) {','if (false) {',"assert.equal(accepted('closed_record','{\"a\":\"x\",\"extra\":true}'),false)"],
 ['off-by-one-bound','_block = n >= x;','_block = n > x;',"assert.equal(accepted('bounded_string','\"x\"'),true)"],
 ['dropped-field','let properties = $list.map(\n        fs,','let properties = $list.map(\n        $List$Empty$const,',"assert.equal(Object.hasOwn(JSON.parse(f.fixture_schema('closed_record')).properties,'a'),true)"],
];
const header=`import assert from 'node:assert/strict';\nimport * as f from './gargamelle/schema_fixtures.mjs';\nimport {Ok} from './gargamelle/gleam.mjs';\nfunction accepted(name,text){const r=f.fixture_decode(name,text);assert.ok(r instanceof Ok);return r[0] instanceof Ok;}\n`;
test('actual isolated compiled mutations are killed by permanent counterexamples',()=>{
 const dir=mkdtempSync(join(tmpdir(),'schema-contract-mutations-'));
 try {
 cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
 const target=join(dir,'gargamelle/gargamelle.mjs');
 for(const [name,from,to,assertion] of variants){
  assert.equal(original.split(from).length-1,1,`${name}: mutation target must be unique`);
  writeFileSync(join(dir,'check.mjs'),header+assertion+';\n');
  writeFileSync(target,original);
  const baseline=spawnSync(process.execPath,['check.mjs'],{cwd:dir,encoding:'utf8',timeout:10000});
  if(baseline.error)throw baseline.error;assert.equal(baseline.status,0,name+' baseline\n'+baseline.stderr);
  writeFileSync(target,original.replace(from,to));
  const mutant=spawnSync(process.execPath,['check.mjs'],{cwd:dir,encoding:'utf8',timeout:10000});
  if(mutant.error)throw mutant.error;assert.notEqual(mutant.status,0,name+' survived');assert.match(mutant.stderr,/AssertionError/,name+': must fail the behavioral assertion, not crash');
 }
 }finally{rmSync(dir,{recursive:true,force:true});}
});


test('revision-3 mutants fail the complete foundation, typed-value and hardening suites',()=>{
 const dir=mkdtempSync(join(tmpdir(),'schema-contract-hardening-mutants-'));
 try {
  cpSync(join(root,'build'),join(dir,'build'),{recursive:true});
  cpSync(join(root,'verification'),join(dir,'verification'),{recursive:true});
  symlinkSync(join(root,'node_modules'),join(dir,'node_modules'),'dir');
  const args=['--test','verification/foundation.test.mjs','verification/generated-values.test.mjs','verification/hardening.test.mjs'];
  const env={...process.env};delete env.NODE_TEST_CONTEXT;
  const run=()=>{const r=spawnSync(process.execPath,args,{cwd:dir,env,encoding:'utf8',timeout:20000});if(r.error)throw r.error;return r;};
  const baseline=run();assert.equal(baseline.status,0,baseline.stdout+baseline.stderr);assert.match(baseline.stdout,/(?:tests|pass) [1-9]/);
  for(const [file,from,to] of [
   ['runtime.mjs','Object.create(null)','{}'],
   ['runtime.mjs','[...text].length','text.length'],
   ['gargamelle.mjs','err("unknown_discriminator", path(p, k))','err("union_no_match", path(p, k))'],
  ]){
   const target=join(dir,'build/dev/javascript/gargamelle',file),source=readFileSync(target,'utf8');
   assert.equal(source.split(from).length-1,1,'mutation target must be unique');
   writeFileSync(target,source.replace(from,to));const mutant=run();writeFileSync(target,source);
   assert.notEqual(mutant.status,0,from+' survived\n'+mutant.stdout+mutant.stderr);assert.match(mutant.stdout+mutant.stderr,/AssertionError|ERR_ASSERTION/,from+' must fail behavioral assertions');
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
