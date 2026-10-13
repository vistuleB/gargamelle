# Verified JSON boundaries

A `Boundary(a, response)` binds an input contract to a handler. The host calls
`forward` with admitted JSON. Gargamelle decodes it and runs the boundary's stored semantic requirements
before invoking the handler. Rejected input returns `ContractError`
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
    gargamelle.contract(gargamelle.array(gargamelle.text())),
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
`boundary_definition` exposes the structural definition used for acceptance, so the
host can review its schema before accepting the boundary. Through the Gleam API,
the host cannot extract the handler or replace the contract within an existing
boundary.

## JSON-only receiving handlers

For storage or transport that needs only JSON, use
`json_boundary(contract, handler)` and `forward_json(receiver, json)`.
The private handler receives `VerifiedJson(a)` after the receiver's stored
contract accepts the input. With no semantic requirements, no decoded value is
constructed and no conversion callback runs. With requirements, decoding runs
once to supply the checks; the decoded value is then discarded.
`json_boundary_contract` exposes the full contract; `json_boundary_definition`
exposes its structural definition.

```gleam
import gargamelle
import gleam/io

pub fn main() {
  let receiver = gargamelle.json_boundary(
    gargamelle.contract(gargamelle.array(gargamelle.text())),
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

For typed output, `encoding.output_boundary(encoder, receiver)` pairs an explicit
encoder with this receiving boundary. `encoding.send` encodes to admitted
unverified JSON and calls `forward_json` once. The receiving contract is
authoritative; there is no separate codec contract to reconcile.
See [Typed JSON encoding](encoding.html) and the complete
[provider loading and saving example](provider-roundtrip.html).

## Paired loading and saving

`paired_boundary(contract, encode, load_handler, save_handler)` registers both
handlers against one stored full contract. `load` decodes incoming JSON before
calling the loading handler; `save` encodes a value and checks the resulting JSON
before calling the saving handler. Each submission performs one contract check.
This counts checks performed by the boundary; application encoding callbacks may
perform additional work.

The encoder argument is a function producing admitted, unchecked JSON. For a
Gargamelle encoder, pass `encoding.encode_json(encoder, _)`. Checked `encoding.encode`
produces a certificate instead of `Json` and cannot be supplied here. The main
module accepts this function to remain independent of `gargamelle/encoding`.

The following replaces `main` in the complete
[provider loading and saving example](provider-roundtrip.html), using its
`Evidence`, `evidence_contract`, and `evidence_encoder` declarations and imports:

```gleam
pub fn main() {
  let registration =
    gargamelle.paired_boundary(
      evidence_contract(),
      encoding.encode_json(evidence_encoder(), _),
      fn(evidence, _) { evidence },
      fn(verified) {
        gargamelle.to_string(
          gargamelle.verified_json(verified),
          gargamelle.Compact,
        )
      },
    )
  let assert Ok(json) =
    gargamelle.parse("{\"answers\":[true,false],\"score\":1}")
  let assert Ok(evidence) = gargamelle.load(registration, json)
  let assert Ok(stored) = gargamelle.save(registration, evidence)
  io.println(stored)
  let assert Error(gargamelle.ContractRejected(gargamelle.Semantic(_))) =
    gargamelle.save(registration, Evidence([True, False], 2))
  io.println("Save rejected: score does not match answers")
}
```

Output:

```text
{"answers":[true,false],"score":1}
Save rejected: score does not match answers
```

`PairedBoundary(a, loaded, saved, encoding_error)` retains independent handler
response types and the encoding function's concrete error type. Type inference
usually determines these parameters without annotations. `paired_boundary_contract`
returns the exact full contract used at both sides, without invoking callbacks.

`load` returns `Result(loaded, ContractError)`. `save` returns
`Result(saved, SaveError(encoding_error))`, distinguishing `EncodingFailed(error)`
from `ContractRejected(error)`. Structural or semantic rejection skips the saving
handler. Encoding rejection also skips contract checks. Handler `Result` responses
remain nested, and callback exceptions propagate as operational failures.

The saving contract remains authoritative even for an application-supplied encoder.
Without semantic requirements, saving validates without conversion. With requirements,
it decodes the emitted JSON once and checks that reconstructed value. It does not
check the encoder input directly. Loading and saving need not be inverses, are not
a transaction, and need not occur together. No individual endpoint or handler can
be extracted or replaced through the paired boundary's public API.

## Semantic requirements

A contract can add checks that JSON Schema does not express. This complete
example checks whether a decoded name agrees with immutable bound context:

```gleam
import gargamelle
import gleam/io

pub fn main() {
  let expected = "Brainy"
  let contract = gargamelle.contract(gargamelle.text())
    |> gargamelle.require("Name agrees with the registered name", fn(name) {
      case name == expected {
        True -> Ok(Nil)
        False -> Error([gargamelle.Violation("", "Unexpected name")])
      }
    })
  let receiver = gargamelle.json_boundary(contract, fn(verified) {
    gargamelle.to_string(gargamelle.verified_json(verified), gargamelle.Compact)
  })
  let assert Ok(json) = gargamelle.parse("\"Brainy\"")
  let assert Ok(response) = gargamelle.forward_json(receiver, json)
  io.println(response)
}
```

This prints `"Brainy"`. The underlying string schema also accepts `"Jokey"`,
but the full contract rejects it before the handler runs. Semantic requirements
inspect decoded data and cannot repair or transform it. Requirements must be
pure and total, with immutable captured context.

`contract_requirements` lists descriptions in declaration order.
`documentation.render_contract` renders the structural definition followed by
all requirement descriptions without running checks. Generated JSON Schema
contains only the structural rules. Descriptions document intended behavior;
they do not prove that callbacks implement it.

## Retaining verified JSON

`verify(contract, json)` returns `Result(VerifiedJson(a), ContractError)`.
It validates without conversion if the contract has no semantic requirements;
otherwise it decodes once and checks the decoded value. The opaque certificate
retains original JSON and the exact full contract, but no decoded data.
`verified_json` retrieves the JSON; `verified_contract` retrieves the full contract;
`verified_definition` retrieves only its structural definition. These accessors
execute no callbacks.

The parameter `a` describes an output type, not contract identity or constraints.
Two `Contract(String)` values may accept different strings. A standalone
`VerifiedJson(String)` therefore does not establish particular constraints.
Receiving boundaries bind checks and handler invocation; forwarding always
checks the recipient's contract, even if another contract accepted that JSON.

To obtain decoded data later, call
`decode_contract(verified_contract(verified), verified_json(verified))`, which
repeats validation, conversion and semantic checks. A typed receiving boundary
avoids that additional work when decoded data is needed immediately.

The original JSON is preserved as admitted. An `Open` record may discard extra
fields from decoded data; those fields remain in the original JSON. Defaults and
maps affect decoded data without rewriting JSON. Verification retains the JSON
and contract, including closures captured by its definition and requirements, but no decoded tree.

## Callbacks and responses

`forward` validates and converts once, runs semantic checks, then invokes the
handler once on acceptance. Structural rejection skips conversion, requirements
and the handler. Semantic rejection skips the handler. Every normal requirement
result is collected in declaration order. Exceptions propagate and may stop later
checks. Conversion callbacks, requirements and handlers are trusted code.

`ContractError.Structural` contains structural `DataError` values;
`ContractError.Semantic` contains `RequirementFailure` values with zero-based
requirement indices, descriptions and `Violation(path, message)` diagnostics.
See [Diagnostic presentation](diagnostics.html) for bounded summaries and complete
JSON reports.

An empty rejection list is replaced with a root violation, so it cannot become
acceptance. Paths are application-supplied JSON Pointers.

The response is whatever the handler returns. If it returns `Result(response,
application_error)`, `forward` returns `Result(Result(response, application_error),
ContractError)`, keeping application errors separate from input failures.
It does not validate outgoing JSON or provide an encoder.

The boundary enforces the supplied contract. The host must still approve that
contract and apply any additional application policy. These opaque types enforce
access through Gleam's public API; they do not isolate hostile JavaScript, Erlang
or foreign-function code running in the same runtime.
