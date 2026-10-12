# Gargamelle

[![Package Version](https://img.shields.io/hexpm/v/gargamelle)](https://hex.pm/packages/gargamelle)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gargamelle/)

Gargamelle defines which JSON your application accepts, how to decode it into
Gleam values, and how to describe it with JSON Schema 2020-12—all from one
Gleam definition.

Its receiving boundaries check that JSON satisfies the stored definition before
invoking your handler. Handlers can receive decoded Gleam values or verified JSON
for storage and transport.

Gargamelle can also generate browsable HTML documentation from those definitions.

| You want to… | Use |
| --- | --- |
| Decode JSON into a Gleam value | `decode` |
| Generate the matching JSON Schema | `schema_json` / `schema_string` |
| Invoke a handler with validated, decoded data | `boundary` → `Boundary` + `forward` |
| Invoke a handler with validated JSON, without decoding | `json_boundary` → `JsonBoundary` + `forward_json` |
| Retain JSON with the definition that accepted it | `verify` → `VerifiedJson` |

## Getting started

Requires Gleam 1.18.1 or later.

Install Gargamelle:

```sh
gleam add gargamelle@0.4.0
```

### JavaScript

Set the target in your project's `gleam.toml`:

```toml
target = "javascript"
```

### Erlang

Set the target in your project's `gleam.toml`:

```toml
target = "erlang"
```

Install `make` and a C compiler, then build the native regex helper:

```sh
gleam deps download
make -C build/packages/gargamelle/priv/regex-src
```

See [Native Erlang setup](https://hexdocs.pm/gargamelle/0.4.0/native-erlang.html)
for tested runtimes and deployment instructions.

## Basic example

```gleam
import gargamelle
import gleam/io
import gleam/string

pub fn main() {
  let definition: gargamelle.Definition(List(String)) = gargamelle.array(gargamelle.text())
  let schema: String = gargamelle.schema_string(definition, gargamelle.Pretty)
  let assert Ok(json): Result(gargamelle.Json, _) = gargamelle.parse("[\"Brainy\", \"Jokey\"]")
  let assert Ok(data): Result(List(String), _) = gargamelle.decode(definition, json)

  io.println(schema)
  io.println(string.join(data, ", "))
}
```

Output:

```text
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "items": {
    "type": "string"
  },
  "type": "array"
}
Brainy, Jokey
```

`Definition(List(String))` describes both accepted JSON and decoded output.
`parse` returns opaque `Json`; `decode` produces `List(String)`. The `Result`
annotations describe the whole `Ok(...)` pattern; `_` leaves the error type inferred.
`schema_string` returns the schema as a `String`. Use `Pretty` for two-space
indentation or `Compact` for canonical JSON. `to_string(json, format)` serializes
any Gargamelle `Json`, not just schemas.

Handle parsing errors and decoding errors in application code; the assertions
keep this example short. `validate` checks acceptance without constructing the
decoded output.

## Receiving boundaries

Use a boundary when a handler must receive only input accepted by its declared
definition. It keeps the handler and that definition together, so callers submit
JSON through one operation instead of separately decoding and invoking the handler.

This complete example uses the same array-of-strings definition for two receivers:

```gleam
import gargamelle
import gleam/io
import gleam/string

pub fn main() {
  let names: gargamelle.Definition(List(String)) = gargamelle.array(gargamelle.text())
  let assert Ok(json): Result(gargamelle.Json, _) = gargamelle.parse("[\"Brainy\", \"Jokey\"]")

  let receiver = gargamelle.boundary(
    names,
    fn(decoded_names, _original_json) { string.join(decoded_names, ", ") },
  )
  let assert Ok(response): Result(String, _) = gargamelle.forward(receiver, json)
  io.println(response)

  let json_receiver = gargamelle.json_boundary(
    names,
    fn(verified) {
      gargamelle.to_string(gargamelle.verified_json(verified), gargamelle.Compact)
    },
  )
  let assert Ok(response): Result(String, _) = gargamelle.forward_json(json_receiver, json)
  io.println(response)
}
```

Output:

```text
Brainy, Jokey
["Brainy","Jokey"]
```

Both boundaries check their stored definition before invoking the handler.
`Boundary` also decodes and passes the typed data and original JSON;
`JsonBoundary` delivers a `VerifiedJson` certificate without running decoding
conversions. Invalid input does not invoke either handler.

`VerifiedJson(a)` retains the original admitted JSON and the exact definition that
accepted it. It does not contain a decoded `a`. The type parameter identifies the
definition's output type, not its particular constraints: two definitions producing
`String` can accept different inputs. Receiving boundaries always check their own
stored definition; a certificate from another definition cannot bypass that check.

Use `boundary_definition` or `json_boundary_definition` to inspect the receiving
definition or generate its schema. See [Verified JSON boundaries](https://hexdocs.pm/gargamelle/0.4.0/boundaries.html)
for retaining certificates and handling application responses.

## Guarantees and scope

- Validation, decoding acceptance and the generated schema describe the same
  structural rules within the documented JSON domain and validator settings.
- Receiving boundaries validate before invoking a handler; invalid input runs
  neither decoding conversions nor the handler.
- Application rules, such as whether a score agrees with its answers, need
  separate checks. A definition does not automatically express those rules.
- Conversion callbacks must be pure and total. Conversion or handler exceptions
  and resource failures remain operational failures, rather than validation errors.
- The opaque Gleam APIs enforce access through public operations. They are not a
  sandbox against hostile code in the same runtime.

See the [technical contract](https://hexdocs.pm/gargamelle/0.4.0/contract.html)
for the JSON domain, external validator settings, decoded-value semantics and limits.

## Typed records

```gleam
import gargamelle as s

pub type User { User(name: String, active: Bool) }

pub fn user_definition() -> s.Definition(User) {
  let assert Ok(fields) =
    s.record(fn(name) { fn(active) { User(name, active) } })
    |> s.required("name", s.text())
  let assert Ok(fields) = s.required(fields, "active", s.boolean())
  s.finish(fields, s.Strict)
}

pub fn read_user(source: String) {
  let assert Ok(json) = s.parse(source)
  s.decode(user_definition(), json)
}
```

For input `{"name":"Brainy","active":true}`, `read_user` returns
`Ok(User("Brainy", True))`. `s.Strict` rejects undeclared fields.
`s.schema_string(user_definition(), s.Pretty)` generates the record’s schema.

## More definitions

| Feature | Constructors |
| --- | --- |
| Recursive structures | `recursive`, `recursive_pair` |
| Tuples and array membership | `tuple`, `element`, `contains` |
| Object key and presence constraints | `property_names`, `dependent_required` |
| Conditional constraints and exclusion | `if_then`, `if_then_else`, `exclude` |
| Numeric constraints | `bounds`, `number_bounds`, `integer_multiple_of` |
| Schema metadata | `title`, `description`, `examples`, `default`, `format` |
| Explicit UUID validation | `assert_format(_, Uuid)` |

Metadata does not change acceptance. A schema `default` annotation does not insert
a value; a defaulted record field is a separate decoding feature. `format` is an
annotation, while `assert_format` adds validation constraints.

See [Advanced definitions](https://hexdocs.pm/gargamelle/0.4.0/advanced.html)
for these features and the HTML documentation recipe.

## Limitations

JavaScript is tested on Node 24.10.0, Chrome 155, Firefox 157 and Safari 27.
Native Erlang requires a C regex helper and is tested on macOS arm64 with OTP 29
and Ubuntu 24.04 x86_64 with OTP 28.5.0.7 and 29.1.1.
See [Browser compatibility](https://hexdocs.pm/gargamelle/0.4.0/browser-support.html)
and [Native Erlang setup](https://hexdocs.pm/gargamelle/0.4.0/native-erlang.html)
for the compatibility matrix, regex Unicode differences and deployment requirements.
Other runtimes and platforms are unverified; Windows native support is unavailable.

- Gargamelle supports the JSON Schema features exposed by its constructors. It
  does not validate arbitrary imported schemas or implement the full 2020-12 dialect.
- JSON numbers are finite parsed binary64 values; `safe_integer` uses JavaScript's
  safe-integer range. Strings and object keys must contain Unicode scalar values.
- General typed intersections, fractional divisibility and fractional constants
  are unsupported. `integer_multiple_of` supports exact safe-integer divisibility;
  UUID is the only supported explicit format assertion.
- Runtime resource use is not bounded. Parsing may round number literals and
  collapse duplicate object keys.
- There is no typed encoder, automatic decode/encode inverse or migration API.
  Defaults, projection and maps can lose information during decoding.

APIs may change before 1.0.

## Related libraries

Gargamelle was inspired by [glon](https://hexdocs.pm/glon/).

[Sextant](https://hexdocs.pm/sextant/sextant.html) also combines typed decoding with
JSON Schema 2020-12 generation. Its `use`-based field API supports definitions whose
later fields depend on earlier decoded values. Gargamelle uses static definitions
and curried record constructors; its schema describes structural acceptance, while
application rules are checked separately. Receiving boundaries bind those definitions
to handlers.

## Further documentation

- [Technical contract](https://hexdocs.pm/gargamelle/0.4.0/contract.html): complete intended acceptance, output, emission and error semantics.
- [Advanced definitions](https://hexdocs.pm/gargamelle/0.4.0/advanced.html): numeric constraints, recursion, tuples, key constraints, membership, conditionals, exclusion and HTML documentation.
- [Verified JSON boundaries](https://hexdocs.pm/gargamelle/0.4.0/boundaries.html): typed ingress and JSON-only receiving handlers.
- [Migrating to 0.4.0](https://hexdocs.pm/gargamelle/0.4.0/migration-0.4.html): boundary APIs and added schema constraints.
- [Migrating to 0.3.0](https://hexdocs.pm/gargamelle/0.4.0/migration-0.3.html): required API renames.
- [Migrating to 0.2.0](https://hexdocs.pm/gargamelle/0.4.0/migration-0.2.html): string requirements and changes to recursive construction.

## Verification

The library is checked with typed-output and rejection fixtures, generated
compositions, independent JSON Schema validators, selected official suite cases
and deliberate implementation mutations. These provide evidence for the contract,
not a formal proof or full-dialect conformance. The package source is
available in the [Hex archive](https://repo.hex.pm/tarballs/gargamelle-0.4.0.tar).

## License

Gargamelle is distributed under the MIT License. See [Licenses](https://hexdocs.pm/gargamelle/0.4.0/license.html)
for the library, native regex engine and retained JSON Schema test-suite notices.
