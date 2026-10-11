import test from 'node:test';
import assert from 'node:assert/strict';
import {checkPackageReadme} from './package-documentation.mjs';

test('archive check rejects stale README bytes and unpublished installation wording', () => {
  const current=Buffer.from('# Library\n\nInstall Library:\n');
  checkPackageReadme(current,current);
  assert.throws(()=>checkPackageReadme(current,Buffer.from('# Older README\n')),
    /Packaged README differs/);
  for(const wording of [
    'This checkout contains the unreleased 0.2.0 candidate.',
    'After 0.2.0 is published, install it with:',
  ]) {
    const stale=Buffer.from(wording);
    assert.throws(()=>checkPackageReadme(stale,stale), /release-preparation instructions/);
  }
});
