import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const mutations=[
 ['missing-length-check','let $ = $list.length(children) === $list.length(xs);','let $ = true;',`assert.equal(s.validate(d,unwrap(s.parse('[]'))) instanceof Ok,false);`],
 ['swapped-validation-positions','$list.zip(children, xs)','$list.zip($list.reverse(children), xs)',`assert.equal(s.validate(d,unwrap(s.parse('["x",true]'))) instanceof Ok,true);`],
 ['extra-items-emitted','put(_pipe, "items", new JBool(false))','put(_pipe, "items", new JBool(true))',`assert.equal(JSON.parse(s.emit_text(d)).items,false);`],
];
test('tuple length, positional diagnostics, and closed emission mutants fail assertions',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gargamelle-tuple-mutants-'));
 try{
 cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
 const target=join(dir,'gargamelle/gargamelle.mjs'),original=readFileSync(target,'utf8');
 const header=`import assert from 'node:assert/strict';import * as s from './gargamelle/gargamelle.mjs';import {Ok} from './gargamelle/gleam.mjs';const unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};const d=s.finish_tuple(s.element(s.element(s.tuple(a=>b=>[a,b]),s.text()),s.boolean()));\n`;
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
