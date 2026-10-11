import assert from 'node:assert/strict';

export function checkPackageReadme(source, packaged) {
  assert.equal(packaged.toString('utf8'), source.toString('utf8'),
    'Packaged README differs from the current source');
  assert.doesNotMatch(packaged.toString('utf8'),
    /This checkout contains the unreleased|After \d+\.\d+\.\d+ is published/i,
    'Packaged README contains release-preparation instructions');
}
