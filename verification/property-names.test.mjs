import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,Some,None,Ok,emitted,evaluate} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
const dict=keys=>s.map(unwrap(s.property_names(s.dictionary(s.number()),keys)),xs=>Object.fromEntries(xs));
async function compare(d,cases){const schema=emitted(d),checks=[compileOracle(schema),await compileSupplementary(schema)];for(const [v,accepted,output] of cases){const r=evaluate(d,v);assert.equal(r.accepted,accepted,JSON.stringify(v));for(const check of checks)assert.equal(check(v).accepted,accepted);if(accepted)assert.deepEqual(r.value,output??v);}}

test('locale dictionary keys constrain syntax without changing typed output',async()=>{
 const keys=unwrap(s.pattern(unwrap(s.bounds(s.text(),None,new Some(35))),'^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'));
 const d=dict(keys);
 await compare(d,[[{en:1.5,'pt-BR':2},true],[{},true],[{English:1},false],[{'':1},false],[{'en-US-extra-long-variant-abcdefgh-abcdefgh':1},false],[{en:'bad'},false],[[],false],[null,false]]);
 assert.equal(emitted(d).propertyNames.maxLength,35);
 assert.match(docs.render(d,'locales'),/each property name/);
});

test('repeated key constraints intersect and never execute key conversion',async()=>{
 let calls=0;const keys=s.map(unwrap(s.pattern(s.text(),'^a')),()=>{calls++;throw new Error('key conversion must not run');});
 const first=unwrap(s.property_names(s.dictionary(s.number()),keys));
 const second=unwrap(s.property_names(s.description(first,'map'),unwrap(s.bounds(s.text(),None,new Some(2)))));
 const d=s.map(unwrap(s.bounds(second,new Some(1),new Some(2))),xs=>Object.fromEntries(xs));
 await compare(d,[[{a:1,ab:2},true],[{abc:1},false],[{b:1},false],[{},false],[{a:1,ab:2,ac:3},false]]);
 assert.equal(emitted(d).propertyNames.allOf.length,2);assert.equal(calls,0);
 const errors=evaluate(dict(unwrap(s.pattern(s.text(),'^ok$'))),{'a/b~':'bad'}).value;
 assert.deepEqual([...errors].map(e=>e.path),['/a~1b~0','/a~1b~0']);
});

test('records validate all present keys including projected extras and hostile names',async()=>{
 const record=s.finish(unwrap(s.required(s.record(x=>({x})),'x',s.number())),s.Policy$Open$const);
 const d=unwrap(s.property_names(record,unwrap(s.string_enum(toList(['x','extra'])))));
 await compare(d,[[{x:1,extra:true},true,{x:1}],[{x:1,unexpected:true},false],[{x:1},true]]);
 const names=['__proto__','constructor','toString','','a/b','~','😀'];
 for(const name of names){const v=Object.fromEntries([[name,1.25]]);await compare(dict(s.string_constant(name)),[[v,true],[Object.fromEntries([[name+'x',1]]),false]]);}
 for(const d of [s.text(),s.number(),s.array(s.text()),s.finish_tuple(s.tuple(null)),s.nullable(s.dictionary(s.text()))])assert.equal(s.property_names(d,s.text()) instanceof Ok,false);
});

test('named constraints and recursive dictionary values compose with key validation',async()=>{
 const key=unwrap(s.named('key',unwrap(s.pattern(s.text(),'^k'))));
 const base=unwrap(s.named('base',s.dictionary(s.number())));
 await compare(s.map(unwrap(s.property_names(base,key)),xs=>Object.fromEntries(xs)),[[{k:1.5},true],[{bad:0},false]]);
 const d=unwrap(s.recursive('key-tree',self=>s.any_of(toList([s.map(s.number(),x=>x),s.map(unwrap(s.property_names(s.dictionary(self),key)),xs=>Object.fromEntries(xs))]))));
 await compare(d,[[{k0:{k1:0.5}},true],[{k0:{bad:1}},false]]);
 assert.equal(emitted(d).$defs['key-tree'].anyOf[1].propertyNames.$ref,'#/$defs/key');
 let escaped;assert.throws(()=>s.recursive('unfinished-key',self=>{escaped=unwrap(s.property_names(s.dictionary(s.number()),s.map(self,()=>'')));throw new Error('stop');}),/stop/);
 assert.throws(()=>s.schema_string(escaped),/unfinalized/);assert.throws(()=>evaluate(escaped,{}),/unfinalized/);
 const conflict=unwrap(s.property_names(unwrap(s.named('same',s.dictionary(s.number()))),unwrap(s.named('same',s.text()))));assert.throws(()=>s.schema_string(conflict),/Conflicting/);
});

test('mapped numeric key definition accepts only empty objects with an explicit strictTypes oracle exception',async()=>{
 const {compileNumericPropertyNamesOracle}=await import('./oracle.mjs');
 let calls=0;
 const keys=s.map(s.number(),()=>{calls++;return 'mapped';});
 const d=dict(keys),schema=emitted(d);
 assert.throws(()=>compileOracle(schema),/type "number" not allowed by context "string".*propertyNames.*strictTypes/);
 const checks=[compileNumericPropertyNamesOracle(schema),await compileSupplementary(schema)];
 const values=[{}, {en:1}, {'1':1}, {'':0}, {'😀':1}, Object.fromEntries([['__proto__',1]]), {en:'bad'}, [], [1], null, true, 1, 'x'];
 for(const value of values){
  const accepted=value!==null&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length===0;
  const actual=evaluate(d,value);assert.equal(actual.accepted,accepted);
  for(const check of checks)assert.equal(check(value).accepted,accepted);
  if(accepted)assert.deepEqual(actual.value,{});
 }
 assert.equal(calls,0);
 assert.throws(()=>compileNumericPropertyNamesOracle({...schema,propertyNames:{type:'number',minimum:0}}),/limited to the retained audit fixture/);
 assert.throws(()=>compileNumericPropertyNamesOracle({...schema,additionalProperties:{type:'string'}}),/limited to the retained audit fixture/);
});
