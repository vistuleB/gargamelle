import { readFileSync, writeFileSync } from 'node:fs';
import { translate } from './translate.mjs';
const provenance = JSON.parse(readFileSync(new URL('./provenance.json', import.meta.url)));
const groups = [];
for (const file of provenance.files) {
  const fixtures = JSON.parse(readFileSync(new URL(file.path, import.meta.url)));
  for (const [index, group] of fixtures.entries()) {
    const row = { id: `${file.path}#${index}`, description: group.description, tests: group.tests.length };
    try { row.recipe = translate(group.schema); row.status = 'selected'; }
    catch (error) { row.status = 'excluded'; row.reason = error.message; }
    groups.push(row);
  }
}
writeFileSync(new URL('./selection.json', import.meta.url), JSON.stringify({ commit: provenance.commit, groups }, null, 2) + '\n');
console.log(`${groups.filter(g => g.status === 'selected').length} selected groups; ${groups.filter(g => g.status === 'excluded').length} explicit exclusions`);
