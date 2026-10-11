# 0.2.1 release preparation

This is a new patch release following 0.2.0. Only the maintainer publishes.
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
- Commit and push the reviewed source. Give the maintainer `gleam publish` only
  after the checks pass; do not run it or move existing release tags.

Public URLs for 0.2.1 are checked against locally generated destinations before
publication. They cannot be verified as live until the maintainer publishes.
Afterward, compare the actual archive and versioned HexDocs with this source.

## Boundaries

The browser scope is the desktop matrix in `docs/browser-support.md`. Regex host
Unicode drift remains explicit. Other platforms, OTP releases and deployment
tooling remain outside the recorded native matrix. Browser CI and realistic
large-contract performance measurements remain separate work; this patch makes
no new performance claim.
