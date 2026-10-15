import gargamelle as s
import gleeunit/should

pub fn typed_keyed_dictionary_test() {
  let assert Ok(keys) = s.pattern(s.string(), "^[a-z]{2}$")
  let assert Ok(def) = s.property_names(s.dictionary(s.number()), keys)
  let assert Ok(value) = s.parse("{\"de\":1.5,\"en\":2.5}")
  s.decode(def, value) |> should.equal(Ok([#("de", 1.5), #("en", 2.5)]))
  let assert Ok(value) = s.parse("{\"a/b~\":0}")
  let assert Error([error]) = s.decode(def, value)
  error.path |> should.equal("/a~1b~0")
}

pub fn alternating_object_modifiers_preserve_key_constraints_test() {
  let assert Ok(keys) = s.pattern(s.string(), "^a")
  let assert Ok(definition) = s.property_names(s.dictionary(s.string()), keys)
  let assert Ok(definition) = s.dependent_required(definition, "a", [])
  let assert Ok(definition) = s.property_names(definition, s.string())
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"},\"propertyNames\":{\"type\":\"string\",\"pattern\":\"^a\"},\"dependentRequired\":{\"a\":[]},\"allOf\":[{\"type\":\"object\",\"propertyNames\":{\"type\":\"string\"}}]}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
  let assert Ok(invalid) = s.parse("{\"z\":\"x\"}")
  s.decode(definition, invalid) |> should.be_error
  let assert Ok(valid) = s.parse("{\"a\":\"x\"}")
  s.decode(definition, valid) |> should.be_ok
}
