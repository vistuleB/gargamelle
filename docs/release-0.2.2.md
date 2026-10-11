# 0.2.2 release preparation

Only the maintainer publishes this new patch release. It carries the public-guide
cleanup not included in the original 0.2.1 archive, and the revised README
introduction and symmetric target setup. There are no runtime or API changes.

## Required evidence

Follow `docs/releasing.md`. Require final-source local preparation, fresh archive
consumers on JavaScript and Erlang, browser reports, and both Linux OTP jobs.
Inspect rendered README, API overview and guides, including the static renderer
image, configured sidebar and consolidated licenses. Keep fingerprints, archive
checksums, final source commit and CI run in `reports/release-handoff-0.2.2.json`.

## Publication

The maintainer command is `gleam publish`, after all preparation gates pass.
Versioned 0.2.2 links are checked against local generated destinations before
publication. Verify the actual Hex archive and live HexDocs after the maintainer
publishes. Do not move existing release tags or update application dependencies.

## Scope

Runtime support remains the documented Node/browser and macOS/Linux OTP matrix.
Other runtimes and deployment tools remain unqualified. Preservation arguments
and test evidence are not a formal proof. The browser result transport now uses
streaming UTF-8 decoding; a request split inside an emoji is retained as a
regression check. Browser hash-navigation checks must start from a fresh URL.
