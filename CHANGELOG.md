# Changelog

## 0.5.0 — Unreleased

- Add opaque `Contract(a)` with ordered reject-only semantic requirements and
  separate structural and semantic rejection diagnostics.
- Receiving boundaries and `verify` now take contracts. JSON-only verification
  skips conversion for check-free contracts and decodes once for semantic checks.
- Certificates retain the full accepting contract, including captured context.
- Add contract inspection and HTML requirement documentation without callbacks.


## 0.4.0 — 2026-10-12

- Preserve every object constraint when `property_names` and
  `dependent_required` modifiers alternate; emitted schemas retain conjunctions.

- Add opaque `JsonBoundary` receiving handlers with one contract check and no
  decoding, for JSON storage and transport.

- Add `assert_format(_, Uuid)` with explicit schema length/pattern checks;
  annotation-only formats remain separate.

- Add exact safe-integer `integer_multiple_of` constraints; fractional divisibility
  remains outside the supported numeric policy.

- Add `dependent_required` object presence constraints and HTML descriptions.

- Add annotation-only `format` metadata with explicit non-assertion semantics.

- Add standalone schema `default` annotations without decoded-value substitution.

- Add schema `examples` annotations and display them in HTML documentation.

- Add opaque `Boundary` and `VerifiedJson` types. `forward` decodes against the
  boundary's stored definition before invoking its private handler with decoded
  data and original JSON. `verify` validates without conversion and retains JSON
  and the checked definition in `VerifiedJson`.

## 0.3.0 — 2026-10-11

- Add `JsonFormat` (`Compact` / `Pretty`) as a required argument to `to_string`
  and `schema_string`. Pretty JSON uses two-space indentation and preserves
  canonical tokens and key order. Show a single typed README example.

- Shorten the HTML record-policy badge to `STRICT`, using the same typography
  and color as `REQUIRED` and `OPTIONAL`.

- Rename `Value` to `Json`, `Policy` to `RecordPolicy`, `Closed` to `Strict`,
  and `value_text` to `to_string`.
- Rename `emit_json` to `schema_json` and `emit_text` to `schema_string`.
- Remove the previous API names. Update type annotations, constructor calls,
  pattern matches and function calls as described in the migration guide.
  Schema bytes, validation, decoding and serialization behavior are unchanged.

## 0.2.2 — 2026-10-11

- Demonstrate typed record decoding and provide a runnable nested renderer recipe.
  Clarify construction-plan lifetimes and safe-integer exclusion; label the public
  archive link accurately and remove implementation commentary from public guides.

- Shorten the README introduction and give JavaScript and Erlang parallel setup
  sections, with shared installation and examples.
- Keep HexDocs focused on usage, contracts and compatibility. Retain contributor
  verification and implementation notes in the source tree, shorten runtime
  guides, and consolidate library and third-party license notices.
- Replace the unstyled HexDocs renderer sample with an embedded screenshot in
  the HTML documentation guide. Retain the local HTML recipe and reference assets.

## 0.2.1 — 2026-10-11

- Align unfolding and plain labels in HTML documentation, including record fields
  and union alternatives. Preserve native disclosure behavior with a fixed
  chevron space; update the copyable stylesheet.
- Position chevrons relative to the label baseline, make record row spacing
  uniform, and end nested guides before the next horizontal divider.
- Show `STRICT FIELDS` as a heading badge and label dictionaries as `dictionary`.
  Keep longer constraints below the heading and define the badge in the guide.

- Add Hex package and HexDocs badges, accessible documentation/evidence links,
  clearer target setup and a browser compatibility guide.
- Verify Chrome 155, Firefox 157 and Safari 27, and extend native mutation checks.
  Core admission, decoding, schema and recursion semantics are unchanged.

## 0.2.0 — 2026-10-11

- Restrict JSON strings, object keys and schema text to Unicode scalar values.
  Reject unpaired surrogates after syntax parsing and duplicate-key resolution.
  Valid pairs and ordinary Gleam `String` outputs are preserved.
- Replace runnable recursive builder references with typed construction plans.
  Only completed definitions can be decoded, validated, emitted or rendered.
  Existing definitions inside recursive builders need `lift`; annotated generic
  helpers and unfinished record, tuple and variant builders gain a recursion
  parameter. See the 0.2.0 migration guide.
- Add native Erlang implementations for all core operations, including immutable
  recursion, binary64 parsing/formatting, canonical JSON and ECMAScript Unicode
  regex matching through a vendored C helper. Native use requires explicit helper
  compilation and installation; current evidence is macOS arm64 with OTP 29.
- Reuse the native regex helper within each validation walk and close it before
  conversion callbacks. Native resource failures remain operational exceptions.
- Fix native integer/float decoding in optional HTML rendering.
- Extend cross-target compile-negative, process-lifetime, generated-oracle,
  mutation and deployment verification without adding JavaScript runtime dependencies.
- Run all 109 selected official schema cases through the actual library on both
  targets. Qualify Ubuntu 24.04 x86_64 on OTP 28.5.0.7 and 29.1.1 through hosted CI.

Other native platforms, OTP releases and deployment formats remain unqualified.
Native regex uses Unicode 16 tables; Node 24.21.0 uses Unicode 17 and has known
property-match differences. The verified reference is Node 24.10.0.

## 0.1.0 — 2026-10-10

- Rename the package and public modules from Concord to Gargamelle.
- Prepare package metadata and consumer documentation for the first public release.
- Document public API contracts, runtime scope, errors and glon compatibility.
- Hide verification fixtures from the public documentation surface.
- Add a publication checklist and verify the exported package in a clean consumer.
- No decoder or schema acceptance changes.

## 0.0.10 — 2026-10-10

- Add checked documentation examples with indexed validation errors, HTML escaping, and no decoder callback execution.

## 0.0.9 — 2026-10-10

- Add `exclude(base, forbidden)` structural exclusion, emitting JSON Schema `not` and retaining the base typed output.
- Intersect repeated exclusions and render forbidden structures in documentation.
- Extend typed, compile-negative, independent-validator, generated, recursion, and mutation verification.

## 0.0.8 — 2026-10-10

- Add structural `if_then` and `if_then_else` constraints while preserving the base definition's typed output.
- Conjoin repeated conditions and render condition/then/else branches in documentation.
- Add typed, compile-negative, independent-validator, generated-composition, recursion, and mutation evidence.

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

Initial standalone extraction of Gargamelle with schema emission, typed decoding,
optional HTML documentation, and verification fixtures.
