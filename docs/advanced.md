# Advanced definitions and documentation

These examples extend the core record and array workflows. Acceptance and output
semantics are specified in the [technical contract](https://hexdocs.pm/gargamelle/0.1.0/contract.html).

## Fractional numbers

`number()` returns `Definition(Float)` and accepts every finite number admitted by
`parse`, including integers and magnitudes outside the safe-integer range.
`number_bounds` intersects finite numeric endpoints; `None` leaves that side
unbounded. Apply bounds before naming a definition or composing it into a union.
Annotations and maps preserve the underlying number node and support bounds.

```gleam
import gargamelle
import gleam/option.{None, Some}

let assert Ok(probability) =
  gargamelle.number_bounds(
    gargamelle.number(),
    Some(gargamelle.Inclusive(0.0)),
    Some(gargamelle.Inclusive(1.0)),
  )
let assert Ok(positive) =
  gargamelle.number_bounds(gargamelle.number(), Some(gargamelle.Exclusive(0.0)), None)
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
`multipleOf` and fractional-number constants are not supported.

## Recursive definitions

`recursive(name, build)` creates a guarded self-recursive definition. Its builder
runs once with a typed definition reference, never a fabricated decoded value.
The builder returns `Result(Definition(a), ConstructionError)`. For example:

```gleam
import gargamelle as s
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
not validation rejections. 

## Optional HTML documentation

`gargamelle/documentation` renders annotated definitions as collapsible HTML
fragments. It is independent of the decoding module: applications that only
validate data need not import or ship it.

```gleam
import gargamelle
import gargamelle/documentation

let name = gargamelle.text() |> gargamelle.description("Display name")
let fragment = documentation.render(name, "display-name")
```

`render(definition, id)` returns an `<article>` fragment. Give each article a unique
ID. The renderer consumes Gargamelle's emitted representation internally rather than
exposing its private definition AST. `render_emitted(schema_json, id, aliases)`
accepts already-emitted Gargamelle schema JSON and returns `Result(String, String)`.
This is a renderer for Gargamelle's schema vocabulary, not a general JSON Schema
validator or documentation engine for arbitrary schema dialects.

Descriptions, field labels, constants, defaults and IDs are HTML-escaped. Object
fields, array items, dictionaries and union alternatives retain their nesting.
Shared `$defs` render once with local links; arbitrary discriminator names work.
Optional aliases are `(omitted_definition, displayed_definition)` pairs. They must
refer to existing definitions and may not chain. They only compress presentation;
the caller must explain any omitted distinctions. No domain-specific aliases are
built into Gargamelle.

The supplied [stylesheet](https://github.com/vistuleB/gargamelle/blob/v0.1.0/documentation/reference.css)
and [script](https://github.com/vistuleB/gargamelle/blob/v0.1.0/documentation/reference.js)
are separate assets in the source repository; they are not included in the Hex
package. Download the release-tagged files into the directory where you will
save your HTML page (repository access is required):

```sh
mkdir -p public
curl -fL https://raw.githubusercontent.com/vistuleB/gargamelle/v0.1.0/documentation/reference.css -o public/reference.css
curl -fL https://raw.githubusercontent.com/vistuleB/gargamelle/v0.1.0/documentation/reference.js -o public/reference.js
```

Save this complete page as `public/index.html`, replacing the marked comment with
the string returned by `documentation.render` in the example above. Insert that
string as HTML rather than escaping it:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Display name reference</title>
  <link rel="stylesheet" href="reference.css">
  <script src="reference.js" defer></script>
</head>
<body>
  <header><h1>Display name reference</h1></header>
  <div class="controls">
    <button type="button" data-fold="expand">Expand all</button>
    <button type="button" data-fold="collapse">Collapse all</button>
  </div>
  <main>
    <!-- Insert the rendered article here. -->
  </main>
</body>
</html>
```

Open `public/index.html` in a browser. See the [rendered sample](https://hexdocs.pm/gargamelle/0.1.0/renderer-sample.html)
for the article produced by this definition.

Native `<details>` folding needs no JavaScript. The optional script implements
the expand/collapse buttons, expands branches for printing, and restores their
previous state afterward. A host can supply its own stylesheet or embed the
fragment in an existing page. Page title, navigation, article grouping and
surrounding prose belong to the caller.

## Fixed-position arrays

`tuple` starts an opaque builder with a curried constructor. Each `element`
consumes one constructor argument; `finish_tuple` closes the array at exactly
that length. The result may be a Gleam tuple, a custom type, or another typed
value:

```gleam
let entry = gargamelle.tuple(fn(label) { fn(weight) { #(label, weight) } })
  |> gargamelle.element(gargamelle.text())
  |> gargamelle.element(gargamelle.number())
  |> gargamelle.finish_tuple
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
a translation dictionary can require locale-shaped keys:

```gleam
let assert Ok(locale) = gargamelle.pattern(
  gargamelle.text(), "^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$",
)
let assert Ok(translations) = gargamelle.property_names(
  gargamelle.dictionary(gargamelle.text()), locale,
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
Gargamelle with both Ajv and Hyperjump. The ordinary oracle remains strict; no
automatic fallback or runtime behavior change is introduced.

## Array membership

`contains(array_definition, matching_definition, minimum, maximum)` returns a
construction result with the original decoded output type. `minimum` is a
nonnegative safe integer; `maximum` is `None` or an inclusive safe integer at
least that minimum. For example, require one or two integer-valued elements
while preserving all decoded numbers:

```gleam
let assert Ok(values) = gargamelle.contains(
  gargamelle.array(gargamelle.number()), gargamelle.safe_integer(), 1, Some(2),
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

A content array can require at least one non-whitespace text item using a
matching text definition with the pattern `\S`. Other items still follow the
base item definition. If items include reference objects, checking whether those
references exist belongs in application code after decoding.

## Structural conditionals

`if_then(base, condition, consequence)` applies the consequence when the
condition accepts the input. `if_then_else(base, condition, consequence,
alternative)` validates exactly the selected branch. Both return a definition
with the base's original output type; the auxiliary definitions may have
independent output types. For example:

```gleam
let assert Ok(positive) = gargamelle.number_bounds(
  gargamelle.number(), Some(gargamelle.Exclusive(0.0)), None,
)
let checked = gargamelle.if_then(
  gargamelle.number(), positive, gargamelle.safe_integer(),
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

A settings record can require a `sequence` field when `showPreview` is explicitly
true. Use an open inspector record requiring `showPreview` with a `True` constant
as the condition, and another requiring `sequence` as the consequence. A decoder
default of true on an absent flag does not trigger this input-level condition.

## Structural exclusion

`exclude(base, forbidden)` requires the base to accept and the forbidden
structural definition to reject the original admitted input. It returns the
base's output type unchanged. The forbidden definition may have any output type;
its converters and mappings never run. For example, forbid integer-valued
numbers while retaining fractional `Float` values:

```gleam
let fractional = gargamelle.exclude(gargamelle.number(), gargamelle.safe_integer())
```

This example excludes only safe integers; it does not impose arbitrary-precision
numeric semantics or reject every integer-valued IEEE-754 number. Exclusion
always follows the exact structural contract supplied by the caller.

Repeated exclusions intersect their requirements. Emission conjoins the base
and each separate `not` schema in `allOf`, preserving earlier exclusions and
annotations. Exclusion failures use `excluded` at the input path. The forbidden
schema's own failures are not reported: its rejection is the condition for
passing this constraint. Operational exceptions still escape rather than being
interpreted as rejection. Base conversion runs only after all validation passes.

Defaults and projections do not affect exclusion selection because checks run
on original JSON. All references are collected even if the forbidden definition
could never accept a valid base input. Same-input recursive cycles, including
cycles through exclusion, are conservatively rejected. Excluding a definition
from itself can legitimately produce an unsatisfiable contract; construction does
not solve satisfiability. Apply primitive modifiers to the base before exclusion.

An identifier can use a nonempty text definition as its base and exclude strings
matching whitespace. Uniqueness across separately decoded records remains an
application check.

## Checked documentation examples

`documentation.render_examples(definition, id, examples)` accepts admitted JSON
values and returns HTML only when all examples validate against the current
definition. It returns every rejected example's zero-based index and ordinary
validation errors. It never decodes examples or executes mapping callbacks.
Examples represent input JSON, including its original missing fields, rather
than projected/defaulted outputs. HTML escapes examples, and an empty example
list produces the ordinary renderer output. Rechecking at render time catches
examples that become invalid after a definition changes.

