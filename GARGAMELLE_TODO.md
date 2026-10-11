# Gargamelle handoff and next work

0.3.0 preparation is tracked in `docs/release-0.3.0.md`. It introduces
`schema_json` and `schema_string`, replacing `emit_json` and `emit_text`. `Json`, `RecordPolicy` and `to_string` replace `Value`,
`Policy` and `value_text`. Previous API names are removed. Core semantics are unchanged.
The preceding 0.2.2 replacement handoff is retained in ignored reports.
The maintainer publishes.

Recorded 2026-10-10; updated through 0.2.0 release candidate preparation.
This is a handoff and prioritized candidate list, not a commitment to implement
all JSON Schema features. Verify external state before acting on it.

## Current checkpoint

- Package: `gargamelle`, version `0.2.0` published 2026-10-11, MIT license.
- Repository: https://github.com/vistuleB/gargamelle (private when last checked).
- Published 0.2.0 source is `41d2948`, verified against the downloaded Hex archive.
  Annotated tag `v0.2.0` identifies that exact checkpoint; later verification and
  repository status edits are separate commits.
- Annotated tag `v0.1.0` remains at `0d15a7a`
  (`Improve onboarding, lineage, and renderer documentation`); it was pushed.
  Graph integration was committed locally on `main` as `08fd1b2`.
  Scalar admission and native regex research were committed as `eaae20a`.
  The previous code/evidence checkpoint is `ef8841b`.
- Documentation cleanup is complete: onboarding precedes the contract, the intro
  credits glon's influence and independent implementation, the comparison section
  is removed, limitations are explicit, app notes are removed, and the renderer
  recipe includes asset downloads, a complete HTML shell and a rendered sample.
  A HexDocs license page fixes the README license link.
- The files are in `gargamelle/`, but Git metadata remains in `concord/.git`.
  Until this is repaired, use explicit `--git-dir` and `--work-tree` arguments.
  The unchanged `.gitignore` has been copied into `gargamelle/` so build outputs
  remain ignored. Do not commit generated artifacts.
- The user reported republishing 0.1.0. A direct fetch of its HexDocs confirmed
  the earlier onboarding and lineage edits, but subsequent README edits were
  made locally afterward. Do not assume the published docs match `0d15a7a`.
  No publication was performed by this agent.
- Final automated evidence passed at `ef8841b`: 34 Gleam tests, 142 Node tests,
  17,788 generated pairs and 109 selected official cases. Docs generation,
  Hex tarball export and release checks passed. Earlier clean consumers of the
  extracted archive built and exercised decoding, validation, schema emission
  and documentation without the app checkout or npm verification tools.
- This handoff was committed in `08fd1b2` and is not in `v0.1.0`.

## Current 0.2.0 work

The user authorized a common Unicode-scalar string/key domain on 2026-10-10.
Unpaired surrogates are final-domain admission errors on JavaScript and Erlang;
valid pairs are preserved exactly. Syntax and duplicate replacement precede
domain checking, so an overwritten invalid value is discarded. The native
parser now owns string escapes as well as structural and numeric scanning.
Production Erlang externals are attached for admission, canonical emission,
code-point counting and UTF-16 sorting. Public construction text is checked too: Result constructors
return construction errors; direct constructors assert the scalar precondition.
The working version is 0.2.0, with contract/evidence revision 5. The maintainer published 0.2.0 on 2026-10-11 from `41d2948`; the downloaded
archive matches every exported file. The release tag identifies that checkpoint.

The native regex binding now vendors standalone QuickJS 2026-06-04 code with
Unicode 16 tables from 2025-09-13. Source hashes and patches are retained under
`priv/regex-src`. An expanded property-alias sweep exposed four extra accepted
names; the corrected backend agrees with Node 24 in 55,282 pairs under sanitizers,
including 598 selected Test262 Boolean `u` projections. This is bounded evidence,
not a complete Test262 run. The actual binding passes 594 direct cases and keeps
native/resource failures operational through auxiliary constraints and defaults.

Immutable plans and private conversion evidence are integrated into main.
All core externals now have native implementations. Native fixtures use the real
regex helper, without regex test adapters. Current validation: 45 JavaScript
Gleam tests, 144 Node tests, 17,788 generated pairs and 109 official schema cases;
53 native tests, twelve cross-target compile-negative checks and 3,636 independent
cases across 36 schemas. All seventeen current portability groups pass.

Fresh consumers of the extracted 0.2.0 archive pass on both targets using pinned
dependency sources offline. Native setup requires an explicit C build. Generated
binaries stay outside `priv`; release deployments must install the helper. The
consumer exposed an integer/float decoding bug in optional rendering, now fixed
with a shared regression. See `docs/native-erlang.md` and the reviewed decisions
in `docs/erlang-portability.md`.

Provider-shaped workload measurements found about 887 ms for decoding 64 records
with four patterned fields. A native-only change now lazily reuses one helper per
validation walk, reducing that observation to about 10.5 ms. The plain control
remains about 0.3 ms. Shared Gleam and JavaScript sources/API are unchanged from
`af9acc5`. Port cleanup precedes conversion callbacks; nested scopes, exceptions,
resource failure recovery and idle/active owner exit have retained regressions.
See `docs/regex-workload-measurements.md` for methods and reproduction. No compiled
pattern cache or permanent worker service was introduced.

The generated native gate now covers the same 886 definitions and 17,788 input
cases as the JavaScript corpus, with Ajv and Hyperjump checking emitted schemas
and an independent interpreter checking 6,459 decoded outputs. Typed cross-target
runs agree on schemas, outputs and full diagnostics. An always-match native
regex mutation is detected through five API paths. A macOS Gleam shipment works
after the helper is explicitly installed and all source checkouts are removed.
See `docs/native-oracle-evidence.md` for scope and reproduction.

Release preparation now has a single offline command, `npm run prepare:release`.
It checks both target gates, docs, archive contents and fresh extracted-archive
consumers, and records hashes and logs in `reports/release-preparation.json`.
`CHANGELOG.md`, the migration guide and `docs/release-0.2.md` describe the candidate
and audit findings. Versioned links target 0.2.0 and become available on publication.
No release tag, push or publication is included. The recommendation remains to
finish native platform qualification before claiming broad Erlang support; a
JavaScript release with a native preview is a separate support-scope decision.

The 27 selected official schema groups now run through the actual typed library
on both targets: all 109 unchanged cases pass (38 accepted, 71 rejected), with
original and emitted schemas checked by Ajv and Hyperjump. The official provenance
and all 357 excluded groups remain unchanged. Native qualification CI is prepared
for Ubuntu 24.04 x86_64 with OTP 28 and 29. The initial hosted run passed
all groups except the regex comparison: a floating Node 24 selection chose
24.21.0/Unicode 17, whereas native tables use Unicode 16. CI now pins the verified
24.10.0 reference; Unicode 17 parity remains unclaimed. No complete hosted pass
was recorded at that checkpoint. The corrected run 38132699640 now passes both
Linux jobs on OTP 28.5.0.7 and 29.1.1. Downloaded fingerprints and log hashes
match commit `715b8f0`; see `docs/linux-qualification.md`.
See `docs/native-ci.md` for scope, version policy and evidence review.

Next: declare the tested native matrix for release, extend native operator
mutation coverage when needed, and check other release tooling. Measure representative application workloads
before optimizing further. Windows is unverified and the helper currently uses
POSIX APIs. Complete Erlang support remains gated on these checks.
Do not publish or move `v0.1.0` for this work.

## Read these first

1. `README.md`: overview, contract, installation, examples and lineage.
2. `docs/contract.md`: complete intended 0.2.0 development semantics, without
   implementation history or verification procedures. This is the public contract.
3. `PRESERVATION.md`: constructor-by-constructor design arguments, not formal proofs.
4. `docs/verification-guide.md` and `verification/generated-notes.md`: evidence,
   retained findings, independent validators and verification machinery.
5. `docs/releasing.md`: publication procedure. Its preparation observations are
   historical; recheck current publication and repository visibility.
6. `docs/verification.md`: original revision-3 design/verification specification.
   It retains specification-time status and some obsolete deferred-feature lists;
   use `docs/contract.md` for consolidated public semantics.
7. `docs/advanced.md` and generated API documentation: advanced construction examples.
8. `docs/erlang-portability.md`, “Decisions for independent review”: implemented
   choices, experimental candidates, alternatives and remaining evidence gaps.
   In particular, investigate successful builder placeholders captured in returned
   closures before claiming reference-lifetime parity.

## Recommended next priority: Erlang support

The user wants Erlang support, but agreed to publish 0.1.0 as a tested JavaScript
reference milestone first. The proposed next milestone is 0.2.0 with verification
on both targets. That is a recommendation, not an implemented backend or a promise.
Do not resume broad vocabulary expansion ahead of the portability investigation.

Start with a read-only portability audit and a concrete implementation plan:

- Inventory every JavaScript external in `src/gargamelle.gleam` and
  `src/runtime.mjs`, including imports of generated runtime modules.
- Identify which operations can move to shared Gleam and which require Erlang
  externals. Most schema traversal and typed conversion should remain shared.
- Check the parser behavior of `gleam_json` on Erlang and the runtime/compiler
  tooling available in the new workspace. Do not assume its admission semantics
  match `JSON.parse` on edge cases.
- Examine `src/gargamelle/documentation.gleam` separately; rendering should stay
  optional and should not introduce application or host-lifecycle dependencies.
- Present unresolved semantic choices before weakening the published contract.

The hard requirements are semantic parity, not merely successful compilation:

- **Numbers:** Erlang supports arbitrary-sized integers; the current public
  model is parsed binary64 and explicit safe-integer limits. Decide how admission
  preserves rounding, underflow, overflow and signed-zero behavior. Never silently
  make acceptance depend on the target.
- **Strings and regex:** lengths count code points, and patterns use ECMAScript
  Unicode `u` search semantics. Erlang's native regex engine is not automatically
  equivalent. Investigate exact compatibility, a stated supported subset, or an
  explicit contract amendment; do not substitute an engine and claim parity.
  Include lone-surrogate admission/representation differences in the audit.
- **Canonical emission:** current ordering is UTF-16 sorting followed by JavaScript
  index-key enumeration and compact JSON serialization. Required arrays have
  their own sorted order. Defaults and hostile keys must be preserved. Consider
  whether identical schema values or identical text is intended across targets;
  any change to existing byte-stability rules needs explicit treatment.
- **Recursion:** private typed reference cells finalize once; rejected references
  remain invalid. Graph traversal uses identity tracking and an active/completed
  guard to avoid exponential rescanning. Find an Erlang representation that
  preserves these invariants without generic typed-value casts or hidden depth caps.
- **Failures:** syntax/domain admission errors, construction errors, data rejection
  and operational failures remain separate. Exceptions/timeouts must not become
  successful validation rejection or conditional/exclusion branch selection.

Build target-specific primitive tests first, then run shared typed and rejection
fixtures on both targets. Add a cross-target corpus checking admission, acceptance,
outputs, errors and emission. Retain the existing independent Node schema-validator
harness; adapt its library invocation so Erlang results are independently compared
without running the JavaScript decoder as an Erlang substitute. Include mutations
and callback-suppression checks. Claim Erlang support only after evidence exists.

## Initial Erlang portability audit — 2026-10-10

The following records the initial audit and implementation stages. The current
0.2.0 work above supersedes unresolved string-domain and attachment status here.

Status: initial audit complete; numeric and graph Erlang externals implemented,
with primitive and actual typed API experiments verified. The full backend remains unavailable. No JavaScript public
semantics or support claims changed.

### Tooling and baseline

Installed: Gleam 1.18.1, Node v24.10.0, Erlang/OTP 29, and `rebar3`.
`gleam build --target erlang` fails with unsupported-target errors propagated
from the JavaScript-only externals. This is the expected baseline, not evidence
of an unrelated compiler failure.

The pinned `gleam_json` 3.1.0 Erlang FFI delegates to OTP `json:decode/1` and
requires OTP 27+. Its normal public parse API does not expose the OTP custom
number/object decoder hooks. Local source inspection and executable probes,
not the JavaScript decoder standing in for Erlang, supplied the observations.
Retained probe: `verification/erlang-portability-probe.escript`; run it from the
repository with `escript verification/erlang-portability-probe.escript` after
fetching dependencies. It exercises pinned gleam_json and native OTP primitives;
it is not a Gargamelle backend test or a release verification gate.

| JSON input / operation | JavaScript reference | Pinned gleam_json / OTP 29 |
|---|---|---|
| `9007199254740993` | Rounded to `9007199254740992` | Exact integer `9007199254740993` |
| `1e400` | Nonfinite-domain admission error | Syntax-style `UnexpectedSequence` |
| `1e-400` | Zero | Float zero |
| `-0` | Negative-zero number (serialization becomes `0`) | Integer zero; sign lost |
| `-0.0` | Negative-zero number | Negative-zero float |
| `"\ud800"` | Admitted lone surrogate | `UnexpectedEndOfInput` |
| `{"a":1,"a":2}` | Last value: 2 | First value: 1 |
| Unicode `^.$` on U+2028 | No match with ECMAScript `u` | Match with `re`'s `unicode` option |
| Serialize float 1.0 | `1` | `1.0` |
| Serialize float 1e-7 | `1e-7` | `1.0e-7` |
| Serialize negative zero | `0` | `-0.0` |

The JavaScript number output was checked through local Gargamelle parse/value
serialization; regex behavior was checked directly on each engine. Signed zero
also follows the inspected JavaScript parser path; text serialization alone
cannot distinguish it. These are selected probes, not an exhaustive corpus.

### Primitive implementation progress

Implemented `src/gargamelle_runtime.erl` and attached Erlang implementations for
`integer`, `finite`, `as_int`, `as_float`, and `int_text`. The JavaScript externals
remain unchanged. Experimental helpers implement original-token binary64 parsing,
ECMAScript number notation, UTF-16 sorting, scalar code-point counting, and scalar
JSON admission/canonical serialization. The admission/canonical/string helpers
are deliberately not attached to the public API while surrogate compatibility
is unresolved.

`npm run verify:erlang-primitives` runs seventeen independent portability test groups,
including the isolated immutable-plan and production integration experiments. The current library graph
group passes with the new construction-plan contract. The earlier captured-
placeholder failures are recorded historically below.
It requires Erlang/OTP 29 for the current evidence and is separate from the
JavaScript verification gate, so JavaScript-only development does not gain an
Erlang prerequisite. The runner compiles native modules in memory, exchanges JSON
requests with `escript`, and does not substitute JavaScript library behavior for
native operations.

Coverage includes 4,000 generated decimal tokens, about 15,000 binary64 formatting
cases including neighbors of powers of ten, safe integer conversion, signed zero,
700 generated scalar JSON objects, malformed/truncated JSON, control escapes,
last-write-wins duplicate keys, discarded overflow values, hostile property names,
UTF-16 key ordering, JavaScript index-key enumeration, and nested nonfinite values.
These are empirical parity checks on OTP 29, not a proof of every numeric input
or every supported OTP release.

Important findings from the adapter experiment:

- OTP's custom integer callback receives `0` for integer-token `-0`; the scanner
  has already discarded the sign. Custom callbacks cannot recover it.
- OTP catches arbitrary float-callback exceptions and reclassifies them as
  `UnexpectedSequence`. Do not use throwing callbacks for domain admission or
  permit them to swallow operational failures.
- Therefore the experimental adapter now owns structural/number-token scanning,
  using OTP only to decode already-delimited scalar string tokens. It defers
  nonfinite-domain rejection until after syntax validation and duplicate-key
  replacement, matching the parsed-value admission model.
- OTP encodes control escape hex digits in uppercase; the prototype uses its own
  JSON string escaping to preserve JavaScript's lowercase canonical bytes.

`verification/portability/reference_cells.erl` demonstrates a possible lifetime
solution without ETS or cell servers: bracket construction state in a private
process-dictionary scope, freeze an immutable registry into the resulting
reference context, and install/restore that context around each operation.
Native tests cover double-binding rejection, irreversible rejection within the
constructed registry, exceptional/nested cleanup, self-recursive converters,
mutual converters with independent output shapes, and transfer after the creator
process exits. The prototype is retained as a direct primitive check. Its design
is now integrated into the shared Definition/Node graph and the native runtime:
explicit fresh identities, transparent context wrappers, frozen typed registries,
and bracketed walk state. No generic casts, cell servers or ETS ownership are used.

**Historical blocker (superseded by main integration):** this design does not preserve a builder
placeholder captured in a decoded closure. New typed tests pass on JavaScript
but fail on Erlang for self recursion, mutual recursion and transfer after the
creator exits. The native graph fixture now has 44 passes and three failures;
the JavaScript suite has 39 passes. Keep these as failing Erlang regressions,
replace the reference ownership design, and demonstrate reclamation as well as
process-independent use before claiming Erlang support. Do not silently restrict
callback outputs or introduce a permanent cell registry. See decision 5 in
`docs/erlang-portability.md` for the mechanism and alternatives. This supersedes
the successful root-transfer evidence below for independently captured references.

The isolated plan/environment prototype in `verification/portability/plans`
now passes twenty behavioral tests per target, twelve compile-negative checks,
native creator-exit handoff and 1,142 independent schema cases per target. Run
`node --test verification/portability/immutable-plans.test.mjs`. See
`docs/immutable-recursion-prototype.md` for the realistic API comparison and
acceptance results. Curried records, optional/default fields, heterogeneous
tuples, separately compiled helper inference and independent nested construction
are covered. Tagged unions, nullable/dictionary children, descriptions and bounds
compose in a provider helper. Schema lookup is private; helper signatures need
only a generic recursion parameter. Scope-aware node identities and immutable
memo dictionaries eliminate measured exponential shared construction work, with
a retained 26-layer case. Reference bindings use identities, not display names.
Conditional, exclusion, contains and property-name probes now preserve base
outputs without executing auxiliary converters. The remaining production APIs
and diagnostics have a source-based migration map in the prototype report.
Private structural evidence now selects typed conversion after whole-input
validation. Converters no longer retain schema lookup or call validation.
At depths 8/32/64, native decode work is roughly 500/1,900/3,800 reductions,
down from 1,900/22,500/85,000. Evidence occupies 76/292/580 native heap words.
The six-layer shared transfer now occupies 5,271 receiver words (previously
36,576); the provider occupies 310 (previously 889). Shared copying and emission
still expand repeated branches. The report documents the evidence/memory tradeoff,
exclusive unions, default receipts, operational failures and exact old-fixture
comparison. This design has now been promoted to the main library.

Main now preserves full DataError paths and branch diagnostics, naming/conflict
policies and canonical schema bytes under immutable recursion. It passes
45 JavaScript tests, 53 native tests, twelve cross-target compile-negative checks
and 3,636 independent cases across 36 schemas. Exact schema text, decoded outputs
and diagnostics match the historical baseline and native runner. The runner
checks the retained baseline source hash. Native regex now uses the vendored QuickJS binding; platform and performance
checks remain before an Erlang support claim. See
`docs/production-recursion-integration.md` and `docs/migration-0.2.md`.

Main removes construction cells/registries, keeps temporary scope-aware walk
caches, and preserves native input-object ordering. Retained regressions cover
captured-plan graph sharing, immutable process handoff, builder/converter
exceptions, distinct mutual outputs and callback suppression. The old positive
runnable-placeholder tests are retained in Git history at `511d5ae`; current
compile-negative tests establish the explicit API change. Documentation and Hex
export pass, and a fresh JavaScript archive consumer exercised recursive helpers,
`lift`, closures, emission and rendering offline. A fresh archive consumer now passes on both targets with an explicit native
helper build and unmodified library source. Previous integration
findings also retain zero-sign equality and repeated exclusive-bound tests.

Regex counterexamples are retained in `verification/portability/regex-baseline.test.mjs`:
native dot/whitespace handling and accepted pattern syntax differ from ECMAScript
`u`. QuickJS's standalone `libregexp` is a candidate exact engine, per its
[primary documentation](https://bellard.org/quickjs/quickjs.html). It is C code,
so a native binding would introduce build/distribution work. Node v24.10.0 uses
Unicode 16.0; engine/table-version compatibility must also be checked. The standalone engine is now vendored with an explicit native build; no restricted
shared regex subset has been selected.

Next implementation work: measure regex workload cost, verify native platform and
release packaging, and extend independent cross-target oracle verification. Keep parser/regex support gated until their admitted
string representation and engine choices preserve the contract or receive an
explicit versioned amendment. Do not publish or move `v0.1.0` for this work.

### Complete external inventory

`src/gargamelle.gleam` now declares 15 JavaScript externals, all supplied by
`src/runtime.mjs`:

| External | Porting treatment |
|---|---|
| `parse` | Target-specific admission adapter; number tokens, duplicate keys, string representation and error classification need explicit handling. |
| `canonical` | Prefer a shared serializer over Value, avoiding a second parse. Needs ECMAScript number formatting, escaping and key enumeration for byte parity. |
| `codepoints` | Shared Unicode scalar counting is feasible only after the lone-surrogate policy is settled. Do not substitute grapheme length. |
| `pattern_valid` | ECMAScript `u` syntax validation; native `re` is not equivalent. |
| `pattern_matches` | ECMAScript `u` search, with operational errors escaping. |
| `sorted` | Shared comparator explicitly implementing UTF-16 code-unit ordering; native binary ordering is insufficient. |
| `integer` | Numeric-integrality predicate; retain safe-integer bounds separately. |
| `finite` | Numeric-domain primitive with target-specific representation checks. |
| `as_int` | Checked primitive Float-to-Int conversion after structural validation. |
| `as_float` | Int-to-binary64 conversion; public construction arguments must be reviewed for Erlang's larger integer domain. |
| `int_text` | Numeric text primitive; inspect all callers before replacing with Erlang integer formatting. |
| `fresh_identity` | Implemented with JavaScript Symbols and Erlang references; `same_reference` now compares these in shared Gleam. |
| `with_walk` | Implemented: bracket native traversal registry on all exits; no-op on JavaScript closure state. |
| `identity_tracker` | Implemented walk-local identity set keyed by primitive binding-scope and node IDs. |
| `recursion_guard` | Implemented active/completed state shared across roots to avoid rescanning shared subgraphs. |

`runtime.mjs` imports `Ok`, `Error` and `toList` from generated `gleam.mjs`, and
`AdmissionError` from generated `gargamelle.mjs`. The parser also receives typed
Value constructor factories from Gleam. Erlang adapters should similarly receive
typed factories or return explicitly typed primitives; no generic casts.

The structural validators, record/tuple builders, converter composition,
conditional/exclusion selection and schema graph traversal are already Gleam.
Keep them shared. Numeric literals, equality, safe bounds, default checks and
ordering still need two-target tests even where there are no externals.

`src/gargamelle/documentation.gleam` has no direct externals or host-lifecycle
requirements. It reparses emitted schema text through gleam_json, sorts object
entries with `string.compare`, and renders numeric constants/defaults. Admission,
number formatting and string/order differences therefore affect rendering too.
Keep it optional; test it independently after core portability. Renderer byte
identity is a separate question from canonical schema byte identity.

### Implementation sequence

1. Resolve the representation and compatibility choices below. Freeze a common
   admitted-domain specification before changing target declarations.
2. Build a target primitive corpus for token-to-binary64 rounding, signed zero,
   huge literals, underflow, overflow, duplicate/hostile/index keys, surrogates,
   code-point counting, regex syntax/search, and canonical text.
   Preserve error categories and paths; exact parser wording need not be equal
   unless explicitly added to the contract.
3. Prototype a dedicated admission adapter. OTP's custom integer/float callbacks
   can consume original numeric tokens; custom object accumulation can implement
   last-write-wins. These hooks alone do not solve lone-surrogate representation
   or prove ECMAScript decimal rounding. Avoid catch-all admission errors.
4. Introduce explicit node identities and thread immutable walk state through
   shared graph traversal. Prototype typed recursive references separately.
   Unscoped process dictionaries fail cross-process use; ETS or servers introduce ownership,
   cleanup and lifecycle questions. Do not choose either as an invisible shortcut.
   No generic value casts or schema-author callbacks with invented values.
5. Implement shared UTF-16 ordering and canonical Value serialization, plus
   target numeric primitives and the selected regex compatibility strategy.
   Preserve JavaScript index-key enumeration, required-array ordering, negative
   zero serialization, defaults and hostile property names.
6. Add Erlang externals only after the primitives pass. Run the shared typed,
   rejection, recursive, invalidation, shared-graph and callback-suppression
   fixtures on both targets. Include definitions passed to another Erlang process.
7. Extend independent Node oracle orchestration to launch an Erlang runner which
   returns normalized admission, validation, decoded fixture output, errors and
   emitted schema. Ajv/Hyperjump must validate those Erlang-emitted schemas against
   the same admitted data. Retain mutations and generated compositions; never
   route Erlang validation through the JavaScript decoder.
8. Verify optional rendering, clean Erlang/JavaScript consumers and packaging.
   Refresh evidence and documentation before making a 0.2.0 support claim.

### Decisions required before implementation

- **Lone surrogates (resolved for 0.2.0):** the published 0.1.0 domain explicitly admits them, but ordinary
  Erlang Gleam Strings use UTF-8. Rejection on Erlang alone breaks parity, and
  replacement characters break preservation. A shared domain amendment or a
  carefully specified representation/API change is required. Recommendation:
  investigate a common Unicode-scalar admission domain for a new version; do not
  silently narrow 0.1.0. The user subsequently authorized the common scalar domain
  for 0.2.0; see the current-work section above.
- **Regex:** native `re` substitution fails even the small probe above. Choose an
  exact ECMAScript-compatible implementation or explicitly amend the contract to
  a defined shared subset in a new version. Recommendation: investigate an exact
  engine first; do not implement the subset before measuring consumer needs and
  documenting syntax/behavior exclusions. A required JavaScript subprocess is
  not a standalone Erlang backend.
- **Canonical text:** retain existing byte rules as the default implementation
  goal. Value-equivalent JSON alone is insufficient under the current contract.
  Changing those rules requires an explicit versioned contract decision.
- **Reference lifetime:** finalized definitions must remain usable beyond their
  constructing process. Evaluate explicit immutable graph/reference designs
  before accepting mutable runtime ownership. This is an implementation research
  question; no published invariant should be weakened to simplify it.

Primary references: [OTP JSON decoder hooks](https://www.erlang.org/doc/apps/stdlib/json.html#decode/3)
and [OTP regex documentation](https://www.erlang.org/doc/apps/stdlib/re.html).
The observed behavior above is from local OTP 29; do not infer every supported
OTP release from the currently hosted documentation.

## Invariants that future work must preserve

For a finalized definition S and admitted x, under pure/total callbacks and
sufficient runtime resources:

```text
Valid202012(emit_json(S), x)
    ⇔ validate(S, x) = Ok(Nil)
    ⇔ ∃v. decode(S, x) = Ok(v)
```

Successful output must also satisfy the definition's value contract. Validation
and emission do not run user converters. Construction does not probe callbacks
with invented values. Maps change output, not acceptance. Auxiliary structural
constraints retain base output and never execute their own converters. Defaults
are checked JSON inputs and apply only on absence; input is not mutated.

There is a schema text/JSON round trip, not an automatic typed decode/encode inverse.
Open-record projection, defaults and arbitrary maps may lose wire information.
Do not advertise universal proof, full-dialect support, arbitrary callback safety
or bounded resource use. The release gate explicitly keeps the preservation
argument subject to human review.

## Implemented feature inventory

The following are complete at the 0.1.0 checkpoint, not new TODOs:

- Primitives, safe integers, enums/constants, arrays, dictionaries, static typed
  records, defaults/options, nullable, maps, any-of/one-of and tagged variants.
- Finite fractional numbers and inclusive/exclusive bounds.
- Named definitions, unique arrays, guarded self recursion and recursive pairs.
- Exact-length typed tuples, property-name constraints and array membership.
- Structural conditionals and exclusion, preserving base decoded outputs.
- Optional HTML documentation and checked input examples with indexed errors.
- Shared-branch recursion-guard performance fix from the v0.0.3 audit.
- Narrow mapped-number property-name oracle exception from the v0.0.5 audit.

## Remaining candidates, driven by concrete demand

After portability, prioritize actual consumer requirements over keyword counts:

- `patternProperties` or schema-constrained extra record properties.
- General typed intersections or dependent-field conveniences with precise outputs.
- Format annotations/assertions with explicit semantics and validator configuration.
- Optional/rest tuple positions or larger heterogeneous recursive groups.
- Better union headings and stable structured diagnostics.
- Renderer-neutral documentation only when a second output format is needed.
- Browser verification and realistic large-contract performance measurements.
- `multipleOf`, fractional constants or broader JSON constants when needed.
- Explicit typed encoding and evolution/migration helpers only with stated laws;
  arbitrary decoding callbacks cannot be automatically inverted.

Arbitrary schema import, remote/dynamic references and full Draft 2020-12 support
are separate projects, not implicit completion criteria for this package.

## App integration boundaries

The sibling `equation-flashcards` repository contains the original
`CONCORD_TODO.md`; it is historical context and was not renamed by this handoff.
The app's dependency remained pinned to an older Concord commit during library
work. Recheck its current state before migration; another chat may be editing it.
Old imports are intentional for that old revision. Renaming the repository does
not imply upgrading the app, changing payload acceptance or rewriting stored data.

App-side candidates include scheduler persisted-state contracts and newer provider
constraints. Keep structural parsing separate from application checks such as
reference existence, grading consistency, uniqueness across records and migrations.
A fresh app build after dependency migration is a separate verification task.

## Working and release procedure

Use Gleam 1.18.1 or later and Node 24 for current verification. The npm package is
private tooling; library consumers need only the Gleam dependencies. Exact Hex
dependency versions reflect the tested first release; widening them needs evidence.

```sh
npm ci
gleam deps download
npm run verify
npm run check:release
gleam docs build
gleam export hex-tarball
```

After dependencies are fetched, verification runs offline. Generated evidence and
build artifacts are ignored; retained counterexamples are source-controlled.
The report fingerprints the source: regenerate it after changes and after a commit
when the evidence must identify that commit. Release checks passing are test evidence,
not a mathematical proof or a publication authorization.

The user has preferred separate commits/tags for completed milestones. Do not move
an already published version to new code. Before publishing, verify the current
Hex state, versions, license, generated documentation and clean-consumer build.
Do not publish, change repository visibility or migrate app behavior merely because
this handoff lists those possibilities; use the active user's instructions.

## Communication preferences

Use factual, information-only language. Avoid conversational validation, praise
and filler. A question alone is not authorization to edit or commit; answer it
first. Explicit imperative requests authorize the requested work. Keep public
docs reader-facing: describe the package and its contract rather than the agent's
progress or anticipated publication state.

## Post-release work — 2026-10-11

0.2.0 is published; preserve its tagged source and admission/recursion contracts.
The archive checksum is recorded in `docs/release-0.2.md`. Repository release-status
edits happen after publication and do not modify the Hex archive. While consumer
feedback is pending, extend native mutation evidence in temporary compiled copies.
No new schema features or Unicode-table upgrades are included in that work.

The native operator mutation group now detects six independently compiled mutants:
one-of ambiguity, present-null optional output, closed-record extra keys, an
inclusive minimum, code-point counting and integer conversion. Schemas stay
unchanged; assertion failures must come from acceptance or decoded outputs, not
compilation or runtime crashes. A restored baseline is checked after each mutant.
This is bounded evidence, not complete native mutation coverage.

## Public documentation cleanup — 2026-10-11

The 0.2.0 archive fetched during the audit already contains the corrected README;
the stale-archive finding was outdated. A further documentation-only replacement
is being prepared: typed records precede the contract, setup names both targets
and the compiler minimum, and API prose names the tested runtime matrix.
Preservation arguments, generated notes, renderer assets and the test-suite license
are configured HexDocs pages. Public source metadata points to the Hex archive
rather than generating inaccessible GitHub links. Repository visibility is unchanged.

Release preparation now compares packaged README bytes with the source, rejects
obsolete unpublished-installation wording, and checks configured pages, local
links/anchors and renderer asset freshness. A retained negative test exercises
stale archive content and stale installation wording. Only the maintainer publishes.
Browser verification is recorded in `docs/browser-verification.md`: Chrome 155,
Firefox 157 and Safari 27 passed the typed tests, generated corpus and DOM checks.
The reusable loopback harness retains fingerprints and full results. Its two
explicit Unicode-table differences are bounded exceptions, not a browser/native
regex equivalence claim. Browser CI, mobile/older engines and realistic
large-contract performance measurements remain open.

`Strict` replaces `Closed`, which is removed. `Open` is unchanged. The renderer
uses the existing “strict fields” badge. No compatibility API is retained.
