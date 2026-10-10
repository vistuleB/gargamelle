# Next extension: typed fixed-position arrays

Status: implemented and verified; see README for the public API.

## Consumer evidence

The equation-flashcards provider's `providers/equation/content.js` constructs
legacy palette entries as `[tool, label]` or `[tool, label, accessibleLabel]`
in `load`, and destructures those positions in `export`. The tool itself may
be a string or a list of strings. Canonical persisted palette entries already
use objects; this extension does not require changing that representation.

This is a concrete heterogeneous-array use case. Two exact-length definitions,
combined with the existing disjoint union constructor and mapped to one typed
result, can represent the two legacy shapes without optional-position rules.
An app migration remains separate work.

## Implemented contract

Use an opaque `Tuple(a)` builder analogous to `Record(a)`:

- `tuple(constructor: a) -> Tuple(a)` starts an empty tuple.
- `element(Tuple(fn(a) -> b), Definition(a)) -> Tuple(b)` adds the next position.
- `finish_tuple(Tuple(a)) -> Definition(a)` closes the tuple.

Each element consumes one argument of the constructor. Decoding produces the
constructor's typed result, not an unchecked heterogeneous list. Construction
stores conversion callbacks and invokes them only after successful validation.

For length N, emission uses `type: "array"`, positional `prefixItems`,
`items: false`, and `minItems: N`. Omit `prefixItems` for the empty tuple because
Draft 2020-12 requires that keyword's array to be nonempty. Empty tuples still
emit `items: false` and `minItems: 0` and accept only `[]`.
No trailing optional positions or arbitrary rest elements in this first API.

## Implementation behavior

A positional node participates in validation, emission, and graph traversal. Size errors
refer to the tuple's path; element errors refer to `/0`, `/1`, and so on.
Tuple positions descend into input values and therefore guard recursive edges,
as record fields and array items already do. Definition collection must still
visit every position, including recursive references and conflicting names.

Documentation must render positional children and exact length; it must not
present a tuple as a homogeneous array. Existing array constraints should either
explicitly support tuples with matching schema semantics or reject construction;
do not silently discard positional constraints.

## Verification coverage

- Gleam output tests using a typed constructor and compile-negative position
  type mismatches.
- Empty, one-element, and larger tuples; short and extra arrays; nonarrays;
  nested error paths; callback execution only on accepted decoding.
- Consumer-shaped two- and three-position palette fixtures, including list
  tools, mapped through a disjoint union to one output type.
- Ajv and Hyperjump acceptance comparisons and an independent positional
  reference interpreter, incorporated into generated composition evidence.
- Recursive tuple descent, unresolved placeholders, named-definition conflicts,
  and mutation tests that detect swapped positions or missing length checks.
- Official test selection only where the original schemas actually match the
  exact-length typed subset. General `prefixItems` also accepts short arrays and
  unconstrained extra items; do not rewrite those cases to claim coverage.
