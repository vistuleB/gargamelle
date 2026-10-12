# Gargamelle

[![Package Version](https://img.shields.io/hexpm/v/gargamelle)](https://hex.pm/packages/gargamelle)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gargamelle/)

Gargamelle generates a typed JSON decoder and a JSON Schema 2020-12 document
from one Gleam definition.

See the [technical contract](https://hexdocs.pm/gargamelle/0.4.0/contract.html).

Gargamelle also provides boundary APIs that bind a definition to a handler.
Incoming JSON is validated against that definition before the handler runs.
Handlers receive decoded Gleam values and the original JSON, or verified JSON
without decoding. Boundary APIs are optional; definitions, decoding and schema
generation can be used directly.

Definitions can also generate browsable HTML documentation.

| Operation | API |
| --- | --- |
| JSON decoding into a Gleam value | `decode` |
| JSON Schema generation | `schema_json` / `schema_string` |
| Validated handler invocation with decoded data | `boundary` → `Boundary` + `forward` |
| Validated handler invocation without decoding | `json_boundary` → `JsonBoundary` + `forward_json` |
| JSON retention with the accepting definition | `verify` → `VerifiedJson` |

## Getting started

Requires Gleam 1.18.1 or later.

Package installation:

```sh
gleam add gargamelle@0.4.0
```

### JavaScript

Target configuration in `gleam.toml`:

```toml
target = "javascript"
```

### Erlang

Target configuration in `gleam.toml`:

```toml
target = "erlang"
```

The native regex helper requires `make` and a C compiler. Helper compilation:

```sh
gleam deps download
make -C build/packages/gargamelle/priv/regex-src
```

[Native Erlang setup](https://hexdocs.pm/gargamelle/0.4.0/native-erlang.html)
documents tested runtimes and deployment requirements.

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
`schema_string` returns the schema as a `String`. `Pretty` uses two-space
indentation; `Compact` produces canonical JSON. `to_string(json, format)` serializes
any Gargamelle `Json`, not just schemas.

Parsing and decoding errors are separate results. The example uses assertions
for brevity; application code handles those errors explicitly. `validate` checks
acceptance without constructing the decoded output.

## Receiving boundaries

A boundary binds a handler to its input definition. Submission validates JSON
against the stored definition and invokes the handler only on success, combining
validation and handler invocation in one operation.

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

`boundary_definition` and `json_boundary_definition` expose the receiving
definition for inspection and schema generation.
[Verified JSON boundaries](https://hexdocs.pm/gargamelle/0.4.0/boundaries.html)
documents certificate retention and application responses.

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

The [technical contract](https://hexdocs.pm/gargamelle/0.4.0/contract.html)
specifies the JSON domain, external validator settings, decoded-value semantics and limits.

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

[Advanced definitions](https://hexdocs.pm/gargamelle/0.4.0/advanced.html)
documents these features and the HTML documentation recipe.

## Limitations

JavaScript is tested on Node 24.10.0, Chrome 155, Firefox 157 and Safari 27.
Native Erlang requires a C regex helper and is tested on macOS arm64 with OTP 29
and Ubuntu 24.04 x86_64 with OTP 28.5.0.7 and 29.1.1.
[Browser compatibility](https://hexdocs.pm/gargamelle/0.4.0/browser-support.html)
and [Native Erlang setup](https://hexdocs.pm/gargamelle/0.4.0/native-erlang.html)
document the compatibility matrix, regex Unicode differences and deployment requirements.
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

Gargamelle is distributed under the MIT License.
[Licenses](https://hexdocs.pm/gargamelle/0.4.0/license.html) contains the library,
native regex engine and retained JSON Schema test-suite notices.
