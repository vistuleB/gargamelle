# Constructor preservation arguments

Contract: revision 3 of `docs/verification.md`.
These are implementation design arguments, not formal proofs or passed release gates.

The opaque `Definition(a)` pairs a closed `Node` tree with a conversion function.
Only library constructors can build definitions. `validate` traverses only the
node; `decode` validates first, then converts. Emission traverses only the node.
Thus ordinary schema rejection does not execute author code. Total/pure mapping
functions remain an explicit assumption. Callback exceptions are deliberately not
caught as validation errors.

## Base cases

- **P01 Boolean/null:** node checks the matching JSON constructor; schema emits
  that type. Conversion returns its Boolean or Nil respectively.
- **P02 string:** both sides require a string. Length uses JavaScript iteration
  code points; patterns call exactly `new RegExp(source,"u").test(input)`.
  Inclusive bounds compose by intersection. Distinct patterns all must hold and
  emit an `allOf` of the same patterns; identical patterns are deduplicated.
  Conversion returns the original string.
- **P03 safe integer:** the node requires `Number.isInteger` and inclusive safe
  bounds. Emission always contains those integer bounds. Parsed integer values
  preserve JavaScript numeric value; negative zero is equivalent to zero.
- **P04 enums/constants:** enum checks string membership, emits the same ordered
  unique set; constants use type-sensitive value equality and emit their type
  and value. The restricted primitive constants avoid JSON-object equality
  questions. Unsafe integer constants and empty/duplicate enums are rejected.

- **P05 finite number:** admission provides a finite binary64 `JNumber`.
  The number node accepts that constructor, and conversion returns its Float
  unchanged. The schema emits `number`, with no safe-integer restriction.
  Numeric bounds compare the same parsed binary64 endpoints and values as the
  independent validators. Inclusive/exclusive lower and upper comparisons emit
  their corresponding JSON Schema keywords. Repeated constraints choose the
  stricter endpoint; exclusivity wins at equal values. Construction rejects
  nonfinite endpoints, inverted intervals, and exclusive equal endpoints.
  Rounding and underflow belong to admission; overflow to infinity is rejected
  there. Negative zero survives decoding while numeric comparisons equate it
  to positive zero. None of these checks invokes author callbacks.

## Composition

- **C01 arrays:** object constructor distinguishes arrays from other JSON values.
  Count bounds and every child must pass. Emission imposes the same count and
  item rules. Conversion maps in order and retains duplicates.
- **C02 records:** required, optional, and defaulted field declarations accumulate
  independently of values. The curried combining function is stored, never
  invoked during construction or emission. Object type, required presence,
  declared-child validity, and explicit open/closed policy match the emitted
  properties/required/additionalProperties. Present null is a value, never
  absence. Optional absence returns None; present returns Some(child result).
  Default construction checks acceptance without conversion; missing defaulted
  fields are converted at decode time. Open extras are projected away; closed
  extras reject. Empty records still check object type.
- **C03 dictionaries:** every own JSON property is retained as a key/value pair;
  bounds count those properties and every value must pass its child. Emission
  uses the same additionalProperties and property counts. Order is not a
  semantic guarantee.
- **C04 nullable:** null succeeds immediately as None; non-null input delegates
  to the child, returning Some and preserving child failures/paths. Emitted
  anyOf admits precisely that union. Nested nullable follows outer-first rules.
- **C05 any-of:** validation requires a child match; conversion chooses the first
  matching child in declaration order. Emission preserves child order, although
  acceptance does not depend on it. Only the selected child's converter runs.
- **C06 one-of:** validation counts all successful child validations, rejects zero
  or multiple matches, and conversion uses the unique matching child. This
  equals emitted exactly-one acceptance. Overlap never invokes converters.
- **C07 tagged union:** `Variant(a, r)` is constructible only from a bare `Record(a, r)`;
  a `Definition(a)` cannot be passed as a branch. Construction rejects duplicate
  tags, empty variants, and discriminator redeclaration. Each augmented record
  includes a required string-constant tag, so branch acceptance is disjoint.
  Direct tag selection therefore equals emitted oneOf. Open/closed policy sees
  the inserted key as declared. Conversion invokes the original branch payload
  converter; tag is not injected into that payload. Missing/wrong/unknown tag
  diagnostics precede branch checks; selected branch errors pass through.
- **A01 annotations:** node validation ignores wrappers. Emission attaches the
  annotation after emitting its child, so outermost repetition wins. Conversion
  is unchanged.
- **A02 maps:** retain the original node exactly and compose only the converter.
  Under the pure/total callback assumption they cannot change acceptance.

## Guarded recursive graphs

`recursive`/`recursive_pair` build immutable schema bindings and independently
typed conversion bodies. Builders run once with construction plans, not decoded
values. Only `Plan(a, Nil)` is an executable `Definition(a)`; open builder plans
cannot cross public decode, validate, emission or renderer type boundaries.
Completed runners capture their bodies and supply typed recursion functions at
execution time. Mutual outputs remain independently typed without generic casts.
Completed definitions and closures capturing them survive creator-process exit.

Graph finalization checks names, definitions and every cycle reachable without
consuming a child. Arrays, tuple positions, dictionary values and record fields
select strict subvalues of finite admitted JSON. Union, nullable, name, reference,
uniqueness and annotation wrappers do not break same-input cycles. The guard is
conservative and does not assert satisfiability or bounded resource use.

Validation follows immutable reference bindings. Induction on strict child
values, with finite same-input paths between descents, gives the same structural
acceptance as local schema references. The checker accumulates full diagnostics
and private evidence of accepted child shapes and union selection. Conversion
uses that evidence only after the whole input succeeds, without repeating checks
or retaining schemas in converter closures. Defaults retain evidence from their
construction-time structural check; they apply only on absence. Auxiliary
constraints discard their evidence and never execute their converters.

Each library node carries a fresh opaque identity. Walk caches key by both binding
scope and node identity: importing a completed graph must not hide an unresolved
foreign reference through an earlier visit of a shared node. A retained regression
and cache mutation test exercise this distinction. Names still register globally;
colliding names must emit equal local structures, including transitive targets.
Emission produces finite local references. Rendering consumes that finite schema.

Defaults cannot be checked against unresolved references. Captured construction
plans remain open; finalization does not mutate them into completed definitions.
There are no construction cells or reference registries. JavaScript uses temporary
closure-owned walk maps; Erlang brackets temporary walk maps and restores earlier
state on every exit, including exceptions. Walk caches do not own runnable
references. These arguments do not establish native regex compatibility or bound
shared-term copying and schema expansion.

## Admission, emission and trusted runtime

Public `Value` is opaque. The public admission operation accepts JSON text,
parses using JavaScript `JSON.parse`, rejects non-finite parsed numbers and
unpaired surrogates in final string values or object keys, and
recursively invokes library-owned constructors with actual parsed values. It
never invokes definition-author functions. Syntax and final-domain failures are typed
admission errors. Other runtime exceptions, including recursion exhaustion, escape
as operational failures; callers/harness must not count them as rejection.

The 0.2.0 Erlang parser owns JSON structural, numeric and string-token scanning.
Surrogate pairs become their UTF-8 scalar encoding. Unpaired units are retained
privately until syntax and duplicate replacement finish, then rejected as domain
errors; they never escape as Gleam Strings. Numeric overflow likewise remains
private until final-domain checking. Thus overwritten invalid values do not
cause admission failure, and later malformed syntax is still a syntax error.

Conversion to emitted text builds Gleam JSON, parses its string, recursively
creates null-prototype objects with sorted keys, then uses JSON.stringify.
This preserves own `__proto__` keys and follows JavaScript index-key enumeration
for final text. `required` is independently sorted with JavaScript's default
UTF-16 comparator. Nested defaults use the same canonicalization. All tree
operations construct fresh values, so parsed input is not mutated.

The number Int/Float runtime helpers are identity functions because both Gleam
numeric types use JavaScript numbers; they are confined to checked primitive
conversion. There is no generic FFI cast or forged typed provider value.

## Current evidence and remaining work

`gleam test` currently runs 34 tests, including concrete typed records/custom
variants, dictionaries/arrays, glon regressions, optional/null states, callback
suppression, hostile keys, Unicode, tags, constraints, constants and defaults.
`schema_fixtures` supplies 25 authored independent-oracle fixtures.

`verification/generated*.test.mjs` adds 10,000 seeded definition/input pairs,
all 345 generic parent/child combinations, nonempty depth-50 chains, independently
specified output/error fixtures, admission/operational tests, callback counters,
and actual isolated mutations for all five required defect classes. Twenty
compile-negative programs establish the public opaque/static API boundary.
Generated coverage and retained findings are documented in
`verification/generated-notes.md`; operational failures are not rejections.

The parent verification harness owns the official cases, cloze compatibility,
oracle discrepancy resolution, fingerprinted report and overall release gate.
These preservation arguments do not independently claim V01–V13 completion or
browser support. Independent review and counterexamples may expose implementation
errors despite the reasoning and tests.

## Exact-length tuples and shared recursion guards

A tuple with N positional children accepts precisely arrays of length N whose
position i satisfies child i. Its schema combines array type, N prefix schemas,
`items: false`, and `minItems: N`; together these require the same length and
positional acceptance. N=0 omits the nonempty-only prefix keyword. Only after all
positions validate does the curried constructor consume each child's decoded
value in declaration order. No element is defaulted or fabricated. Tuple edges
consume a strict input child and therefore guard recursion.

Guard finalization uses identity sets local to the traversal. A revisit of an
active node establishes a same-input back edge and is rejected. A completed node
has already had every same-input outgoing edge checked, so revisiting it cannot
introduce a new cycle; it may safely be skipped. Only successful completion marks
a node checked. Both sets are shared across all collected definition roots and
discarded when finalization returns. Shared union layers therefore no longer
recheck each duplicate branch exponentially. This does not change schema emission
or impose a decoding-depth limit.

## Object property names

For an admitted object, every own property name is a JSON string. The
property-name wrapper retains the original object's validation and applies each
key node to that string; emitted `propertyNames` evaluates the same string with
the same child schemas. Repeated constraints use conjunction, not replacement.
The explicit object type is redundant with the supported dictionary/record body
and lets strict validators check constraints adjacent to a named reference.
An empty object vacuously satisfies its key constraints; nonobjects still fail
the original typed body.

The original converter is retained unchanged. Key converters are never stored
or called; key names remain unchanged even if the key definition has a mapping.
Open-record projection and default insertion occur only after input validation
and do not add keys to the input being checked. Definition collection visits both
body and key nodes so missing references and name conflicts cannot be hidden.
The recursion guard follows the body as a same-input edge; key checks inspect
synthesized primitive strings, not the enclosing object. Named key bodies are
independently finalized under the existing graph guard.

## Array membership

Membership retains the base array/tuple validator and counts positions accepted
by the matching node. Emitted `contains` and its explicit inclusive minimum and
optional maximum impose the identical count constraint. Duplicated values count
separately. Multiple requirements are conjoined using `allOf`; they do not
replace one another. A zero minimum without a maximum is true for every array,
so its redundant schema keywords and counting work can be omitted. Nonarrays
still fail the base typed definition.

Only the original converter is retained. Matching converters are not invoked,
and unmatched elements are neither removed nor changed. Thus the accepted output
is exactly the base definition's typed result. Membership checks consume an
array item, so graph guards follow only the base as a same-input edge while
collection still visits every matcher to reject unresolved/conflicting names.
Repeated evaluation of overlapping complex schemas may be expensive; this
extension does not claim linear validation cost for arbitrary compositions.

## Structural conditionals

A conditional retains the base's acceptance and inspects the same admitted input
with its condition node. If that node accepts, the consequence must accept;
otherwise the optional alternative must accept. Absent alternatives impose no
additional constraint. This is the same selection rule as emitted JSON Schema
`if`/`then`/`else`. Repeated conditions are conjoined in `allOf` alongside the
base, rather than replacing schema keywords. Typed node validation remains the
source of both condition selection and selected-branch acceptance.

Only the base converter is retained. Auxiliary converters are never called, so
conditions cannot mutate input, insert defaults, project fields, or change the
output type through their conversion maps. Defaults of the base are materialized
only after all input validation succeeds. Condition failures do not become data
errors; selected-branch errors retain ordinary paths. Operational exceptions do
not select the alternative branch.

Collection and same-input guard traversal visit the base, condition, consequence,
and optional alternative. This rejects non-progressing cycles even in unreachable
branches and checks unfinalized references/name conflicts before any emission or
decoding. Conditionals do not introduce input descent or a hidden depth cap.

## Structural exclusion

Exclusion accepts exactly when the base accepts and every forbidden node rejects
the same admitted input. Each emitted `not` negates precisely that forbidden
schema, and `allOf` conjoins those negations with the base. Repeated constraints
therefore intersect rather than overwrite keywords. No conversion result is
used to choose exclusion; defaults, projection, and maps do not alter input.

Only the base converter is retained, so accepted values decode to the unchanged
base output type. Forbidden callbacks are neither invoked nor given invented
values. A forbidden acceptance yields an `excluded` error at the current path;
forbidden rejection contributes no error. Operational exceptions escape instead
of establishing forbidden rejection. Graph collection and same-input guards
visit both base and forbidden nodes, rejecting unresolved references, conflicting
names, and non-progressing recursive cycles. Negation does not introduce descent
or a decoding-depth cap and does not require a satisfiability solver.
