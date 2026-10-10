import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const mutations=[
 ['all-items-counted','return check(matching, item, "") instanceof $Empty;','return true;',`assert.equal(s.validate(d,unwrap(s.parse('[0.5,0.25,1]'))) instanceof Ok,true);`],
 ['maximum-ignored','size_ok(count, new Some(minimum), maximum)','size_ok(count, new Some(minimum), Option$None$const)',`assert.equal(s.validate(d,unwrap(s.parse('[1,2,3]'))) instanceof Ok,false);`],
 ['minimum-emission-dropped','"minContains"','"x-minContains"',`assert.equal(JSON.parse(s.emit_text(d)).minContains,1);`],
];
test('membership counting, maximum, and schema emission mutants fail assertions',()=>{
 const dir=mkdtempSync(join(tmpdir(),'concord-membership-mutants-'));
 try{
 cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
 const target=join(dir,'concord/concord.mjs'),original=readFileSync(target,'utf8');
 const header=`import assert from 'node:assert/strict';import * as s from './concord/concord.mjs';import {Ok,toList} from './concord/gleam.mjs';import {Some} from './gleam_stdlib/gleam/option.mjs';const unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};const d=unwrap(s.contains(s.array(s.number()),s.safe_integer(),1,new Some(2)));\n`;
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
