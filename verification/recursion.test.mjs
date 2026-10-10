import test from 'node:test';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {s,unwrap,toList,Some,None,Ok,emitted,evaluate,evaluateText} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import {Error as GleamError} from '../build/dev/javascript/gargamelle/gleam.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
const tree=(name='tree',onLeaf=x=>x)=>unwrap(s.recursive(name,self=>s.any_of(toList([
 s.map(s.number(),x=>({leaf:onLeaf(x)})),
 s.map(s.array(self),xs=>({children:[...xs]})),
]))));
const expected=v=>typeof v==='number'?{leaf:v}:{children:v.map(expected)};
async function validators(d){const schema=emitted(d);return [compileOracle(schema),await compileSupplementary(schema)];}
function compare(d,checks,value,accepted){const text=JSON.stringify(value),input=JSON.parse(text),actual=evaluateText(d,text);for(const check of checks)assert.equal(check(input).accepted,accepted);assert.equal(actual.accepted,accepted);if(accepted)assert.deepEqual(actual.value,expected(input));}

test('self recursion emits finite refs, decodes deep trees and agrees with independent validators',async()=>{
 const d=tree(),schema=emitted(d),checks=await validators(d);
 assert.equal(schema.$ref,'#/$defs/tree');assert.deepEqual(Object.keys(schema.$defs),['tree']);
 assert.equal(schema.$defs.tree.anyOf[1].items.$ref,'#/$defs/tree');
 assert.ok(s.emit_text(d).length<500);
 compare(d,checks,[-1.25,[],[1,[2.5,[]]]],true);
 for(const value of [null,true,'0',{},[1,false],[[],['bad']]])compare(d,checks,value,false);
 let valid=1.25,bad='bad';
 for(let i=0;i<150;i++){valid=[valid];bad=[bad];}
 compare(d,checks,valid,true);compare(d,checks,bad,false);
 assert.equal(evaluate(d,valid).accepted,true);
 const html=docs.render(d,'recursive');assert.ok(html.length<5000);assert.match(html,/href="#recursive-definition-116-114-101-101"/);
});

test('seeded recursive trees preserve values and schema agreement',async()=>{
 const d=tree(),checks=await validators(d);
 for(const seed of [1,71,991,0xdeadbeef,0xfedcba98]){
  let state=seed>>>0;const random=n=>{state=(Math.imul(state,1664525)+1013904223)>>>0;return state%n;};
  const make=depth=>depth===0||random(3)===0?(random(200)-100)/4:Array.from({length:random(4)},()=>make(depth-1));
  for(let i=0;i<100;i++){
   const value=make(i%8);compare(d,checks,value,true);
   compare(d,checks,[value,{invalid:true}],false);
  }
 }
});

function mutual(){return unwrap(s.recursive_pair('alpha','beta',(a,b)=>{
 let ar=unwrap(s.required(s.record(x=>({children:[...x]})),'children',s.array(b)));
 let br=unwrap(s.required(s.record(x=>next=>({name:x,next:next instanceof Some?next[0]:null})),'name',s.text()));
 br=unwrap(s.optional(br,'next',a));
 return new Ok([s.finish(ar,s.Policy$Closed$const),s.finish(br,s.Policy$Closed$const)]);
}));}

test('mutual recursion resolves either root, retains field paths, and composes with defaults and names',async()=>{
 const [a,b]=mutual();
 const valid={children:[{name:'x',next:{children:[{name:'y'}]}}]};
 const decoded={children:[{name:'x',next:{children:[{name:'y',next:null}]}}]};
 for(const [d,values] of [[a,[valid,{children:[]},{children:[{name:1}]},{children:[{name:'x',next:null}]}]],[b,[{name:'x'},{name:'x',next:{children:[]}},null,{name:1}]]]){
  const checks=await validators(d);assert.deepEqual(Object.keys(emitted(d).$defs).sort(),['alpha','beta']);
  for(const value of values){const actual=evaluate(d,value);for(const check of checks)assert.equal(actual.accepted,check(value).accepted);}
 }
 assert.deepEqual(evaluate(a,valid).value,decoded);
 const errors=[...s.decode(a,unwrap(s.parse('{"children":[{"name":"x","next":{"children":[{"name":false}]}}]}')))[0]];
 assert.equal(errors[0].path,'/children/0/next/children/0/name');assert.equal(errors[0].category,'string_type');
 const r=unwrap(s.defaulted(s.record(x=>x),'root',a,unwrap(s.parse(JSON.stringify(valid)))));
 assert.deepEqual(evaluate(s.finish(r,s.Policy$Closed$const),{}).value,decoded);
 const named=unwrap(s.named('wrapper',s.array(a)));assert.equal(evaluate(named,[valid]).accepted,true);
});

test('construction rejects unresolved, non-progressing and conflicting recursion without callbacks on fabricated values',()=>{
 for(const name of ['', 'a/b','a~b','__proto__','tree\n']){
  let calls=0;assert.equal(s.recursive(name,self=>{calls++;return new Ok(self);}) instanceof Ok,false);assert.equal(calls,0);
 }
 assert.equal(s.recursive_pair('same','same',()=>{throw Error('must not run');}) instanceof Ok,false);
 for(const build of [self=>new Ok(self),self=>new Ok(s.description(self,'loop')),self=>new Ok(s.nullable(self)),self=>s.any_of(toList([self,s.number()])),self=>s.one_of(toList([self,self]))])assert.equal(s.recursive('loop',build) instanceof Ok,false);
 assert.equal(s.recursive_pair('a','b',(a,b)=>new Ok([b,a])) instanceof Ok,false);
 let escaped;
 assert.equal(s.recursive('invalid',self=>{escaped=s.array(self);return new Ok(self);}) instanceof Ok,false);
 assert.throws(()=>s.emit_text(escaped),/unfinalized recursive/);
 assert.throws(()=>s.decode(escaped,unwrap(s.parse('[]'))),/unfinalized recursive/);
 let builderCalls=0,decoded=[];
 const d=unwrap(s.recursive('callback-tree',self=>{builderCalls++;return s.any_of(toList([s.map(s.number(),x=>{decoded.push(x);return x;}),s.map(s.array(self),xs=>[...xs])]));}));
 assert.equal(builderCalls,1);assert.deepEqual(decoded,[]);s.emit_text(d);s.validate(d,unwrap(s.parse('[1,[2]]')));assert.deepEqual(decoded,[]);
 assert.deepEqual(evaluate(d,[1,[2]]).value,[1,[2]]);assert.deepEqual(decoded,[1,2]);assert.equal(builderCalls,1);
 const conflict=s.recursive('same',()=>new Ok(unwrap(s.named('same',s.text()))));assert.equal(conflict instanceof Ok,false);
 const independent=tree('other');assert.equal(evaluate(independent,[1]).accepted,true);
 let unbound;const marker=new s.ConstructionError('builder failure');
 const failed=s.recursive('failed',self=>{unbound=self;return new GleamError(marker);});
 assert.equal(failed instanceof Ok,false);assert.equal(failed[0],marker);
 assert.throws(()=>s.emit_text(unbound),/unfinalized recursive/);
 const textTree=unwrap(s.recursive('tree',self=>s.any_of(toList([s.text(),s.map(s.array(self),xs=>[...xs])]))));
 const wrapper=d=>unwrap(s.named('wrapper',s.array(d)));
 assert.throws(()=>s.emit_text(unwrap(s.any_of(toList([wrapper(tree()),wrapper(textTree)])))),/Conflicting named schema definitions/);
});

test('unfinished placeholders cannot supply defaults or be decoded before finalization',()=>{
 const defaultValue=unwrap(s.parse('[]'));
 assert.equal(s.recursive('default-loop',self=>s.defaulted(s.record(x=>x),'value',s.array(self),defaultValue)) instanceof Ok,false);
 assert.throws(()=>s.recursive('premature',self=>{s.decode(s.array(self),defaultValue);return new Ok(self);}),/unfinalized recursive/);
});

test('unguarded cycles nested below consuming edges are rejected and operational exceptions remain exceptions',()=>{
 assert.equal(s.recursive_pair('safe','bad',(a,b)=>new Ok([s.array(b),b])) instanceof Ok,false);
 let calls=0;const marker=Error('author callback operational failure');
 const d=tree('throwing',()=>{calls++;throw marker;});
 s.validate(d,unwrap(s.parse('[[1]]')));assert.equal(calls,0);
 assert.throws(()=>s.decode(d,unwrap(s.parse('[[1]]'))),e=>e===marker);assert.equal(calls,1);
 const onlyArrays=unwrap(s.recursive('arrays',self=>new Ok(s.array(self))));
 assert.equal(evaluate(onlyArrays,[[],[[]]]).accepted,true);assert.equal(evaluate(onlyArrays,[1]).accepted,false);
});

test('stack exhaustion during recursive decoding is an operational exception',async()=>{
 const {spawnSync}=await import('node:child_process');
 const source=`import assert from 'node:assert/strict';
import {s,unwrap,toList} from ${JSON.stringify(new URL('./generated-api.mjs',import.meta.url).href)};
const d=unwrap(s.recursive('stack',self=>{
 let branch=s.map(s.array(self),()=>0);
 for(let i=0;i<80;i++)branch=s.map(branch,x=>x);
 return s.any_of(toList([s.number(),branch]));
}));
const value=unwrap(s.parse('['.repeat(100)+'0'+']'.repeat(100)));
assert.throws(()=>s.decode(d,value),e=>e instanceof RangeError);
console.log('decoder resource exception preserved');`;
 const result=spawnSync(process.execPath,['--stack_size=256','--input-type=module','-e',source],{encoding:'utf8',timeout:10000});
 if(result.error)throw result.error;
 assert.equal(result.status,0,result.stdout+result.stderr);
 assert.match(result.stdout,/decoder resource exception preserved/);
});

test('large finite named graphs emit and validate without growing the traversal stack',()=>{
 let d=s.number();
 for(let i=0;i<2000;i++)d=unwrap(s.named('layer-'+i,s.array(d)));
 // The input is shallow; all schema nodes still need readiness/name checks.
 assert.equal(s.validate(d,unwrap(s.parse('[]'))) instanceof Ok,true);
 assert.equal(Object.keys(emitted(d).$defs).length,2000);
});


test('dictionary recursion preserves own hostile keys and rejects invalid leaves',async()=>{
 const d=unwrap(s.recursive('dictionary-tree',self=>new Ok(s.map(s.dictionary(self),xs=>Object.fromEntries(xs)))));
 const checks=await validators(d);
 for(const value of [{},{a:{b:{}}},JSON.parse('{"__proto__":{"constructor":{}}}'),{a:1},null,[]]){
  const actual=evaluate(d,value);for(const check of checks)assert.equal(actual.accepted,check(value).accepted);
  if(actual.accepted)assert.deepEqual(actual.value,value);
 }
});

test('shared union layers finalize without exponential guard traversal',()=>{
 const code=`import {s,Ok,unwrap,toList} from ${JSON.stringify(new URL('./generated-api.mjs',import.meta.url).href)};
 const start=performance.now();
 const d=unwrap(s.recursive('tree',self=>{let d=s.map(s.array(self),()=>0);for(let i=0;i<32;i++)d=unwrap(s.named('layer-'+i,unwrap(s.any_of(toList([d,d])))));return new Ok(d);}));
 console.log(JSON.stringify({ms:performance.now()-start,bytes:s.emit_text(d).length}));`;
 const run=spawnSync(process.execPath,['--input-type=module','-e',code],{encoding:'utf8',timeout:5000});
 assert.ifError(run.error);assert.equal(run.status,0,run.stderr);
 const report=JSON.parse(run.stdout);assert.ok(report.bytes<4000);
});

test('guard completion is local to finalization and does not hide active back edges',()=>{
 for(let i=0;i<3;i++){
  const good=unwrap(s.recursive('same-name',self=>new Ok(s.array(self))));assert.equal(evaluate(good,[]).accepted,true);
  assert.equal(s.recursive('same-name',self=>s.any_of(toList([self,self]))) instanceof Ok,false);
  assert.equal(s.recursive_pair('first','second',(a,b)=>new Ok([s.description(b,'shared'),unwrap(s.any_of(toList([a,a])))])) instanceof Ok,false);
 }
});
