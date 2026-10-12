# Encoder prototype for review

This records the original isolated experiment. The 0.6.0 integration supersedes
its Definition-only Codec and check-free certification assumptions; see
[Encoder integration decisions](encoding-design.md) and
[Typed JSON encoding](encoding.md).

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
constructs admitted JSON, then calls `verify` against the stored definition;
contract violations produce the definition's full data errors. The certificate
retains JSON and the checked definition, without a decoded value. Checked
encoding invokes no decoding constructors or map callbacks.

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
  s.verified_json(verified)
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
  insert defaults or project fields. A recipient that decodes the produced JSON
  is not guaranteed to reconstruct the original input `a`. The certificate
  intentionally retains neither that input nor a reconstructed value.
- Use Gargamelle's public `verify` operation to create output certificates.
  `Codec` stores the actual definition alongside its encoder. There is no
  unchecked certificate constructor, and the certificate retains that definition
  so recipients can inspect which contract was checked. A recipient's boundary
  still checks against its own definition.
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
  `parse` once. Checked encoding then calls `validate` once through `verify`.
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
constraint and shape rejection, duplicate fields, safe-integer limits, zero
conversion during certification, non-inverse mappings when explicitly decoded,
and process-independent recursive construction.
Five forbidden programs fail compilation on both targets. JavaScript admission
checks reject infinity, negative infinity, NaN, and lone surrogates in values
and keys. Six output cases are checked independently with Ajv and Hyperjump.
The guide's record example compiles and runs on both targets, getter exceptions
propagate. Explicit decoding in round-trip tests is separate from certification;
checked encoding itself constructs no decoded value.

The existing production decoder and schema emitter are unchanged. This evidence
supports continuing the prototype; it is not a complete encoder contract or a
new release qualification.
