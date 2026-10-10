# Gargamelle handoff and next work

Recorded 2026-10-10; updated through development checkpoint `eaae20a`.
This is a handoff and prioritized candidate list, not a commitment to implement
all JSON Schema features. Verify external state before acting on it.

## Current checkpoint

- Package: `gargamelle`, version `0.2.0` in development, MIT license.
- Repository: https://github.com/vistuleB/gargamelle (private when last checked).
- Annotated tag `v0.1.0` remains at `0d15a7a`
  (`Improve onboarding, lineage, and renderer documentation`); it was pushed.
  Graph integration was committed locally on `main` as `08fd1b2`.
  Scalar admission and native regex research were committed as `eaae20a`.
  The previous code/evidence checkpoint is `ef8841b`.
- Documentation cleanup is complete: onboarding precedes the contract, the intro
  credits glon's influence and independent implementation, the comparison is
  concise, limitations are explicit, app notes are removed, and the renderer
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
The working version is 0.2.0, with contract/evidence revision 4. Nothing has been
published or tagged for this milestone.

The standalone native regex experiment found an empirical candidate: QuickJS
2026-06-04 regex code with the two Unicode table files from 2025-09-13 agrees with
Node 24/Unicode 16 in 13,572 pairs, including operational-failure handling through
an Erlang port. Each unmodified release has retained counterexamples. No native
dependency or production regex binding has been added. See
`docs/erlang-portability.md` for the decision, reproduction, archive/source hashes
and the remaining packaging/conformance work.

Next: broaden native regex conformance and package its binding, then extend
independent cross-target oracles and clean consumer tests. Complete Erlang support
remains gated on the two regex externals.

Current checkpoint validation passed: 36 JavaScript-target Gleam tests, 144 Node
tests, 17,788 generated pairs and 109 official cases; nine native portability
checks, including 43 actual Erlang Gleam API tests with only regex test adapters.
The native regex candidate passed 13,572 pairs under address/undefined-behavior
sanitizers. Docs generation, Hex export and a fresh JavaScript consumer of the
extracted 0.2.0 archive passed using the pinned dependency sources offline.

## Read these first

1. `README.md`: concise overview, contract, installation, examples and glon comparison.
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

`npm run verify:erlang-primitives` runs ten independent portability test groups,
including the isolated immutable-plan experiment. The current library graph
group fails on the three captured-placeholder regressions described below.
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

**Current blocker (2026-10-10):** this design does not preserve a builder
placeholder captured in a decoded closure. New typed tests pass on JavaScript
but fail on Erlang for self recursion, mutual recursion and transfer after the
creator exits. The native graph fixture now has 43 passes and three failures;
the JavaScript suite has 38 passes. Keep these as failing Erlang regressions,
replace the reference ownership design, and demonstrate reclamation as well as
process-independent use before claiming Erlang support. Do not silently restrict
callback outputs or introduce a permanent cell registry. See decision 5 in
`docs/erlang-portability.md` for the mechanism and alternatives. This supersedes
the successful root-transfer evidence below for independently captured references.

The isolated plan/environment prototype in `verification/portability/plans`
now passes seventeen behavioral tests per target, eight compile-negative checks,
native creator-exit handoff and 984 independent schema cases per target. Run
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
Deep branch selection still rescans validated subtrees. Bounded native copying
shows substantial amplification for repeatedly shared branches (261 sender words
to 36,576 receiver words at six layers); the realistic provider transfers and uses
889 receiver words. Shared emission also expands repeated unnamed branches.
The library has not been rewritten. Next, prototype private validation evidence
for typed conversion, measuring callback suppression, defaults, exclusive unions,
handoff and retained term sizes. Then integrate with the production checker and
emitter incrementally, preserving naming/conflict and canonical-byte policies.

The actual Erlang fixture runs 35 shared Gleam tests and seven additional typed
API tests against a temporary library copy. It covers recursive and mutually
recursive outputs, transfer after creator exit, composition of independent
contexts, defaults, rejection, conflicting names, shared graph construction,
builder/converter exceptions and restoration of an enclosing construction scope.
It attaches experimental scalar parsing/canonicalization and native regex only
in that copy; it does not claim full Erlang semantics. The production source
still rejects an Erlang build through its unsupported admission/string/regex
externals. Integration found and fixed an unscoped default-check traversal and
OTP signed-zero exact-equality differences in constants and number endpoints.
Retained shared tests cover zero-sign equality and repeated exclusive bounds.

Regex counterexamples are retained in `verification/portability/regex-baseline.test.mjs`:
native dot/whitespace handling and accepted pattern syntax differ from ECMAScript
`u`. QuickJS's standalone `libregexp` is a candidate exact engine, per its
[primary documentation](https://bellard.org/quickjs/quickjs.html). It is C code,
so a native binding would introduce build/distribution work. Node v24.10.0 uses
Unicode 16.0; engine/table-version compatibility must also be checked. No native
engine dependency has been added and no shared subset has been selected.

Next implementation work: finish exact ECMAScript regex compatibility and native
canonical emission, then extend independent cross-target oracle
verification. Keep parser/regex support gated until their admitted
string representation and engine choices preserve the contract or receive an
explicit versioned amendment. Do not publish or move `v0.1.0` for this work.

### Complete external inventory

`src/gargamelle.gleam` now declares 18 JavaScript externals, all supplied by
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
| `with_construction` | Implemented: frozen native typed registry; no-op scope on JavaScript closure cells. |
| `with_context` | Implemented: install/restore frozen native context; no-op on JavaScript. |
| `with_walk` | Implemented: bracket native traversal registry on all exits; no-op on JavaScript closure state. |
| `recursive_cell` | Implemented typed once-bound reference state, irreversible rejection and frozen cross-process context. |
| `identity_tracker` | Implemented walk-local identity set keyed by explicit node IDs. |
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
