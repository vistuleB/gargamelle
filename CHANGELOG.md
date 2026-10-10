# Changelog

## 0.0.4 — 2026-10-10

- Add typed exact-length tuple builders and positional HTML documentation.
- Add tuple typed-output, oracle, generated composition, and mutation evidence.
- Fix exponential recursion-guard traversal of shared union branches using local active/checked identity sets.
- Add shared-graph performance and cycle-rejection regressions.

## 0.0.3 — 2026-10-10

- Add guarded self-recursive definitions and mutually recursive pairs with distinct typed outputs.
- Emit finite local reference graphs and reject non-progressing cycles or unfinished references.
- Extend deep-input, typed-output, mutation, resource-failure, and generated composition verification.

## 0.0.2 — 2026-10-10

- Add finite-number definitions decoding to Gleam `Float`.
- Add inclusive/exclusive numeric bounds and repeated interval intersections.
- Render exclusive endpoints in optional HTML documentation.
- Extend numeric boundary, composition, typed-output, mutation, and official-suite verification.
- Document binary64 parsing semantics, including rounding, overflow, underflow, and signed zero.

`multipleOf` and fractional-number constants remain deferred.

## 0.0.1 — 2026-10-10

Initial standalone extraction of Concord with schema emission, typed decoding,
optional HTML documentation, and verification fixtures.
