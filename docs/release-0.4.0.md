# 0.4.0 release preparation

The audit of `736466a` found that alternating object modifiers could overwrite
emitted `dependentRequired` or `propertyNames` assertions. The replacement
candidate preserves collisions as additional `allOf` clauses, including existing
conjunctions. Regression checks cover both reported cases, repeated triggers and
conditional composition against runtime validation, decoding, Ajv and Hyperjump.
Evidence from `736466a` is superseded and must not qualify the corrected archive.

The maintainer requested 0.4.0 preparation after JSON-only boundary integration.
Only the maintainer publishes, using `gleam publish` for this new version.
Current Hex metadata and the downloaded 0.3.0 archive were inspected on 2026-10-12;
0.4.0 was absent, and 0.3.0 already includes the required JSON format arguments.

The release adds typed and JSON-only boundaries, retained JSON/definition
certificates, schema metadata, dependentRequired, safe-integer divisibility, and
explicit UUID assertions. Fractional divisibility and other asserted formats
remain deferred; review decisions are in `multiple-of-policy.md` and
`format-assertion-policy.md`. The encoder stays under `verification/encoder/` and
is not a shipped API. No application dependencies, repository visibility or tags
are changed as part of this preparation.

The equation provider's current actual result definition was compiled in an
isolated JavaScript consumer and submitted to a host-owned JSON-only receiver.
Four cases checked storage acceptance and rejection, with zero conversion
callbacks and no app checkout edits. Its source checksum and observations are in
`reports/provider-json-boundary.json`.

Follow `docs/releasing.md`. Exact final source, archive hashes, review observations,
browser results and Linux run IDs belong in `reports/release-handoff-0.4.0.json`.
`reports/release-preparation.json` records the full local gate. Documentation and
archive evidence must match the final source fingerprint; earlier release
evidence does not qualify this snapshot. The README and public guides describe
library behavior rather than preparation status.
