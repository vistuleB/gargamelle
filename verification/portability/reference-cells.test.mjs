import test from 'node:test';
import assert from 'node:assert/strict';
import {run} from './runner.mjs';

test('scoped cell prototype survives process exit and cleans up exceptional scopes',()=>{
  const [reply]=run([{cells:true}]);
  assert.deepEqual(reply,{handoff:true,once_bound:true,rejection:true,cleanup:true,recursion:true,independent_types:true});
});
