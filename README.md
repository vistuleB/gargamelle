# Gargamelle

Gargamelle builds a typed JSON decoder and a JSON Schema 2020-12 document from the
same Gleam definition. Validate incoming JSON, construct application values, and
optionally render HTML documentation with checked examples.

The [technical contract](https://github.com/vistuleB/gargamelle/blob/main/docs/contract.md)
specifies schema/decoder equivalence, decoded-value semantics, canonical emission,
and the assumptions and limits of those guarantees.

Gargamelle targets JavaScript and is tested on Node 24. Erlang, browsers, Bun and
Deno are not verified.
Gargamelle implements the schema vocabulary exposed by its constructors, not a
validator for arbitrary imported JSON Schemas. APIs may change before 1.0.

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
binary64 numbers. Parsing may round literals and collapse duplicate object keys.
The equivalence assumes pure, total callbacks, sufficient runtime resources, and
external validation of the same parsed value without coercion, inserted defaults
or removed properties. Admission failure, structural rejection and operational
failure are distinct; exceptions and resource exhaustion are not rejection.

`emit_text(S)` is byte-stable canonical JSON. Parsing it recovers `emit_json(S)`
as a JSON value. This is a schema serialization round trip; there is no typed
encoder or decode/encode inversion guarantee. Defaults, projection and maps can
lose information, and some output values may be unreachable.

The [technical contract](https://github.com/vistuleB/gargamelle/blob/main/docs/contract.md)
specifies the complete intended semantics. [Preservation arguments](https://github.com/vistuleB/gargamelle/blob/main/PRESERVATION.md)
and differential tests support these invariants; they are not a machine-checked
proof or a claim of full JSON Schema dialect support.

## Getting started

Install the package:

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

Handle admission errors separately from validation errors in application code;
these assertions only keep the introductory example short. `validate` checks
acceptance without invoking converters. `decode` validates before constructing
output. See the record and recursive examples below and the generated API docs.

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

[glon](https://hexdocs.pm/glon/) also derives a typed decoder and schema from one
definition. Gargamelle uses static curried record builders and a different error
model, so adopting it requires changes to definitions and call sites.
`safe_integer` deliberately restricts integers to JavaScript’s safe range; `number` accepts finite binary64 values.
`one_of` rejects overlapping matches; `any_of` converts the first matching branch.
Defaults are validated JSON inputs decoded through the field definition.
`optional` distinguishes absence from null; combine it with `nullable` when both
are allowed (the result is `Option(Option(a))`). Map or flatten that output if the
application wants one option. Parse text before decoding; `emit_json` returns
Gargamelle’s `Value`, while `emit_text` returns portable schema text.

Gargamelle also supports numeric/size bounds, patterns, dictionaries, guarded
recursion, exact tuples, property names, membership, conditionals and exclusion.
It does not currently provide arbitrary schema import, general intersections,
format assertions, `multipleOf`, fractional constants, encoding or migrations.

## Further documentation

- [Technical contract](https://github.com/vistuleB/gargamelle/blob/main/docs/contract.md): complete intended acceptance, output, emission and error semantics.
- [Advanced definitions](https://github.com/vistuleB/gargamelle/blob/main/docs/advanced.md): numeric constraints, recursion, tuples, key constraints, membership, conditionals, exclusion and HTML documentation.
- [Verification and development](https://github.com/vistuleB/gargamelle/blob/main/docs/verification-guide.md): setup commands, independent validators, generated coverage, retained discrepancies and release evidence.
- [Preservation arguments](https://github.com/vistuleB/gargamelle/blob/main/PRESERVATION.md): reasoning about how constructors preserve the contract.
- [Release checklist](https://github.com/vistuleB/gargamelle/blob/main/docs/releasing.md): packaging and publication checks.

## Verification

The library is checked with typed-output and rejection fixtures, generated
compositions, independent JSON Schema validators, selected official suite cases
and deliberate implementation mutations. These provide evidence for the contract,
not a formal proof or full-dialect conformance. See the verification guide for
commands, coverage and known validator discrepancies.

## License

Gargamelle is distributed under the [MIT License](LICENSE). The retained JSON Schema
test-suite fixtures carry their own [license](https://github.com/vistuleB/gargamelle/blob/main/verification/official/LICENSE).
