import gargamelle as s
import gargamelle/record
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should

pub type Person {
  Person(name: String, age: Int, nickname: Option(String), active: Bool)
}

pub fn person_definition(policy: s.RecordPolicy) -> s.Definition(Person) {
  let assert Ok(definition) =
    record.start4(Person)
    |> record.required("name", s.string())
    |> record.required("age", s.safe_integer())
    |> record.optional("nickname", s.string())
    |> record.defaulted("active", s.boolean(), s.json_bool(True))
    |> record.finish(policy)
  definition
}

fn baseline(policy: s.RecordPolicy) -> s.Definition(Person) {
  let constructor = fn(name) {
    fn(age) {
      fn(nickname) { fn(active) { Person(name, age, nickname, active) } }
    }
  }
  let assert Ok(fields) = s.required(s.record(constructor), "name", s.string())
  let assert Ok(fields) = s.required(fields, "age", s.safe_integer())
  let assert Ok(fields) = s.optional(fields, "nickname", s.string())
  let assert Ok(fields) =
    s.defaulted(fields, "active", s.boolean(), s.json_bool(True))
  s.finish(fields, policy)
}

pub fn typed_constructor_and_presence_test() {
  let definition = person_definition(s.Strict)
  let assert Ok(json) = s.parse("{\"name\":\"Azrael\",\"age\":3}")
  s.decode(definition, json)
  |> should.equal(Ok(Person("Azrael", 3, None, True)))
  let assert Ok(json) =
    s.parse(
      "{\"name\":\"Azrael\",\"age\":3,\"nickname\":\"A\",\"active\":false}",
    )
  s.decode(definition, json)
  |> should.equal(Ok(Person("Azrael", 3, Some("A"), False)))
  s.to_string(json, s.Compact)
  |> should.equal(
    "{\"active\":false,\"age\":3,\"name\":\"Azrael\",\"nickname\":\"A\"}",
  )
}

pub fn equivalent_schemas_decoding_and_validation_test() {
  list.each([s.Strict, s.Open], fn(policy) {
    let definition = person_definition(policy)
    let old = baseline(policy)
    s.schema_string(definition, s.Compact)
    |> should.equal(s.schema_string(old, s.Compact))
    list.each(
      [
        "{\"name\":\"Azrael\",\"age\":3}",
        "{\"name\":\"Azrael\",\"age\":3,\"active\":false,\"nickname\":\"A\"}",
        "{\"name\":\"Azrael\",\"age\":3,\"extra\":true}", "{}", "[]", "null",
        "{\"name\":false,\"age\":3}",
        "{\"name\":\"Azrael\",\"age\":3,\"nickname\":null}",
        "{\"name\":\"Azrael\",\"age\":3,\"active\":null}",
        "{\"name\":\"Azrael\",\"age\":3.5}",
      ],
      fn(source) {
        let assert Ok(json) = s.parse(source)
        s.validate(definition, json) |> should.equal(s.validate(old, json))
        s.decode(definition, json) |> should.equal(s.decode(old, json))
      },
    )
  })
}

pub fn both_record_policies_test() {
  let assert Ok(json) = s.parse("{\"name\":\"Azrael\",\"age\":3,\"extra\":42}")
  s.decode(person_definition(s.Open), json)
  |> should.equal(Ok(Person("Azrael", 3, None, True)))
  let assert Error([s.ValidationError(category, path, _, _, _)]) =
    s.decode(person_definition(s.Strict), json)
  category |> should.equal("extra_key")
  path |> should.equal("/extra")
}

pub fn start_curried_and_start1_test() {
  let assert Ok(curried) =
    record.start(fn(a) { fn(b) { #(a, b) } })
    |> record.required("a", s.string())
    |> record.required("b", s.boolean())
    |> record.finish(s.Strict)
  let assert Ok(ordinary) =
    record.start2(fn(a, b) { #(a, b) })
    |> record.required("a", s.string())
    |> record.required("b", s.boolean())
    |> record.finish(s.Strict)
  s.schema_string(curried, s.Compact)
  |> should.equal(s.schema_string(ordinary, s.Compact))
  let assert Ok(single) =
    record.start1(fn(value) { value })
    |> record.required("name", s.string())
    |> record.finish(s.Open)
  let assert Ok(json) = s.parse("{\"name\":\"Azrael\"}")
  s.decode(single, json) |> should.equal(Ok("Azrael"))
}

pub fn zero_field_curried_start_test() {
  let assert Ok(definition) = record.start(Nil) |> record.finish(s.Strict)
  let assert Ok(json) = s.parse("{}")
  s.decode(definition, json) |> should.equal(Ok(Nil))
}

pub fn duplicate_error_survives_remaining_pipeline_test() {
  let constructor = fn(a) { fn(b) { #(a, b) } }
  let assert Ok(fields) = s.required(s.record(constructor), "x", s.string())
  let assert Error(expected) = s.required(fields, "x", s.safe_integer())
  record.start4(fn(_: String, _: Int, _: Option(String), _: Bool) { Nil })
  |> record.required("x", s.string())
  |> record.required("x", s.safe_integer())
  |> record.optional("ignored", s.string())
  |> record.defaulted("ignored", s.boolean(), s.json_null())
  |> record.finish(s.Strict)
  |> should.equal(Error(expected))
}

pub fn invalid_default_is_a_construction_error_test() {
  let value = s.json_null()
  let assert Error(expected) =
    s.defaulted(s.record(fn(x) { x }), "active", s.boolean(), value)
  record.start1(fn(x) { x })
  |> record.defaulted("active", s.boolean(), value)
  |> record.finish(s.Open)
  |> should.equal(Error(expected))
}

pub fn optional_duplicate_preserves_core_error_test() {
  let constructor = fn(a) { fn(b) { #(a, b) } }
  let assert Ok(fields) = s.required(s.record(constructor), "x", s.string())
  let assert Error(expected) = s.optional(fields, "x", s.boolean())
  record.start2(fn(a, b) { #(a, b) })
  |> record.required("x", s.string())
  |> record.optional("x", s.boolean())
  |> record.finish(s.Strict)
  |> should.equal(Error(expected))
}

pub fn construction_validation_and_emission_suppress_callbacks_test() {
  let child = s.map(s.boolean(), fn(_) { panic as "converter called" })
  let assert Ok(definition) =
    record.start2(fn(_: String, _: Bool) { panic as "constructor called" })
    |> record.required("name", s.string())
    |> record.defaulted("active", child, s.json_bool(True))
    |> record.finish(s.Strict)
  let assert Ok(json) = s.parse("{\"name\":\"Azrael\"}")
  s.validate(definition, json) |> should.equal(Ok(Nil))
  s.schema_string(definition, s.Compact) |> should.not_equal("")
  let assert Ok(invalid) = s.parse("{\"name\":false}")
  s.decode(definition, invalid) |> should.be_error
}

pub type Tree {
  Tree(name: String, children: List(Tree))
}

pub fn open_recursion_environment_test() {
  let assert Ok(definition) =
    s.recursive("tree", fn(self) {
      record.start2(Tree)
      |> record.required("name", s.string())
      |> record.required("children", s.array(self))
      |> record.finish(s.Strict)
    })
  let assert Ok(json) =
    s.parse(
      "{\"name\":\"Azrael\",\"children\":[{\"name\":\"Jokey\",\"children\":[]}]}",
    )
  s.decode(definition, json)
  |> should.equal(Ok(Tree("Azrael", [Tree("Jokey", [])])))
  s.validate(definition, json) |> should.equal(Ok(Nil))
  s.schema_string(definition, s.Compact) |> should.not_equal("")
}
