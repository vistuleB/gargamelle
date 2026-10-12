# Encoder prototype for review

The experiment lives under `verification/encoder/`; it is not a shipped module
or a release preparation. Run it with:

```sh
node --test verification/encoder.test.mjs
```

## Proposed shape

`Encoder(a)` explicitly describes how to produce JSON from `a`. Primitive encoders
compose into arrays, nullable values and records. Record fields supply getters;
the encoder does not inspect Gleam records or reverse their constructors.
`contramap` adapts an encoder using a getter or projection. `choice` encodes the
selected branch of a `Result`, which can be projected from an application sum type.

The two output routes are:

```text
encode_json(Encoder(a), a) → Result(Json, EncodingError)
encode(Codec(a), a)        → Result(VerifiedJson(a), EncodingError)
```

`codec(encoder, definition)` pairs an encoder and a definition with the same
output type. That shared type does not prove schema agreement. Checked encoding
constructs admitted JSON, then forwards it through a stored boundary; contract
violations produce the definition's full data errors. The certificate retains
original JSON and the one decoded result, exactly as an ingress boundary does.

For example, a record encoder supplies a getter for each field:

```gleam
import encoder as e
import gargamelle as s

pub type Named {
  Named(name: String)
}

pub fn main() {
  let assert Ok(record) =
    e.field(e.record(), "name", e.text(), fn(value: Named) { value.name })
  let encoder = e.finish(record)
  let assert Ok(record) =
    s.required(s.record(Named), "name", s.text())
  let definition = s.finish(record, s.Strict)
  let codec = e.codec(encoder, definition)
  let assert Ok(verified) = e.encode(codec, Named("Brainy"))
  s.verified_data(verified)
}
```

`optional_field` omits a field when its getter returns `None`. A regular `field`
with a `nullable` encoder instead emits `null` for `None`. Duplicate keys are
construction errors. Arbitrary finite floats and safe integers have separate
encoders; nonfinite numbers and unsafe integers are rejected rather than silently
altered. Admission enforces Gargamelle's Unicode-scalar string and key domain.

## Decisions to review

- An encoder is independent of a decoder. A `Codec` pairs them for checked
  output; it does not claim they are inverses. In particular, decoding may map,
  insert defaults or project fields. The retained decoded value is the result of
  decoding the produced JSON, not assumed to equal the original input `a`.
  Reusing the original `a` as the certificate's decoded data would violate this
  rule for codecs whose encoders and definitions do not round-trip identically.
- Reuse the existing opaque boundary to create the certificate. No additional
  standalone `VerifiedJson` constructor or definition-identity mechanism is needed.
- Recursive construction uses typed plans and a completed immutable closure.
  The builder runs once; an unfinished reference cannot be encoded. There are
  no casts, mutable reference cells, registries or release obligations. Completed
  recursive codecs and their output survive creator-process exit on Erlang.
- Unlike schema recursion, this prototype does not analyze whether an encoder
  descends. A recursive encoder that immediately calls itself can diverge.
  Getters and branch projections are trusted code, like decoding maps, and can
  raise operational exceptions. Whether to constrain recursion further remains
  an integration question.
- Encoding first constructs `gleam/json.Json`, serializes it, and calls Gargamelle
  `parse` once. Checked encoding then calls `decode` once through the boundary.
  This keeps the prototype outside the library while enforcing admission, but
  creates temporary JSON text. Production integration should assess cost and
  direct admitted-JSON construction before adopting this implementation.
- Encoding errors currently stop at the first failing getter/primitive and have
  no structured field path. Contract errors retain existing JSON Pointer details.
  Better encoding diagnostics, dictionaries, tagged-union helpers and mutual
  recursion are follow-up candidates, not prototype guarantees.

## Evidence

The initial experiment passes 12 behavioral tests on each target, including
primitive and recursive record round trips, optional omission versus null,
constraint and shape rejection, duplicate fields, safe-integer limits, single
conversion, non-inverse mappings, and process-independent recursive construction.
Five forbidden programs fail compilation on both targets. JavaScript admission
checks reject infinity, negative infinity, NaN, and lone surrogates in values
and keys. Six output cases are checked independently with Ajv and Hyperjump.
The guide's record example compiles and runs on both targets, getter exceptions
propagate, and the complete `npm test` run passes 52 shared Gleam tests and 150
Node checks, including the isolated prototype gate.

The existing production decoder and schema emitter are unchanged. This evidence
supports continuing the prototype; it is not a complete encoder contract or a
new release qualification.
