# Gargamelle

Gargamelle builds a typed JSON decoder and a JSON Schema 2020-12 document from the
same Gleam definition. Validate incoming JSON, construct application values, and
optionally render HTML documentation with checked examples.

Gargamelle began as an investigation into improving [glon](https://hexdocs.pm/glon/). It became an independent
implementation rather than a fork: no glon source code was copied. Glon inspired
the combined typed-decoder/schema approach, and issues found during that
investigation informed Gargamelle's regression tests.

This checkout contains the unreleased 0.2.0 candidate. JSON strings and object keys must contain only
Unicode scalar values; unpaired surrogates fail admission. The published 0.1.0
release retains its original JavaScript string domain.
Recursive builders now use construction plans; only completed definitions can
be decoded or emitted. See the [0.2.0 migration guide](https://hexdocs.pm/gargamelle/0.2.0/migration-0.2.html).

The [technical contract](https://hexdocs.pm/gargamelle/0.2.0/contract.html)
specifies schema/decoder equivalence, decoded-value semantics, canonical emission,
and the assumptions and limits of those guarantees.

JavaScript is tested on Node 24. The native Erlang implementation is tested on
macOS arm64 with OTP 29 and Ubuntu 24.04 x86_64 with OTP 28.5.0.7 and 29.1.1,
and requires a C helper; see [Native Erlang setup](https://hexdocs.pm/gargamelle/0.2.0/native-erlang.html).
Other native platforms and OTP releases remain unverified. APIs may change before 1.0.

## Getting started

After 0.2.0 is published, install it with:

```sh
gleam add gargamelle@0.2.0
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
output. See the typed record example below, the [recursive examples](https://hexdocs.pm/gargamelle/0.2.0/advanced.html), and the [API reference](https://hexdocs.pm/gargamelle/0.2.0/gargamelle.html).

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

The [technical contract](https://hexdocs.pm/gargamelle/0.2.0/contract.html)
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

## Limitations

- Native verification covers the runtime matrix above and Gleam shipment
  deployment. Other platforms, OTP releases and deployment tools are unverified.
  The regex helper uses POSIX APIs; Windows is not supported. Browsers, Bun and
  Deno are unverified.
- Native regex Unicode properties use Unicode 16 tables; JavaScript uses its
  host tables. Regex parity is verified against Node 24.10.0, not Node 24.21.0
  with Unicode 17.
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

The links below target the 0.2.0 documentation and will become available when
the candidate is published. The published 0.1.0 documentation remains available
at [HexDocs](https://hexdocs.pm/gargamelle/0.1.0/).

- [Technical contract](https://hexdocs.pm/gargamelle/0.2.0/contract.html): complete intended acceptance, output, emission and error semantics.
- [Advanced definitions](https://hexdocs.pm/gargamelle/0.2.0/advanced.html): numeric constraints, recursion, tuples, key constraints, membership, conditionals, exclusion and HTML documentation.
- [Verification and development](https://hexdocs.pm/gargamelle/0.2.0/verification-guide.html): setup commands, independent validators, generated coverage, retained discrepancies and release evidence.
- [Preservation arguments](https://github.com/vistuleB/gargamelle/blob/v0.2.0/PRESERVATION.md): reasoning about how constructors preserve the contract.
- [Release checklist](https://github.com/vistuleB/gargamelle/blob/v0.2.0/docs/releasing.md): packaging and publication checks.

## Verification

The library is checked with typed-output and rejection fixtures, generated
compositions, independent JSON Schema validators, selected official suite cases
and deliberate implementation mutations. These provide evidence for the contract,
not a formal proof or full-dialect conformance. See the verification guide for
commands, coverage and known validator discrepancies.

## License

Gargamelle is distributed under the [MIT License](https://hexdocs.pm/gargamelle/0.2.0/license.html). The retained JSON Schema
test-suite fixtures carry their own [license](https://github.com/vistuleB/gargamelle/blob/v0.2.0/verification/official/LICENSE).
