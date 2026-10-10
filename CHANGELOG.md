# Changelog

## 0.0.7 — 2026-10-10

- Add structural array membership with `contains`, `minContains`, and `maxContains`, preserving original typed outputs.
- Support repeated membership constraints, fixed tuples, named arrays, and recursive array values.
- Extend documentation and typed, independent-validator, generated, and mutation verification.

## 0.0.6 — 2026-10-10

- Retain the v0.0.5 mapped-number property-name audit case with an explicit exact-fixture Ajv strictTypes lint exception and Hyperjump comparison.

## 0.0.5 — 2026-10-10

- Add `property_names` constraints for dictionaries and records, preserving their typed outputs.
- Intersect repeated key constraints and render property-name contracts in HTML documentation.
- Extend typed, compile-negative, independent-validator, mutation, and generated-composition evidence for object keys.

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
