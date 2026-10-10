import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { compileOracle, compareAcceptance } from './oracle.mjs';

test('oracle preserves input and performs no coercion, defaults or extra-key removal', () => {
  const schema = {
    type: 'object', properties: { count: { type: 'integer', default: 1 } },
    additionalProperties: false,
  };
  const check = compileOracle(schema);
  const missing = {};
  assert.equal(check(missing).accepted, true);
  assert.deepEqual(missing, {});
  const invalid = { count: '1', extra: true };
  assert.equal(check(invalid).accepted, false);
  assert.deepEqual(invalid, { count: '1', extra: true });
});

test('oracle uses code-point lengths and Unicode regex semantics', () => {
  const check = compileOracle({ type: 'string', maxLength: 1, pattern: '^.$' });
  assert.equal(check('😀').accepted, true);
  assert.equal(check('ab').accepted, false);
  assert.equal(check('e\u0301').accepted, false);
});

test('oracle enforces one-of exclusivity and nullability independently', () => {
  assert.equal(compileOracle({ oneOf: [{ type: 'string' }, { type: 'string' }] })('x').accepted, false);
  assert.equal(compileOracle({ anyOf: [{ type: 'string', enum: ['a'] }, { type: 'null' }] })(null).accepted, true);
});

test('oracle rejects malformed schemas instead of treating them as data rejection', () => {
  assert.throws(() => compileOracle({ type: 'string', minLength: -1 }), /Invalid emitted schema/);
});

test('comparison detects both directions of mismatch and propagates crashes', () => {
  const schema = { type: 'string' };
  assert.throws(() => compareAcceptance({ schema, value: 'valid', decode: () => ({ accepted: false }) }), /Acceptance mismatch/);
  assert.throws(() => compareAcceptance({ schema, value: 42, decode: () => ({ accepted: true }) }), /Acceptance mismatch/);
  assert.throws(() => compareAcceptance({ schema, value: 42, decode: () => { throw new Error('crash'); } }), /crash/);
  assert.throws(() => compareAcceptance({ schema, value: 42, decode: () => ({}) }), /explicitly report/);
});

test('comparison rejects input mutation even when acceptance agrees', () => {
  assert.throws(() => compareAcceptance({
    schema: { type: 'object' }, value: {},
    decode: value => { value.extra = 1; return { accepted: true }; },
  }), /Input mutated/);
});

test('known oracle discrepancy remains visible and is not mistaken for contract evidence', () => {
  const [fixture] = JSON.parse(readFileSync(new URL('./known-oracle-discrepancies.json', import.meta.url), 'utf8'));
  assert.equal(Object.hasOwn(fixture.schema.properties, '__proto__'), true);
  assert.equal(Object.hasOwn(fixture.instance, '__proto__'), true);
  assert.equal(compileOracle(fixture.schema)(fixture.instance).accepted, fixture.observedAjvAcceptance);
  assert.notEqual(fixture.observedAjvAcceptance, fixture.expectedAcceptance);
  // Characterization only: the normative expected acceptance remains true.
  assert.throws(() => compareAcceptance({
    schema: fixture.schema, value: fixture.instance,
    decode: () => ({ accepted: fixture.expectedAcceptance }),
  }), /Acceptance mismatch/);
});
