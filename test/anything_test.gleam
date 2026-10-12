import gargamelle as s
import gleam/list
import gleeunit/should

pub fn anything_preserves_every_admitted_kind_test() {
  list.each(
    [
      "null", "true", "false", "1.25", "-0", "1e308", "\"💜\"", "[]", "{}",
      "{\"__proto__\":1,\"a\":[null,{},[false,\"x\"]]}",
    ],
    fn(source) {
      let assert Ok(json) = s.parse(source)
      s.decode(s.anything(), json) |> should.equal(Ok(json))
      s.validate(s.anything(), json) |> should.equal(Ok(Nil))
      let assert Ok(verified) = s.verify(s.contract(s.anything()), json)
      s.verified_json(verified) |> should.equal(json)
      s.to_string(s.verified_json(verified), s.Compact)
      |> should.equal(s.to_string(json, s.Compact))
    },
  )
}

pub fn anything_metadata_preserves_other_field_rules_test() {
  let assert Ok(fields) =
    s.required(
      s.record(fn(name) { fn(metadata) { #(name, metadata) } }),
      "name",
      s.text(),
    )
  let assert Ok(fields) = s.required(fields, "metadata", s.anything())
  let definition = s.finish(fields, s.Strict)
  let assert Ok(json) =
    s.parse("{\"name\":\"Brainy\",\"metadata\":{\"arbitrary\":[1,true,null]}}")
  let assert Ok(#("Brainy", metadata)) = s.decode(definition, json)
  s.to_string(metadata, s.Compact)
  |> should.equal("{\"arbitrary\":[1,true,null]}")
  list.each(
    [
      "{\"name\":1,\"metadata\":{}}",
      "{\"name\":\"Brainy\"}",
      "{\"name\":\"Brainy\",\"metadata\":{},\"extra\":1}",
    ],
    fn(source) {
      let assert Ok(json) = s.parse(source)
      s.decode(definition, json) |> should.be_error()
    },
  )
}

pub fn anything_schema_and_named_composition_test() {
  s.schema_string(s.anything(), s.Compact)
  |> should.equal(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"}",
  )
  let assert Ok(named) = s.named("metadata", s.anything())
  s.schema_string(s.array(named), s.Compact)
  |> should.equal(
    "{\"$defs\":{\"metadata\":{}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"items\":{\"$ref\":\"#/$defs/metadata\"},\"type\":\"array\"}",
  )
  let assert Ok(json) = s.parse("[{},null,2]")
  let assert Ok(values) = s.decode(s.array(named), json)
  list.length(values) |> should.equal(3)
}

pub fn anything_default_and_boundary_semantics_test() {
  let default = s.json_array([s.json_bool(True), s.json_null()])
  let assert Ok(fields) =
    s.defaulted(
      s.record(fn(value) { value }),
      "metadata",
      s.anything(),
      default,
    )
  let definition = s.finish(fields, s.Strict)
  let assert Ok(empty) = s.json_object([])
  s.decode(definition, empty) |> should.equal(Ok(default))
  let receiver =
    s.boundary(s.contract(s.anything()), fn(decoded, original) {
      #(decoded, original)
    })
  s.forward(receiver, default) |> should.equal(Ok(#(default, default)))
  let contract =
    s.contract(s.anything())
    |> s.require("Metadata must be null", fn(json) {
      case s.to_string(json, s.Compact) {
        "null" -> Ok(Nil)
        _ -> Error([s.Violation("", "Expected null")])
      }
    })
  s.verify(contract, default) |> should.be_error()
  s.verify(contract, s.json_null()) |> should.be_ok()
}

pub fn anything_union_exclusion_and_recursion_test() {
  let excluded = s.exclude(s.anything(), s.text())
  let assert Ok(text) = s.json_string("Brainy")
  s.validate(excluded, text) |> should.be_error()
  s.validate(excluded, s.json_null()) |> should.equal(Ok(Nil))
  let assert Ok(union) =
    s.any_of([s.anything(), s.map(s.text(), fn(_) { s.json_null() })])
  s.decode(union, text) |> should.equal(Ok(text))
  let assert Ok(exclusive) =
    s.one_of([s.anything(), s.map(s.text(), fn(_) { s.json_null() })])
  s.validate(exclusive, text) |> should.be_error()
  s.decode(exclusive, s.json_null()) |> should.equal(Ok(s.json_null()))
  let assert Ok(recursive) =
    s.recursive("arbitrary", fn(_self) { Ok(s.anything()) })
  s.decode(recursive, text) |> should.equal(Ok(text))
}
