# Release workflow

This is the authoritative checklist for preparing, reviewing and verifying a
Gargamelle release. Read it before release work. Complete each applicable step
before reporting that the package is ready.

## Responsibilities and records

The agent prepares the source, documentation, archive and verification evidence.
**The maintainer publishes the package.** Do not run `gleam publish`, use publishing
credentials, or replace a release on the maintainer's behalf.

Keep preparation status, unresolved decisions, commit IDs and archive checksums in
internal release records such as `docs/release-<version>.md` and
`GARGAMELLE_TODO.md`. Record user-facing changes, including API replacements, in the changelog. The README describes the library, its use and its limitations; it must not
contain checkout status, publication plans, agent progress or instructions to
install a version after it is published.

Repository visibility changes, application dependency upgrades and data migrations
are separate work. Do not perform them as part of release preparation.

## 1. Establish the release contents

- [ ] Confirm the intended version and whether this is a new release or a
  maintainer-requested replacement. Check the current Hex release before assuming
  that a replacement is possible.
- [ ] Align `gleam.toml`, `package.json`, and both root version fields in
  `package-lock.json`. Keep the npm package private; it is verification tooling.
- [ ] Review the changelog against the actual changes,
  including breaking changes. Check version-specific assumptions in the
  preparation script, source/archive URLs and documentation links. The script
  explicitly checks the candidate version; update that guard for a new release.
- [ ] Check compiler and dependency requirements against the evidence. Do not
  widen dependency ranges or runtime support claims without compatibility checks.
- [ ] Preserve the package license, vendored regex license and provenance, and
  the license for retained JSON Schema test-suite fixtures.

JavaScript and Erlang are supported on the tested runtimes described in
[Native Erlang setup](native-erlang.md). Review that matrix and the recorded CI
results for this release. A pass on one platform does not qualify other platforms,
OTP releases, JavaScript hosts or deployment tools. Keep the native Unicode-table
version and JavaScript reference version explicit when describing regex parity.

## 2. Review the documentation as a reader

This is a required editorial pass over the complete release documentation,
not a substitute for tests and not a sequence of isolated wording fixes.

- [ ] Read the README from beginning to end. The introduction should explain the
  library plainly; installation and useful examples should precede the formal
  contract. Check paragraph order, grammar, repetition and unnecessary detail.
- [ ] Confirm that Getting Started states the minimum Gleam version, labels
  target selection and provides an adjacent Erlang setup link. Compile the README
  examples and check their documented results in a fresh consumer.
- [ ] Read the API overview and packaged guides together with the README. Their
  target support, limitations, terminology and examples must agree.
- [ ] Remove internal development commentary from reader-facing pages. Keep
  API changes and release history in the changelog. Do not fix an internal note merely by changing its tense.
- [ ] Review the configured HexDocs sidebar for reader value. Contributor test
  instructions, release gates, harness findings and implementation review notes
  belong in the source tree, not as public guide pages.
- [ ] Follow source, evidence, license and asset links without repository
  authentication. Public claims must have accessible supporting material. Use
  packaged HexDocs pages or the public Hex source archive when the repository is
  private; do not change repository visibility to repair a documentation link.
- [ ] Check links against the intended version. For new HexDocs pages, verify the
  local rendered destination before publication and the public destination
  afterward. A future URL is not evidence that a page is already available.
- [ ] Check the renderer recipe as a complete example: obtaining assets,
  producing the fragment, assembling the page and viewing the result.
- [ ] Open the generated README, API overview and changed guides in a browser.
  Inspect paragraph separation, headings, code blocks, navigation and links.
  Passing source checks alone does not establish a readable rendered page.

## 3. Run the package checks

Install pinned dependencies with `npm ci` and `gleam deps download` on first setup.
Use the tested Node reference (currently 24.10.0), Gleam 1.18.1, Erlang/OTP, `make`
and a C compiler. Once dependencies are installed, the preparation checks run
offline:

```sh
npm run prepare:release
```

The command runs the JavaScript and native gates, generates documentation, exports
the Hex archive, and exercises fresh archive consumers on both targets. It checks
licenses and vendor hashes, rejects generated/private artifacts, compares the
packaged README with the source, and checks configured documentation pages,
local links/anchors and renderer asset freshness. It does not publish.

- [ ] Inspect `reports/release-preparation.json` and its logs. Require a successful
  result for the final source snapshot; verify fingerprints, archive members,
  versions, counts and support boundaries. Failures and skipped checks must be
  resolved or explicitly recorded as release limitations.
- [ ] Inspect `build/gargamelle-<version>.tar` and the rendered documentation under
  `build/dev/docs/gargamelle`. Confirm that the README and public source match
  the reviewed files and that only intended public API modules are exposed.
- [ ] Require passing Linux qualification for the release commit through
  `.github/workflows/native-qualification.yml` when claiming the Linux matrix.
  Inspect the retained reports, not just the presence of the workflow file.
- [ ] Keep test evidence distinct from proof. `npm run check:release` checks
  JavaScript evidence only; it does not replace the full preparation command or
  independent review of the preservation arguments.

Finish edits before the final preparation run. Any subsequent source or
configuration change invalidates its fingerprint; regenerate the report before
calling the revised package ready. Do not reuse evidence from an earlier archive.

## 4. Hand off to the maintainer

- [ ] Commit and push the reviewed files when authorized. Record the exact source
  commit, prepared archive checksum and remaining limitations internally.
- [ ] Report what changed, what passed and what remains unverified. State
  explicitly that nothing was published by the agent.
- [ ] Give the maintainer the command appropriate to the requested release:
  `gleam publish` for a new version, or `gleam publish --replace` for a replacement
  when Hex permits it. If replacement is unavailable, agree on a new version and
  repeat preparation with that version.

Do not move an existing release tag without explicit maintainer instruction.
Keep tag operations tied to the reviewed source, and preserve the record of the
original archive when preparing a replacement.

## 5. Verify after the maintainer publishes

- [ ] Fetch the actual Hex release metadata and source archive. Compare its README,
  metadata and source files with the reviewed package; record the published
  checksum and corresponding source commit. A maintainer's publication report
  is not a byte comparison.
- [ ] Fetch the versioned HexDocs README, API overview and configured guides.
  Check the live content and public links separately from the archive; one can
  be updated while the other remains stale. Allow for propagation, then report
  any remaining mismatch precisely.
- [ ] Build a fresh consumer pinned to the published Hex version and exercise
  documented behavior. Verify each claimed target with its required setup.
- [ ] Record publication and replacement history in the internal release record
  and update the changelog date. Do not add publication bookkeeping to the README.
