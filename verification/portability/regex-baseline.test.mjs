import test from 'node:test';
import assert from 'node:assert/strict';
import {run} from './runner.mjs';

// Counterexamples to native-engine substitution, not backend implementation tests.
test('native Erlang re cannot replace the ECMAScript u engine unchanged',()=>{
  const cases=[
    {pattern:'^.$',text:'\u2028'},
    {pattern:'^\\s$',text:'\ufeff'},
    {pattern:'^\\S$',text:'\ufeff'},
    {pattern:'\\a',text:'a'},
    {pattern:'(?i)a',text:'A'},
    {pattern:'\\u{1F49C}',text:'💜'},
    {pattern:'^a$',text:'a\n'},
    {pattern:'\\p{L}+',text:'é'},
    {pattern:'^.$',text:'💜'},
    {pattern:'[',text:''},
  ];
  const native=run(cases), javascript=cases.map(({pattern,text})=>{
    try{return {valid:true,matched:new RegExp(pattern,'u').test(text)};}
    catch(error){if(error instanceof SyntaxError)return {valid:false};throw error;}
  });
  // Syntax and matching both need compatibility handling.
  assert.notDeepEqual(native[0],javascript[0]);
  assert.notDeepEqual(native[1],javascript[1]);
  assert.notDeepEqual(native[2],javascript[2]);
  assert.notDeepEqual(native[3],javascript[3]);
  assert.notDeepEqual(native[4],javascript[4]);
  assert.deepEqual(native[8],javascript[8]);
  assert.deepEqual(native[9],javascript[9]);
});
