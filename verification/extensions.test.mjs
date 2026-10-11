import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,Some,None,evaluate,emitted} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
async function compare(d,values){const schema=emitted(d),a=compileOracle(schema),h=await compileSupplementary(schema);for(const raw of values){const v=JSON.parse(JSON.stringify(raw));assert.equal(evaluate(d,v).accepted,a(v).accepted);assert.equal(evaluate(d,v).accepted,h(v).accepted);}}

test('named finite definitions preserve decoding and emit bounded reusable DAGs',async()=>{
 let d=s.text();for(let i=0;i<21;i++)d=unwrap(s.named('level-'+i,s.array(d)));
 assert.equal(Object.keys(emitted(d).$defs).length,21);assert.ok(s.schema_string(d).length<3000);
 let valid='x';for(let i=0;i<21;i++)valid=[valid];
 await compare(d,[valid,[],null,[[false]],'x']);
 for(const name of ['', 'a/b','a~b','__proto__','name\n'])assert.equal(s.named(name,s.text()).isOk(),false);
});

test('conflicting named definitions fail emission, including conflicts hidden behind reused parents',()=>{
 const one=unwrap(s.named('same',s.text())),two=unwrap(s.named('same',s.boolean()));
 const direct=unwrap(s.any_of(toList([one,two])));
 assert.throws(()=>s.schema_string(direct),/Conflicting named schema definitions/);
 const parent=d=>unwrap(s.named('parent',s.array(d)));
 assert.throws(()=>s.schema_string(unwrap(s.any_of(toList([parent(one),parent(two)])))),/Conflicting named schema definitions/);
 const repeated=unwrap(s.any_of(toList([one,one])));assert.equal(Object.keys(emitted(repeated).$defs).length,1);
});

test('unique array values use JSON equality, not object identity or property order',async()=>{
 let record=s.record(x=>y=>[x,y]);record=unwrap(s.required(record,'x',s.safe_integer()));record=unwrap(s.optional(record,'y',s.text()));
 const d=unwrap(s.unique_items(s.array(s.finish(record,s.Policy$Closed$const))));
 await compare(d,[[],[{x:1},{x:2}],[{x:1},{x:1}],[{x:1,y:'a'},{y:'a',x:1}],null,[{x:1},{x:1,y:'a'}]]);
 assert.equal(evaluate(d,[{x:1},{x:1}]).accepted,false);
 const ints=unwrap(s.unique_items(unwrap(s.bounds(s.array(s.safe_integer()),new Some(1),new Some(3)))));
 await compare(ints,[[],[0,-0],[1,1.0],[1,2],[1,2,3],[1,2,3,4],false]);
 assert.equal(s.unique_items(s.text()).isOk(),false);
});
