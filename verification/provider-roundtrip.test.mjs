import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
test('provider fixture accepts valid load/save and rejects semantic violations on both targets',()=>{
  // Keep the behavioral regression independently of the public guide layout.
  // The fixture asserts both load and save rejection before printing these lines.
  const expected='{"answers":[true,false],"score":1}\nLoad rejected: score does not match answers\nSave rejected: score does not match answers';
  for(const target of ['javascript','erlang']){
    const result=spawnSync('gleam',['run','--target',target,'--module','provider_roundtrip'],{cwd:root,encoding:'utf8',timeout:60000});
    assert.equal(result.status,0,result.stderr);
    assert.equal(result.stdout.trim(),expected,target);
  }
});
