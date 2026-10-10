import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { build, evaluate, emitted } from './generated-api.mjs';
import { translate } from './official/translate.mjs';
import { compileOracle } from './oracle.mjs';
const base = new URL('./official/', import.meta.url);
const provenance = JSON.parse(readFileSync(new URL('provenance.json', base)));
const selection = JSON.parse(readFileSync(new URL('selection.json', base)));

test('official source integrity and complete selected/excluded group inventory', () => {
  assert.equal(provenance.commit, selection.commit);
  let count = 0;
  for (const file of provenance.files) {
    const bytes = readFileSync(new URL(file.path, base));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), file.sha256);
    const groups = JSON.parse(bytes);
    for (const [index, group] of groups.entries()) {
      const row = selection.groups.find(g => g.id === `${file.path}#${index}`);
      assert.ok(row); assert.equal(row.tests, group.tests.length);
      if (row.status === 'selected') assert.deepEqual(row.recipe, JSON.parse(JSON.stringify(translate(group.schema))));
      else { assert.ok(row.reason); assert.throws(() => translate(group.schema), error => error.message === row.reason); }
      count++;
    }
  }
  assert.equal(count, selection.groups.length);
});

for (const row of selection.groups.filter(g => g.status === 'selected')) {
  test(`official ${row.id}: ${row.description}`, () => {
    const [path, index] = row.id.split('#');
    const group = JSON.parse(readFileSync(new URL(path, base)))[Number(index)];
    const definition = build(row.recipe);
    const check = compileOracle(emitted(definition));
    for (const fixture of group.tests) {
      assert.equal(check(fixture.data).accepted, fixture.valid, `oracle: ${fixture.description}`);
      assert.equal(evaluate(definition, fixture.data).accepted, fixture.valid, `decoder: ${fixture.description}`);
    }
  });
}
