import gargamelle as s
import gleam/option.{type Option, Some}
import gleeunit/should

pub type Tree {
  Tree(Option(List(Tree)))
}

pub fn presence_and_null_test() {
  let assert Ok(definition) =
    s.dependent_required(s.dictionary(s.nullable(s.string())), "token", [
      "expires_at",
    ])
  let assert Ok(absent) = s.parse("{}")
  s.validate(definition, absent) |> should.be_ok
  let assert Ok(missing) = s.parse("{\"token\":null}")
  let assert Error([error]) = s.validate(definition, missing)
  error.category |> should.equal("dependent_required")
  error.missing_key |> should.equal(Some("expires_at"))
  let assert Ok(present) = s.parse("{\"token\":null,\"expires_at\":null}")
  s.validate(definition, present) |> should.be_ok
  let assert Ok(reverse) = s.parse("{\"expires_at\":null}")
  s.validate(definition, reverse) |> should.be_ok
}

pub fn defaults_do_not_trigger_dependencies_test() {
  let assert Ok(default) = s.parse("\"default\"")
  let assert Ok(record) =
    s.defaulted(s.record(fn(token) { token }), "token", s.string(), default)
  let assert Ok(definition) =
    s.dependent_required(s.finish(record, s.Open), "token", ["expires_at"])
  let assert Ok(empty) = s.parse("{}")
  s.decode(definition, empty) |> should.equal(Ok("default"))
  let assert Ok(present) = s.parse("{\"token\":\"x\"}")
  s.decode(definition, present) |> should.be_error
}

pub fn repeated_rules_and_modifiers_test() {
  let assert Ok(definition) =
    s.dependent_required(s.dictionary(s.boolean()), "a", ["b", "b"])
  let assert Ok(definition) =
    s.dependent_required(s.title(definition, "flags"), "a", ["a", "c"])
  let assert Ok(definition) = s.bounds(definition, Some(1), Some(3))
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"additionalProperties\":{\"type\":\"boolean\"},\"dependentRequired\":{\"a\":[\"b\",\"a\",\"c\"]},\"minProperties\":1,\"maxProperties\":3,\"title\":\"flags\"}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
  let assert Ok(present) = s.parse("{\"a\":true,\"b\":false,\"c\":true}")
  s.validate(definition, present) |> should.be_ok
}

pub fn construction_and_recursive_composition_test() {
  s.dependent_required(s.string(), "a", []) |> should.be_error
  let assert Ok(definition) =
    s.recursive("dependent-tree", fn(self) {
      let assert Ok(record) =
        s.optional(s.record(Tree), "children", s.array(self))
      s.dependent_required(s.finish(record, s.Open), "marker", ["children"])
    })
  let assert Ok(valid) = s.parse("{\"marker\":true,\"children\":[{}]}")
  s.decode(definition, valid) |> should.be_ok
  let assert Ok(invalid) = s.parse("{\"children\":[{\"marker\":true}]}")
  let assert Error([error]) = s.validate(definition, invalid)
  error.path |> should.equal("/children/0")
  s.schema_json(definition)
}

pub fn alternating_object_modifiers_preserve_dependencies_test() {
  let assert Ok(definition) =
    s.dependent_required(s.dictionary(s.string()), "a", ["b"])
  let assert Ok(definition) = s.property_names(definition, s.string())
  let assert Ok(definition) = s.dependent_required(definition, "c", ["d"])
  let assert Ok(definition) = s.property_names(definition, s.string())
  let assert Ok(definition) = s.dependent_required(definition, "a", ["e"])
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"},\"dependentRequired\":{\"a\":[\"b\"]},\"propertyNames\":{\"type\":\"string\"},\"allOf\":[{\"type\":\"object\",\"dependentRequired\":{\"c\":[\"d\"]}},{\"type\":\"object\",\"propertyNames\":{\"type\":\"string\"}},{\"type\":\"object\",\"dependentRequired\":{\"a\":[\"e\"]}}]}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
  let assert Ok(invalid) = s.parse("{\"a\":\"present\",\"e\":\"present\"}")
  s.decode(definition, invalid) |> should.be_error
  let assert Ok(valid) =
    s.parse("{\"a\":\"x\",\"b\":\"x\",\"c\":\"x\",\"d\":\"x\",\"e\":\"x\"}")
  s.decode(definition, valid) |> should.be_ok
}
