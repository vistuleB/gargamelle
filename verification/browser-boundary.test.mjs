import test from 'node:test';
import assert from 'node:assert/strict';
import {knownUnicodeDifference} from './browser/regex-boundary.mjs';

test('browser Unicode classification permits only the recorded U+11DB0 differences', () => {
  const row={pattern:'\\p{L}',text:'\u{11DB0}',node:{valid:true,matched:false},browser:{valid:true,matched:true}};
  assert.equal(knownUnicodeDifference(row),true);
  assert.equal(knownUnicodeDifference({...row,pattern:'\\p{Assigned}'}),true);
  for(const change of [
    {pattern:'\\p{N}'},{text:'A'},{node:{valid:true,matched:true}},
    {browser:{valid:false}},{browser:{valid:true,matched:false}},
  ]) assert.equal(knownUnicodeDifference({...row,...change}),false);
});
