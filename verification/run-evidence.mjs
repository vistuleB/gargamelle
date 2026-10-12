import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { root, fingerprint, required, evidenceKind, rowEvidence, sha256, verifyCoverage } from './evidence.mjs';
import { oracleOptions } from './oracle.mjs';

if (Number(process.versions.node.split('.')[0]) !== 24) throw new Error('Evidence requires Node 24');
const reports = resolve(root, 'reports'); mkdirSync(reports, { recursive: true });
const before = fingerprint();
const run = (command, args, logfile, timeout = 180000) => {
  const r = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout, maxBuffer: 30 * 1024 * 1024 });
  const output = (r.stdout ?? '') + (r.stderr ?? '');
  writeFileSync(resolve(reports, logfile), output);
  if (r.error || r.status !== 0) throw new Error(`${command} failed; see reports/${logfile}: ${r.error ?? r.status}`);
  return output;
};
writeFileSync(resolve(reports, 'evidence.json'), JSON.stringify({ status: 'running', source: before.digest }) + '\n');
try {
  run('gleam', ['format', '--check', 'src', 'test'], 'format.log');
  const gleam = run('gleam', ['test'], 'gleam.log');
  const tests = readdirSync(resolve(root, 'verification')).filter(name => name.endsWith('.test.mjs')).sort();
  for (const evidence of Object.values(rowEvidence).flat()) {
    readFileSync(resolve(root, 'verification', evidence));
    if (evidence.endsWith('.test.mjs') && !tests.includes(evidence)) throw new Error(`Evidence test not scheduled: ${evidence}`);
  }
  const tap = run(process.execPath, ['--test', '--test-reporter=tap', ...tests.map(name => `verification/${name}`)], 'node.tap');
  const counts = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(k => [k, Number(tap.match(new RegExp(`^# ${k} (\\d+)$`, 'm'))?.[1] ?? NaN)]));
  if (!counts.tests || counts.pass !== counts.tests || counts.fail !== 0 || counts.skipped !== 0 || counts.cancelled !== 0 || counts.todo !== 0) throw new Error('Incomplete or unsuccessful Node test run');
  const coverage = JSON.parse(readFileSync(resolve(root, 'verification/generated-coverage.json'))); verifyCoverage(coverage);
  const selection = JSON.parse(readFileSync(resolve(root, 'verification/official/selection.json')));
  const after = fingerprint();
  if (before.digest !== after.digest) throw new Error('Source changed during evidence run; rerun after changes stop');
  const composition = JSON.parse(readFileSync(resolve(reports, 'composition-coverage.json')));
  const compositionMutations = JSON.parse(readFileSync(resolve(reports, 'composition-mutations.json')));
  for (const result of [composition, compositionMutations]) {
    if (result.status !== 'passed' || result.source !== after.digest) throw new Error('Missing or stale composition evidence');
  }
  if (composition.sequenceCount !== 32 || composition.recursiveSequences !== 4
      || compositionMutations.mutants.length !== 3
      || compositionMutations.mutants.some(m => m.status !== 'killed')) throw new Error('Incomplete bounded composition coverage');
  const version = (command, args) => {
    const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 10000 });
    if (result.error || result.status !== 0) throw new Error(`Cannot record ${command} version`);
    return result.stdout.trim();
  };
  const gitHead = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8', timeout: 10000 });
  const baseCommit = gitHead.status === 0 ? gitHead.stdout.trim() : null;
  const sourceCommit = baseCommit !== null && version('git', ['status', '--porcelain', '--', '.']) === '' ? baseCommit : null;
  const report = {
    status: 'passed', contractRevision: 6, scope: 'Node candidate; not a formal proof or publication approval',
    generatedAt: new Date().toISOString(), source: after, baseCommit,
    sourceCommit,
    sourceIsWorkingTreeSnapshot: true, versions: { node: process.version, gleam: version('gleam', ['--version']) },
    dependencyLockSha256: sha256(readFileSync(resolve(root, 'package-lock.json'))),
    gleamLockSha256: sha256(readFileSync(resolve(root, 'manifest.toml'))), oracleOptions,
    commands: ['gleam format --check src test', 'gleam test', `node --test --test-reporter=tap ${tests.map(n => `verification/${n}`).join(' ')}`],
    limits: { subprocessTimeoutMs: 180000, maxOutputBytes: 30 * 1024 * 1024 },
    counts: { gleam: Number(gleam.match(/(\d+) passed, no failures/)?.[1]), node: counts }, coverage,
    composition: { report: 'reports/composition-coverage.json', sha256: sha256(readFileSync(resolve(reports, 'composition-coverage.json'))), sequences: composition.sequenceCount, comparisons: composition.comparisons,
      mutations: 'reports/composition-mutations.json', mutationsSha256: sha256(readFileSync(resolve(reports, 'composition-mutations.json'))), killed: compositionMutations.mutants.length },
    conformance: { commit: selection.commit, selectedGroups: selection.groups.filter(g => g.status === 'selected').length, selectedCases: selection.groups.filter(g => g.status === 'selected').reduce((n, g) => n + g.tests, 0), excludedGroups: selection.groups.filter(g => g.status === 'excluded').length, manifest: 'verification/official/selection.json' },
    oracleExceptions: JSON.parse(readFileSync(resolve(root, 'verification/known-oracle-discrepancies.json'))),
    logs: Object.fromEntries(['format.log','gleam.log','node.tap'].map(name => [name, sha256(readFileSync(resolve(reports, name)))])),
    rows: Object.fromEntries(required.map(id => [id, { status: id === 'V08' ? 'review-required' : 'passed', kind: evidenceKind(id), evidence: rowEvidence[id] }])),
    excludedGuarantees: ['Browser/Erlang support', 'Full JSON Schema dialect support', 'Machine-checked proof', 'Production adoption/publication'],
  };
  if (!report.counts.gleam) throw new Error('No successful Gleam test count found');
  writeFileSync(resolve(reports, 'evidence.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(`Node candidate evidence passed: ${report.counts.gleam} Gleam tests; ${counts.tests} Node tests; ${coverage.pairs} generated pairs; ${report.conformance.selectedCases} official cases.`);
} catch (error) {
  writeFileSync(resolve(reports, 'evidence.json'), JSON.stringify({ status: 'failed', source: before.digest, error: String(error) }, null, 2) + '\n');
  throw error;
}
