import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import * as diagnostics from '../build/dev/javascript/gargamelle/gargamelle/diagnostics.mjs';
import {s,toList,None} from './generated-api.mjs';

test('diagnostic JSON rejects non-scalar application strings',()=>{
  const error=new s.Structural(toList([new s.ValidationError('custom','\ud800',None,toList([]),toList([]))]));
  assert.equal(diagnostics.to_json(error).isOk(),false);
});

test('documented diagnostic output matches on both targets',()=>{
  const guide=readFileSync(new URL('../docs/diagnostics.md',import.meta.url),'utf8');
  const source=guide.match(/```gleam\n([\s\S]*?)\n```/)[1];
  assert.equal(source,readFileSync(new URL('../test/diagnostics_example.gleam',import.meta.url),'utf8').trimEnd());
  const expected=guide.match(/```text\n([\s\S]*?)\n```/)[1];
  for(const target of ['javascript','erlang']){
    const result=spawnSync('gleam',['run','--target',target,'--module','diagnostics_example'],{
      cwd:fileURLToPath(new URL('../',import.meta.url)),encoding:'utf8',timeout:60000,
    });
    assert.equal(result.status,0,result.stderr);
    assert.equal(result.stdout.trim(),expected,target);
  }
});
