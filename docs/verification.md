# Gleam schema library: contract and verification matrix

Status: engineering baseline, revision 3, 2026-10-10. Document audits concluded;
further amendments follow implementation findings and section 9. Specification only; no new
library exists and no verification row is marked passed. The initial experiment
is a possible fork of glon 1.0.0. This document does not authorize publication,
production integration, or a claim of formal verification.

Implementation extension, 2026-10-10: P05 finite-number contracts and
inclusive/exclusive bounds are now implemented. The original revision-3 status
above describes the specification checkpoint; current automated results are in
`reports/evidence.json`. This extension retains the same parsed-value domain J.
`multipleOf` and fractional constants remain outside scope. Guarded self-recursion
and mutually recursive pairs are also implemented with finite local reference
graphs. Same-input cycles fail construction; no decoder depth cap is introduced.
C09 exact-length typed tuples are implemented with positional `prefixItems`,
closed tails, and empty-tuple support. Same-input guard traversal shares active
and completed identity sets to avoid repeated shared-branch verification.

## 1. Product and scope

Build a Gleam library in which one typed definition produces both a JSON Schema
and a decoder. The definition is authoritative; the schema is an artifact.
This is not an importer/compiler for arbitrary JSON Schema documents.

The app's [cloze provider](../providers/cloze/README.md) implements fill-in-the-blank
cards. Its content payload defines a card, its session payload saves unfinished
responses, and its result payload records a completed response and its grading
evidence. It is our first integration example, not part of the library itself.

The first milestone must provide cloze-shaped definitions for content, session,
and result, and document compatibility with the existing schemas. The safe-integer
policy below deliberately adds bounds absent from some existing integer fields;
do not claim exact equivalence with those existing schemas. Card-specific semantic
validation remains separate. Existing application records and behavior stay
unchanged during the experiment.

Initial target: Gleam compiled to JavaScript, exercised under Node. Browser
compatibility requires a separate smoke check before claiming it; Erlang support
is deferred. Emit JSON Schema Draft 2020-12 with an explicit root `$schema`.
Do not claim full dialect support: the library exposes only the subset below.

Terminology used throughout:

- **Definition author**: the developer writing schema definitions and mapping
  functions. **Card provider** refers only to an app integration such as cloze.
- **Value contract**: the required relationship between accepted input and its
  decoded output, specified in section 3, beyond agreement about acceptance.
- **Admission**: the boundary that parses or checks an input before it reaches
  the JSON-value decoder. Admission errors concern syntax or values outside J;
  validation errors concern in-domain values that violate a schema.
- **Oracle**: the independent reference validator, initially Ajv 2020, configured
  in section 6. It supplies evidence, not an infallible definition of correctness.

## 2. Central claim and its domain

For every successfully constructed definition S and input value x in domain J:

    Valid202012(emit_json(S), x) iff decode(S, x) = Ok(v) for some v

The decoder must return Error for schema-invalid values, not throw. For accepted
values, v must also satisfy the value contract of S. Agreement about acceptance
alone is insufficient.

J is the JSON data model as represented after JavaScript JSON parsing: null,
booleans, strings, finite IEEE-754 numbers, arrays, and objects with string keys.
No undefined, functions, bigint, NaN, infinities, cycles, accessors, prototypes
with behavior, or arbitrary host objects. Input admission must enforce this
boundary or the public API must make such inputs inaccessible.

The initial claim is about parsed values, not arbitrary-precision numeric JSON
text. Parsing can round numbers and collapse duplicate object keys. If a text
entry point is provided, document that it uses JavaScript JSON parsing semantics;
syntax errors and non-finite parsed numbers are admission errors. The validator
and decoder must receive the same parsed value.

All promises assume sufficient runtime resources and pure, total definition-author
mapping functions. The library must not execute author callbacks with invented values.
Exceptions/nontermination in arbitrary author code cannot be proved absent by
this library. Such exceptions are not ordinary validation errors and must not be
counted as successful rejections in the verification harness.

No fixed input-size or definition-size cap is part of schema acceptance. Nested
unions can require many branch evaluations; expanding shared definitions into
inline schemas can also increase size substantially. Runtime exhaustion or an
external execution-budget limit must be reported as an operational failure,
distinct from schema rejection and admission error. Such failures leave a test
unverified or failed, never passed. Bounded resource use is not a current guarantee.

## 3. Supported definitions and required semantics

These are conceptual constructors, not committed API spellings.

| ID | Construct | Schema/acceptance contract | Decoded-value contract |
|---|---|---|---|
| P01 | Boolean, null | Exactly the corresponding JSON type | Preserve value |
| P02 | String | String only; optional inclusive min/max length and pattern | Preserve string exactly; no trimming, case changes, or Unicode normalization |
| P03 | Safe integer | `integer` plus explicit bounds within -9007199254740991…9007199254740991; optional tighter inclusive bounds | Preserve mathematical integer; accept parsed `1.0` as 1; -0 and 0 are equivalent |
| P05 | Finite number | `number`; optional finite inclusive/exclusive endpoints, intersected on repetition | Preserve the admitted binary64 value as Float, including signed zero; comparison treats both zero signs equally |
| P04 | String enum; string, safe-integer, Boolean and null constants | Exact membership/equality, without coercion | Preserve value; optional mapping follows A02 |
| C01 | Homogeneous array | Array; every item satisfies its child; optional inclusive min/max item count | Preserve order and duplicates; decode every element |
| C02 | Record | Object; declared required/optional fields; explicit extra-field policy | Decode declared fields by wire name and combine into a typed value |
| C03 | String-key dictionary | Object; every value satisfies its child; optional inclusive min/max property count | Preserve every key and decode each value; key order has no semantic meaning |
| C04 | Nullable child | Child accepts OR input is null, including nullable enums/constants/unions | Option(a): None for null, Some(decoded child) otherwise; outer null check takes precedence |
| C05 | Any-of | At least one child accepts | Select the first successful branch in declaration order |
| C06 | One-of | Exactly one child accepts | Decode that unique branch; reject overlapping matches |
| C07 | Tagged union | Object branches with required, distinct string-constant discriminators; equivalent to their emitted one-of | Select the matching variant; discriminator is consumed, not duplicated in branch output |
| C12 | Structural conditional | Base accepts; if condition accepts, consequence accepts; otherwise optional alternative accepts | Retain base output; auxiliary converters never run |
| C11 | Array membership | Typed array/tuple body and inclusive count limits on structurally matching positions | Retain original output; never invoke matching converters |
| C10 | Property names | Dictionary/record input; each present own key satisfies every supplied string-output key definition | Retain original output and keys; never invoke key converters |
| C09 | Exact-length tuple | Array of exactly N elements; position i satisfies child i | Apply the curried typed constructor in positional order |
| C08 | Guarded recursion | Local `$defs`/`$ref` graphs; every cycle must descend through an item, tuple position, dictionary value, or record field | Preserve the declared recursive output type; mutually recursive pairs may have distinct output types |
| A01 | Description/title | Annotation only; no change in accepted inputs or decoded values | Preserve child result |
| A02 | Total map | No change to schema or acceptance | Apply mapping to successfully decoded value; mapping cannot add rejection rules |

Safe-integer bounds are visible in the emitted schema, not a hidden runtime
restriction. P05 numbers use finite IEEE-754 binary64 values after JSON parsing,
including values outside safe-integer bounds. Inclusive/exclusive finite bounds
emit the matching numeric keywords; repeated bounds intersect. Nonfinite
endpoints, inverted bounds, and exclusive equal endpoints fail construction.
Parsed rounding and underflow are preserved; overflow to infinity is an admission
error. Negative zero survives decoding but numeric comparisons equate both zero
signs. `multipleOf`, arbitrary-precision decimals, and fractional constants remain
deferred.

String lengths count Unicode code points, not UTF-16 code units or grapheme
clusters. Include astral characters, combining sequences, NUL and escaped lone
surrogates in JavaScript fixtures. Pattern matching uses ECMAScript RegExp with
the `u` flag, search semantics, and no implicit anchoring. Invalid patterns are
construction errors. The Gleam-side adapter must call JavaScript
`new RegExp(source, "u")` and use `.test(input)`; no `g`, `y`, `i`, or `m` flags,
and no alternate Gleam regex engine. Configure Ajv with `unicodeRegExp: true`.
Regex execution bounds/ReDoS resistance are not claimed; patterns are trusted
definition-author inputs. Test repeated calls to catch accidental statefulness.

Record field presence is independent of nullability. For child output type `a`,
required/defaulted fields yield `a`; optional fields yield Gleam's `Option(a)`.
No additional presence type is needed. In particular, optional nullable fields
yield `Option(Option(a))`:

| Field kind | Missing | Present null | Present other value |
|---|---|---|---|
| Required child | Reject | Child decides | Child decides |
| Optional child | None | Some(child result) if the child accepts null; otherwise reject | Some(decoded child), if child accepts |
| Optional nullable child (derived example) | None | Some(None) | Some(Some(decoded child)), if child accepts |
| Defaulted child | Decode declared JSON default | Child decides; never substitute default | Child decides; never substitute default |

The optional-nullable row is ordinary optional applied to nullable, not a separate
constructor. Missing and present-null remain distinguishable; collapsing them requires an
explicit map. Defaults must validate against the child's acceptance rules when
the definition is constructed, without invoking author mappings or record
constructors. Decode the default, including those transformations, when supplying
an absent field at runtime. JSON Schema's `default` is an annotation; injecting a default into
the decoded value is an additional, documented value contract, not validator
mutation. Invalid present values must never fall back to defaults.

Nullable nesting is permitted and follows the same outer-first rule:
`nullable(nullable(string))` decodes null to `None`, and `"x"` to
`Some(Some("x"))`. `nullable(null)` accepts only null and returns `None`.
For `nullable(one_of(...))`, null returns `None` without consulting the union,
even if several inner branches accept null; non-null input follows the union's
exactly-one rule. Some values of the output type are therefore unreachable.
That is permitted; surjectivity onto the output type is not a guarantee.
For non-null input that fails the child, propagate the child's error and path
unchanged; do not synthesize a two-branch any-of error from the emitted form.

Every record chooses either closed (reject undeclared keys) or open (accept and
project away undeclared keys). Neither policy is implicit. Dictionaries preserve
arbitrary keys. Mixed declared fields plus schema-constrained extra fields are
deferred. Empty records still require objects. Keys such as `__proto__`,
`constructor`, empty strings, quotes and Unicode must be handled as data.

Tagged-union construction owns a named discriminator field and inserts its
required string constant into each branch record. A branch must not redeclare
that wire name, even with the same constant. Initially branch inputs must be bare
record definitions, not records wrapped in A01 descriptions or A02 mappings.
Variant-level descriptions and mappings may be supplied separately: descriptions
annotate the augmented branch schema and mappings transform its decoded payload.
The constructor must not unwrap arbitrary definitions to discover a record;
non-record or wrapped-record branches are construction errors (or excluded by
the API's types). The record retains its open/closed policy;
the inserted discriminator is a declared key for that policy, so closed branches
accept it. Branch decoding validates the inserted key as part of the augmented
record and returns the branch's ordinary typed payload, wrapped in the selected
variant. Variant mappings follow A02. The tag is not a hidden extra payload field.
For a non-object input, report an object-type error at the input path. For an
object missing the tag, report a missing-required-field error at the containing
object with `missingKey` set to the discriminator. For a wrong-type or unknown
tag, report respectively a discriminator-type or unknown-discriminator error at
the tag's JSON Pointer path. After selection, propagate the selected branch's
errors directly. Do not replace these diagnostics with an all-branches failure.

### Canonical schema emission

Equivalent schema forms can be correct. These choices additionally fix a stable,
reviewable output form for this library; optimizations need an explicit contract
amendment rather than changing snapshots incidentally. Child schemas are inline.

Two operations are required (names are conceptual): `emit_json(S)` returns a JSON
schema value, and `emit_text(S)` returns its canonical JSON string. Parsing
`emit_text(S)` must recover `emit_json(S)` as a JSON value; object member order is
not part of that value equality. Byte-stability applies to `emit_text`, not to
the in-memory JSON representation.

| Construct | Emitted form (schematic) |
|---|---|
| Boolean / null | `{"type":"boolean"}` / `{"type":"null"}` |
| String | `{"type":"string"}` plus supplied `minLength`, `maxLength`, `pattern` |
| Safe integer | `{"type":"integer","minimum":effective_min,"maximum":effective_max}`; always include safe bounds or tighter bounds |
| String enum | `{"type":"string","enum":[declared values]}` |
| Constant | `{"type":corresponding_type,"const":value}`; safe-integer constants use type `integer` |
| Conditional | `allOf` containing the base and separate `if`/`then`/optional `else` schemas |
| Membership | Array body plus `contains`, explicit `minContains`, optional `maxContains`; repeated requirements use `allOf`; vacuous zero/no-maximum requirement omitted |
| Property names | Object body plus `propertyNames: key`; repeated constraints use `allOf`; explicit object type beside named references |
| Tuple | `{"type":"array","prefixItems":[children],"items":false,"minItems":N}`; omit `prefixItems` for N=0 |
| Array | `{"type":"array","items":child}` plus supplied `minItems`/`maxItems` |
| Record | `{"type":"object","properties":{...},"required":[...],"additionalProperties":true_or_false}`; include empty properties/required |
| Dictionary | `{"type":"object","additionalProperties":child}` plus supplied `minProperties`/`maxProperties` |
| Nullable | `{"anyOf":[child,{"type":"null"}]}` unconditionally, including nested nullable, enum and null children |
| Any-of / one-of | `{"anyOf":[children]}` / `{"oneOf":[children]}` in declaration order; no flattening or deduplication |
| Tagged union | `{"oneOf":[augmented branch records]}` in declaration order |
| Required / optional field | Include / omit wire name in record `required`; presence alone does not change child schema |
| Defaulted field | Omit wire name from `required`; attach declared JSON `default` to its child schema |
| Description/title | Attach `description`/`title` to the child schema object; outermost repeated annotation wins |
| Total map | Emit child schema unchanged |

Root emission adds only `$schema: "https://json-schema.org/draft/2020-12/schema"`;
no automatic `$id`, `$defs`, title or other metadata. Emit no unknown keywords.
Required-name arrays are sorted by lexicographic UTF-16 code-unit order, without
locale collation; enum/union arrays retain declaration order. For canonical text,
recursively insert object properties in that same sorted order, then serialize
using compact JavaScript `JSON.stringify`, without a trailing newline. The final
text follows JavaScript property enumeration order: array-index keys come first
in numeric order, followed by other string keys in insertion order. This is not
a promise of lexicographically ordered keys in the final text. For example, field
names `"10"` and `"2"` appear as `"2","10"` inside `properties`, but as
`["10","2"]` in `required`. The rule also applies inside JSON defaults; other
array order is preserved. Repeated text emission must be byte-identical.

Every emission/conversion step must preserve all keys as own enumerable data
properties, including `__proto__`, `constructor`, and `toString`. Use safe property
construction (such as null-prototype objects or explicit data-property definition)
or a serializer with equivalent behavior. Ordinary assignment to an inherited
setter must not discard a property or change a prototype. The ordering rule does
not authorize unsafe object construction. Exercise these keys in both emitted
schema properties and default objects, as well as in decoded inputs.

Repeated bounds emit their intersection (largest lower/smallest upper bound).
Identical pattern strings are deduplicated, retaining their first declaration
position. After deduplication, repeated distinct patterns must all hold: emit a string schema with the length
bounds and `allOf` children of the form `{"type":"string","pattern":p}`,
in declaration order. A single pattern uses the direct form above. This narrowly
generated conjunction must be supported and tested; a public arbitrary all-of builder
remains deferred. Default annotations must not alter acceptance.

## 4. Construction and architectural contracts

- Field declarations are static and independent of decoded values. An object
  builder collects field schemas and combines actual decoded values afterward.
  It must not discover structure by invoking a continuation with fabricated null
  or undefined values. Value-dependent alternatives use explicit unions.
- The internal definition type is opaque. Public constructors preserve the
  acceptance claim. No escape hatch can inject an unrelated schema, decoder,
  arbitrary predicate, or raw assertion keyword while retaining that claim.
- Construction errors are typed and identifiable: duplicate wire fields,
  duplicate discriminator tags, branch redeclaration of its discriminator,
  empty enum/union, negative/nonintegral sizes,
  reversed bounds, invalid regex, unsafe numeric constants/bounds, and invalid
  defaults. Duplicate enum values are rejected for predictability.
- Additional APIs for semantic validation must not masquerade as equivalent
  schema decoders. They have a separate result/error stage.
- Emission is deterministic, valid for the selected meta-schema, and independent
  of callback execution and process history. For repeated annotations, the
  outermost annotation wins. Constraints compose by intersection, not accidental
  replacement. Contradictory bounds are construction errors.
- Decoding and validation do not mutate input. Data-error locations use JSON
  Pointer (RFC 6901): root is `""`, array indices are decimal, and tokens escape
  `~` as `~0` and `/` as `~1`. A missing required field points to its containing
  object with a separate `missingKey`; an undeclared key points to that key.
  Each error has a category. General any-of/one-of errors point to the union input and report
  zero-based branch indices: child failures for no match, matching indices for
  one-of ambiguity. Nullable and tagged-union diagnostics follow their specific
  rules in section 3. Nested child paths remain relative to the document root.
  Assert these rules against our own fixtures, not equality with Ajv's error
  choices. Exact English wording and error enumeration order are not promises.
- No filesystem, network, application storage, UI, or host lifecycle dependencies
  belong in the core library. A narrow, documented regex/JSON-runtime FFI is
  acceptable; an FFI value cast used to bypass the type model is not.

Deferred: arbitrary schema import, remote/dynamic refs, larger recursion groups, public all-of/not/conditionals,
unevaluated keywords, tuples, pattern properties, format assertions, uniqueItems,
general JSON-valued enums/constants, encoders/round-trip promises, Erlang support,
and a machine-checked proof. There is no API that silently ignores these features.

## 5. Verification matrix

All rows currently have status **specified; not implemented or verified**.
Status may become passed only with a reproducible command and recorded evidence.
V01–V13 are all mandatory for the initial Node milestone. The browser smoke check
mentioned in V12 is an additional gate only for claiming browser support;
conditional text-entry tests apply if that entry point is exposed. These are
explicit applicability rules, not permission to skip other obligations.

| ID | Obligation | Required evidence / adversarial cases |
|---|---|---|
| V01 | Emitted schema is valid and deterministic | Meta-schema validation for every generated definition; JSON/text value agreement; byte-stable canonical-text fixtures; emitted properties/defaults with `__proto__`, `constructor`, `toString`, `"10"`, `"2"`; required-array ordering; annotation wrapping; repeated-pattern conjunctions and deduplication |
| V02 | Schema-valid implies decoder success | Differential testing including missing/null, boundary values, unknown keys and all union branches; crashes/timeouts fail |
| V03 | Decoder success implies schema-valid | Same differential corpus in reverse; include overlapping one-of branches and invalid values nested deeply |
| V04 | Correct decoded values and errors | Independently authored fixtures for every P/C/A row; reordered object keys; array order; defaults; nested presence states; maps; discriminator consumption and missing/unknown/wrong-type tag errors; nullable child-error propagation; branch selection; JSON Pointer escaping and missing-key/union diagnostics |
| V05 | Constructor safety | Invalid-definition fixtures for every error above; forbidden tagged-union branch shapes rejected or excluded by compile-time negative fixtures; callbacks instrumented to detect construction-time invocation; no fabricated-value FFI |
| V06 | Primitive semantics | Each JSON type against each primitive; bounds at b-1/b/b+1; safe-integer endpoints; fractions; Unicode/regex fixtures; constants with same-looking wrong types |
| V07 | Object semantics | Required/optional/defaulted combinations; nonobjects; empty records; open/closed policies; dictionary bounds; hostile-looking and array-index property names preserved through schema emission and decoding; no prototype changes or input mutation |
| V08 | Compositional preservation | Written argument per constructor plus nested generated cases, including nullable(null), nullable(nullable), nullable(one-of with overlapping null branches), optional(nullable), described record children and arrays of unions |
| V09 | Independent standards evidence | Pinned official suite cases representable by our constructors; explicit selection/exclusion manifest; suite expected answers must agree with both oracle and decoder |
| V10 | Harness detects defects | Deliberately broken variants: first-match one-of, null-as-missing, disabled extra-key check, off-by-one bound, dropped field; each must cause a failing test |
| V11 | Cloze structural coverage and compatibility | Definitions for all three provider payloads; curated valid/invalid payloads; compare new emission and existing schemas on a shared corpus; identify explicit safe-integer bound differences; typed outputs checked separately |
| V12 | Admission and runtime | Invalid JSON text if exposed; non-JSON host inputs cannot reach core; resource failures reported distinctly; JS Node checks mandatory, browser gate separate |
| V13 | Regression retention | Permanent fixtures for every discovered mismatch, including the six glon regressions below; a fix cannot remove its counterexample |

Retain these observed glon 1.0.0 regressions as initial fixtures, independently
of any temporary investigation files:

1. One-of containing two string branches must reject a string matching both.
2. Optional nonnullable string must reject a present null.
3. Nullable string enum must accept null in both schema and decoder.
4. Empty record must reject a numeric input.
5. Description around the tail of a two-field record must not lose the second
   field from the schema while retaining it in the decoder.
6. Object construction must never call a definition-author continuation with undefined
   pretending to be a value of its declared type. Test callbacks that inspect
   their argument, not only record constructors that happen not to inspect it.

## 6. Executable evidence protocol

Use pinned Ajv 2020 as the initial independent validator. Enable schema checking;
set `unicodeRegExp: true`; disable coercion, default insertion and extra-property
removal. Record exact
validator options and package/compiler/runtime versions. The oracle must not
call library validation functions or share its constraint-evaluation code.
Strict-mode lint exceptions, if needed for valid emitted schemas, must be narrow
and documented; never suppress a semantic disagreement through oracle options.
Never silently exclude an in-domain counterexample from a test run.

For V11, interpret the existing cloze schemas, which omit `$schema`, as Draft
2020-12 in the test harness. Compare acceptance on the same parsed inputs, not
schema text. The new emitted schemas must independently satisfy the canonical
emission rules and the schema/decoder equivalence claim. Report every difference
from existing schemas, including the documented safe-integer restriction; a finite
corpus does not prove equivalence between old and new schemas.

Import a pinned revision of the official JSON Schema Test Suite. Since this is
not a schema importer, translate representable test schemas into builder fixtures
and retain original case IDs, schemas, instances and expected answers. Check the
translation; do not count rewritten tests with weaker constraints as the original
case. Record unsupported cases before running tests, with reasons tied to scope.

Generate definitions as well as inputs, including valid-by-construction values,
targeted invalid mutations and unrelated JSON values. Require every constructor,
both validity outcomes where possible, boundary categories and every supported
parent/child combination to appear. Include hand-authored output fixtures so a
shared generator defect cannot make all evidence self-confirming.

Initial candidate gate: at least 10,000 definition/input pairs across ten fixed
seeds, nesting depths 0–6, with coverage reported, plus a separate depth-50 nesting
corpus and all deterministic/conformance/regression fixtures. These counts are
an evidence budget, not a correctness theorem. Invalid mutation candidates may
remain valid; ask the oracle rather than assuming a mutation changes acceptance.

Shrink mismatches to small definition/input pairs without losing the discrepancy.
Retain seed, original and minimized cases, emitted schema, oracle outcome,
decoder outcome and decoded value/error. A timeout, crash, admission discrepancy
or harness exception is never counted as ordinary rejection. Every test command
returns nonzero on an unresolved mismatch or harness failure.

Each candidate report records contract revision, source commit, dependency lock,
commands, versions, counts/coverage, exclusions, failures and time/resource limits.
One documented offline command must reproduce the fixed evidence suite after
dependencies and fixtures have been fetched. Random exploratory runs supplement
that command and must save failing seeds.

## 7. Reasoning versus proof

Write a preservation argument for each constructor: assuming equivalent child
schemas/decoders, explain why its generated schema and decoder accept exactly the
same inputs, and why the output follows its value contract. Primitive rules form
the base cases. Static object fields make structural induction possible.

For one-of, count successful child matches, reject zero or multiple, and return
the unique result. For any-of, acceptance is existential but output selection is
ordered. Annotation wrappers leave both acceptance and output unchanged. Record
arguments must cover object type, required presence, child validity and extra keys
separately. Defaults affect output only on absence.

These arguments are reviewable design reasoning, not a machine-checked proof of
source code. Tests cannot establish universal equivalence. The trusted base still
includes Gleam/compiler, JSON parsing, regex engine, JS runtime and oracle;
independent official expectations reduce but do not eliminate oracle risk.

## 8. Cloze integration findings and separation of concerns

The existing provider implementation is not an oracle for this library:

- Authored content forbids extra keys, but the runtime decoder accepts host-added
  fields. Test the authored closed schema directly; a future runtime adapter must
  use an explicitly different definition or project before that boundary.
- Current size checks count JS UTF-16 units, whereas the schema length contract
  counts code points. Keep an astral-character counterexample. Resolve application
  compatibility separately; do not copy the discrepancy into library semantics.
- Existing `learningVersion` has no schema upper bound. The experimental definition
  adds the public safe-integer maximum. Exercise the difference in comparison tests;
  it is a documented compatibility delta, not a failure of new schema/decoder
  equivalence and not permission to change the application's existing contract.
- Unique blank IDs, exactly-once references, normalized answer uniqueness,
  signature compatibility, correct result totals and matching current content
  remain semantic checks after structural decoding. A payload can pass schema
  validation and fail these checks without violating this library's contract.

The initial milestone does not migrate these checks, rewrite records, or change
production behavior. Its output is a standalone evaluation and compatibility report.

## 9. Completion and rules for the implementer

A candidate is ready for review only when V01–V13 pass for the Node milestone, each
constructor has a preservation argument, all three cloze structural definitions
are expressible, known discrepancies have retained tests, and a clean checkout
can reproduce the evidence. Documentation must state subset, JS target, parsed
number limitations, callback assumptions and excluded guarantees. Do not label
this outcome full JSON Schema compliance or a formal proof.

Before implementation, record whether to fork glon or start a new implementation.
Reuse is justified only where its code reduces work while satisfying this contract;
preserving its unsafe object-builder API is not a goal. Prefer a fresh core if
repair would largely replace it or obscure the preservation arguments. This is
an implementation decision and does not change the acceptance gates. Record the
upstream version and reused files. Glon 1.0.0 declares MIT licensing; verify and
retain applicable copyright and license notices in any reused or modified code
and in the distributed package. Do not represent a separate package as upstream.

Implementation choices are autonomous within this contract. No failing fixture
may be deleted, excluded, weakened or reclassified merely to pass. An incorrect
test may be corrected with a recorded standards-based explanation; retain the
original counterexample and rationale. Oracle disagreement requires investigation,
not a vote among implementations.

Stop and propose an explicit contract amendment if a fix requires scope expansion,
weaker equivalence, a new runtime restriction, a different dialect, or removal of
a required feature. Routine API design, bug fixes and test additions do not need
approval. Report incomplete work as incomplete. Public release and application
adoption are separate decisions after this gate, ideally with independent review.

## References

- [JSON Schema Draft 2020-12 validation specification](https://json-schema.org/draft/2020-12/json-schema-validation)
- [JSON Schema Draft 2020-12 core specification](https://json-schema.org/draft/2020-12/json-schema-core)
- [Official JSON Schema Test Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite)
- [Ajv dialect and keyword documentation](https://ajv.js.org/json-schema.html)
- [JSON Pointer, RFC 6901](https://www.rfc-editor.org/rfc/rfc6901)
- [Glon 1.0.0 API](https://hexdocs.pm/glon/glon.html)
- Existing integration fixtures: `providers/cloze/{content,session,result}.schema.json`,
  `providers/cloze/contracts.gleam`, and `providers/cloze/README.md`.


## Integration amendment: finite named definitions and unique arrays

The all-provider migration adds two explicitly tested capabilities beyond the
revision-3 constructor matrix. `named(name, definition)` preserves the typed
value and validation behavior while emitting a local `$defs` entry and `$ref`.
Names use ASCII letters followed by letters/digits/underscore/hyphen. Definitions
are finite DAGs, not recursive callbacks. Repeated names with unequal emitted
bodies (including descendant conflicts) fail emission operationally; no ambiguous
schema is returned. Apply bounds/patterns before naming. Provider equation trees
use 21 named levels matching their existing depth-20 content limit.

`unique_items(array_definition)` preserves the list type and conversion, adds
`uniqueItems: true`, and rejects duplicates by canonical JSON equality (including
object key-order independence and numerical zero equivalence). It accepts a bare
array definition with bounds already applied; other constructors reject at
construction. The generated revision-3 matrix remains unchanged; dedicated
`extensions.test.mjs` differential cases against both validators cover these
extensions, conflicts, deep DAG emission, and structural JSON equality.
