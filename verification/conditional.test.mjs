import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,Some,None,Ok,emitted,evaluate} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import * as docs from '../build/dev/javascript/concord/concord/documentation.mjs';
const record=(fields,open=true)=>{
 const curry=(i,values)=>i===fields.length?Object.fromEntries(fields.map(([name],j)=>[name,values[j]])):value=>curry(i+1,[...values,value]);
 let r=s.record(curry(0,[]));for(const [name,def] of fields)r=unwrap(s.required(r,name,def));return s.finish(r,open?s.Policy$Open$const:s.Policy$Closed$const);
};
async function compare(d,cases){const schema=emitted(d),checks=[compileOracle(schema),await compileSupplementary(schema)];for(const [v,accepted,output] of cases){const actual=evaluate(d,v);assert.equal(actual.accepted,accepted,JSON.stringify(v));for(const check of checks)assert.equal(check(v).accepted,accepted);if(accepted&&output!==undefined)assert.deepEqual(actual.value,output);}}

test('equation initial-answer visibility structurally requires a sequence',async()=>{
 const base=record([['editor',record([['initialAnswerVisible',s.boolean()]])]]);
 const condition=record([['editor',record([['initialAnswerVisible',s.boolean_constant(true)]])]]);
 const requirement=record([['sequence',s.array(record([['kind',s.text()],['text',s.text()]]))]]);
 const d=s.if_then(base,condition,requirement);
 await compare(d,[[{editor:{initialAnswerVisible:true},sequence:[{kind:'symbol',text:'x'}]},true,{editor:{initialAnswerVisible:true}}],[{editor:{initialAnswerVisible:true}},false],[{editor:{initialAnswerVisible:false}},true,{editor:{initialAnswerVisible:false}}],[{editor:{initialAnswerVisible:'true'}},false]]);
 const errors=evaluate(d,{editor:{initialAnswerVisible:true},sequence:[{kind:'symbol',text:0}]}).value;
 assert.equal([...errors][0].path,'/sequence/0/text');
 const html=docs.render(d,'sequence');assert.match(html,/if condition/);assert.match(html,/then requirement/);
 // Missing condition fields fail its required checks, so the implication is vacuous.
 const loose=s.map(s.dictionary(s.boolean()),xs=>Object.fromEntries(xs));
 await compare(s.if_then(loose,record([['enabled',s.boolean_constant(true)]]),record([['ready',s.boolean_constant(true)]])),[[{},true],[{enabled:false},true],[{enabled:true},false],[{enabled:true,ready:true},true]]);
});

test('else selection, base validation, and repeated conditionals preserve output',async()=>{
 const positive=unwrap(s.number_bounds(s.number(),new Some(new s.Exclusive(0)),None));
 const negative=unwrap(s.number_bounds(s.number(),None,new Some(new s.Inclusive(-1))));
 const d=s.if_then_else(s.map(s.number(),x=>({value:x})),positive,s.safe_integer(),negative);
 await compare(d,[[1,true,{value:1}],[1.5,false],[-1.5,true,{value:-1.5}],[0,false],['x',false]]);
 const repeated=s.if_then(d,s.number(),unwrap(s.number_bounds(s.number(),None,new Some(new s.Inclusive(2)))));
 await compare(repeated,[[2,true,{value:2}],[3,false],[-1,true,{value:-1}]]);
 assert.equal(emitted(repeated).allOf.length,3);
 assert.match(docs.render(d,'else'),/else requirement/);
 const incompatible=s.if_then(s.text(),s.number(),s.boolean());
 await compare(incompatible,[['text',true],[1,false],[true,false]]);
});

test('condition and both branch converters never run; validation inspects input before defaults',async()=>{
 let auxiliary=0,base=0;
 const inspector=d=>s.map(d,()=>{auxiliary++;throw new Error('auxiliary callback');});
 const d=s.if_then_else(s.map(s.number(),x=>{base++;return x;}),inspector(s.safe_integer()),inspector(s.number()),inspector(s.number()));
 await compare(d,[[1,true,1],[0.5,true,0.5],['bad',false]]);assert.equal(auxiliary,0);assert.equal(base,2);
 const r=unwrap(s.defaulted(s.record(x=>({enabled:x})),'enabled',s.boolean(),unwrap(s.parse('true'))));
 const defaulted=s.if_then(s.finish(r,s.Policy$Open$const),record([['enabled',s.boolean_constant(true)]]),record([['ready',s.boolean_constant(true)]]));
 await compare(defaulted,[[{},true,{enabled:true}],[{enabled:true},false],[{enabled:false},true,{enabled:false}],[{enabled:true,ready:true},true,{enabled:true}]]);
});

test('conditional graphs collect all branches and reject same-input cycles',async()=>{
 const d=unwrap(s.recursive('conditional-tree',self=>s.any_of(toList([s.number(),s.map(s.if_then(s.array(self),s.array(s.number()),unwrap(s.bounds(s.array(s.number()),new Some(1),None))),xs=>[...xs])]))));
 await compare(d,[[[1,[2]],true],[[],false],[['bad'],false]]);
 assert.equal(s.recursive('loop',self=>new Ok(s.if_then(s.number(),self,s.number()))) instanceof Ok,false);
 assert.equal(s.recursive('loop',self=>new Ok(s.if_then_else(s.number(),s.number(),s.number(),self))) instanceof Ok,false);
 let escaped;assert.throws(()=>s.recursive('unbound',self=>{escaped=s.if_then(s.number(),s.text(),self);throw new Error('stop');}),/stop/);
 assert.throws(()=>s.emit_text(escaped),/unfinalized/);assert.throws(()=>evaluate(escaped,1),/unfinalized/);
 const conflict=s.if_then(s.number(),unwrap(s.named('same',s.text())),unwrap(s.named('same',s.number())));assert.throws(()=>s.emit_text(conflict),/Conflicting/);
});
