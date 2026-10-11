import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,Some,None,Ok,emitted,evaluate,build} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
const tuple=children=>{
 const curry=(i,out)=>i===children.length?out:x=>curry(i+1,[...out,x]);
 return s.finish_tuple(children.reduce((t,d)=>s.element(t,d),s.tuple(curry(0,[]))));
};
async function compare(d,cases){const schema=emitted(d),checks=[compileOracle(schema),await compileSupplementary(schema)];for(const [value,accepted,output] of cases){const actual=evaluate(d,value);assert.equal(actual.accepted,accepted,JSON.stringify(value));for(const check of checks)assert.equal(check(value).accepted,accepted);if(accepted)assert.deepEqual(actual.value,output??value);}}

test('exact tuples include empty and arbitrary arity with positional validation',async()=>{
 for(let length=0;length<=6;length++){
  const children=Array.from({length},(_,i)=>i%2?s.boolean():s.text()),value=children.map((_,i)=>i%2?true:'x');
  const d=tuple(children),schema=emitted(d);
  assert.equal(schema.items,false);assert.equal(schema.minItems,length);
  assert.equal(Object.hasOwn(schema,'prefixItems'),length>0);
  await compare(d,[[value,true],[value.concat(null),false],[null,false],[{},false],[false,false],...(length?[[value.slice(1),false],[value.map((x,i)=>i===0?0:x),false]]:[])]);
 }
 const d=tuple([s.array(s.number()),s.text()]);
 const errors=evaluate(d,[[1,'bad'],false]).value;
 assert.deepEqual([...errors].map(e=>e.path),['/0/1','/1']);
 const html=docs.render(d,'tuple');assert.match(html,/position 0/);assert.match(html,/position 1/);assert.match(html,/exactly 2 positions/);assert.match(html,/extra positions rejected/);
 assert.match(docs.render(tuple([]),'empty'),/exactly 0 positions/);
});

test('tuple conversion callbacks execute only after complete validation',()=>{
 let calls=0;const d=s.finish_tuple(s.element(s.tuple(x=>{calls++;return {value:x};}),s.map(s.text(),x=>{calls++;return x;})));
 assert.equal(calls,0);s.schema_string(d);docs.render(d,'callbacks');assert.equal(calls,0);
 for(const v of [[],['x',true],[false]])assert.equal(evaluate(d,v).accepted,false);
 assert.equal(calls,0);assert.deepEqual(evaluate(d,['x']).value,{value:'x'});assert.equal(calls,2);
 const mapped=s.map(tuple([s.text()]),xs=>toList(xs));
 assert.equal(s.bounds(mapped,None,new Some(2)) instanceof Ok,false);
 assert.equal(s.unique_items(mapped) instanceof Ok,false);
});

test('legacy palette pair and triple union maps to a shared output type',async()=>{
 const tool=unwrap(s.any_of(toList([s.text(),s.map(s.array(s.text()),xs=>[...xs])])));
 const pair=s.map(tuple([tool,s.text()]),([tool,label])=>({tool,label,accessibleLabel:null}));
 const triple=s.map(tuple([tool,s.text(),s.text()]),([tool,label,accessibleLabel])=>({tool,label,accessibleLabel}));
 const d=unwrap(s.one_of(toList([pair,triple])));
 await compare(d,[[['x','X'],true,{tool:'x',label:'X',accessibleLabel:null}],[[['x','+','y'],'sum','sum of x and y'],true,{tool:['x','+','y'],label:'sum',accessibleLabel:'sum of x and y'}],[['x'],false],[['x','X',null],false],[['x','X','alt','extra'],false],[[[1],'X'],false]]);
});

test('tuple recursive edges descend and collection checks every position',async()=>{
 const d=unwrap(s.recursive('tuple-tree',self=>s.any_of(toList([s.map(s.number(),x=>x),s.map(tuple([s.text(),self]),([tag,next])=>({tag,next}))]))));
 await compare(d,[[['a',['b',0.5]],true,{tag:'a',next:{tag:'b',next:0.5}}],[['a',['b',false]],false]]);
 assert.equal(emitted(d).$defs['tuple-tree'].anyOf[1].prefixItems[1].$ref,'#/$defs/tuple-tree');
 let escaped;assert.throws(()=>unwrap(s.recursive('unfinished',self=>{escaped=tuple([self]);throw new Error('stop');})),/stop/);
 assert.throws(()=>evaluate(escaped,[]),/not finalized|unfinalized/);assert.throws(()=>s.schema_string(escaped),/not finalized|unfinalized/);
 const conflict=tuple([unwrap(s.named('same',s.text())),unwrap(s.named('same',s.number()))]);assert.throws(()=>s.schema_string(conflict),/conflict/i);
 const defaults=unwrap(s.defaulted(s.record(x=>x),'entry',tuple([s.text(),s.number()]),unwrap(s.parse('["x",0.5]'))));
 assert.deepEqual(evaluate(s.finish(defaults,s.RecordPolicy$Closed$const),{}).value,['x',0.5]);
});
