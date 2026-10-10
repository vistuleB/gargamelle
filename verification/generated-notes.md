# Generated evidence and retained implementation findings

Contract revision 3. Run `gleam test` then
`node --test verification/generated*.test.mjs verification/compile-negative.test.mjs`.
The parent suite includes these automatically. No network is needed once locked
dependencies are present. This document does not mark the overall release gate.

## Generation and comparison

`generated-api.mjs` is a test-only adapter: recipes invoke exported compiled
Gleam constructors with correctly represented Lists/Options/functions. It cannot
inject a Node/Definition. All outputs are normalized via total public `map`
functions for independent hand-authored JSON expected-value fixtures. Separate
Gleam tests exercise typed records and custom variants without that adapter.

The fixed corpus uses ten literal xorshift seeds and 50 definitions ×20 inputs
per seed: 10,000 pairs, requested depths 0–6. Proposals are derived independently
from the recipe. Some union proposals are intentionally ambiguous; the oracle,
not the generator, determines validity. Extra-key, missing-field, wrong-type,
length and numeric mutations are proposals, never assumed invalid. Arbitrary
JSON values supplement them. Proposals vary union branch, nullable presence,
optional/defaulted presence, names and tags, including hostile keys. Coverage
requires both outcomes for every root and nested constructor and all 180 generic parent/child constructor combinations.

Nine additional depth-50 chains use linear structure. Arrays/dictionaries have
nonempty witnesses; nullable chains use non-null witnesses; each also has an
invalid leaf so validation reaches the deepest child. Coverage JSON records
counts, seeds, edges, outcomes and requested random depths. The artifact is
regenerated, not a source of expected results.

Every comparison checks emitted schema meta-validity through Ajv and Hyperjump, repeated text stability, JSON/text agreement, and input immutability.
Failures retain original recipe/input/seed/outcomes. Greedy shrinking considers
child definitions and strictly smaller values while preserving the discrepancy.
A separate shrinker test verifies minimization and exception propagation.
Operational errors retain context separately from validation rejection. An
in-flight checkpoint written before each definition keeps the recipe and corpus
available after native process termination; it is deleted only on success.

## Actual mutations

`generated-mutations.test.mjs` copies the compiled library and dependencies into
an isolated temporary directory, verifies the unmodified baseline, applies one
unique textual mutation, and runs the corresponding permanent behavioral test.
The original five required variants must fail with an assertion (not import/crash errors):
first-match one-of; null-as-missing; extra-key checks removed; an off-by-one bound;
and dropped emitted properties. Source/build files in the project are untouched.

## Retained findings and test corrections

1. **Operational parser exceptions misclassified as admission errors.** The
   initial parser caught every JSON.parse exception and called it syntax failure.
   The FFI now catches only SyntaxError. The injected RangeError regression in
   `generated-runtime.test.mjs` retains this counterexample. A separate low-stack
   subprocess exercises actual conversion recursion exhaustion and requires an
   operational exit, not a decoded Error result.
2. **Depth-50 corpus exponential expansion (generator defect).** The first
   record specimen reused its child in both required and optional fields.
   Nesting this specimen 50 times constructs a binary input tree (~2^50 leaves)
   and caused Node OOM. The depth corpus now has one nested required field at
   each level, preserving depth 50; the depth0–6 and pair-coverage corpora retain
   required/optional combinations. This changes test shape, not library limits
   or acceptance. No OOM was counted as a rejection/pass.
3. **Negative-zero expected-value correction.** An initial JS fixture expected
   strict Object.is distinction between -0 and 0 after JSON.stringify transport.
   Contract P03 explicitly equates them, and JSON.stringify(-0) is "0". The
   fixture remains and expects 0; text admission separately exercises "-0".
4. **Compiled name adapter correction.** Gleam exports the keyword-named `null`
   function as `null$` in JavaScript. The test adapter now calls that emitted
   public symbol; the initial TypeError was a harness failure, never rejection.

No schema/decoder mismatch has been discarded or suppressed. Parent-owned tests
retain and independently resolve the documented Ajv `__proto__` discrepancy.

## Hardening pass

Each generated input is serialized once; both external validators receive its
parsed value, and Concord receives exactly that text. Explicit text fixtures
retain negative zero rather than accidentally serializing it away. Hyperjump
checks the entire corpus. Ajv splits require a successful declared-`__proto__`
key-renaming diagnosis; unexplained splits fail. Classification does not alter
normative schemas or inputs. Generated decoded values are compared with a separate
recipe interpreter; recorded nested-node visits expose paths lacking outcomes.

Three additional mutations remove null-prototype emission, use UTF-16 length
instead of code-point length, and corrupt the unknown-tag error category. Each is
run against the complete foundation, typed-value and hardening suites after a
passing baseline. The original five mutants still use targeted counterexamples.
Differential counterexamples now shrink asynchronously against Hyperjump so a
known Ajv defect cannot steer minimization.

The new suite-running mutations exposed two harness gaps during hardening:
Node's inherited `NODE_TEST_CONTEXT` suppresses recursively launched test suites,
so child-suite runs remove it and assert a nonzero baseline test count. A UTF-16
length mutation also survived the selected fixtures until an explicit one-code-
point bound was paired with an astral character; that fixture is now permanent.
Neither failure was counted as a successful mutation kill.
