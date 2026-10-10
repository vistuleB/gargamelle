# Concord

Isolated Node-targeted project governed by
[contract revision 3](docs/verification.md).
The equation-flashcards application imports this package from the sibling `concord` checkout for its provider contracts.
It remains unpublished; no historical data is rewritten by that integration.

## Setup and checks

Use Gleam 1.18.1 or later and Node 24 (enforced by npm scripts; other Node majors are unverified). Dependencies are pinned in the project
manifests and resolved lockfiles. Run `npm ci` and `gleam deps download` on first
setup, then `npm test` for the available tests. After dependencies are fetched,
tests must run offline.

Run `npm run verify` for the complete Node candidate evidence run. It checks
formatting, runs Gleam and Node tests, enforces generated coverage thresholds, and
writes `reports/evidence.json` with source hashes, dependency versions, logs,
conformance selection and per-row evidence. After fetching dependencies, this
command runs offline. `npm run check:release` accepts only a successful report
whose source fingerprint and logs are unchanged. It does not approve publication
or claim a mathematical proof.

The harness currently retains a known Ajv 8.20.0 discrepancy for a declared
`__proto__` property in a closed record. Its characterization test passing means
the discrepancy remains visible, not that Ajv agrees in this case. Pinned Hyperjump
1.18.0 checks every generated definition/input pair, as well as the dedicated
`verification/supplementary-oracle.test.mjs` fixtures. A split is classified only
when renaming the declared hostile key restores Ajv agreement; unexplained splits
fail verification. The generated report counts classified splits. This explicitly documented exception
does not change schemas, decoder behavior or Ajv options. See
`verification/known-oracle-discrepancies.json`.

## Implementation decision

Start with a fresh core. Glon's general idea (a typed definition producing both
a decoder and a schema) is retained, but its continuation-probing object API
would need replacement. A fresh static builder makes the preservation arguments
easier to inspect. No glon source is copied into this scaffold. Any later reuse
must record source/version and retain applicable MIT notices before distribution.
This is a private experiment, not a published or publish-ready package.

The initial work is implementation and verification of the standalone contract.
Cloze is the first integrated provider. Further provider migration and publication
remain separate decisions.

## Verification coverage

The implementation agent completed the core and generated, mutation, runtime,
typed-output and compile-negative evidence. The coordinating agent reviewed it
and added independent validator checks, official-suite selection, cloze payload
comparisons and the final evidence gate. The generated suite includes 10,000
seeded pairs, all 308 generic parent/child combinations and thirteen depth-50 chains.
Twenty-eight actual compiled-library mutations must fail behavioral assertions,
including five numeric, three recursion, and three tuple, and three key-constraint, and three membership, and three conditional mutants. The three
new revision-3 mutations run the full foundation, typed-value and hardening suites.
Nineteen forbidden Gleam programs must fail compilation after a positive baseline.

The official suite is pinned to commit
`7de0e6a06031ede80028583dd45d0cd41105ae5b`. All 46 core files are retained with
hashes and licence. `verification/official/selection.json` identifies 27 selected
groups and 357 exclusions with reasons. No unsupported schema is strengthened to
make it fit our constructors. Optional suite collections and full-dialect
conformance are not claimed. Existing cloze schemas are frozen from checkpoint `ceb244a` for independent compatibility comparisons; safe-integer limits and the provider's UTF-16 length difference
are explicitly exercised.

See [PRESERVATION.md](PRESERVATION.md) for constructor reasoning and
[generated notes](verification/generated-notes.md) for failure retention,
shrinking, and implementation findings. `reports/evidence.json` is the current
verification result; it is generated locally and excluded from source control.
The original contract document's unverified status records its specification-time
state, not the current candidate report. Browser/Erlang support, publication and
broader production adoption remain outside this milestone.

## Static object API example

```gleam
import concord as s

pub type User { User(name: String, active: Bool) }

pub fn user_definition() {
  let assert Ok(fields) =
    s.record(fn(name) { fn(active) { User(name, active) } })
    |> s.required("name", s.text())
  let assert Ok(fields) = s.required(fields, "active", s.boolean())
  s.finish(fields, s.Closed)
}
```

`s.emit_text(definition)` emits canonical schema text. `s.parse(text)` admits JSON;
`s.decode(definition, value)` validates before running constructor/mapping functions.
Admission errors, data errors and operational exceptions remain distinct.
The safe-integer and trusted-callback limitations are part of the contract.

## Output and evidence details

`dictionary(child)` decodes to a Gleam `List(#(String, a))` (key/value pairs),
not a JavaScript object. The test adapter explicitly maps that list to an object.

Generated checks compare decoded output with an independent recipe interpreter,
including optional presence, defaults, nullable values, union selection and maps.
Coverage records visits and outcomes by definition-node path, and requires both
acceptance and rejection for every constructor at nested positions. This is a
bounded corpus, not exhaustive path coverage for every generated definition.

Reports distinguish automated evidence from V08's preservation argument, which
remains `review-required`. File existence is not proof of that argument. A report
always identifies a hashed working-tree snapshot; Git commit fields are null when the checkout has no Git history. `sourceCommit` is null when the
relevant source is uncommitted, with `baseCommit` retained for context. After a
checkpoint commit, regenerate evidence to identify the containing commit.

## Fractional numbers

`number()` returns `Definition(Float)` and accepts every finite number admitted by
`parse`, including integers and magnitudes outside the safe-integer range.
`number_bounds` intersects finite numeric endpoints; `None` leaves that side
unbounded. Apply bounds before naming a definition or composing it into a union.
Annotations and maps preserve the underlying number node and support bounds.

```gleam
import concord
import gleam/option.{None, Some}

let assert Ok(probability) =
  concord.number_bounds(
    concord.number(),
    Some(concord.Inclusive(0.0)),
    Some(concord.Inclusive(1.0)),
  )
let assert Ok(positive) =
  concord.number_bounds(concord.number(), Some(concord.Exclusive(0.0)), None)
```

This is the parsed IEEE-754 binary64 model, not arbitrary-precision decimal
arithmetic. `parse` rejects numeric overflow to infinity as an admission error,
including overflow nested in arrays/objects. Parsing may round decimal text or
underflow it to zero. Decoding preserves the resulting number, including negative
zero; schema comparisons treat both zero signs equally. Serializing through
`value_text` follows JSON serialization and normalizes negative zero to `0`.
The independent validators and decoder must receive the same parsed value.

Bounds emit `minimum`/`maximum` or `exclusiveMinimum`/`exclusiveMaximum`.
Repeated bounds intersect, with exclusivity winning at equal endpoints.
Nonfinite endpoints, inverted intervals, and exclusive equal endpoints are
construction errors. An interval between adjacent representable numbers can be
constructed even when it accepts no binary64 value; schema and decoder agree.
`bounds` remains the integer/size API; use `number_bounds` for numbers.
`multipleOf` and fractional-number constants are not included in this extension.

## Recursive definitions

`recursive(name, build)` creates a guarded self-recursive definition. Its builder
runs once with a typed definition reference, never a fabricated decoded value.
The builder returns `Result(Definition(a), ConstructionError)`. For example:

```gleam
import concord as s
import gleam/result

pub type Tree {
  Leaf(Float)
  Branch(List(Tree))
}

pub fn tree_definition() {
  s.recursive("tree", fn(self) {
    use leaf <- result.try(s.required(s.record(Leaf), "value", s.number()))
    use branch <- result.try(
      s.required(s.record(Branch), "children", s.array(self)),
    )
    s.tagged("kind", [
      s.variant("leaf", leaf, s.Closed),
      s.variant("branch", branch, s.Closed),
    ])
  })
}
```

`recursive_pair(first_name, second_name, build)` supplies two references, with
independent output types. Return `Ok(#(first_body, second_body))`; the result
contains both finalized definitions, each usable as a root. This first API
supports self-recursion and pairs, not arbitrary heterogeneous recursion groups.

Every cycle must descend into an array item, dictionary value, or record field.
Direct reference loops, loops through nullable/union/annotation wrappers, and
mutual aliases without child descent are construction errors. This is a
conservative syntactic guard, not a proof that every definition has an accepted
value. Names use the same restricted syntax as `named`; pair names must differ.
Conflicting definitions sharing a name are rejected during graph finalization or
when composed definitions are emitted/validated.

Builder references are scoped to construction. They cannot be decoded/emitted
before finalization, nor used to validate a default while unresolved. A rejected
construction invalidates its bound placeholders; escaped placeholders cause
operational failures even in empty arrays. Add defaults containing recursive
values after their definitions are finalized. Nested construction cannot close
over an unfinished outer reference; use `recursive_pair` for that relationship.

Schemas emit finite local `$defs`/`$ref` graphs. Decoding follows the same
references, preserving typed values and nested error paths. Documentation renders
references as links rather than expanding recursive trees. There is no hidden
depth limit. Stack exhaustion and callback exceptions remain operational failures,
not validation rejections. The equation provider's existing depth-20 contracts
are unchanged; migrating them would be a separate app behavior decision.

## Optional HTML documentation

`concord/documentation` renders annotated definitions as collapsible HTML
fragments. It is independent of the decoding module: applications that only
validate data need not import or ship it.

```gleam
import concord as concord
import concord/documentation

let name = concord.text() |> concord.description("Name shown to the learner")
let fragment = documentation.render(name, "learner-name")
```

`render(definition, id)` returns an `<article>` fragment. Give each article a unique
ID. The renderer consumes Concord's emitted representation internally rather than
exposing its private definition AST. `render_emitted(schema_json, id, aliases)`
accepts already-emitted Concord schema JSON and returns `Result(String, String)`.
This is a renderer for Concord's schema vocabulary, not a general JSON Schema
validator or documentation engine for arbitrary schema dialects.

Descriptions, field labels, constants, defaults and IDs are HTML-escaped. Object
fields, array items, dictionaries and union alternatives retain their nesting.
Shared `$defs` render once with local links; arbitrary discriminator names work.
Optional aliases are `(omitted_definition, displayed_definition)` pairs. They must
refer to existing definitions and may not chain. They only compress presentation;
the caller must explain any omitted distinctions. No domain-specific aliases are
built into Concord.

Use `documentation/reference.css` for the supplied page styling and
`documentation/reference.js` for optional expand/collapse and print restoration.
Native `<details>` folding needs no JavaScript. Buttons with `data-fold="expand"`
and `data-fold="collapse"` control all rendered branches. The script expands all
branches for printing and restores their previous state afterward. A host can
supply its own stylesheet or embed the fragment in an existing page. Page title,
navigation, article grouping and surrounding prose belong to the caller.

## Fixed-position arrays

`tuple` starts an opaque builder with a curried constructor. Each `element`
consumes one constructor argument; `finish_tuple` closes the array at exactly
that length. The result may be a Gleam tuple, a custom type, or another typed
value:

```gleam
let entry = concord.tuple(fn(label) { fn(weight) { #(label, weight) } })
  |> concord.element(concord.text())
  |> concord.element(concord.number())
  |> concord.finish_tuple
// ["x", 1.25] decodes to #(String, Float); shorter/longer arrays are rejected.
```

An empty builder accepts only `[]` and returns its supplied constructor value.
Emission uses `prefixItems`, `items: false`, and `minItems` equal to the length;
the empty tuple omits `prefixItems` to remain meta-schema valid. Positional errors
use paths such as `/1`. Positions guard recursive edges by descending into the
input. Conversion callbacks run only after the whole input passes validation.

There are no optional trailing positions or rest elements. Use a disjoint union
of exact-length definitions, mapped to one output type, for two alternative
lengths. `bounds` and `unique_items` remain homogeneous-array operations and
reject tuple nodes, including tuples mapped to lists.

## Object key constraints

`property_names(object_definition, key_definition)` returns a construction
result with the same decoded output type as the original object. For example,
a locale dictionary can share the app's existing locale-field syntax:

```gleam
let assert Ok(locale) = concord.pattern(
  concord.text(), "^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$",
)
let assert Ok(translations) = concord.property_names(
  concord.dictionary(concord.text()), locale,
)
```

The key definition has output type `String`, but only its structural validation
is used; its conversion and mapping callbacks never run. Original dictionary
keys and value decoding are preserved. Every present own key is checked,
including undeclared fields in open records. Empty objects have no key checks.
Absent optional or defaulted record fields do not introduce input keys to check.
Key failures use the property's escaped JSON Pointer path, so a key and its value
can produce separate errors at the same path.

Repeated calls intersect the key contracts using `propertyNames: {allOf: ...}`.
Object type, value contracts, and property-count bounds remain enforced. Named
and annotated dictionary/record definitions are supported; arbitrary unions,
nullable objects, and unfinished recursive object placeholders are rejected by
this constructor. Apply constraints to the dictionary body inside a recursive
builder instead. Key definitions themselves may use names, unions, and maps.
`patternProperties` and generalized additional-property handling remain deferred.

A mapped numeric definition may legally have output type `String` while retaining
its numeric acceptance schema. Used for property names, it accepts only empty
objects because actual names are strings. Ajv's `strictTypes` lint refuses this
valid unsatisfiable key contract. Verification retains an exact-schema exception
for that audit fixture, explicitly disables only `strictTypes`, and compares
Concord with both Ajv and Hyperjump. The ordinary oracle remains strict; no
automatic fallback or runtime behavior change is introduced.

## Array membership

`contains(array_definition, matching_definition, minimum, maximum)` returns a
construction result with the original decoded output type. `minimum` is a
nonnegative safe integer; `maximum` is `None` or an inclusive safe integer at
least that minimum. For example, require one or two integer-valued elements
while preserving all decoded numbers:

```gleam
let assert Ok(values) = concord.contains(
  concord.array(concord.number()), concord.safe_integer(), 1, Some(2),
)
```

Every item must still satisfy the original array/tuple contract. Matches count
positions, including duplicates, rather than distinct values. A match uses only
structural validation; its conversion and mapping callbacks never run. The
original converter runs only after the complete definition accepts the input.
The matching definition may have a different output type from an array element.
Count failures use `contains_count` at the array's JSON Pointer path.

Repeated calls intersect their membership requirements, emitted as separate
`allOf` branches. Zero minimum permits no matches; maximum zero requires none.
Zero minimum with no maximum is vacuous and emits no membership keywords, which
also avoids Ajv's strict-mode rejection of an ignored `contains` keyword. Its
matching definition still participates in reference/name validation.

Array and fixed-tuple bodies, names, descriptions, titles, and existing unique
arrays are supported. Nullable arrays and arbitrary unions are rejected as base
contracts. Apply bounds and uniqueness before membership constraints when those
operations require an unwrapped homogeneous array. Recursive membership checks
consume array items; no depth cap is introduced. Complex overlapping body and
match schemas may repeat validation work; there is no shared input cache.

The verbatim provider's existing nonempty-answer check supplies a consumer
example: an answer must contain non-whitespace text (`\S`) or a formula-reference
object. Formula-ID existence is still a provider responsibility. The app has not
been migrated to this feature.

## Structural conditionals

`if_then(base, condition, consequence)` applies the consequence when the
condition accepts the input. `if_then_else(base, condition, consequence,
alternative)` validates exactly the selected branch. Both return a definition
with the base's original output type; the auxiliary definitions may have
independent output types. For example:

```gleam
let assert Ok(positive) = concord.number_bounds(
  concord.number(), Some(concord.Exclusive(0.0)), None,
)
let checked = concord.if_then(
  concord.number(), positive, concord.safe_integer(),
)
// Positive numbers must be safe integers; nonpositive finite numbers remain valid.
```

All checks inspect the original admitted JSON. Defaults, projection, or mapping
from the base decoder do not change condition selection. Auxiliary conversion
callbacks never run. Only the base converter runs, after the base and selected
requirements all accept. Unselected branch data errors are not reported; condition
errors select `else` or impose no further requirement when there is no `else`.
Operational exceptions still escape and are not treated as condition failure.
Selected-branch errors preserve their ordinary categories and input paths.

Repeated calls intersect their requirements. Emission uses `allOf` with the
base schema and separate `if`/`then`/optional `else` schemas, so nested conditions
cannot overwrite earlier ones. There is no general typed `allOf` constructor in
this extension. Primitive modifiers, array/object constraints, and defaults
should be defined on the base before adding conditionals; existing modifiers
reject unsupported wrapper nodes rather than dropping conditional checks.

For object inspection, use required fields to make presence part of the
condition. Open inspector records can require selected fields without rejecting
other fields of the base input. A closed inspector imposes its full closed shape.
A failed condition does not itself reject input, but the base must still accept.
All condition and branch references participate in graph finalization even when
a branch cannot be selected. Same-input recursive cycles are conservatively
rejected, including unreachable branches; no satisfiability analysis is performed.

The equation provider's `editor.initialAnswerVisible` rule supplies a consumer
example: when that flag is explicitly true, require a sequence. A decoder default
of true on an absent flag would not trigger this input-level condition. The app's
existing semantic check and dependency pin remain unchanged.
