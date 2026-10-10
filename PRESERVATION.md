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
- **C07 tagged union:** `Variant(a)` is constructible only from a bare `Record(a)`;
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

## Admission, emission and trusted runtime

Public `Value` is opaque. The public admission operation accepts JSON text,
parses using JavaScript `JSON.parse`, rejects non-finite parsed numbers, and
recursively invokes library-owned constructors with actual parsed values. It
never invokes definition-author functions. Syntax/non-finite failures are typed
admission errors. Other runtime exceptions, including recursion exhaustion, escape
as operational failures; callers/harness must not count them as rejection.

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

`gleam test` currently runs 17 tests, including concrete typed records/custom
variants, dictionaries/arrays, glon regressions, optional/null states, callback
suppression, hostile keys, Unicode, tags, constraints, constants and defaults.
`schema_fixtures` supplies 25 authored independent-oracle fixtures.

`verification/generated*.test.mjs` adds 10,000 seeded definition/input pairs,
all 160 generic parent/child combinations, nonempty depth-50 chains, independently
specified output/error fixtures, admission/operational tests, callback counters,
and actual isolated mutations for all five required defect classes. Seven
compile-negative programs establish the public opaque/static API boundary.
Generated coverage and retained findings are documented in
`verification/generated-notes.md`; operational failures are not rejections.

The parent verification harness owns the official cases, cloze compatibility,
oracle discrepancy resolution, fingerprinted report and overall release gate.
These preservation arguments do not independently claim V01–V13 completion or
browser support. Independent review and counterexamples may expose implementation
errors despite the reasoning and tests.
