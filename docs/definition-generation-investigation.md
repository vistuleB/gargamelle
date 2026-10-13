# Definition-derived generation: private prototype

This is private investigation tooling under `verification/experiments`, not a
public API or release candidate. Main and the publication package are unchanged.

## Mechanism and scope

The Node prototype inspects JSON Schema emitted by a completed definition through
the public API. It proposes JSON, admits it, and accepts it only when the public
validator succeeds. It does not inspect opaque definition internals or change the
library. Structural generation invokes no decoding callbacks. Contract generation
uses `validate_contract`, which decodes when requirements need decoded data.

Primitive values, constants, enums, homogeneous arrays, exact tuples, records,
dictionaries, alternatives, and local named/recursive references have proposal
strategies. Metadata does not influence acceptance. Some supported assertion
keywords, including numeric divisibility, uniqueness, conditionals, exclusions,
property-name rules, dependencies, and membership, are only rejection filters.
`allOf` proposes from a base branch and checks the whole conjunction; it never
overwrites colliding keywords. Regex patterns and unknown keywords return explicit
`unsupported` results. This is a limited subset, not a general JSON Schema generator.

## Reproducibility and budgets

Generation records the emitted schema's SHA-256, normalized options, seed, and
attempt count. The initial LCG has defined unsigned 32-bit arithmetic, including
seed zero. This fixes replay for this implementation; it is neither cryptographic
randomness nor a claim of representative statistical coverage.

Budgets limit attempts, JSON depth, nodes, collection width, and scalar text length
in strings and keys. Proposal expansion also has conservative node/reference limits,
so a search may exhaust even when a value fits the final JSON size budgets. A result
is `generated`, `unsupported`, or `exhausted`. Exhaustion means no accepted sample
was found by this search, not that the contract is unsatisfiable. Operational failures
propagate rather than becoming rejection or exhaustion.

Structural and semantic-contract generation are labeled separately. Contract results
include requirement descriptions. The schema hash and those descriptions do not
identify arbitrary semantic predicates: replay also requires the same check code and
immutable captured context. Changing a predicate can change the result without
changing the schema hash. No claim of semantic replay from schema alone is made.

## Shrinking

Shrinking removes fields/elements and simplifies scalar values, including candidates
inside nested JSON. Every retained candidate must remain admitted, accepted by the
chosen structural definition or full contract, and satisfy the supplied failing
property. Exceptions from that property remain operational failures. Input is not
mutated. Step and candidate budgets are explicit; exhaustion returns the still-valid
counterexample.

The shrinker is greedy and returns a local minimum within its proposal set, not a
globally smallest counterexample. Cross-field semantics can prevent individual
changes: reducing an answer list and its score may require a coordinated proposal
that this prototype does not supply. Failure-predicate code/context must be retained
with a counterexample; it cannot be reconstructed from a seed.

## Initial evidence and limitations

- Fixed seeds reproduce sample JSON and replay metadata exactly.
- 300 samples from 15 definitions agree with Ajv and Hyperjump, including recursive
  definitions, nullable arrays, collection bounds, uniqueness, and numeric assertions.
- A separate declared `__proto__` case retains the existing documented Ajv discrepancy
  and verifies it with the key-renaming diagnosis; it is not silently ignored.
- 100 seeded nullable-integer-array samples are admitted and accepted on Erlang.
  Sampling itself remains Node-only; a Gleam implementation has not been attempted.
- Tests distinguish semantic exhaustion from structural generation, preserve callback
  exceptions, and preserve acceptance plus the failing property during shrinking.

The prototype is independent of the existing release corpus. It has not been added
to release preparation, docs navigation, or the package API. Further decisions would
need useful consumer-generated cases, constraint-aware proposal quality, and a small
cross-target design. No implementation commitment follows from these tests.

Run after dependencies and JavaScript development modules are built:

```sh
node --test verification/experiments/definition-generation.test.mjs
```
