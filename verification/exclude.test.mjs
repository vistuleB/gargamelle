import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,Some,None,Ok,emitted,evaluate} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
async function compare(d,cases){const schema=emitted(d),checks=[compileOracle(schema),await compileSupplementary(schema)];for(const [v,accepted,output] of cases){const actual=evaluate(d,v);assert.equal(actual.accepted,accepted,JSON.stringify(v));for(const check of checks)assert.equal(check(v).accepted,accepted);if(accepted&&output!==undefined)assert.deepEqual(actual.value,output);}}

test('formula code exclusion forbids whitespace, backslash and Unicode punctuation',async()=>{
 const bad=unwrap(s.pattern(s.text(),String.raw`[\\\s\p{P}]`));
 const d=s.exclude(unwrap(s.bounds(s.text(),new Some(1),None)),bad);
 const accepted=['alpha','α','a1','+','∞','😀','e\u0301','\u200b','\ue000'];
 const rejected=['',' ','a b','a\nb','a\tb','a\u00a0b','a\ufeffb','a\\b','a_b','a-b','a:b','a/b','a—b','a。b'];
 await compare(d,[...accepted.map(v=>[v,true,v]),...rejected.map(v=>[v,false]),[1,false],[null,false]]);
 assert.match(docs.render(d,'code'),/must not match/);
 // Prefix-free uniqueness remains a provider concern, not a per-code schema.
 assert.equal(evaluate(d,'a').accepted,true);assert.equal(evaluate(d,'ab').accepted,true);
});

test('exclusion preserves output, intersects repeated constraints and suppresses forbidden callbacks',async()=>{
 let calls=0;
 const forbidden=s.map(s.safe_integer(),()=>{calls++;throw new Error('forbidden conversion');});
 const d=s.exclude(s.map(s.number(),x=>({value:x})),forbidden);
 await compare(d,[[0.5,true,{value:0.5}],[1,false],['x',false]]);assert.equal(calls,0);
 const repeated=s.exclude(s.description(d,'fraction'),unwrap(s.number_bounds(s.number(),None,new Some(new s.Inclusive(0)))));
 await compare(repeated,[[0.5,true,{value:0.5}],[-0.5,false],[1,false]]);
 assert.equal(emitted(repeated).allOf.length,2); // annotation preserves the nested first exclusion.
 const direct=s.exclude(s.exclude(s.number(),s.safe_integer()),unwrap(s.number_bounds(s.number(),None,new Some(new s.Inclusive(0)))));
 assert.equal(emitted(direct).allOf.length,3);
 await compare(s.exclude(s.text(),s.number()),[['x',true,'x'],[1,false]]);
 await compare(s.exclude(s.number(),s.number()),[[1,false],[0.5,false]]);
});

test('forbidden object shapes and original input semantics compose with projection and defaults',async()=>{
 const r=unwrap(s.defaulted(s.record(x=>({enabled:x})),'enabled',s.boolean(),unwrap(s.parse('true'))));
 const banned=s.finish(unwrap(s.required(s.record(x=>x),'enabled',s.boolean_constant(true))),s.Policy$Open$const);
 const d=s.exclude(s.finish(r,s.Policy$Open$const),banned);
 await compare(d,[[{},true,{enabled:true}],[{enabled:false,extra:1},true,{enabled:false}],[{enabled:true},false]]);
 const nested=s.array(d),errors=evaluate(nested,[{enabled:true}]).value;
 assert.equal([...errors][0].category,'excluded');assert.equal([...errors][0].path,'/0');
 // Additional invalid fields still fail the base even when the exclusion does not match.
 await compare(d,[[{enabled:'bad'},false]]);
});

test('exclusion collects forbidden references and rejects same-input recursive cycles',async()=>{
 const d=unwrap(s.recursive('excluding-tree',self=>s.any_of(toList([s.number(),s.map(s.exclude(s.array(self),s.array(s.null$())),xs=>[...xs])]))));
 await compare(d,[[[1,[2]],true],[[],false],[['bad'],false]]);
 assert.equal(s.recursive('loop',self=>new Ok(s.exclude(s.number(),self))) instanceof Ok,false);
 let escaped;assert.throws(()=>s.recursive('unbound',self=>{escaped=s.exclude(s.number(),self);throw new Error('stop');}),/stop/);
 assert.throws(()=>s.schema_string(escaped),/unfinalized/);assert.throws(()=>evaluate(escaped,1),/unfinalized/);
 const conflict=s.exclude(unwrap(s.named('same',s.number())),unwrap(s.named('same',s.text())));assert.throws(()=>s.schema_string(conflict),/Conflicting/);
});
