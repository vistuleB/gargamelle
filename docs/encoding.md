# Typed JSON encoding

`gargamelle/encoding` defines explicit encoders independently of decoders.
`Encoder(a)` describes how to produce admitted JSON from `a`. Record encoders
supply getters; the library does not inspect records, derive encoders from
`Definition(a)`, or reverse decoding constructors.

| Operation | API | Result on success |
| --- | --- | --- |
| Plain admitted JSON encoding | `encode_json(encoder, value)` | `Json` |
| Encoding checked against a stored Contract | `encode(codec, value)` | `VerifiedJson(a)` |
| Typed output through a receiving boundary | `send(output, value)` | Handler response |

Encoder construction and checked encoding are in `gargamelle/encoding`, imported
as `gargamelle_encoding`. Output boundary construction, inspection, and `send` are
in `gargamelle/boundary`, imported as `gargamelle_boundary`.

## Record example

```gleam
import gargamelle/boundary as gargamelle_boundary
import gargamelle as s
import gargamelle/encoding as gargamelle_encoding
import gleam/io

pub type Named {
  Named(name: String)
}

pub fn main() {
  let assert Ok(fields) = gargamelle_encoding.field(gargamelle_encoding.record(), "name", gargamelle_encoding.text(), fn(value: Named) { value.name })
  let encoder: gargamelle_encoding.Encoder(Named) = gargamelle_encoding.finish(fields)
  let assert Ok(fields) = s.required(s.record(Named), "name", s.text())
  let contract = s.contract(s.finish(fields, s.Strict))
    |> s.require("Name is nonempty", fn(value) {
      case value.name == "" {
        True -> Error([s.Violation("/name", "Name must not be empty")])
        False -> Ok(Nil)
      }
    })

  let assert Ok(json) = gargamelle_encoding.encode_json(encoder, Named("Brainy"))
  io.println(s.to_string(json, s.Compact))

  let codec = gargamelle_encoding.codec(encoder, contract)
  let assert Ok(verified) = gargamelle_encoding.encode(codec, Named("Brainy"))
  io.println(s.to_string(s.verified_json(verified), s.Compact))

  let receiver = gargamelle_boundary.json(contract, fn(verified) {
    s.to_string(s.verified_json(verified), s.Compact)
  })
  let output = gargamelle_boundary.output(encoder, receiver)
  let assert Ok(response) = gargamelle_boundary.send(output, Named("Brainy"))
  io.println(response)
}
```

Output:

```text
{"name":"Brainy"}
{"name":"Brainy"}
{"name":"Brainy"}
```

These are three independent operations. Plain encoding does not claim conformance
with a schema or Contract. Checked encoding produces a certificate only after
its stored Contract accepts the encoded JSON. `codec_contract` exposes that exact
Contract. Encoding and decoding need not be inverses: projection, defaults and
maps may cause reconstructed data to differ from the original encoder input.
Semantic requirements check reconstructed data, not the encoder input directly.

## Receiving authority and callback counts

`output(encoder, receiver)` pairs an encoder with an existing
`JsonBoundary`. The receiver's Contract is the only acceptance authority;
`output_contract` exposes it; `output_definition` exposes its structural definition
for schema generation. Neither accessor runs callbacks. No second Contract or
definition is stored.

`send` performs plain encoding, then calls `forward_json` once. It does not use
checked `encode` before forwarding. There is one Gargamelle Contract check. A
Contract with no semantic requirements validates without conversion; otherwise
it decodes once and checks the decoded value. Accepted output invokes the handler
once. Structural, semantic, encoding or admission rejection invokes no handler.
Handler return values remain generic, including nested `Result` responses.

## Composition

Primitive encoders cover strings, booleans, null, finite numbers and safe integers.
`json()` composes already admitted Gargamelle JSON, including arbitrary metadata.
It preserves canonical JSON rather than source formatting or declaration order.
`array` preserves element order. `nullable` emits null for `None`; `optional_field`
omits its property for `None`. Required fields may use a nullable encoder when
absence and null need distinct treatment. Duplicate record keys fail construction.

`contramap` adapts an encoder with a getter or projection. `choice` encodes the
selected branch of a `Result`; a projection can adapt an application sum type.
Getters run in declaration order and encoding stops at its first failure.
Construction executes no getters or projections.

`recursive` builds a self-recursive encoder once using typed construction plans
and an immutable completed body. Only completed `Encoder(a)` values can execute;
construction references cannot be encoded or supplied as completed encoders.
`lift` composes a completed encoder into a plan with a recursion environment.
Encoders, codecs and output boundaries remain usable after creator-process exit
on Erlang. Recursion must descend through input; immediate self-calls can diverge.
Mutually recursive encoder pairs are not provided.

## Errors and limits

`EncodingError` distinguishes primitive failures, field construction failures,
final JSON admission failures, and receiving `ContractError` values.

| Error | Attribution | Reason |
| --- | --- | --- |
| `InvalidValue(path, problem)` | JSON Pointer into the would-be encoded JSON | `NonFiniteNumber`, `UnsafeInteger`, or `NonScalarString` |
| `InvalidField(name, problem)` | Supplied field name during construction | `DuplicateKey` or `NonScalarKey` |
| `Admission(path, error)` | Root for final admission failures | Underlying admission diagnostic |
| `Contract(error)` | Receiving Contract's existing diagnostics | Structural or semantic rejection |

Runtime paths refer to the output representation, not the source Gleam record.
For example, an invalid score in the third answer is attributed to
`/answers/2/score`. The root is `""`; an empty field name is `/`. Field-name tokens
escape `~` as `~0` and `/` as `~1`. Nullable, choice and projection wrappers do not
add artificial path segments. Recursive encoders retain the complete nested path.

String-domain checks run at the leaf before serialization, so invalid string
admission retains that location. Field construction identifies a rejected key
separately because an unfinished builder has no known containing JSON location.
The final whole-document admission remains a defensive check; failures there use
the root rather than an invented field attribution. Encoding stops at its first
failure and does not run later element encoders or field getters.

```gleam
import gargamelle/encoding as gargamelle_encoding
import gleam/io

pub fn main() {
  let encoder = gargamelle_encoding.array(gargamelle_encoding.safe_integer())
  let assert Error(gargamelle_encoding.InvalidValue(path, gargamelle_encoding.UnsafeInteger)) =
    gargamelle_encoding.encode_json(encoder, [42, 9_007_199_254_740_991 + 1])
  io.println(path)
}
```

Output:

```text
/1
```

Contract structural failures retain their existing JSON Pointer attribution;
semantic failures retain requirement indices and supplied paths.
Getters, projections, converters, requirements and handlers are trusted application
code. Exceptions and resource failures remain operational failures.

Encoding constructs intermediate `gleam/json.Json`, serializes
it and admits the JSON text once. This enforces the same admission domain as
`parse`, including finite binary64 numbers and Unicode scalar strings and keys.
It creates temporary text and does not claim single-pass encoding and certification.
Safe-integer encoders reject values outside the common safe range. General numeric
encoding uses `Float`; nonfinite values are rejected before serialization.

Direct JSON construction, additional collection helpers and
automatic encoder derivation are not provided.
