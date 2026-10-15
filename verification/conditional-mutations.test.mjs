import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const mutations=[
 ['inverted-condition','let $ = inspect(probe, v, "", bindings)[0] instanceof $Empty;\n            if ($) {\n              return inspect(yes, v, p, bindings)[0];','let $ = !(inspect(probe, v, "", bindings)[0] instanceof $Empty);\n            if ($) {\n              return inspect(yes, v, p, bindings)[0];',`assert.equal(s.validate(d,unwrap(s.parse('1'))) instanceof Ok,true);`],
 ['else-validation-removed','return inspect(alternative, v, p, bindings)[0];','return $List$Empty$const;',`assert.equal(s.validate(d,unwrap(s.parse('0.5'))) instanceof Ok,false);`],
 ['then-emission-dropped','["then", emit(yes)]','["x-then", emit(yes)]',`assert.equal(JSON.parse(s.schema_string(d, s.JsonLayout$Compact$const)).allOf[1].then?.const,1);`],
];
test('condition selection, else validation, and then emission mutants fail assertions',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gargamelle-conditional-mutants-'));
 try{
 cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
 const target=join(dir,'gargamelle/gargamelle.mjs'),original=readFileSync(target,'utf8');
 const header=`import assert from 'node:assert/strict';import * as s from './gargamelle/gargamelle.mjs';import {Ok,toList} from './gargamelle/gleam.mjs';import {Some,Option$None$const as None} from './gleam_stdlib/gleam/option.mjs';const unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};const d=s.if_then_else(s.number(),s.safe_integer(),unwrap(s.integer_constant(1)),unwrap(s.number_bounds(s.number(),None,new Some(new s.Inclusive(0)))));\n`;
 for(const [name,from,to,assertion] of mutations){
 assert.equal(original.split(from).length-1,1,name+' unique mutation');
 writeFileSync(join(dir,'check.mjs'),header+assertion);
 const run=()=>spawnSync(process.execPath,['check.mjs'],{cwd:dir,encoding:'utf8',timeout:10000});
 const baseline=run();assert.ifError(baseline.error);assert.equal(baseline.status,0,baseline.stderr);
 writeFileSync(target,original.replace(from,to));const mutant=run();writeFileSync(target,original);
 assert.ifError(mutant.error);assert.notEqual(mutant.status,0,name+' survived');assert.match(mutant.stderr,/AssertionError/);
 }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
