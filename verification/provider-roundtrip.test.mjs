import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
test('documented provider load/save example executes on both targets',()=>{
  const guide=readFileSync(new URL('../docs/provider-roundtrip.md',import.meta.url),'utf8');
  const source=guide.match(/```gleam\n([\s\S]*?)\n```/)[1];
  assert.equal(source,readFileSync(new URL('../test/provider_roundtrip.gleam',import.meta.url),'utf8').trimEnd());
  const expected=guide.match(/```text\n([\s\S]*?)\n```/)[1];
  for(const target of ['javascript','erlang']){
    const result=spawnSync('gleam',['run','--target',target,'--module','provider_roundtrip'],{cwd:root,encoding:'utf8',timeout:60000});
    assert.equal(result.status,0,result.stderr);
    assert.equal(result.stdout.trim(),expected,target);
  }
});
