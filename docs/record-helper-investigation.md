# Static record-helper investigation

Private prototype on the development branch; no shipped module, README, release
metadata, or consumer source changed. Files remain under verification/experiments.

## Result and recommendation

Shared declarations remove a concrete duplication: each field name is declared
once beside its definition, encoder, and getter. The four-field example drops
from 48 formatted lines for separate definition/encoder construction to 29 for
shared construction, including function boundaries. The common curried constructor
and bounded-age definition are excluded from both counts. This is an example,
not a general readability or performance measurement.

Retain this prototype as evidence for an optional record helper. Shared declarations
are the stronger candidate: they make field-name discrepancies harder to introduce.
Result-chaining helpers alone remove repeated assertions but offer limited benefit
over ordinary Result handling. Neither requires a change to core record operations.
Promotion into the public API has not been performed.

[Sextant's field-declaration style](https://sextant.hexdocs.pm/sextant.html)
inspired this investigation. Its documentation describes schema generation with
zero-value placeholders when later fields depend on decoded values. This prototype
uses static Result pipelines instead. Shared encoding declarations are a separate
extension; no Sextant implementation was copied.

## Excluded convenience helper

A separate Result-chaining helper was evaluated and not retained in this commit.
It reduced repeated assertions but did not remove currying or duplicated field
names. The shared builder already provides the useful Result chaining while
keeping definition and encoder declarations together.

## Shared decoding/encoding declarations

shared_record stores the existing definition and encoder builders together. Each
operation receives the field's name, definition, encoder, and getter. Required and
defaulted fields use ordinary getters; optional getters return Option. Finishing
returns a Definition/Encoder tuple, not a certificate of their equivalence:

```gleam
pub fn shared() {
  shared_record.start(constructor())
  |> shared_record.required(
    "name",
    gargamelle.text(),
    gargamelle_encoding.text(),
    fn(person: Person) { person.name },
  )
  |> shared_record.required(
    "age",
    age_definition(),
    gargamelle_encoding.safe_integer(),
    fn(person) { person.age },
  )
  |> shared_record.optional(
    "nickname",
    gargamelle.text(),
    gargamelle_encoding.text(),
    fn(person) { person.nickname },
  )
  |> shared_record.defaulted(
    "active",
    gargamelle.boolean(),
    gargamelle_encoding.boolean(),
    fn(person) { person.active },
    gargamelle.json_bool(True),
  )
  |> shared_record.finish(gargamelle.Strict)
}
```

The same compiled example supplies Person, constructor, age_definition, imports,
and main. Its output is:

```json
{"active":true,"age":3,"name":"Azrael"}
```

## Guarantees and limitations

- Field definitions are fixed during construction. No decoded field value or
  invented placeholder is supplied to subsequent declarations.
- Required, optional, and defaulted presence semantics are unchanged. Defaulted
  fields are optional at ingress; the encoder emits the current typed field value.
- Construction invokes no record constructors, decoding conversions, or getters.
  As with ordinary calls, expressions used to prepare arguments still execute.
- Duplicate/non-scalar names and invalid defaults retain the underlying diagnostics.
  Shared construction checks the definition first and wraps construction errors in
  Definition/Encoding variants; the original error payload remains unchanged.
- Matching Gleam types do not prove matching constraints or inverse behavior.
  Unchecked encoding remains unchecked. Codec or receiving-boundary verification
  remains necessary for output constraints; a deliberately mismatched encoder is
  rejected by checked encoding.
- Shared construction currently accepts only completed definitions and encoders.
  Open recursion environments are deliberately outside this bounded prototype.
- Explicit getters and the curried constructor remain. No full Sextant-style
  syntax, new semantic checks, schema keywords, or automatic encoder inference is
  introduced. This does not demonstrate that curried constructors can be removed.

## Verification

Command: node --test verification/experiments/record-helpers.test.mjs

- Seven Gleam comparisons and the complete example pass on JavaScript and Erlang.
- Compact schema output is identical for baseline and shared forms.
- A fixed 270-case product has 16 accepted and 254 rejected cases. Validation,
  decoding, decoded values, and error details match; Ajv and Hyperjump independently
  agree on acceptance. Successful decoded values encode identically and still
  satisfy the definition.
- Missing, defaulted, optional, wrong-type, extra-key, numeric-bound, and unsafe
  encoder-value cases are exercised. Duplicate declarations, invalid defaults,
  first-error retention, escaped pointer paths, and JavaScript non-scalar values
  retain their existing errors.
- Three invalid declarations fail compilation on both targets: incomplete
  constructor, wrong getter type, and wrong encoder type.
- A compiling mutation that changes the encoder's field name is detected by the
  output/checked-error comparisons.

This is bounded comparison evidence for the optional wrappers, not a general
proof of all record combinations or release qualification. Existing unrelated
generation/shrinking work remains separate and uncommitted.
