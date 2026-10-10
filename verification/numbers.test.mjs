import test from 'node:test';
import assert from 'node:assert/strict';
import {build,evaluate,evaluateText,emitted,s,unwrap,Some,None,Ok,toList} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import {reference} from './reference.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';

const bounded=(lo,hi)=>unwrap(s.number_bounds(s.number(),lo,hi));
function next(value,up){
 if(value===0)return up?Number.MIN_VALUE:-Number.MIN_VALUE;
 const bytes=new ArrayBuffer(8),view=new DataView(bytes);
 view.setFloat64(0,value);
 let bits=view.getBigUint64(0);
 bits+=(value>0===up)?1n:-1n;
 view.setBigUint64(0,bits);
 return view.getFloat64(0);
}

test('finite numbers preserve parsed Float values, including signed zero and rounding',()=>{
 const d=s.number();
 assert.equal(emitted(d).type,'number');
 assert.equal(Object.hasOwn(emitted(d),'minimum'),false);
 for(const text of ['0','-0','1.0','-1.25','1e308','-1e308','1.7976931348623157e308','5e-324','-5e-324','1e-400','-1e-400','9007199254740993','0.10000000000000001','1.0000000000000001']){
  const r=evaluateText(d,text);
  assert.equal(r.accepted,true,text);
  assert.ok(Object.is(r.value,JSON.parse(text)),text);
 }
 for(const text of ['1e309','-1e309','[1e309]','{"x":1e309}','NaN','Infinity'])assert.equal(s.parse(text) instanceof Ok,false,text);
 for(const value of [null,true,false,'1','',[],{}])assert.equal(evaluate(d,value).accepted,false);
});

test('inclusive/exclusive bounds and neighboring representable values agree with both validators',async()=>{
 const values=[-Number.MAX_VALUE,-1e308,-Number.MIN_VALUE,-0,0,Number.MIN_VALUE,1e308,Number.MAX_VALUE,null,true,'0',[],{}];
 let seed=0x91237;
 for(let i=0;i<120;i++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;values.push((seed/2**32-0.5)*8);}
 const recipes=[{kind:'number'}];
 for(const point of [-1.25,-Number.MIN_VALUE,0,Number.MIN_VALUE,0.1,1.5,Number.MAX_VALUE]){
  for(const exclusive of [false,true]){
   recipes.push({kind:'number',min:point,exclusiveMin:exclusive});
   recipes.push({kind:'number',max:point,exclusiveMax:exclusive});
  }
  recipes.push({kind:'number',min:point,max:point});
  for(const v of [next(point,false),point,next(point,true)])if(Number.isFinite(v))values.push(v);
 }
 for(const exclusiveMin of [false,true])for(const exclusiveMax of [false,true])recipes.push({kind:'number',min:-1.25,max:1.5,exclusiveMin,exclusiveMax});
 for(const recipe of recipes){
  const d=build(recipe),schema=emitted(d),ajv=compileOracle(schema),hyperjump=await compileSupplementary(schema);
  for(const value of values){
   // Give both validators exactly the parsed value received by the decoder.
   const text=Object.is(value,-0)?'-0':JSON.stringify(value),input=JSON.parse(text);
   const expected=reference(recipe,input),actual=evaluateText(d,text);
   assert.equal(ajv(input).accepted,expected.accepted,JSON.stringify({recipe,text}));
   assert.equal(hyperjump(input).accepted,expected.accepted,JSON.stringify({recipe,text}));
   assert.equal(actual.accepted,expected.accepted,JSON.stringify({recipe,text}));
   if(actual.accepted)assert.ok(Object.is(actual.value,input));
  }
 }
});

test('bounds compose by intersection, retain exclusive equality, and reject invalid construction',()=>{
 let d=bounded(new Some(new s.Inclusive(-2.5)),new Some(new s.Inclusive(2.5)));
 d=unwrap(s.number_bounds(s.description(d,'measurement'),new Some(new s.Exclusive(-1.25)),new Some(new s.Exclusive(1.5))));
 d=unwrap(s.number_bounds(d,new Some(new s.Inclusive(-1.25)),new Some(new s.Inclusive(2))));
 assert.equal(emitted(d).exclusiveMinimum,-1.25);assert.equal(emitted(d).exclusiveMaximum,1.5);
 assert.equal(emitted(d).description,'measurement');
 for(const value of [-1.25,next(-1.25,true),0,next(1.5,false),1.5])assert.equal(evaluate(d,value).accepted,value>-1.25&&value<1.5);
 const singleton=bounded(new Some(new s.Inclusive(0.5)),new Some(new s.Inclusive(0.5)));
 assert.equal(evaluate(singleton,0.5).accepted,true);assert.equal(evaluate(singleton,next(0.5,true)).accepted,false);
 for(const n of [NaN,Infinity,-Infinity])for(const C of [s.Inclusive,s.Exclusive]){
  assert.equal(s.number_bounds(s.number(),new Some(new C(n)),None) instanceof Ok,false);
  assert.equal(s.number_bounds(s.number(),None,new Some(new C(n))) instanceof Ok,false);
 }
 for(const [lo,hi] of [[new s.Inclusive(2),new s.Inclusive(1)],[new s.Exclusive(1),new s.Inclusive(1)],[new s.Inclusive(1),new s.Exclusive(1)],[new s.Exclusive(1),new s.Exclusive(1)]])assert.equal(s.number_bounds(s.number(),new Some(lo),new Some(hi)) instanceof Ok,false);
 assert.equal(s.number_bounds(singleton,new Some(new s.Exclusive(0.5)),None) instanceof Ok,false);
 assert.equal(s.number_bounds(s.map(s.text(),()=>1.0),None,None) instanceof Ok,false);
 assert.equal(s.bounds(s.number(),new Some(1),None) instanceof Ok,false);
 // A mathematically nonempty interval can contain no representable number.
 const empty=bounded(new Some(new s.Exclusive(1)),new Some(new s.Exclusive(next(1,true))));
 assert.equal(evaluate(empty,1).accepted,false);assert.equal(evaluate(empty,next(1,true)).accepted,false);
});

test('Float contracts preserve defaults, callbacks, nested paths, names, and documentation',()=>{
 let calls=[];
 const d=s.map(bounded(new Some(new s.Exclusive(0)),new Some(new s.Inclusive(1))),x=>{calls.push(x);return x*2;});
 let r=unwrap(s.defaulted(s.record(x=>x),'p',d,unwrap(s.parse('0.25'))));
 const record=s.finish(r,s.Policy$Closed$const);
 assert.deepEqual(calls,[]);assert.equal(s.decode(record,unwrap(s.parse('{}')))[0],0.5);assert.deepEqual(calls,[0.25]);
 calls=[];assert.equal(s.decode(record,unwrap(s.parse('{"p":0}'))) instanceof Ok,false);assert.deepEqual(calls,[]);
 assert.equal(s.defaulted(s.record(x=>x),'p',d,unwrap(s.parse('0'))) instanceof Ok,false);
 const array=s.array(s.number());const error=[...s.decode(array,unwrap(s.parse('["0"]')))[0]][0];
 assert.equal(error.category,'number_type');assert.equal(error.path,'/0');
 const named=unwrap(s.named('probability',d));assert.equal(emitted(named).$defs.probability.type,'number');
 assert.equal(s.decode(named,unwrap(s.parse('0.5')))[0],1);
 const html=docs.render(d,'probability');assert.match(html,/number/);assert.match(html,/value &gt; 0/);assert.match(html,/value: −∞ … 1/);
 const union=unwrap(s.one_of(toList([s.number(),s.map(s.safe_integer(),x=>x)])));
 assert.equal(s.decode(union,unwrap(s.parse('1'))) instanceof Ok,false);
 assert.equal(s.decode(union,unwrap(s.parse('0.5')))[0],0.5);
});
