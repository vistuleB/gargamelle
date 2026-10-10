import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { compileSupplementary } from './supplementary-oracle.mjs';
import { compileOracle } from './oracle.mjs';
import { fixture_schema, fixture_decode } from '../build/dev/javascript/gargamelle/schema_fixtures.mjs';
import { Ok } from '../build/dev/javascript/gargamelle/gleam.mjs';

test('declared __proto__ acceptance is independently verified without changing Ajv', async () => {
  const [f] = JSON.parse(readFileSync(new URL('./known-oracle-discrepancies.json', import.meta.url)));
  const schema = JSON.parse(fixture_schema('hostile'));
  const check = await compileSupplementary(schema);
  for (const [input, expected] of [[f.instance, true], [{}, false], [JSON.parse('{"__proto__":1}'), false], [JSON.parse('{"__proto__":"x","extra":1}'), false]]) {
    assert.equal(check(input).accepted, expected);
    const actual = fixture_decode('hostile', JSON.stringify(input));
    assert.ok(actual instanceof Ok);
    assert.equal(actual[0] instanceof Ok, expected);
  }
  assert.equal(compileOracle(schema)(f.instance).accepted, f.observedAjvAcceptance);
  assert.equal(check(f.instance).accepted, f.expectedAcceptance);
});
