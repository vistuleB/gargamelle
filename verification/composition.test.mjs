import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdirSync,writeFileSync} from 'node:fs';
import {s,unwrap,toList} from './generated-api.mjs';
import {runCompositionSuite} from './composition-suite.mjs';
import {root,fingerprint} from './evidence.mjs';
import {join} from 'node:path';

test('seeded compositions preserve equivalence, non-weakening and whitelisted order',async()=>{
  const coverage=await runCompositionSuite({s,unwrap,toList});
  assert.equal(coverage.sequenceCount,32);
  assert.equal(coverage.recursiveSequences,4);
  assert.ok(coverage.separatedRepetitions.includes('dependency'));
  assert.ok(coverage.separatedRepetitions.includes('keys'));
  assert.equal(coverage.wrapperFamilies.length,7);
  mkdirSync(join(root,'reports'),{recursive:true});
  writeFileSync(join(root,'reports/composition-coverage.json'),JSON.stringify({status:'passed',source:fingerprint().digest,...coverage},null,2)+'\n');
});
