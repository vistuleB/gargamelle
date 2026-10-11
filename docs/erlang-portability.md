# Erlang string and regex investigation

Recorded 2026-10-10; updated after main-source recursion integration at `900040e`.
The native regex binding is now implemented. Platform and performance gates remain
open; this is not an Erlang support claim or a change to the published package.

## String boundary and authorized 0.2.0 decision

The 0.1.0 contract admits lone UTF-16 surrogates and promises exact decoded
`String` values. Gleam's Erlang String is a UTF-8 binary. The retained
`verification/portability/string-representation.escript` exercises the same OTP
functions used by the pinned Gleam string and JSON externals. A valid astral
scalar works. Encoding a surrogate as WTF-8 or raw UTF-16 makes string length,
lowercase and JSON encoding raise operational errors. Returning the literal
six-character sequence `\ud800` produces valid UTF-8 but changes the value.
Replacing it with U+FFFD also changes the value. Neither is a compatible String
implementation. See the [Gleam externals guide](https://gleam.run/documentation/externals/).

Authorized decision for 0.2.0: admit JSON whose final string values and object
keys contain only Unicode scalar values, on both targets. Keep all valid surrogate
pairs, with no normalization or replacement. Unpaired surrogates produce a domain
admission error after JSON syntax and duplicate-key resolution, just as nonfinite
numbers do. Keep decoded `String` output and the current constructor API.
Document the domain change explicitly; leave 0.1.0 and its tag unchanged.

The alternative is preserving the full JavaScript domain through a new opaque
UTF-16 text API, including dictionary keys and affected record/string outputs.
That would require an API redesign and explicit conversion into ordinary Gleam
String. An internal parser adapter cannot supply that public representation.
The user authorized the scalar domain on 2026-10-10. It is now implemented in
JavaScript admission and the native Erlang parser. Metadata marks the working
tree as 0.2.0 in development; no 0.2.0 publication or tag has been created.

## Standalone regex experiment

QuickJS's [standalone libregexp](https://bellard.org/quickjs/) does not require
the JavaScript interpreter. The retained C probe calls that library directly and
exchanges length-prefixed packets through an Erlang port. Pattern bytes are UTF-8;
input is explicit UTF-16, preserving both pairs and lone surrogates in this
experiment. Syntax failure, match/no-match and operational failure are separate.
A deliberately exhausted execution budget returns operational failure, and the
same port handles its next request successfully.

The corpus has 13,572 pattern/input pairs: syntax restrictions, anchoring,
whitespace, astral and surrogate matching, backreferences, named groups and
duplicate names, lookaround, quantifiers, scoped flags, generated compositions,
and Unicode properties with Unicode 16/17 boundary characters. Node v24.10.0
with Unicode 16.0 is the reference.

- QuickJS 2025-09-13 rejects duplicate named groups allowed by Node.
- QuickJS 2026-06-04 supports that syntax but its Unicode 17 tables differ from
  Node's Unicode 16 property matches.
- QuickJS 2026-06-04 with `libunicode-table.h` and `unicode_gen_def.h` from
  2025-09-13 had zero differences in this corpus. No engine code was patched.

That original corpus was bounded empirical evidence. The implementation now vendors
this combination under `priv/regex-src`, corrects the Unicode version macro to 16,
and excludes two binary properties that QuickJS accepts outside ECMAScript's
[property allowlist](https://github.com/tc39/ecma262/blob/main/table-binary-unicode-properties.html).
The expanded sweep found 48 discrepancies: the canonical names
`IDS_Unary_Operator`, `Modifier_Combining_Mark` and aliases `IDSU`, `MCM` were
accepted by QuickJS and rejected by Node. Those cases remain in the corpus.

The corrected sources passed 55,282 pattern/input pairs against Node 24 under
AddressSanitizer and UndefinedBehaviorSanitizer. Coverage includes positive and
negated property names/aliases from the tables, generated expressions and 598
Boolean search projections from selected Test262 programs. All 139 selected
programs passed their original assertions on Node. Native projections normalize
flags to `u` and omit unsupported flags, non-scalar patterns and long inputs;
this is not a full native Test262 run. The selection, exclusions and source hashes
are retained in `verification/portability/test262-selection.json` and the report.

The production Erlang binding uses a standalone executable, with no JavaScript
subprocess. Installation requires an explicit C build; see
[Native Erlang setup](native-erlang.md). A fresh consumer of the extracted Hex
archive passed on both targets with unmodified library source, pinned dependency
sources and the explicit native build. Integer bounds exposed a separate renderer
bug: OTP JSON decoding distinguishes integers from floats. The renderer now keeps
both types, with a shared regression for bounds and numeric constants/defaults.

## Decisions for independent review

Implementation checkpoint: `eaae20a`. “Implemented” below describes the working
code, not an approved release. The scalar-domain change was explicitly authorized
by the user; the remaining implementation choices were made by the agent or are
still proposals. Review these before claiming complete Erlang support.

### 1. Scalar domain and constructor failures — implemented

The authorized domain change preserves ordinary Gleam String outputs by rejecting
unpaired surrogates on both targets. It also excludes object keys containing
them. The compatibility cost is real: some JSON accepted by 0.1.0 is rejected by
0.2.0, even when an open record would otherwise ignore the affected field.

I extended the scalar requirement to schema text arguments so emitted schemas
remain in the admitted domain. Result-returning constructors produce construction
errors; direct constructors such as `string_constant` and `title` assert the
precondition. This preserves their return types but adds an operational failure
for invalid text. Review whether those direct constructors should instead return
Result in 0.2.0, and whether a dedicated scalar-string predicate should replace
the current JSON encode/parse check. The latter is simple but adds allocation and
couples constructor checking to the admission parser.

### 2. Final-tree domain checking — implemented

Syntax parsing and last-key-wins replacement finish before domain checks. Thus
`{"x":"\ud800","x":1}` is admitted, while the reverse order is rejected.
The native parser temporarily represents unpaired units as private WTF-8 bytes;
they must never reach public Value factories. This also preserves distinct keys
until their validity is checked. Review the scanner's escape handling and the
boundary between private intermediate data and typed public strings.

If a final tree contains both a nonfinite number and a non-scalar string, Erlang
currently prioritizes the numeric error; JavaScript reports the first encountered
domain error during conversion. Both reject admission, but their messages can
differ. I have not treated message precedence as part of parity. Decide whether
callers need a stable error category/precedence beyond AdmissionError.

### 3. Owning the native JSON scanner — implemented

OTP's default parser loses integer-token negative zero, chooses the wrong
duplicate-key value, rejects surrogates during syntax parsing, and can reclassify
number callback exceptions. I chose a dedicated structural/number/string scanner
rather than attempting to repair those results afterward. The cost is maintaining
a JSON parser and its error boundary. Native corpus checks include syntax,
duplicates, numeric extremes, every surrogate unit and generated escaped strings;
they are not exhaustive parser verification. Review whether an existing parser
with original-token access and deferred string-domain checks can replace this
code without weakening semantics. No additional public depth limit was added;
stack/resource failures remain operational.

### 4. Numeric formatting and canonical bytes — implemented

Erlang uses original decimal tokens with `binary_to_float`, and adapts OTP's
shortest float digits to ECMAScript notation thresholds. Canonical emission keeps
UTF-16 ordering, index-key enumeration and lowercase control escapes. I retained
the JavaScript byte contract rather than switching to native Erlang formatting
or accepting only value-equivalent schemas.

The seeded rounding/formatting corpus passed on OTP 29. It does not prove every
binary64 case or establish a minimum supported OTP release. Review ties in
shortest-digit selection and extreme decimal rounding across the OTP versions
we intend to support. Serialization still encodes through gleam_json, reparses,
then emits canonical text; a direct Value serializer could reduce allocations
and remove that intermediate dependency without changing the byte rules.

### 5. Scoped process dictionaries and frozen contexts — incomplete

Private construction state is bracketed in the process dictionary, frozen into
the returned definition, then installed/restored around operations. Walk state
uses the same bracketing. Fresh node identities avoid structural equality in graph
tracking. This avoids cell servers, ETS ownership and creator-process lifetime
dependencies, at the cost of ambient state and context wrappers.

**Historical cell-backend findings, superseded by the main-source migration below.**
The original regressions and implementation are retained in Git history at
`511d5ae`; the current native graph gate passes 53 tests under the new contract.

Transfer after creator exit, nested exception cleanup and independent-context
composition have typed API tests. Review reentrancy, context installation on every
traversal/conversion path, and the memory/copy cost of retaining entire registries.
Typed regression tests now establish a compatibility failure when a converter
returns a closure capturing a builder placeholder. Both self recursion and
`recursive_pair` pass on JavaScript and fail on Erlang after decoding returns.
Transferring the decoded closure to another process, after its creator exits,
also fails. The native fixture reports 44 passing tests and three failures;
the JavaScript suite reports 39 passing tests. Those failures were reproduced at `511d5ae` with `gleam test --target javascript`
and `node --test verification/portability/graph-api.test.mjs`.

The shared tests are in `test/reference_lifetime_test.gleam`; the transfer case
is in `verification/portability/graph_api_test.gleam`. They require the captured
definition to remain usable. The native gate deliberately fails until that
requirement is met; the failures are not reclassified as expected successes.

The root contains a frozen context, but the original placeholder captured by
user code does not. Its cell reads a key from the current process dictionary.
Once decoding restores the previous context, validation fails with
`ConstructionError("unfinalized recursive reference: captured")` (or `second`
for the pair). Keeping the context installed would violate scope cleanup and
would still not transfer it with the decoded closure. Adding context wrappers
to the returned root cannot change a placeholder already captured by user code.

**Decision requiring review:** preserve the existing callback and output-type
contract, and treat independently escaping placeholders as an Erlang release
blocker. A builder-only placeholder restriction would be a public semantic
change; it has not been adopted. Re-running builders or inspecting arbitrary
decoded outputs would also violate existing guarantees.

The replacement reference backend needs bindings that remain reachable from
the original placeholder, survive creator exit, and can be reclaimed after all
users release them. This is an ownership problem, not another missing traversal
wrapper. A global ETS registry could provide lookup but needs an explicit
lifetime policy: [OTP documents](https://www.erlang.org/docs/28/apps/stdlib/ets.html)
that tables are not garbage-collected when references disappear. A permanent
registry has not been added. NIF resources have
[garbage-collected resource terms](https://www.erlang.org/doc/apps/erts/erl_nif.html),
but a proposed cell implementation must also demonstrate collection when stored
converter closures refer back to their own cells; resource reclamation alone
does not establish that property. No replacement ownership design is implemented
or claimed leak-free.

An isolated replacement experiment now compiles and passes on both targets.
It uses typed construction plans, explicit recursion environments and immutable
completed bodies. Self recursion, an independently typed pair, native handoff,
callback suppression, defaults and compile-negative cases are exercised. See
[the prototype report](immutable-recursion-prototype.md) for its API comparison,
1,142-case independent schema checks per target, and limits. Curried record/tuple
builders and generic helpers now compile without public schema lookup types.
The user authorized main-source integration after this experiment. The new
construction-plan contract is now implemented in the main library; it is an
explicit 0.2.0 API migration, not a transparent fix to the old lifetime promise.
The migration guide documents the loss of independently runnable builder
references while preserving ordinary closure outputs and completed-definition
lifetimes. No code has been published.

Provider helpers now cover tagged unions, nullable/dictionary children and
modifiers. The prototype uses native node/reference identities and scope-aware
immutable memo dictionaries for construction. The measured 16-layer shared case
dropped from roughly 5.3 million to 1,200 native reductions, without reference
storage in process dictionaries or permanent registries. Auxiliary conditional,
exclusion, membership and property-name checks now compose without executing
their converters. Private validation evidence now records union selection and
accepted children, then drives typed conversion after the entire input passes.
Converters retain neither schema lookup nor branch schemas. The depth-64 native
case dropped from about 85,000 to 3,800 reductions, with 580 words of evidence.
The six-layer shared received term dropped from 36,576 to 5,271 words; the
provider dropped from 889 to 310. Shared copying and emission still expand
repeated branches. The prototype report records the tradeoff: private transient
receipts and cached default receipts, plus standalone validation's currently
unoptimized receipt allocation. The isolated integration now preserves the
production checker/emitter and structured errors, and is now promoted to main.
See [production integration evidence](production-recursion-integration.md).

The integration uses a closed `Definition(a) = Plan(a, Nil)` specialization and
an explicit `lift` for completed definitions inside recursive builders. This
keeps ordinary definitions simple, while generic construction helpers acquire
a recursion type parameter. The migration guide records that helper-signature cost. Main walk adapters take
primitive scope and node keys, avoiding inspection of compiler-private Option
representations. Both runtimes have removed construction cells and registries.
Temporary graph-walk caches must include binding scope as well as node identity;
a retained captured-plan/shared-graph regression demonstrated why identity alone
can hide an unresolved reference. No cache owns runnable references.

Cross-target comparison also exposed native input-object ordering differences.
The admission adapter now preserves first key insertion and last duplicate value,
then applies JavaScript index-key enumeration. This changes native dictionary
output and diagnostic ordering to match JavaScript; it does not change canonical
schema sorting or the admitted JSON domain. Shared tests retain duplicates,
nested ordering and index-boundary cases.

### 6. QuickJS code with Unicode 16 tables — implemented candidate

The mixed-source backend is now the production implementation on the working
branch. `priv/regex-src/PROVENANCE.json` records archive hashes, upstream and
vendored file hashes, and both local patches. Review compatibility between newer
algorithms and older generated data; the expanded corpus does not prove exhaustive
ECMAScript conformance. Retain the property-alias counterexamples when updating.

Unicode 16 matches the tested Node 24 runtime. JavaScript still uses the host's
RegExp implementation, so other Node or browser versions need their own parity
checks. Update engine and tables deliberately together, rerun the differential
corpus and review the contract before changing this pin. Automatic dependency
updates must not silently change the native Unicode behavior.

### 7. Port ownership and explicit native build — implemented candidate

Each validation walk lazily starts a private worker that owns one native helper
and reuses it across regex requests. It closes the port before conversion callbacks
execute. Standalone requests receive their own scope; nested scopes restore the
outer session. Owner death closes idle and active ports. Caller dictionaries,
process flags and mailboxes remain unchanged after the operation. A crash,
allocation failure, exhausted execution budget or timeout raises an operational
error. Auxiliary condition, exclusion, contains, property
name and default checks preserve that boundary. No permanent service, reference
registry, pattern cache or manual release obligation was introduced.

The helper accepts packets up to 16 MiB, checks 512 KiB of stack growth and limits
execution to 100,000 timeout ticks. A four-second native alarm bounds stuck work,
including after owner exit; transport and worker waits are five and six seconds.
These are implementation resource guards, not extra schema constraints. They can
raise for otherwise valid input. Compile-time allocation is not bounded by the
execution tick counter; allocation failures and the native deadline remain guards.

The archive includes MIT-licensed C source and a Makefile, with generated binaries
outside `priv` so host binaries cannot accidentally enter Hex exports. Consumers
must run an explicit build and install the helper for release deployment. Gleam
1.18.1 does not run native build hooks for a local Gleam path dependency. A separate
rebar3/Hex dependency could automate distribution, but introduces another package;
it has not been created.

The initial direct-binding check measured about 7.5 ms per pair, including
separate helper starts for syntax and matching. Provider-shaped workloads then
confirmed that startup dominated these workloads: 64 records with four patterned fields
took about 887 ms to decode. Operation-scoped reuse reduced that observation to
10.5 ms, with no shared Gleam or JavaScript changes. The same plain record control
took about 0.3 ms. See `docs/regex-workload-measurements.md` for raw-report
reproduction, methods and the retained per-call baseline.

Review this temporary transport scope: it must not become definition/reference
ownership, survive an operation or remain active during user conversion callbacks.
No compiled-pattern cache was added. The per-request budget and deadline remain
unchanged. Native regex is still slower than the tested built-in JavaScript path;
representative workloads and platform/deployment evidence remain required.

### 8. Support and evidence boundaries — implemented gate

All main-source externals now have native implementations. The actual Erlang API
and production-plan fixtures compile the vendored helper and use the real regex
binding. They pass 53 native tests, twelve cross-target compile-negative checks and
3,636 independent schema cases, including exact historical and cross-target
schema/output/diagnostic comparisons. All sixteen portability groups pass. A
separate binding check covers 594 syntax/search cases and operational failures.

The native setup is tested on macOS with OTP 29, Node 24 and a C compiler. Linux,
Windows and minimum OTP versions still need verification; the helper currently
uses POSIX APIs. The generated native gate checks 886 definitions and 17,788
inputs with two independent schema validators, including 6,459 independently
interpreted decoded outputs. Five public API paths detect an always-match regex
adapter mutation. A macOS Gleam shipment passes after explicit helper installation
and removal of source checkouts. See `native-oracle-evidence.md`. All 109 selected official cases also pass natively against unchanged expected
results and both validators. Unsupported official groups remain excluded. Linux
CI for OTP 28 and 29 is prepared but has no hosted pass yet. Broader operator
mutations, other release tooling and
representative workload performance remain release gates. Working metadata is 0.2.0, contract revision 5.
The 0.1.0 tag is unchanged. No native dependency or new version has been published.

## Reproduction

Download and extract the official source archives outside the repository:

| Archive | SHA-256 |
|---|---|
| [2025-09-13](https://bellard.org/quickjs/quickjs-2025-09-13.tar.xz) | `6f1f322aea3bb3a90858db85c9fe717013fde4df7dfcafe2f57e78f5bb4b4a0c` |
| [2026-06-04](https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz) | `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a` |

With Node 24, OTP 29 and a C compiler installed, run:

```sh
node verification/portability/quickjs-probe.mjs /path/to/quickjs-2025-09-13
node verification/portability/quickjs-probe.mjs /path/to/quickjs-2026-06-04
node verification/portability/quickjs-probe.mjs /path/to/quickjs-2026-06-04 /path/to/quickjs-2025-09-13
escript verification/portability/string-representation.escript
```

Set `PROBE_SANITIZERS=1` for an additional AddressSanitizer/UndefinedBehaviorSanitizer
run of the native engine and transport probe. This requires compiler sanitizer
support and writes a separate report.

The first two commands deliberately fail the parity gate when differences remain.
Reports under `reports/` record source hashes and every counterexample; they are
ignored build evidence. The overlay command copies into a temporary directory,
changes only the two table files, and removes that copy after testing. It does
not alter the downloaded archives or introduce a JavaScript subprocess on Erlang.

To reproduce the expanded check against the exact vendored sources:

```sh
# Extract the pinned Test262 archive recorded in test262-selection.json first.
PROBE_SANITIZERS=1 node verification/portability/quickjs-probe.mjs priv/regex-src - /path/to/test262
npm run verify:erlang-primitives
```

The Test262 argument is optional; without it the selected Test262 projections are
omitted and the count differs. The manifest verifies every selected source and
harness file. Reports record omissions, runtime Unicode version and source hashes.
