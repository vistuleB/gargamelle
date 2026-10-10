import { readdirSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../', import.meta.url));
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export const evidenceKind = id => id === 'V08' ? 'tests-and-reviewed-argument' : 'automated-tests';
export const required = Array.from({ length: 13 }, (_, i) => `V${String(i + 1).padStart(2, '0')}`);
export const rowEvidence = {
  V01: ['contains.test.mjs', 'property-names.test.mjs', 'tuple.test.mjs', 'recursion.test.mjs', 'numbers.test.mjs', 'extensions.test.mjs', 'generated.test.mjs', 'generated-values.test.mjs', 'foundation.test.mjs'],
  V02: ['extensions.test.mjs', 'hardening.test.mjs', 'generated.test.mjs', 'conformance.test.mjs', 'supplementary-oracle.test.mjs'],
  V03: ['hardening.test.mjs', 'generated.test.mjs', 'conformance.test.mjs', 'supplementary-oracle.test.mjs'],
  V04: ['hardening.test.mjs', 'generated-values.test.mjs', 'foundation.test.mjs', 'cloze.test.mjs'],
  V05: ['compile-negative.test.mjs', 'generated-values.test.mjs'],
  V06: ['generated.test.mjs', 'generated-values.test.mjs', 'conformance.test.mjs'],
  V07: ['generated-values.test.mjs', 'supplementary-oracle.test.mjs', 'cloze.test.mjs'],
  V08: ['generated.test.mjs', '../PRESERVATION.md'],
  V09: ['conformance.test.mjs', 'official/provenance.json', 'official/selection.json'],
  V10: ['contains-mutations.test.mjs', 'property-names-mutations.test.mjs', 'tuple-mutations.test.mjs', 'recursion-mutations.test.mjs', 'number-mutations.test.mjs', 'generated-mutations.test.mjs', 'oracle.test.mjs'],
  V11: ['cloze.test.mjs'],
  V12: ['generated-runtime.test.mjs', 'compile-negative.test.mjs'],
  V13: ['foundation.test.mjs', 'generated-values.test.mjs', 'generated-runtime.test.mjs'],
};

export function fingerprint() {
  const files = [];
  function visit(directory) {
    for (const item of readdirSync(directory, { withFileTypes: true })) {
      if (['build', 'node_modules', 'reports', '.git'].includes(item.name)) continue;
      const path = resolve(directory, item.name);
      if (item.isDirectory()) visit(path);
      else if (item.name !== 'generated-coverage.json') files.push(path);
    }
  }
  visit(root);
  const hashes = Object.fromEntries(files.sort().map(path => [relative(root, path), sha256(readFileSync(path))]));
  return { digest: sha256(JSON.stringify(hashes)), files: hashes };
}

export function verifyCoverage(coverage) {
  if (!(coverage.decodedValues > 1000) || !Object.keys(coverage.nodePaths ?? {}).length) throw new Error("Missing decoded-value or nested-path evidence");
  if (coverage.pairs < 10000 || coverage.seeds.length !== 10 || new Set(coverage.seeds).size !== 10 || coverage.depth50 < 12) throw new Error('Generated corpus below contract thresholds');
  for (let depth = 0; depth <= 6; depth++) if (!coverage.depths[depth]) throw new Error(`Missing depth ${depth}`);
  const kinds = ['boolean','null','string','integer','enum','constant','number','recursive','array','dictionary','record','nullable','any','one','tagged','description','title','map','tuple','property_names','contains'];
  for (const kind of kinds) {
    if (!coverage.constructors[kind] || !coverage.outcomes[`${kind}:true`] || !coverage.outcomes[`${kind}:false`]) throw new Error(`Missing constructor/outcome coverage ${kind}`);
    if (!coverage.nestedOutcomes?.[`${kind}:true`] || !coverage.nestedOutcomes?.[`${kind}:false`]) throw new Error(`Missing nested outcome evidence ${kind}`);
    for (const parent of ['array','dictionary','record','nullable','any','one','tagged','description','title','map','tuple','property_names','contains']) {
      if (!coverage.edges[`${parent}>${kind}`]) throw new Error(`Missing edge ${parent}>${kind}`);
    }
  }
}
