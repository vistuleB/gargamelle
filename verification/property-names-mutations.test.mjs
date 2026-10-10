import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const mutations=[
 ['key-validation-removed','return inspect(\n                    key,\n                    new JString(pair[0]),\n                    path(p, pair[0]),\n                    bindings,\n                  )[0];','return toList([]);',`assert.equal(s.validate(d,unwrap(s.parse('{"bad":1}'))) instanceof Ok,false);`],
 ['values-tested-instead-of-keys','return inspect(\n                    key,\n                    new JString(pair[0]),\n                    path(p, pair[0]),\n                    bindings,\n                  )[0];','return inspect(key, pair[1], path(p, pair[0]), bindings)[0];',`assert.equal(s.validate(d,unwrap(s.parse('{"en":1}'))) instanceof Ok,true);`],
 ['key-schema-emission-dropped','"propertyNames", key_schema','"x-propertyNames", key_schema',`assert.equal(JSON.parse(s.emit_text(d)).propertyNames?.const,'en');`],
];
test('key validation, key/value distinction, and schema emission mutants fail assertions',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gargamelle-key-mutants-'));
 try{
 cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
 const target=join(dir,'gargamelle/gargamelle.mjs'),original=readFileSync(target,'utf8');
 const header=`import assert from 'node:assert/strict';import * as s from './gargamelle/gargamelle.mjs';import {Ok,toList} from './gargamelle/gleam.mjs';const unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};const d=unwrap(s.property_names(s.dictionary(s.number()),s.string_constant('en')));\n`;
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
