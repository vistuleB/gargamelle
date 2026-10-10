import gargamelle as s
import gleeunit/should

pub fn typed_keyed_dictionary_test() {
  let assert Ok(keys) = s.pattern(s.text(), "^[a-z]{2}$")
  let assert Ok(def) = s.property_names(s.dictionary(s.number()), keys)
  let assert Ok(value) = s.parse("{\"de\":1.5,\"en\":2.5}")
  s.decode(def, value) |> should.equal(Ok([#("de", 1.5), #("en", 2.5)]))
  let assert Ok(value) = s.parse("{\"a/b~\":0}")
  let assert Error([error]) = s.decode(def, value)
  error.path |> should.equal("/a~1b~0")
}
