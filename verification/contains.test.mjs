import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,Some,None,Ok,emitted,evaluate,build} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
const contains=(base,match,min=1,max=null)=>unwrap(s.contains(base,match,min,max==null?None:new Some(max)));
const numbers=s.map(s.array(s.number()),xs=>[...xs]);
async function compare(d,cases){const schema=emitted(d),checks=[compileOracle(schema),await compileSupplementary(schema)];for(const [v,accepted,output] of cases){const actual=evaluate(d,v);assert.equal(actual.accepted,accepted,JSON.stringify(v));for(const check of checks)assert.equal(check(v).accepted,accepted);if(accepted)assert.deepEqual(actual.value,output??v);}}

test('membership counts structural matches and preserves nonmatching items',async()=>{
 const d=contains(numbers,s.safe_integer(),1,2);
 await compare(d,[[[0.5,1,2.5],true],[[1,1],true],[[1,2,3],false],[[0.5],false],[[],false],[[1,'bad'],false],[{},false],[null,false]]);
 assert.equal(emitted(d).minContains,1);assert.equal(emitted(d).maxContains,2);
 const html=docs.render(d,'members');assert.match(html,/matching items/);assert.match(html,/matching items: 1 … 2/);
 await compare(contains(numbers,s.safe_integer(),0,0),[[[],true],[[0.5],true],[[1],false]]);
 await compare(contains(numbers,s.safe_integer(),0),[[[],true],[[1,2,3],true]]);
});

test('verbatim answers require nonblank text or a formula reference',async()=>{
 const formula=s.finish(unwrap(s.required(s.record(id=>({id})),'id',s.text())),s.Policy$Closed$const);
 const part=unwrap(s.any_of(toList([s.text(),formula])));
 const meaningful=unwrap(s.any_of(toList([unwrap(s.pattern(s.text(),'\\S')),formula])));
 const d=contains(s.map(s.array(part),xs=>[...xs]),meaningful);
 await compare(d,[[['  ','word','\n'],true],[[{id:'formula1'}],true],[['',' \t\n','\u00a0','\ufeff'],false],[[],false],[[{id:0}],false]]);
 // Formula existence remains a provider check, separate from this shape.
 assert.equal(evaluate(d,[{id:'unknown'}]).accepted,true);
});

test('repeated constraints intersect; match converters are never executed',async()=>{
 let calls=0;const matcher=s.map(s.safe_integer(),()=>{calls++;throw new Error('match conversion');});
 const integer=contains(numbers,matcher,1,2);
 const d=contains(s.description(integer,'both'),unwrap(s.number_bounds(s.number(),new Some(new s.Exclusive(0)),None)),2,3);
 await compare(d,[[[1,0.5],true],[[1],false],[[-1,-2,0.5],false],[[1,2,3],false]]);
 assert.equal(emitted(d).allOf.length,2);assert.equal(calls,0);
 const bounded=unwrap(s.bounds(d,new Some(2),new Some(2)));
 await compare(bounded,[[[1,0.5],true],[[1,0.5,0.75],false]]);
 for(const [min,max] of [[-1,null],[2,1],[0,-1],[NaN,null],[0,Infinity],[1.5,null]])assert.equal(s.contains(numbers,s.number(),min,max==null?None:new Some(max)) instanceof Ok,false);
 for(const base of [s.text(),s.dictionary(s.number()),s.nullable(s.array(s.number()))])assert.equal(s.contains(base,s.number(),1,None) instanceof Ok,false);
});

test('membership composes with named arrays, tuples, uniqueness and recursive values',async()=>{
 const named=unwrap(s.named('numbers',numbers));await compare(contains(named,s.safe_integer()),[[[0.5,1],true],[[0.5],false]]);
 const unique=s.map(unwrap(s.unique_items(s.array(s.number()))),xs=>[...xs]);await compare(contains(unique,s.safe_integer()),[[[1,0.5],true],[[1,1],false]]);
 const tuple=build({kind:'tuple',children:[{kind:'number'},{kind:'string'}]});await compare(contains(tuple,s.number(),1,1),[[[0.5,'x'],true],[[0.5,1],false]]);
 const d=unwrap(s.recursive('member-tree',self=>s.any_of(toList([s.map(s.number(),x=>x),s.map(contains(s.array(self),s.number(),1),xs=>[...xs])]))));
 await compare(d,[[[1,[2,3]],true],[[[1]],false],[[1,[]],false]]);
 let escaped;assert.throws(()=>s.recursive('unbound',self=>{escaped=contains(numbers,self);throw new Error('stop');}),/stop/);
 assert.throws(()=>s.schema_string(escaped),/unfinalized/);assert.throws(()=>evaluate(escaped,[]),/unfinalized/);
 const conflict=contains(unwrap(s.named('same',numbers)),unwrap(s.named('same',s.number())));assert.throws(()=>s.schema_string(conflict),/Conflicting/);
});
