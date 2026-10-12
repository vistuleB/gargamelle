# Verified JSON boundaries

A `Boundary(a, response)` binds an input definition to a handler. The host calls
`forward` with admitted JSON. Gargamelle decodes it against the boundary's stored
definition before invoking the handler. Invalid input returns decoding errors
and the handler does not run.

The handler receives two arguments: the decoded `a` and the original `Json`.
If only the data is needed, ignore the second argument. The boundary decodes
once; it does not construct a certificate or retain either value after the call
unless application code retains them.

```gleam
import gargamelle
import gleam/io
import gleam/string

// The component publishes a boundary; its handler stays private.
pub fn names_boundary() -> gargamelle.Boundary(List(String), String) {
  gargamelle.boundary(
    gargamelle.array(gargamelle.text()),
    fn(names, _) { string.join(names, ", ") },
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

## JSON-only receiving handlers

For storage or transport that needs only JSON, use
`json_boundary(definition, handler)` and `forward_json(receiver, json)`.
The private handler receives `VerifiedJson(a)` after the receiver's stored
definition accepts the input. No decoded value is constructed and no conversion
callback runs. `json_boundary_definition` exposes that exact checked definition.

```gleam
import gargamelle
import gleam/io

pub fn main() {
  let receiver = gargamelle.json_boundary(
    gargamelle.array(gargamelle.text()),
    fn(verified) {
      gargamelle.to_string(gargamelle.verified_json(verified), gargamelle.Compact)
    },
  )
  let assert Ok(json) = gargamelle.parse("[\"Brainy\", \"Jokey\"]")
  let assert Ok(text) = gargamelle.forward_json(receiver, json)
  io.println(text)
}
```

This prints `["Brainy","Jokey"]`, without constructing a decoded list.

Each submission performs one Gargamelle contract check. Admission, authorization,
storage limits and other host policies are separate checks. Submission accepts
`Json`, not a certificate from another contract. If a handler returns `Result`,
the application result is nested inside the outer validation result. Handler
exceptions and resource failures propagate as operational failures.

For a future typed output path, pair an encoder with this receiving boundary,
encode to admitted unverified JSON, and call `forward_json` once. The receiving
definition is authoritative; there is no separate codec definition to reconcile.

## Retaining verified JSON

`verify(definition, json)` checks acceptance without constructing a decoded value
or invoking conversion callbacks. It returns `Result(VerifiedJson(a), List(DataError))`.
The opaque certificate retains the JSON and the exact definition that accepted it.
`verified_json` retrieves the original JSON; `verified_definition` retrieves its
checked contract. Neither accessor validates or decodes.

The parameter `a` describes the definition's output type, not its identity or
constraints. Two `Definition(String)` values may accept different strings. A
function accepting a standalone `VerifiedJson(String)` therefore cannot assume
a particular string constraint. Use a boundary to bind the check and handler
invocation; `forward` accepts `Json` and always checks its own stored definition.

The certificate contains no decoded data. To obtain a Gleam value later, call
`decode(verified_definition(verified), verified_json(verified))`, or forward its
JSON through the recipient's boundary. That performs validation and conversion
at that time. Verification is useful when transporting JSON without needing its
decoded representation immediately.

The original JSON is preserved as admitted. An `Open` record may discard extra
fields from decoded data; those fields remain in the original JSON. Defaults and
maps affect decoded data without rewriting JSON. Verification retains the JSON
and definition, including closures captured by that definition, but no decoded tree.

## Callbacks and responses

`forward` validates and converts once, then invokes the handler once. Invalid
input runs neither conversion callbacks nor the handler. `verify` never invokes
conversion callbacks. Conversion callbacks and handlers are trusted code;
exceptions and resource failures propagate as operational failures.

The response is whatever the handler returns. If it returns `Result(response,
application_error)`, `forward` returns `Result(Result(response, application_error),
List(DataError))`, keeping application errors separate from input failures.
It does not validate outgoing JSON or provide an encoder.

The boundary enforces the supplied definition. The host must still approve that
contract and apply any additional application policy. These opaque types enforce
access through Gleam's public API; they do not isolate hostile JavaScript, Erlang
or foreign-function code running in the same runtime.
