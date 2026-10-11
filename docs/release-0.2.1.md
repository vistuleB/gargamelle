# 0.2.1 publication and replacement record

The maintainer published 0.2.1 on 2026-10-11 at 19:19:49 UTC
(3:19:49 PM EDT), from commit `5015a8981bf2937c0897250642c394b69b1e51a6`.
Hex reports archive SHA-256
`8ced43de361f030540093f1a4df4384975881ef8ced1e8eda3ff997b29155234`,
matching the original prepared archive. Original metadata, archive and evidence
are retained under `reports/published-0.2.1/`.

This replacement cleans up public documentation: contributor verification and
implementation notes stay in the source tree, runtime guides are shorter, license
notices are consolidated, and the renderer guide includes a static screenshot
instead of an unstyled sample page. Only the maintainer publishes.
The release scope is documentation, HTML renderer presentation and additional
verification. Admission, decoding, schema emission, recursion construction and
native helper semantics remain unchanged. No application dependency is changed.

## Required evidence and handoff

- `reports/release-preparation.json`: final source fingerprint, archive checksum,
  both target gates, documentation links/assets and fresh archive consumers.
- `reports/browser-verification/`: frozen compiled modules, source fingerprint,
  full Chrome/Safari/Firefox results and explicitly classified Unicode differences.
- Linux qualification: both Ubuntu 24.04 OTP jobs must pass for the release commit.
  Download their artifacts and inspect the preparation reports before handoff.
- Rendered README, API overview, changed guides and the standalone renderer page
  must be inspected. README examples are exercised by fresh archive consumers.
- Commit and push the reviewed source. Give the maintainer `gleam publish --replace` only
  after the checks pass; do not run it or move existing release tags.

Hex permits replacement within one hour of initial publication: the deadline
is 2026-10-11 at 20:19:49 UTC (4:19:49 PM EDT). See
https://hex.pm/docs/publish. Replacement has not been performed by the agent.

The replacement pages are checked against locally generated destinations.
After the maintainer replaces the release, compare the actual archive and
versioned HexDocs with this source. Final source fingerprints, commit IDs and
archive checksums belong in `reports/release-handoff-0.2.1.json`.

## Boundaries

The browser scope is the desktop matrix in `docs/browser-support.md`. Regex host
Unicode drift remains explicit. Other platforms, OTP releases and deployment
tooling remain outside the recorded native matrix. Browser CI and realistic
large-contract performance measurements remain separate work; this patch makes
no new performance claim.

## Superseded preparation

The documentation replacement candidate was not published. Hex metadata fetched
on 2026-10-11 still matches the original archive checksum above. Subsequent
README edits invalidate the replacement evidence. A separate 0.2.1 checkout was
built for optional maintainer-only documentation publication; its path is recorded
in `reports/docs-publish-0.2.1-path.txt`. The source package cleanup is carried
forward into 0.2.2. Do not use the old replacement handoff as release approval.
