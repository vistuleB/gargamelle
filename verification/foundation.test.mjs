import assert from 'node:assert/strict';
import test from 'node:test';
import { names, fixture_schema, fixture_decode } from '../build/dev/javascript/gargamelle/schema_fixtures.mjs';
import { Ok } from '../build/dev/javascript/gargamelle/gleam.mjs';
import { compileOracle } from './oracle.mjs';

function decode(name, value) {
  const parsed = fixture_decode(name, JSON.stringify(value));
  assert.ok(parsed instanceof Ok, `Unexpected admission error for ${name}`);
  return { accepted: parsed[0] instanceof Ok, value: parsed[0][0] };
}

// Independently authored inputs. This is a foundation corpus, not the required
// generated-definition suite, and must not be reported as completion of V02/03.
const corpus = [
  null, true, false, 0, -0, 1, -3, -2, 3, 4, 1.5,
  Number.MAX_SAFE_INTEGER, Number.MAX_SAFE_INTEGER + 1,
  '', 'a', 'b', 'ab', 'abc', 'abcd', 'a😀', '😀', 'e\u0301', '\0', '\u{10ffff}',
  [], ['a'], ['a', 'b', 'c'], ['a', 'b', 'c', 'd'], [null], [1],
  {}, { a: 'x' }, { a: null }, { a: 1 }, { a: 'x', b: null },
  { a: 'x', b: 'y' }, { a: 'x', extra: true }, { a: 'x', b: 'y', c: 'z', d: 'w' },
  { kind: 'a', value: 'x' }, { kind: 'b' }, { kind: 'unknown' }, { kind: null },
  { kind: 'a', value: 1 }, { kind: 'b', extra: true },
  { '10': 'x', '2': 'y' }, JSON.parse('{"__proto__":"x"}'),
  JSON.parse('{"constructor":"x","toString":"y"}'),
];

for (const name of names()) {
  if (name === 'hostile') continue; // Explicit Ajv limitation; independently checked by supplementary-oracle.test.mjs.
  test(`foundation differential: ${name} (${corpus.length} inputs)`, () => {
    const check = compileOracle(JSON.parse(fixture_schema(name)));
    for (const raw of corpus) {
      const value = JSON.parse(JSON.stringify(raw));
      assert.equal(decode(name, value).accepted, check(value).accepted,
        `${name}: ${JSON.stringify(value)}`);
    }
  });
}

test('hostile fixture preserves normative acceptance and characterizes retained Ajv discrepancy', () => {
  const schema = JSON.parse(fixture_schema('hostile'));
  assert.equal(Object.hasOwn(schema.properties, '__proto__'), true);
  const input = JSON.parse('{"__proto__":"x"}');
  assert.deepEqual(decode('hostile', input), { accepted: true, value: 'x' });
  assert.equal(compileOracle(schema)(input).accepted, false);
  assert.equal(decode('hostile', JSON.parse('{"__proto__":1}')).accepted, false);
});

test('decoded outputs implement defaults, branch order, presence, nullability and tags', () => {
  const cases = [
    ['optional', {}, 'None'], ['optional', { a: 'x' }, 'Some(x)'],
    ['defaulted', {}, 'fallback'], ['defaulted', { a: 'x' }, 'x'],
    ['nullable_nullable', null, 'None'], ['nullable_nullable', 'x', 'Some(Some(x))'],
    ['nullable_overlap', null, 'None'], ['any_order', 'x', 'first'],
    ['tagged', { kind: 'a', value: 'x' }, 'a:x'], ['tagged', { kind: 'b' }, 'b'],
    ['open_record', { a: 'x', extra: true }, 'x:None'],
    ['array', ['b', 'a', 'b'], '[b][a][b]'],
  ];
  for (const [name, input, expected] of cases) {
    assert.deepEqual(decode(name, input), { accepted: true, value: expected });
  }
});

test('canonical emission preserves integer-like keys and deduplicates patterns', () => {
  const text = fixture_schema('integer_keys');
  assert.equal(text, fixture_schema('integer_keys'));
  const schema = JSON.parse(text);
  assert.deepEqual(Object.keys(schema.properties), ['2', '10']);
  assert.deepEqual(schema.required, ['10', '2']);
  const patterns = JSON.parse(fixture_schema('patterns'));
  assert.deepEqual(patterns.allOf, [{ pattern: 'a', type: 'string' }, { pattern: 'b', type: 'string' }]);
});

test('tag and nullable errors use contract paths instead of synthetic union failures', () => {
  for (const [input, category, path] of [
    [{}, 'missing_required', ''], [{ kind: '?' }, 'unknown_discriminator', '/kind'],
    [{ kind: 1 }, 'discriminator_type', '/kind'],
    [{ kind: 'a', value: 1 }, 'string_type', '/value'],
  ]) {
    const result = decode('tagged', input);
    assert.equal(result.accepted, false);
    const [error] = result.value;
    assert.equal(error.category, category);
    assert.equal(error.path, path);
  }
  const [error] = decode('nullable_nullable', 1).value;
  assert.equal(error.category, 'string_type');
  assert.equal(error.path, '');
});
