import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { root, fingerprint, required, evidenceKind, rowEvidence, sha256, verifyCoverage } from './evidence.mjs';

try {
  const report = JSON.parse(readFileSync(resolve(root, 'reports/evidence.json')));
  if (report.status !== 'passed' || report.contractRevision !== 5) throw new Error('No successful revision-5 evidence run');
  if (report.source.digest !== fingerprint().digest) throw new Error('Evidence is stale after source changes');
  for (const id of required) {
    if (report.rows[id]?.status !== (id === 'V08' ? 'review-required' : 'passed') || report.rows[id]?.kind !== evidenceKind(id) || JSON.stringify(report.rows[id].evidence) !== JSON.stringify(rowEvidence[id])) throw new Error(`Incomplete evidence mapping for ${id}`);
  }
  for (const [name, digest] of Object.entries(report.logs)) {
    if (sha256(readFileSync(resolve(root, 'reports', name))) !== digest) throw new Error(`Evidence log changed: ${name}`);
  }
  verifyCoverage(report.coverage);
  console.log('READY FOR REVIEW: standalone Node candidate passed automated evidence checks; V08 preservation argument requires human review. Not a formal proof or publication approval.');
} catch (error) {
  console.error(`NOT READY: ${error.message}. Run npm run verify.`);
  process.exitCode = 1;
}
