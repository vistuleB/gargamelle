# Verification and development

This guide describes the verification harness and its evidence. The intended
public semantics are specified separately in the [technical contract](https://github.com/vistuleB/gargamelle/blob/main/docs/contract.md).

## Setup and checks

Use Gleam 1.18.1 or later and Node 24 (enforced by npm scripts; other Node majors are unverified). Dependencies are pinned in the project
manifests and resolved lockfiles. Run `npm ci` and `gleam deps download` on first
setup, then `npm test` for the available tests. After dependencies are fetched,
tests must run offline.

Run `npm run verify` for the complete Node candidate evidence run. It checks
formatting, runs Gleam and Node tests, enforces generated coverage thresholds, and
writes `reports/evidence.json` with source hashes, dependency versions, logs,
conformance selection and per-row evidence. After fetching dependencies, this
command runs offline. `npm run check:release` accepts only a successful report
whose source fingerprint and logs are unchanged. It does not approve publication
or claim a mathematical proof.

The harness currently retains a known Ajv 8.20.0 discrepancy for a declared
`__proto__` property in a closed record. Its characterization test passing means
the discrepancy remains visible, not that Ajv agrees in this case. Pinned Hyperjump
1.18.0 checks every generated definition/input pair, as well as the dedicated
`verification/supplementary-oracle.test.mjs` fixtures. A split is classified only
when renaming the declared hostile key restores Ajv agreement; unexplained splits
fail verification. The generated report counts classified splits. This explicitly documented exception
does not change schemas, decoder behavior or Ajv options. See
`verification/known-oracle-discrepancies.json`.

## Verification coverage

Verification covers generated inputs, mutations, runtime behavior, typed outputs,
compile-negative cases, independent validators, selected official JSON Schema
cases and cloze payload compatibility. The generated suite includes 10,000
seeded pairs, all 345 generic parent/child combinations and fourteen depth-50 chains.
Thirty-one actual compiled-library mutations must fail behavioral assertions,
including five numeric, three recursion, and three tuple, and three key-constraint, and three membership, and three conditional, and three exclusion mutants. The three
new revision-3 mutations run the full foundation, typed-value and hardening suites.
Twenty forbidden Gleam programs must fail compilation after a positive baseline.

The official suite is pinned to commit
`7de0e6a06031ede80028583dd45d0cd41105ae5b`. All 46 core files are retained with
hashes and licence. `verification/official/selection.json` identifies 27 selected
groups and 357 exclusions with reasons. No unsupported schema is strengthened to
make it fit our constructors. Optional suite collections and full-dialect
conformance are not claimed. Existing cloze schemas are frozen from checkpoint `ceb244a` for independent compatibility comparisons; safe-integer limits and the provider's UTF-16 length difference
are explicitly exercised.

See [PRESERVATION.md](https://github.com/vistuleB/gargamelle/blob/main/PRESERVATION.md) for constructor reasoning and
[generated notes](https://github.com/vistuleB/gargamelle/blob/main/verification/generated-notes.md) for failure retention,
shrinking, and implementation findings. `reports/evidence.json` is the current
verification result; it is generated locally and excluded from source control.
The original contract document's unverified status records its specification-time
state, not the current candidate report. Browser/Erlang support and broader production adoption remain unverified.

## Output and evidence details

`dictionary(child)` decodes to a Gleam `List(#(String, a))` (key/value pairs),
not a JavaScript object. The test adapter explicitly maps that list to an object.

Generated checks compare decoded output with an independent recipe interpreter,
including optional presence, defaults, nullable values, union selection and maps.
Coverage records visits and outcomes by definition-node path, and requires both
acceptance and rejection for every constructor at nested positions. This is a
bounded corpus, not exhaustive path coverage for every generated definition.

Reports distinguish automated evidence from V08's preservation argument, which
remains `review-required`. File existence is not proof of that argument. A report
always identifies a hashed working-tree snapshot; Git commit fields are null when the checkout has no Git history. `sourceCommit` is null when the
relevant source is uncommitted, with `baseCommit` retained for context. After a
checkpoint commit, regenerate evidence to identify the containing commit.


## Erlang portability primitives

With Erlang/OTP 29 installed, run `npm run verify:erlang-primitives` for the
experimental native numeric, admission, serialization, and reference-cell checks.
These compare Erlang operations directly with Node and retain native-regex
counterexamples. They are separate from the JavaScript verification gate and do
not establish support for a complete Erlang backend. The admission experiments
cover Unicode-scalar strings; lone surrogates remain an unresolved compatibility
issue.

The same command runs an isolated Erlang build of the actual library and all
shared Gleam tests, plus typed recursion, process-transfer, composition, conflict
and exception-cleanup tests. The fixture attaches scalar admission and native
regex adapters only to its temporary source copy. Those adapters are test
scaffolding and do not establish ECMAScript regex or lone-surrogate parity.
Production source retains the unsupported-target gate for those operations.
