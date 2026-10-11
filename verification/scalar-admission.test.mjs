import test from 'node:test';
import assert from 'node:assert/strict';
import {s,Ok,unwrap,toList} from './generated-api.mjs';

test('scalar admission checks final strings and keys after syntax and duplicate replacement',()=>{
  for(const text of [
    '"\\ud800"','"\\udfff"','"\\ud800x"','"x\\udfff"','"\\ud800\\ud800"',
    '["\\udc00"]','{"x":{"y":"\\ud800"}}','{"\\ud800":1}',
    '{"x":0,"x":"\\udfff"}','{"\\ud800":1,"\\ud800":2}',
    '"'+String.fromCharCode(0xd800)+'"',
  ]) {
    const result=s.parse(text);
    assert.equal(result instanceof Ok,false,text);
    assert.equal(result[0][0],'non-scalar string',text);
  }
  for(const text of [
    '"\\ud800\\udc00"','"\\udbff\\udfff"','"💜"','"e\\u0301"',
    '"\\\\ud800"','{"x":"\\ud800","x":"valid"}',
    '{"x":["\\udfff"],"x":null}','{"💜":1}',
  ]) {
    const admitted=unwrap(s.parse(text));
    assert.deepEqual(JSON.parse(s.to_string(admitted)),JSON.parse(text),text);
  }
  for(const text of ['["\\ud800",]','"\\ud800\\uXX00"','{"x":"\\ud800"}x']) {
    const result=s.parse(text);
    assert.equal(result instanceof Ok,false,text);
    assert.match(result[0][0],/^syntax:/,text);
  }
});

test('schema constructors reject non-scalar text without changing their return types',()=>{
  const invalid=String.fromCharCode(0xd800);
  for(const result of [
    s.string_enum(toList([invalid])),s.pattern(s.text(),invalid),
    s.required(s.record(x=>x),invalid,s.text()),
    s.optional(s.record(x=>x),invalid,s.text()),
    s.tagged(invalid,toList([s.variant('ok',s.record('ok'),new s.Strict())])),
  ]) assert.equal(result instanceof Ok,false);
  for(const build of [
    ()=>s.string_constant(invalid),()=>s.title(s.text(),invalid),
    ()=>s.description(s.text(),invalid),()=>s.variant(invalid,s.record('x'),new s.Strict()),
    ()=>s.variant_description(s.variant('ok',s.record('x'),new s.Strict()),invalid),
  ]) assert.throws(build,/Unicode scalar values/);
  assert.ok(s.string_enum(toList(['💜','e\u0301'])) instanceof Ok);
});
