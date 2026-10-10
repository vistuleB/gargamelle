import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

export function run(requests) {
  const result = spawnSync('escript', ['verification/portability/primitives.escript'], {
    input: requests.map(x => JSON.stringify(x)).join('\n') + '\n',
    encoding: 'utf8', timeout: 60000, maxBuffer: 20 * 1024 * 1024,
  });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  const responses = result.stdout.trim().split('\n').map(x => JSON.parse(x));
  assert.equal(responses.length, requests.length);
  return responses;
}

