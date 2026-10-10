import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build, emitted, evaluate } from './generated-api.mjs';
import { compileOracle } from './oracle.mjs';

// Hand-authored definitions, independently of the existing provider schemas.
const text = (min, max) => ({ kind: 'string', min, max });
const constant = value => ({ kind: 'constant', value });
const integer = (min, max) => ({ kind: 'integer', min, max });
const array = (child, min, max) => ({ kind: 'array', child, min, max });
const record = (fields, open = false) => ({ kind: 'record', open, fields: Object.entries(fields).map(([name, child]) => ({ name, child })) });
const id = { ...text(undefined, 120), patterns: ['^[A-Za-z][A-Za-z0-9_-]*$'] };
const entryId = { kind: 'string', patterns: ['^[A-Za-z][A-Za-z0-9_-]{0,119}$'] };
const recipes = {
  content: record({
    id, title: text(1, 500), prompt: text(1, 500), learningVersion: integer(1, Number.MAX_SAFE_INTEGER), type: constant('cloze'),
    parts: array({ kind: 'one', children: [text(1, 500), record({ blank: id })] }, 1, 50),
    blanks: array(record({ id, label: text(1, 500), answers: array(text(1, 500), 1, 10) }), 1, 12),
  }),
  session: record({ clozeSignature: text(), responses: { kind: 'dictionary', child: text(undefined, 500), max: 12 } }, true),
  result: record({ type: constant('cloze'), version: constant(1), data: record({
    entries: array(record({ blankId: entryId, response: text(undefined, 500), accepted: array(text(1, 500), 1, 10), correct: { kind: 'boolean' } }, true), 1, 12),
    correct: integer(0, 12), total: integer(1, 12),
  }, true) }),
};
const valid = {
  content: { id: 'card_1', title: 'Title', prompt: 'Fill the blank', learningVersion: 1, type: 'cloze', parts: ['A ', { blank: 'a' }], blanks: [{ id: 'a', label: 'A', answers: ['answer'] }] },
  session: { clozeSignature: 'signature', responses: { a: 'answer' } },
  result: { type: 'cloze', version: 1, data: { entries: [{ blankId: 'a', response: 'answer', accepted: ['answer'], correct: true }], correct: 1, total: 1 } },
};
const replacements = [null, false, 0, -1, 1.5, '', 'x', 'x'.repeat(501), [], {}, ['x'], '😀'.repeat(500)];
function paths(value, path = []) {
  return [path, ...(value && typeof value === 'object' ? Object.entries(value).flatMap(([k, v]) => paths(v, [...path, k])) : [])];
}
function replace(value, path, next, remove = false) {
  if (!path.length) return next;
  const copy = structuredClone(value); let parent = copy;
  for (const k of path.slice(0, -1)) parent = parent[k];
  if (remove) delete parent[path.at(-1)]; else parent[path.at(-1)] = next;
  return copy;
}
function original(name) {
  return JSON.parse(readFileSync(new URL(`./fixtures/cloze-v1/${name}.schema.json`, import.meta.url)));
}

for (const name of Object.keys(recipes)) {
  test(`cloze ${name}: structural acceptance and decoded payload`, () => {
    const definition = build(recipes[name]);
    const check = compileOracle(emitted(definition));
    const old = compileOracle({ ...original(name), $schema: 'https://json-schema.org/draft/2020-12/schema' });
    let comparisons = 0;
    for (const path of paths(valid[name])) {
      for (const replacement of replacements) {
        const value = replace(valid[name], path, replacement);
        const expected = check(value).accepted;
        assert.equal(evaluate(definition, value).accepted, expected, `${name}: ${path.join('/')}`);
        assert.equal(old(value).accepted, expected, `${name}: unexpected compatibility delta at ${path.join('/')}`);
        comparisons++;
      }
      if (path.length) {
        const value = replace(valid[name], path, null, true);
        // JSON serialization removes holes in arrays as null; compare same parsed value.
        const parsed = JSON.parse(JSON.stringify(value));
        assert.equal(evaluate(definition, parsed).accepted, check(parsed).accepted);
        assert.equal(old(parsed).accepted, check(parsed).accepted);
      }
    }
    assert.ok(comparisons >= 48);
    assert.deepEqual(evaluate(definition, valid[name]), { accepted: true, value: valid[name] });
  });
}

test('cloze known compatibility differences are explicit, not silently normalized', () => {
  const content = build(recipes.content);
  const old = compileOracle(original('content'));
  const unsafe = { ...valid.content, learningVersion: Number.MAX_SAFE_INTEGER + 1 };
  assert.equal(old(unsafe).accepted, true);
  assert.equal(compileOracle(emitted(content))(unsafe).accepted, false);
  assert.equal(evaluate(content, unsafe).accepted, false);
  const astral = { ...valid.content, title: '😀'.repeat(500) };
  assert.equal(astral.title.length, 1000); // Existing provider implementation uses UTF-16 length.
  assert.equal(old(astral).accepted, true);
  assert.equal(evaluate(content, astral).accepted, true);
  assert.equal(evaluate(content, { ...valid.content, hostDerived: true }).accepted, false);
});

test('open session/result project extras; structural decoding does not add semantic grading', () => {
  const session = build(recipes.session);
  assert.deepEqual(evaluate(session, { ...valid.session, extra: true }).value, valid.session);
  const result = build(recipes.result);
  const input = structuredClone(valid.result); input.data.extra = true; input.data.entries[0].extra = true;
  assert.deepEqual(evaluate(result, input).value, valid.result);
  const semanticMismatch = structuredClone(valid.result); semanticMismatch.data.correct = 0;
  assert.equal(evaluate(result, semanticMismatch).accepted, true); // Counts-vs-entries is a separate semantic check.
});
