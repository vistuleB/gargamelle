import test from 'node:test';
import assert from 'node:assert/strict';
import {s,toList,unwrap} from './generated-api.mjs';

test('direct JSON constructors retain the admitted numeric and string domains',()=>{
  for(const value of [NaN,Infinity,-Infinity])assert.equal(s.json_number(value).isOk(),false);
  for(const value of ['', 'Brainy', '\ud83d\udc9c', '\0', '\"\\\n']){
    const json=unwrap(s.json_string(value));
    assert.equal(JSON.parse(s.to_string(json,s.JsonFormat$Compact$const)),value);
  }
  for(const value of ['\ud800','\udfff','before\ud800after'])assert.equal(s.json_string(value).isOk(),false);
  for(const value of [Number.MAX_VALUE,Number.MIN_VALUE,-0,1.25,9007199254740992]){
    const json=unwrap(s.json_number(value));
    assert.deepEqual(unwrap(s.decode(s.number(),json)),value);
  }
});

test('object constructors keep own hostile keys, reject duplicates and canonicalize serialization',()=>{
  const string=unwrap(s.json_string('safe'));
  const json=unwrap(s.json_object(toList([['__proto__',string],['constructor',string],['',s.json_null()]])));
  const raw=JSON.parse(s.to_string(json,s.JsonFormat$Compact$const));
  assert.equal(Object.hasOwn(raw,'__proto__'),true);assert.equal(raw.__proto__,'safe');
  assert.equal(Object.getPrototypeOf(raw),Object.prototype);
  assert.equal(s.json_object(toList([['x',string],['x',s.json_null()]])).isOk(),false);
  assert.equal(s.json_object(toList([['\ud800',string]])).isOk(),false);
});
