import gargamelle as s
import gleam/list
import gleeunit/should

@external(erlang, "encoding_support", "invalid_text")
@external(javascript, "./encoding_support.mjs", "invalid_text")
fn invalid_text() -> String

pub fn scalar_constructors_roundtrip_test() {
  let assert Ok(name) = s.json_string("Brainy\n💜")
  let assert Ok(number) = s.json_number(1.25)
  let assert Ok(integer) = s.json_int(-42)
  list.each(
    [
      #(s.json_null(), "null"),
      #(s.json_bool(True), "true"),
      #(s.json_bool(False), "false"),
      #(name, "\"Brainy\\n💜\""),
      #(number, "1.25"),
      #(integer, "-42"),
    ],
    fn(pair) {
      s.to_string(pair.0, s.Compact) |> should.equal(pair.1)
      let assert Ok(reparsed) = s.parse(pair.1)
      reparsed |> should.equal(pair.0)
    },
  )
}

pub fn nested_constructors_and_hostile_keys_test() {
  let assert Ok(name) = s.json_string("Jokey")
  let assert Ok(number) = s.json_int(2)
  let assert Ok(object) =
    s.json_object([
      #("__proto__", name),
      #("constructor", s.json_bool(True)),
      #("10", number),
      #("2", s.json_null()),
    ])
  let array = s.json_array([object, s.json_array([])])
  s.to_string(array, s.Compact)
  |> should.equal(
    "[{\"2\":null,\"10\":2,\"__proto__\":\"Jokey\",\"constructor\":true},[]]",
  )
  let assert Ok(reparsed) = s.parse(s.to_string(array, s.Pretty))
  s.to_string(reparsed, s.Compact)
  |> should.equal(s.to_string(array, s.Compact))
}

pub fn constructor_domain_rejections_test() {
  s.json_string(invalid_text()) |> should.equal(Error(s.NonScalarString))
  s.json_object([#(invalid_text(), s.json_null())])
  |> should.equal(Error(s.NonScalarKey(invalid_text())))
  s.json_int(9_007_199_254_740_991 + 1)
  |> should.equal(Error(s.UnsafeInteger))
  s.json_int(-9_007_199_254_740_991 - 1)
  |> should.equal(Error(s.UnsafeInteger))
  list.each([9_007_199_254_740_991, -9_007_199_254_740_991], fn(value) {
    let assert Ok(json) = s.json_int(value)
    s.decode(s.safe_integer(), json) |> should.equal(Ok(value))
  })
}

pub fn duplicate_and_first_rejected_key_test() {
  s.json_object([#("name", s.json_null()), #("name", s.json_bool(True))])
  |> should.equal(Error(s.DuplicateKey("name")))
  s.json_object([
    #("", s.json_null()),
    #("", s.json_bool(False)),
    #(invalid_text(), s.json_null()),
  ])
  |> should.equal(Error(s.DuplicateKey("")))
  s.json_object([
    #(invalid_text(), s.json_null()),
    #("name", s.json_null()),
    #("name", s.json_null()),
  ])
  |> should.equal(Error(s.NonScalarKey(invalid_text())))
  let assert Ok(empty) = s.json_object([])
  s.to_string(empty, s.Compact) |> should.equal("{}")
}

pub fn constructed_json_in_defaults_and_annotations_test() {
  let assert Ok(name) = s.json_string("Brainy")
  let assert Ok(fields) =
    s.defaulted(s.record(fn(name) { name }), "name", s.text(), name)
  let definition = s.finish(fields, s.Strict)
  let assert Ok(empty) = s.json_object([])
  s.decode(definition, empty) |> should.equal(Ok("Brainy"))
  let annotated = s.text() |> s.default(name) |> s.examples([name])
  s.schema_string(annotated, s.Compact)
  |> should.equal(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"default\":\"Brainy\",\"examples\":[\"Brainy\"],\"type\":\"string\"}",
  )
}
