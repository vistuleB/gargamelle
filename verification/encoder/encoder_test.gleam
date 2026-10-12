import encoder as e
import gargamelle as s
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

pub fn main() {
  gleeunit.main()
}

pub fn primitive_roundtrips_test() {
  let assert Ok(text) = e.encode(e.codec(e.text(), s.text()), "Brainy\n😀")
  s.verified_data(text) |> should.equal("Brainy\n😀")
  let assert Ok(number) = e.encode(e.codec(e.number(), s.number()), 1.25)
  s.verified_data(number) |> should.equal(1.25)
  let assert Ok(boolean) = e.encode(e.codec(e.boolean(), s.boolean()), True)
  s.verified_data(boolean) |> should.equal(True)
  let assert Ok(integer) =
    e.encode(e.codec(e.safe_integer(), s.safe_integer()), 9_007_199_254_740_991)
  s.verified_data(integer) |> should.equal(9_007_199_254_740_991)
}

pub fn arrays_nullable_and_empty_test() {
  let codec =
    e.codec(e.array(e.nullable(e.text())), s.array(s.nullable(s.text())))
  let assert Ok(value) = e.encode(codec, [Some("Brainy"), None])
  s.verified_data(value) |> should.equal([Some("Brainy"), None])
  s.to_string(s.verified_json(value), s.Compact)
  |> should.equal("[\"Brainy\",null]")
  let assert Ok(empty) = e.encode(codec, [])
  s.verified_data(empty) |> should.equal([])
}

pub type Person {
  Person(name: String, age: Option(Int), nickname: Option(String))
}

pub fn person_encoder() {
  let assert Ok(record) =
    e.field(e.record(), "name", e.text(), fn(p: Person) { p.name })
  let assert Ok(record) =
    e.optional_field(record, "age", e.safe_integer(), fn(p) { p.age })
  let assert Ok(record) =
    e.field(record, "nickname", e.nullable(e.text()), fn(p) { p.nickname })
  e.finish(record)
}

pub fn person_definition() {
  let assert Ok(record) =
    s.required(
      s.record(fn(name) {
        fn(age) { fn(nickname) { Person(name, age, nickname) } }
      }),
      "name",
      s.text(),
    )
  let assert Ok(record) = s.optional(record, "age", s.safe_integer())
  let assert Ok(record) = s.required(record, "nickname", s.nullable(s.text()))
  s.finish(record, s.Strict)
}

pub fn record_getters_optional_versus_null_test() {
  let codec = e.codec(person_encoder(), person_definition())
  let person = Person("Brainy", None, None)
  let assert Ok(encoded) = e.encode(codec, person)
  s.verified_data(encoded) |> should.equal(person)
  s.to_string(s.verified_json(encoded), s.Compact)
  |> should.equal("{\"name\":\"Brainy\",\"nickname\":null}")
  let person = Person("Jokey", Some(100), Some("J"))
  let assert Ok(encoded) = e.encode(codec, person)
  s.verified_data(encoded) |> should.equal(person)
}

pub fn constraints_reject_well_typed_output_test() {
  let codec = e.codec(e.text(), s.string_constant("Brainy"))
  let assert Error(e.Contract(errors)) = e.encode(codec, "Jokey")
  let assert Ok(json) = s.parse("\"Jokey\"")
  s.decode(s.string_constant("Brainy"), json) |> should.equal(Error(errors))
}

pub fn record_shape_mismatch_rejected_test() {
  let assert Ok(record) =
    e.field(e.record(), "wrong", e.text(), fn(p: Person) { p.name })
  let codec = e.codec(e.finish(record), person_definition())
  e.encode(codec, Person("Brainy", None, None)) |> should.be_error
}

pub fn duplicate_fields_rejected_test() {
  let assert Ok(record) = e.field(e.record(), "name", e.text(), fn(x) { x })
  let assert Error(e.EncodingError(reason)) =
    e.field(record, "name", e.text(), fn(x) { x })
  reason |> should.equal("duplicate record key: name")
}

pub fn unsafe_integer_rejected_test() {
  e.encode_json(e.safe_integer(), 9_007_199_254_740_992) |> should.be_error
  e.encode_json(e.safe_integer(), -9_007_199_254_740_992) |> should.be_error
}

pub fn encoded_and_decoded_values_need_not_be_equal_test() {
  let codec = e.codec(e.text(), s.map(s.text(), fn(text) { text <> "!" }))
  let assert Ok(verified) = e.encode(codec, "Brainy")
  s.verified_data(verified) |> should.equal("Brainy!")
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("\"Brainy\"")
}

pub fn checked_encoding_converts_once_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let codec =
    e.codec(
      e.text(),
      s.map(s.text(), fn(text) {
        tick()
        text
      }),
    )
  let assert Ok(verified) = e.encode(codec, "Brainy")
  s.verified_data(verified) |> should.equal("Brainy")
  s.verified_data(verified) |> should.equal("Brainy")
  count() |> should.equal(1)
}

pub type Tree {
  Tree(name: String, children: List(Tree))
}

pub fn tree_encoder() {
  e.recursive(fn(self) {
    let assert Ok(record) =
      e.field(e.record(), "name", e.text(), fn(tree: Tree) { tree.name })
    let assert Ok(record) =
      e.field(record, "children", e.array(self), fn(tree) { tree.children })
    Ok(e.finish(record))
  })
}

pub fn tree_definition() {
  s.recursive("encoder-tree", fn(self) {
    let assert Ok(record) =
      s.required(
        s.record(fn(name) { fn(children) { Tree(name, children) } }),
        "name",
        s.text(),
      )
    let assert Ok(record) = s.required(record, "children", s.array(self))
    Ok(s.finish(record, s.Strict))
  })
}

pub fn recursive_record_roundtrip_and_transfer_test() {
  let codec =
    handoff(fn() {
      let assert Ok(encoder) = tree_encoder()
      let assert Ok(definition) = tree_definition()
      e.codec(encoder, definition)
    })
  let tree = Tree("Brainy", [Tree("Jokey", []), Tree("Grouchy", [])])
  let verified =
    handoff(fn() {
      let assert Ok(value) = e.encode(codec, tree)
      value
    })
  s.verified_data(verified) |> should.equal(tree)
}

pub type Sum {
  Number(Float)
  Numbers(List(Sum))
}

pub fn recursive_choice_builder_once_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let assert Ok(encoder) =
    e.recursive(fn(self) {
      tick()
      Ok(
        e.contramap(e.choice(e.number(), e.array(self)), fn(value) {
          case value {
            Number(n) -> Ok(n)
            Numbers(ns) -> Error(ns)
          }
        }),
      )
    })
  let assert Ok(json) =
    e.encode_json(encoder, Numbers([Number(1.25), Numbers([])]))
  s.to_string(json, s.Compact) |> should.equal("[1.25,[]]")
  e.encode_json(encoder, Number(2.0)) |> should.be_ok
  count() |> should.equal(1)
}

pub fn original_encoding_without_definition_test() {
  let assert Ok(json) =
    e.encode_json(person_encoder(), Person("Brainy", None, None))
  s.to_string(json, s.Pretty)
  |> should.equal("{\n  \"name\": \"Brainy\",\n  \"nickname\": null\n}")
}
