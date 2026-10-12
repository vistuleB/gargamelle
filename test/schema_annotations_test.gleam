import gargamelle as s
import gleam/option as gleam_option
import gleeunit/should

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
    s.examples(s.text(), [value])
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
