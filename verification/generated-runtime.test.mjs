import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { retainOperationalFailure } from './generated-retention.mjs';
import { s,Ok,unwrap } from './generated-api.mjs';

test('JSON text admission distinguishes syntax/nonfinite from validation',()=>{
 for(const text of ['','{','undefined','NaN','[1,]','{"a":}', '1e400','-1e400','{"nested":[1e400]}']) assert.equal(s.parse(text) instanceof Ok,false,text);
 for(const text of ['null','true','-0','1.0','"\\ud83d\\udc9c"','"\\u0000"','{"x":1,"x":2}'])assert.ok(s.parse(text) instanceof Ok,text);
 assert.equal(s.to_string(unwrap(s.parse('{"x":1,"x":2}')), s.JsonLayout$Compact$const),'{"x":2}');
 const x=unwrap(s.parse('false'));assert.equal(s.decode(s.string(),x) instanceof Ok,false);
});

test('callback and resource exceptions remain operational failures, not schema rejections',()=>{
 const marker=new Error('provider callback failure');
 const d=s.map(s.string(),()=>{throw marker;});
 const input=unwrap(s.parse('"x"'));
 assert.ok(s.validate(d,input) instanceof Ok);
 assert.doesNotThrow(()=>s.schema_string(d, s.JsonLayout$Compact$const));
 assert.throws(()=>s.decode(d,input),e=>e===marker);
 const source=`import {parse} from ${JSON.stringify(new URL('../build/dev/javascript/gargamelle/gargamelle.mjs',import.meta.url).href)};
 try { const r=parse('['.repeat(10000)+'null'+']'.repeat(10000)); console.error('incorrectly returned',r.constructor.name); process.exit(3); }
 catch(e) { if(e instanceof RangeError){ console.log('operational RangeError'); process.exit(42); } throw e; }`;
 const resource=spawnSync(process.execPath,['--stack_size=256','--input-type=module','-e',source],{encoding:'utf8',timeout:10000});
 if(resource.error)throw resource.error;
 assert.equal(resource.status,42,resource.stdout+resource.stderr);
 assert.match(resource.stdout,/operational RangeError/);
});

test('unsafe/nonintegral construction parameters reject without invoking callbacks',()=>{
 // These runtime calls supplement Gleam compile checks at the JavaScript ABI.
 for(const n of [Number.MAX_SAFE_INTEGER+1,Infinity,NaN,1.5]){
  assert.equal(s.integer_constant(n) instanceof Ok,false);
 }
});

test('regression: parser operational errors must not be mislabeled syntax errors',()=>{
 const original=JSON.parse; const marker=new RangeError('injected parser resource exhaustion');
 try { JSON.parse=()=>{throw marker;}; assert.throws(()=>s.parse('null'),e=>e===marker); }
 finally { JSON.parse=original; }
});

test('operational retention preserves seed, recipe and value independently of validation',()=>{
 const dir=mkdtempSync(join(tmpdir(),'schema-operational-retention-'));
 try { const context={seed:17,index:2,inputIndex:3,stage:'oracle-decode'};const recipe={kind:'string'};const value='x';
 const file=retainOperationalFailure({recipe,value,context,error:new RangeError('injected resource failure')},dir);
 const retained=JSON.parse(readFileSync(file,'utf8'));
 assert.deepEqual(retained.context,context);assert.deepEqual(retained.recipe,recipe);assert.equal(retained.value,value);assert.equal(retained.classification,'operational-failure');assert.equal(retained.error.name,'RangeError');
 } finally {rmSync(dir,{recursive:true,force:true});}
});
