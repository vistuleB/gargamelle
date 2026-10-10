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
seeded pairs, all 170 generic parent/child combinations and nine depth-50 chains.
Thirteen actual compiled-library mutations must fail behavioral assertions,
including five numeric validation, emission, and construction mutants. The three
new revision-3 mutations run the full foundation, typed-value and hardening suites.
Nine forbidden Gleam programs must fail compilation after a positive baseline.

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
