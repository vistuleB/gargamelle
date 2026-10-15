import gargamelle as s
import gleam/option as gleam_option
import gleeunit/should

pub fn format_is_not_an_assertion_test() {
  let definition = s.format_annotation(s.string(), "email")
  let assert Ok(json) = s.parse("\"not an email\"")
  s.decode(definition, json) |> should.equal(Ok("not an email"))
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"string\",\"format\":\"email\"}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
}

pub fn custom_format_replaces_and_preserves_constraints_test() {
  let assert Ok(definition) =
    s.format_annotation(s.string(), "email")
    |> s.bounds(gleam_option.Some(1), gleam_option.None)
  let definition = s.format_annotation(definition, "application-name")
  let assert Ok(empty) = s.parse("\"\"")
  s.validate(definition, empty) |> should.be_error
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"string\",\"minLength\":1,\"format\":\"application-name\"}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
}

pub fn default_annotation_does_not_supply_missing_field_test() {
  let assert Ok(value) = s.parse("false")
  let child = s.default_annotation(s.string(), value)
  let assert Ok(record) = s.required(s.record(fn(x) { x }), "name", child)
  let definition = s.finish(record, s.Strict)
  let assert Ok(missing) = s.parse("{}")
  s.decode(definition, missing) |> should.be_error
  let assert Ok(present) = s.parse("{\"name\":\"Brainy\"}")
  s.decode(definition, present) |> should.equal(Ok("Brainy"))
}

pub fn defaulted_field_overrides_child_default_annotation_test() {
  let assert Ok(annotation) = s.parse("false")
  let assert Ok(actual) = s.parse("\"Brainy\"")
  let assert Ok(record) =
    s.defaulted(
      s.record(fn(x) { x }),
      "name",
      s.default_annotation(s.string(), annotation),
      actual,
    )
  let definition = s.finish(record, s.Strict)
  let assert Ok(empty) = s.parse("{}")
  s.decode(definition, empty) |> should.equal(Ok("Brainy"))
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"default\":\"Brainy\"}},\"required\":[],\"additionalProperties\":false}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
}

pub fn examples_are_metadata_test() {
  let assert Ok(valid) = s.parse("\"Brainy\"")
  let assert Ok(invalid) = s.parse("false")
  let definition = s.examples(s.string_constant("Brainy"), [valid, invalid])
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"const\":\"Brainy\",\"type\":\"string\",\"examples\":[\"Brainy\",false]}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
  s.decode(definition, valid) |> should.equal(Ok("Brainy"))
  s.validate(definition, invalid) |> should.be_error
}

pub fn examples_replace_and_preserve_modifiers_test() {
  let assert Ok(value) = s.parse("\"Brainy\"")
  let assert Ok(definition) =
    s.examples(s.string(), [value])
    |> s.bounds(gleam_option.None, gleam_option.Some(6))
  let definition = s.examples(definition, [])
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"string\",\"maxLength\":6,\"examples\":[]}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
  s.decode(definition, value) |> should.equal(Ok("Brainy"))
}
