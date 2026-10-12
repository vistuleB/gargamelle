# 0.3.0 release preparation

0.3.0 was published on 2026-10-11 from `cc57613`. The published archive has
been compared with that commit; every source member matches. The current
replacement adds `JsonFormat` with required format arguments, plus a typed
monolithic README example using `Pretty`. The maintainer explicitly requested
replacement of 0.3.0 while Hex permits it. `schema_json` returns a schema Json;
`schema_string` returns a String in the chosen layout. `Json`, `RecordPolicy` and `to_string` replace `Value`,
`Policy` and `value_text`. Previous API names are removed; callers must migrate.
Public examples and current verification callers use the preferred names.

Follow `docs/releasing.md` before publication. Require both target gates, directly
compiled README/renderer examples, removed-name compile-negative checks, schema comparisons
against the unchanged frozen baseline, fresh archive consumers, browser reports,
and Linux OTP 28/29 reports for the final commit. The baseline comparison adapts
only API names in temporary copied callers; frozen sources stay unchanged.

Only the maintainer publishes this correction, using `gleam publish --replace`
when Hex permits replacement. Exact commits, fingerprints and archive checksums
belong in `reports/release-handoff-0.3.0.json`. No existing tags or application
dependencies are changed. Current runtime qualification limits remain unchanged.

`Strict` replaces `Closed`, which is removed. `Open` is unchanged. The renderer
uses the existing “STRICT” badge. No compatibility API is retained.
