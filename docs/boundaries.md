# Verified JSON boundaries

A `Boundary(a, response)` binds an input definition to a handler. The host calls
`forward` with admitted JSON. Gargamelle decodes it against the boundary's stored
definition before invoking the handler. Invalid input returns decoding errors
and the handler does not run.

The handler receives an opaque `VerifiedJson(a)` containing the original `Json`
and the decoded `a`. `verified_json` and `verified_data` retrieve those values
without repeating validation or conversion.

```gleam
import gargamelle
import gleam/io
import gleam/string

// The component publishes a boundary; its handler stays private.
pub fn names_boundary() -> gargamelle.Boundary(List(String), String) {
  gargamelle.boundary(
    gargamelle.array(gargamelle.text()),
    fn(input) { string.join(gargamelle.verified_data(input), ", ") },
  )
}

pub fn main() {
  let boundary = names_boundary()
  let definition = gargamelle.boundary_definition(boundary)
  io.println(gargamelle.schema_string(definition, gargamelle.Pretty))
  let assert Ok(json) = gargamelle.parse("[\"Brainy\", \"Jokey\"]")
  let assert Ok(response) = gargamelle.forward(boundary, json)
  io.println(response)
}
```

This prints the array-of-strings schema followed by `Brainy, Jokey`.
`boundary_definition` exposes the exact definition used for acceptance, so the
host can review its schema before accepting the boundary. Through the Gleam API,
the host cannot extract the handler or replace the definition within an existing
boundary.

## What is verified

`VerifiedJson(a)` means the stored JSON successfully decoded under the definition
used to create it. The type parameter describes the decoded output type, not the
identity of that definition. Two `Definition(String)` values may accept different
strings. A function accepting a standalone `VerifiedJson(String)` therefore cannot
assume a particular string constraint. Use a boundary to bind the check and the
handler invocation; `forward` accepts `Json`, not a certificate from another boundary.

The original JSON is retained as admitted. An `Open` record may discard extra
fields from decoded data; those fields remain in `verified_json`. Defaults and
maps affect decoded data without rewriting the stored JSON. Both representations
remain reachable while the wrapper is retained, with memory use depending on the
definition and runtime sharing.

## Callbacks and responses

`forward` validates and converts once, then invokes the handler once. Invalid
input runs neither conversion callbacks nor the handler. Accessing stored data
does not rerun callbacks. Conversion callbacks and handlers are trusted code;
exceptions and resource failures propagate as operational failures.

The response is whatever the handler returns. If it returns `Result(response,
application_error)`, `forward` returns `Result(Result(response, application_error),
List(DataError))`, keeping application errors separate from input failures.
It does not validate outgoing JSON or provide an encoder.

The boundary enforces the supplied definition. The host must still approve that
contract and apply any additional application policy. These opaque types enforce
access through Gleam's public API; they do not isolate hostile JavaScript, Erlang
or foreign-function code running in the same runtime.
