# Gargamelle

Gargamelle builds a typed JSON decoder and a JSON Schema 2020-12 document from the
same Gleam definition. Validate incoming JSON, construct application values, and
optionally render HTML documentation with checked examples.

Gargamelle began as an investigation into improving [glon](https://hexdocs.pm/glon/). It became an independent
implementation rather than a fork: no [glon](https://hexdocs.pm/glon/) source code was copied. [Glon](https://hexdocs.pm/glon/) inspired
the combined typed-decoder/schema approach, and issues found during that
investigation informed Gargamelle's regression tests.

This checkout is developing 0.2.0. JSON strings and object keys must contain only
Unicode scalar values; unpaired surrogates fail admission. The published 0.1.0
release retains its original JavaScript string domain.

The [technical contract](docs/contract.md)
specifies schema/decoder equivalence, decoded-value semantics, canonical emission,
and the assumptions and limits of those guarantees.

Gargamelle targets JavaScript and is tested on Node 24. APIs may change before 1.0.

## Getting started

Install the published 0.1.0 package:

```sh
gleam add gargamelle@0.1.0
```

Set `target = "javascript"` in your project’s `gleam.toml`:

```toml
target = "javascript"
```

```gleam
import gargamelle

pub fn read_names(source: String) {
  let assert Ok(value) = gargamelle.parse(source)
  gargamelle.decode(gargamelle.array(gargamelle.text()), value)
}

pub fn names_schema() {
  gargamelle.emit_text(gargamelle.array(gargamelle.text()))
}
```

For input `["Ada", "Grace"]`, `read_names` returns `Ok(["Ada", "Grace"])`.
`names_schema()` returns the following schema text:

```json
{"$schema":"https://json-schema.org/draft/2020-12/schema","items":{"type":"string"},"type":"array"}
```

Handle admission errors separately from validation errors in application code;
these assertions only keep the introductory example short. `validate` checks
acceptance without invoking converters. `decode` validates before constructing
output. See the typed record example below, the [recursive examples](https://hexdocs.pm/gargamelle/0.1.0/advanced.html), and the [API reference](https://hexdocs.pm/gargamelle/0.1.0/gargamelle.html).

## Design and contract

A `Definition(a)` specifies an acceptance predicate over admitted JSON and a
conversion from accepted inputs to `a`. The definition is authoritative; schema
emission, validation and decoding are interpretations of the same structural
representation. The opaque API prevents independently injecting a schema,
decoder or arbitrary rejection predicate.

For a finalized definition S and admitted input x, the intended invariant is:

```text
Valid202012(emit_json(S), x)
    ⇔ validate(S, x) = Ok(Nil)
    ⇔ ∃v. decode(S, x) = Ok(v)
```

This is an equivalence of acceptance, plus a contract for v. Arrays preserve order
and duplicates; dictionaries preserve keys; records construct declared types with
explicit presence, default and extra-field policies. `any_of` converts the first
matching branch; `one_of` accepts exactly one match. Maps change the output but
cannot add rejection rules. Optional nullable fields retain three states:
missing, present null, and present non-null.

Construction is static. Curried record builders collect field definitions without
probing callbacks with fabricated values. Validation and emission never execute
conversion callbacks. Decoding validates the original input before conversion;
auxiliary conditions, membership, exclusions and key constraints inspect that
input without running their converters. Semantic application checks belong after
structural decoding. New constructors must preserve both acceptance equivalence
and the specified decoded-value behavior.

The input domain is finite JSON trees after JavaScript parsing, with finite
binary64 numbers and Unicode scalar strings and keys. Parsing may round literals
and collapse duplicate object keys. Domain checks apply to the final parsed tree.
The equivalence assumes pure, total callbacks, sufficient runtime resources, and
external validation of the same parsed value without coercion, inserted defaults
or removed properties. Admission failure, structural rejection and operational
failure are distinct; exceptions and resource exhaustion are not rejection.

`emit_text(S)` is byte-stable canonical JSON. Parsing it recovers `emit_json(S)`
as a JSON value. This is a schema serialization round trip; there is no typed
encoder or decode/encode inversion guarantee. Defaults, projection and maps can
lose information, and some output values may be unreachable.

The [technical contract](docs/contract.md)
specifies the complete intended semantics. [Preservation arguments](PRESERVATION.md)
and differential tests support these invariants; they are not a machine-checked
proof or a claim of full JSON Schema dialect support.

## Typed records

```gleam
import gargamelle as s

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

## Comparison with glon

Both libraries derive a typed decoder and JSON Schema from one definition.
Gargamelle uses static curried record builders, checked JSON defaults, and separate
admission and validation errors. Its contract explicitly defines numeric limits,
optional-field presence, union matching, and callback execution.

## Limitations

- Erlang, browsers, Bun, and Deno are not verified.
- Only the JSON Schema features exposed by the constructors are supported.
  Gargamelle does not validate arbitrary imported schemas or implement the full
  Draft 2020-12 dialect.
- General typed intersections, format assertions, `multipleOf`, and fractional
  constants are not supported.
- Numbers use parsed binary64 values; `safe_integer` is limited to JavaScript's
  safe-integer range.
- Conversion callbacks must be pure and total. Exceptions and resource exhaustion
  remain operational failures; runtime resource use is not bounded.
- There is no typed encoder, automatic decode/encode inverse, or migration API.

## Further documentation

The HexDocs links below describe the published 0.1.0 release. The current
development contract is linked above.

- [Technical contract](https://hexdocs.pm/gargamelle/0.1.0/contract.html): complete intended acceptance, output, emission and error semantics.
- [Advanced definitions](https://hexdocs.pm/gargamelle/0.1.0/advanced.html): numeric constraints, recursion, tuples, key constraints, membership, conditionals, exclusion and HTML documentation.
- [Verification and development](https://hexdocs.pm/gargamelle/0.1.0/verification-guide.html): setup commands, independent validators, generated coverage, retained discrepancies and release evidence.
- [Preservation arguments](https://github.com/vistuleB/gargamelle/blob/v0.1.0/PRESERVATION.md): reasoning about how constructors preserve the contract.
- [Release checklist](https://github.com/vistuleB/gargamelle/blob/v0.1.0/docs/releasing.md): packaging and publication checks.

## Verification

The library is checked with typed-output and rejection fixtures, generated
compositions, independent JSON Schema validators, selected official suite cases
and deliberate implementation mutations. These provide evidence for the contract,
not a formal proof or full-dialect conformance. See the verification guide for
commands, coverage and known validator discrepancies.

## License

Gargamelle is distributed under the [MIT License](https://hexdocs.pm/gargamelle/0.1.0/license.html). The retained JSON Schema
test-suite fixtures carry their own [license](https://github.com/vistuleB/gargamelle/blob/v0.1.0/verification/official/LICENSE).
