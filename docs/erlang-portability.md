# Erlang string and regex investigation

Recorded 2026-10-10 after graph integration commit `08fd1b2`. This is development
research, not an Erlang support claim or a change to the published contract.

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

This is bounded empirical evidence, not complete ECMAScript conformance. The
table overlay is experimental and needs broader property/Test262 coverage before
production adoption. The 2026 `libunicode.h` version macro still says 17 in the
temporary copy; production packaging must correct metadata to the actual tables.
The 2026 executor requires `lre_get_alloc_count`, including internal registers,
rather than allocating only visible capture slots as in the 2025 API.

No native dependency or production binding has been added. A separate rebar3
dependency is a possible way to compile/distribute a native helper; Gleam supports
[rebar3 dependency packages](https://gleam.run/documentation/gleam-toml-reference/).
Clean-consumer builds, executable lookup, platform support, request lifecycle,
resource failure handling and caching still need implementation and verification.

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

Transfer after creator exit, nested exception cleanup and independent-context
composition have typed API tests. Review reentrancy, context installation on every
traversal/conversion path, and the memory/copy cost of retaining entire registries.
Typed regression tests now establish a compatibility failure when a converter
returns a closure capturing a builder placeholder. Both self recursion and
`recursive_pair` pass on JavaScript and fail on Erlang after decoding returns.
Transferring the decoded closure to another process, after its creator exits,
also fails. The native fixture reports 43 passing tests and three failures;
the JavaScript suite reports 38 passing tests. Reproduce with:

```sh
gleam test --target javascript
node --test verification/portability/graph-api.test.mjs
```

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
This demonstrates a
possible **different recursion contract**; it does not fix the existing library
or authorize a public API migration.

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
unoptimized receipt allocation. Next, assess an isolated integration with the
production checker/emitter and structured errors; the shipped API is unchanged.

### 6. QuickJS code with older Unicode tables — experimental candidate

The mixed-source candidate resolves the two observed release gaps and passed the
13,572-pair corpus under sanitizers. I have not selected it as a production
dependency. Review compatibility between the newer Unicode algorithms and older
generated tables, property aliases/script data, duplicate-group semantics and
broader Test262 coverage. Archive and source hashes identify the experiment;
the stale version macro must be corrected if this combination is packaged.

Pinning Unicode 16 would make the native engine match the tested Node runtime.
The public phrase “ECMAScript Unicode u” does not by itself specify a Unicode
table version. We still need an explicit upgrade policy and tests for supported
Node/OTP versions. I would not automatically update either engine or its tables
while continuing to claim cross-target parity.

### 7. Port, NIF and build packaging — undecided

The experiment uses a port to a standalone native executable. It demonstrates
matching without a JavaScript subprocess; it does not settle production lifecycle
or performance. A port isolates native failures but adds messaging and executable
distribution. A NIF avoids that transport but needs careful scheduler, crash and
resource handling. A rebar3 dependency could provide native build hooks, with a C
toolchain and potentially a separate Hex package as additional requirements.
Review deployment targets and expected validation volume before selecting the
binding, port ownership, pattern caching or packaging approach.

The probe's 16 MiB packet limit, 512 KiB stack check, execution tick budget and
five-second response wait are research settings, not proposed public limits.
Production resource failures must remain operational; they must not become syntax
errors, no-match results, or conditional/exclusion branch selection.

### 8. Support and evidence boundaries — implemented gate

The actual Erlang API fixture temporarily attaches native re adapters for the two
unported regex externals. All other core operations use production implementations.
Passing those tests proves the exercised structural/typed paths under the fixture;
it does not prove ECMAScript regex parity through the production API. The QuickJS
experiment is a separate native-engine check. Independent schema-oracle runs
against an actual Erlang library runner, complete cross-target cases, clean Erlang
consumers and platform builds remain required before a support claim.

I moved working metadata to 0.2.0 and evidence to contract revision 4 to identify
the authorized domain change. The 0.1.0 tag is unchanged. Review compatibility
notes and release criteria before publication; neither a 0.2.0 release nor a
production native dependency has been published.

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
