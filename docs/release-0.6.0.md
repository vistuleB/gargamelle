# 0.6.0 release record

The qualified candidate was fast-forwarded to main at commit `95f599a`.
Hex records publication of 0.6.0 at 2026-10-12T14:34:07Z. The maintainer publishes;
no existing release tag is moved. The 0.7.0 work remains isolated on `codex/json-070`.

Scope: explicit typed encoding, checked Codec output, receiving-authority output
boundaries, and structured encoding diagnostics. The public encoding and migration
guides distinguish admitted JSON from Contract-checked output.

The provider integration compiles the application's actual provider sources in an
isolated consumer. Typed cloze output exercises real permanent and current-context
contracts, independent schema validators, callback counts, and rejection before
storage. Application sources and production dependencies are not changed.

Release records are ignored reports: `release-preparation.json`, provider integration,
browser verification, retained Linux qualification, and `release-handoff-0.6.0.json`.
Only successful records matching the final source fingerprint qualify the candidate.

Deferred: direct JSON construction, record-builder ergonomics, additional collection
helpers, and mutual encoder recursion. Serialize-then-admit is deliberate; no
single-pass or inverse claim is made. Callback exceptions remain operational.

## README replacement

The maintainer requested removal of the HTML-documentation and typed-encoder
paragraphs from the introduction. The operations table and detailed guides remain.
This replacement changes the packaged README only; source and configuration match
the qualified 0.6.0 package. Documentation and archive are regenerated and compared
with the prior archive. Runtime qualification is retained for identical source;
no unchanged runtime suite is rerun for this editorial edit. The replacement
record is `reports/readme-replacement-0.6.0.json`. Publication remains the
maintainer's action with `gleam publish --replace`.
