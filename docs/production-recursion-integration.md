# Production recursion integration experiment

Recorded 2026-10-10. Initially tested in an isolated fixture at `511d5ae`,
this design is now integrated into `src/gargamelle.gleam` on main. No version
has been published. The runner uses the main library directly and retains
`integration/baseline.gleam` and its JavaScript runtime as the historical
comparison implementation. Its baseline source hash is checked before execution.

Run it with:

```sh
node --test verification/portability/production-plans.test.mjs
```

## API and ownership decisions

All constructors compose `Plan(output, recursion)`. A completed definition is
the closed specialization `Definition(output) = Plan(output, Nil)`. Ordinary
definitions continue to infer their types without mentioning a recursion
environment. Generic record, tuple and variant helpers carry an additional
type parameter. `lift(completed)` imports a completed definition into an open
recursive construction.

Self-recursive builders receive `Plan(a, Recursive(a))`; mutually recursive
builders share a pair of independently typed recursion functions. Builders run
once. The completed runner captures immutable bodies and supplies recursion at
execution time. Captured construction plans remain legal callback outputs, but
cannot be passed to decode, validate, emission or the documentation renderer.
Completed definitions and decoded closures capturing completed definitions remain
usable after transfer and creator-process exit.

Reference bindings are immutable graph data keyed by fresh identities. Display
names retain the production syntax and global conflicting-name rejection policy.
Imported graphs carry their own bindings. There is no permanent reference
registry, reference cell, manual release operation or cast of typed outputs.
Walk caches remain temporary per-operation state; they do not own references.

Private structural evidence drives conversion after the entire input passes.
It records accepted children, union selection and checked defaults. Converters
retain neither schemas nor structural lookup. The production checker still
accumulates complete diagnostics, including branch errors, ambiguous matches,
missing keys and escaped JSON Pointer paths. Auxiliary constraints never execute
their converters. Standalone validation currently allocates and discards evidence;
that cost remains a possible optimization, not a reason to change semantics.

## Retained findings

The first cross-target comparison exposed native object-order differences.
Map enumeration had lost JSON key insertion order, changing dictionary outputs
and extra-key diagnostics. The production Erlang admission adapter now preserves
first insertion order while retaining last-write-wins duplicate values, then
enumerates array-index keys before other keys as JavaScript does. Shared tests
cover duplicate keys, nested objects and the 4294967294/4294967295 index boundary.
Canonical schema ordering retains its separate existing rules.

A second regression exposed an integration-specific cache error. A captured open
plan could be visited first under its completed graph's bindings and then under
an unrelated construction. Caching only the node identity skipped the second
visit and incorrectly accepted an unresolved reference. Walk keys now include
the binding scope. The test retains both graph-sharing paths and requires
construction rejection on both targets. The smaller prototype already used
scope-aware memoization; copying the production cache required preserving that
distinction too.

The main JavaScript and Erlang walk adapters receive separate primitive scope
and node identities from Gleam callbacks. They do not inspect Option values or
compiler-specific composite keys. The binding-scope mutation test deliberately
removes the scope from the identity cache and must fail the retained rejection
assertion.

## Validation evidence

- 44 main-source JavaScript tests, including the five promoted integration tests.
- 52 Erlang tests: those tests plus eight native process/graph tests.
- Twelve compile-negative checks across both targets, including rejection of
  construction plans by executable APIs and access to private constructors.
- 36 emitted schemas and 3,636 cases checked independently with Ajv 2020-12.
  The validator uses own properties, with no coercion or default insertion.
- Exact comparison with the historical JavaScript implementation for emitted schema
  text, validation acceptance, decoded fixture outputs and full diagnostics.
- Exact native/JavaScript comparison of the same integrated fixtures.

The old implementation recorded three native failures for escaped runnable
builder references. Main now implements a different, explicit construction-plan
contract: the old positive tests are replaced with completed-definition lifetime
tests and compile-negative checks. Their original programs remain in Git history
at `511d5ae`. Main's native graph fixture passes all 52 tests; no old failure is
reclassified as a successful execution of its original program.

All eleven portability groups pass. Documentation generation and Hex tarball
export pass. A fresh JavaScript consumer of the extracted archive, using copied
pinned Gleam dependency sources and no repository verification tools, exercised
recursive `lift`, a separately annotated generic helper, distinct mutual outputs,
validation, decoding, emission, rendering and a decoded closure.

Native regex uses a test adapter based on Erlang `re`. These cases do not establish
ECMAScript regex compatibility. Full native support still requires the selected
regex engine, packaging and broader independent conformance evidence.

## Cost observations and remaining work

The production depth-8/32/64 decode samples used approximately
2,100/5,600/10,900 native reductions. They include production preflight and full
union diagnostics, so they are not directly comparable to the smaller prototype's
checker. A simple completed-definition transfer occupied 103 sender heap words,
112 flattened words and 109 receiver words. These are bounded measurements on
OTP 29, not timing thresholds or general memory bounds. Repeated shared branches
can still expand during transfer and emission, as the prototype report records.

Public migration examples and helper/lifetime tests are now updated, and unused
construction-cell machinery is removed from both runtimes. Standalone validation
still allocates evidence, and shared copying/emission can expand repeated edges.
Next, extend native oracle coverage and finish the regex binding and distribution
gate before claiming Erlang support. An unmodified clean Erlang consumer remains
blocked by the two regex externals. Neither a release nor an application dependency
migration follows automatically from this integration.
