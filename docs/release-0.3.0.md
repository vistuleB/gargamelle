# 0.3.0 release preparation

The user requested clearer schema function names and version 0.3.0 for the next
publication. `schema_json` returns a schema Json; `schema_string` returns its
canonical JSON String. `Json`, `RecordPolicy` and `to_string` replace `Value`,
`Policy` and `value_text`. Every previous name remains a deprecated alias.
Public examples and current verification callers use the preferred names.

Follow `docs/releasing.md` before publication. Require both target gates, directly
compiled README/renderer examples, alias compatibility checks, schema comparisons
against the unchanged frozen baseline, fresh archive consumers, browser reports,
and Linux OTP 28/29 reports for the final commit. The baseline comparison adapts
only API names in temporary copied callers; frozen sources stay unchanged.

Only the maintainer publishes, using `gleam publish` for this new version. There
is no replacement deadline. Exact commits, fingerprints and archive checksums
belong in `reports/release-handoff-0.3.0.json`. No existing tags or application
dependencies are changed. Current runtime qualification limits remain unchanged.
