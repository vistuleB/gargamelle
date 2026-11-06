//// Shared static field declarations for record definitions and encoders.
//// Produces the existing encoding.Codec, with a structural Contract. Each field
//// consumes one constructor argument and retains a getter from the whole record.
////
//// Child codecs must have no semantic requirements, including optional and
//// defaulted children. Requirements are rejected, never silently discarded.
//// Attach semantic requirements to the completed record's Contract separately.
//// Only completed definitions and encoders are supported, not recursion plans.
////
//// Operations preserve the first construction error and skip subsequent builder
//// work. Gleam still evaluates arguments eagerly after an earlier error.
//// Construction runs no constructors, getters or decoding conversions.

import gargamelle as g
import gargamelle/encoding as gargamelle_encoding
import gleam/option.{type Option}
import gleam/result

/// Construction failures are distinct from input and runtime encoding failures.
/// Field failures retain the declared name and original error without rewriting it.
pub type BuildError {
  Definition(cause: g.DefinitionError)
  FieldDefinition(name: String, cause: g.DefinitionError)
  FieldEncoding(name: String, cause: gargamelle_encoding.EncodingError)
  SemanticRequirements(name: String, descriptions: List(String))
}

/// A partially applied decoding constructor and an encoder for the whole record.
pub opaque type Fields(remaining, whole) {
  Fields(g.Record(remaining, Nil), gargamelle_encoding.Record(whole, Nil))
}

/// Start from record.start or an ordinary-constructor adapter such as start2.
/// An existing definition-construction error is preserved as Definition(error).
pub fn start(
  builder: Result(g.Record(a, Nil), g.DefinitionError),
) -> Result(Fields(a, whole), BuildError) {
  use definition <- result.try(result.map_error(builder, Definition))
  Ok(Fields(definition, gargamelle_encoding.record()))
}

fn child_definition(
  name: String,
  child: gargamelle_encoding.Codec(a),
) -> Result(g.Definition(a), BuildError) {
  let contract = gargamelle_encoding.contract(child)
  case g.contract_requirements(contract) {
    [] -> Ok(g.contract_definition(contract))
    descriptions -> Error(SemanticRequirements(name, descriptions))
  }
}

/// Declare a required field once for decoding, schemas and encoding.
/// Reject child semantic requirements before adding either field declaration.
pub fn required(
  fields: Result(Fields(fn(a) -> b, whole), BuildError),
  name: String,
  child: gargamelle_encoding.Codec(a),
  get: fn(whole) -> a,
) -> Result(Fields(b, whole), BuildError) {
  use Fields(definition, encoder) <- result.try(fields)
  use child_definition <- result.try(child_definition(name, child))
  use definition <- result.try(
    g.required(definition, name, child_definition)
    |> result.map_error(FieldDefinition(name, _)),
  )
  use encoder <- result.try(
    gargamelle_encoding.field(
      encoder,
      name,
      gargamelle_encoding.encoder(child),
      get,
    )
    |> result.map_error(FieldEncoding(name, _)),
  )
  Ok(Fields(definition, encoder))
}

/// Absence decodes as None. On encoding None omits the key; Some uses the child
/// encoder. JSON null is distinct from absence and must be supported by the child.
/// Child semantic requirements are rejected even if the field could be absent.
pub fn optional(
  fields: Result(Fields(fn(Option(a)) -> b, whole), BuildError),
  name: String,
  child: gargamelle_encoding.Codec(a),
  get: fn(whole) -> Option(a),
) -> Result(Fields(b, whole), BuildError) {
  use Fields(definition, encoder) <- result.try(fields)
  use child_definition <- result.try(child_definition(name, child))
  use definition <- result.try(
    g.optional(definition, name, child_definition)
    |> result.map_error(FieldDefinition(name, _)),
  )
  use encoder <- result.try(
    gargamelle_encoding.optional_field(
      encoder,
      name,
      gargamelle_encoding.encoder(child),
      get,
    )
    |> result.map_error(FieldEncoding(name, _)),
  )
  Ok(Fields(definition, encoder))
}

/// Validate the default during construction without decoding. Absence decodes
/// that default; present invalid input fails. Encoding always writes the getter's
/// actual value, including when equal to the default. Child semantic requirements
/// are rejected even when the default satisfies the structural definition.
pub fn defaulted(
  fields: Result(Fields(fn(a) -> b, whole), BuildError),
  name: String,
  child: gargamelle_encoding.Codec(a),
  default: g.Json,
  get: fn(whole) -> a,
) -> Result(Fields(b, whole), BuildError) {
  use Fields(definition, encoder) <- result.try(fields)
  use child_definition <- result.try(child_definition(name, child))
  use definition <- result.try(
    g.defaulted(definition, name, child_definition, default)
    |> result.map_error(FieldDefinition(name, _)),
  )
  use encoder <- result.try(
    gargamelle_encoding.field(
      encoder,
      name,
      gargamelle_encoding.encoder(child),
      get,
    )
    |> result.map_error(FieldEncoding(name, _)),
  )
  Ok(Fields(definition, encoder))
}

/// Finish when the constructor output and encoder input have the same type.
/// Strict rejects unknown input fields. Open accepts and discards them during
/// decoding; encoding writes declared fields only. Neither policy proves that
/// constructors and getters are inverses.
pub fn finish(
  fields: Result(Fields(a, a), BuildError),
  policy: g.RecordPolicy,
) -> Result(gargamelle_encoding.Codec(a), BuildError) {
  use Fields(definition, encoder) <- result.try(fields)
  Ok(gargamelle_encoding.codec(
    gargamelle_encoding.finish(encoder),
    g.contract(g.finish(definition, policy)),
  ))
}
