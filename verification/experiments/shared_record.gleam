//// Private shared static field declarations; no automatic encoder inference.

import gargamelle
import gargamelle/encoding as gargamelle_encoding
import gleam/option.{type Option}
import gleam/result

pub type BuildError {
  Definition(gargamelle.ConstructionError)
  Encoding(gargamelle_encoding.EncodingError)
}

pub opaque type Record(record, remaining) {
  Record(
    gargamelle.Record(remaining, Nil),
    gargamelle_encoding.Record(record, Nil),
  )
}

pub fn start(
  constructor: remaining,
) -> Result(Record(record, remaining), BuildError) {
  Ok(Record(gargamelle.record(constructor), gargamelle_encoding.record()))
}

pub fn required(
  builder: Result(Record(record, fn(value) -> remaining), BuildError),
  name: String,
  child: gargamelle.Definition(value),
  encode: gargamelle_encoding.Encoder(value),
  get: fn(record) -> value,
) -> Result(Record(record, remaining), BuildError) {
  use Record(definition, encoder) <- result.try(builder)
  use definition <- result.try(
    gargamelle.required(definition, name, child) |> result.map_error(Definition),
  )
  use encoder <- result.try(
    gargamelle_encoding.field(encoder, name, encode, get)
    |> result.map_error(Encoding),
  )
  Ok(Record(definition, encoder))
}

// Optional getters return Option(value); the definition/encoder describe value.
pub fn optional(
  builder: Result(Record(record, fn(Option(value)) -> remaining), BuildError),
  name: String,
  definition: gargamelle.Definition(value),
  encoder: gargamelle_encoding.Encoder(value),
  get: fn(record) -> Option(value),
) -> Result(Record(record, remaining), BuildError) {
  use Record(decode, encode) <- result.try(builder)
  use decode <- result.try(
    gargamelle.optional(decode, name, definition)
    |> result.map_error(Definition),
  )
  use encode <- result.try(
    gargamelle_encoding.optional_field(encode, name, encoder, get)
    |> result.map_error(Encoding),
  )
  Ok(Record(decode, encode))
}

// Absent input receives the decoding default; encoding emits the typed value.
pub fn defaulted(
  builder: Result(Record(record, fn(value) -> remaining), BuildError),
  name: String,
  child: gargamelle.Definition(value),
  encode: gargamelle_encoding.Encoder(value),
  get: fn(record) -> value,
  default: gargamelle.Json,
) -> Result(Record(record, remaining), BuildError) {
  use Record(definition, encoder) <- result.try(builder)
  use definition <- result.try(
    gargamelle.defaulted(definition, name, child, default)
    |> result.map_error(Definition),
  )
  use encoder <- result.try(
    gargamelle_encoding.field(encoder, name, encode, get)
    |> result.map_error(Encoding),
  )
  Ok(Record(definition, encoder))
}

pub fn finish(
  builder: Result(Record(record, record), BuildError),
  policy: gargamelle.RecordPolicy,
) -> Result(
  #(gargamelle.Definition(record), gargamelle_encoding.Encoder(record)),
  BuildError,
) {
  use Record(definition, encoder) <- result.try(builder)
  Ok(#(
    gargamelle.finish(definition, policy),
    gargamelle_encoding.finish(encoder),
  ))
}
