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

// Explicit decoding only in round-trip tests; checked encoding does not do this.
fn decode_for_test(verified: s.VerifiedJson(a)) -> a {
  let assert Ok(data) =
    s.decode(s.verified_definition(verified), s.verified_json(verified))
  data
}

pub fn primitive_roundtrips_test() {
  let assert Ok(text) = e.encode(e.codec(e.string(), s.string()), "Brainy\n😀")
  decode_for_test(text) |> should.equal("Brainy\n😀")
  let assert Ok(number) = e.encode(e.codec(e.number(), s.number()), 1.25)
  decode_for_test(number) |> should.equal(1.25)
  let assert Ok(boolean) = e.encode(e.codec(e.boolean(), s.boolean()), True)
  decode_for_test(boolean) |> should.equal(True)
  let assert Ok(integer) =
    e.encode(e.codec(e.safe_integer(), s.safe_integer()), 9_007_199_254_740_991)
  decode_for_test(integer) |> should.equal(9_007_199_254_740_991)
}

pub fn arrays_nullable_and_empty_test() {
  let codec =
    e.codec(e.array(e.nullable(e.string())), s.array(s.nullable(s.string())))
  let assert Ok(value) = e.encode(codec, [Some("Brainy"), None])
  decode_for_test(value) |> should.equal([Some("Brainy"), None])
  s.to_string(s.verified_json(value), s.Compact)
  |> should.equal("[\"Brainy\",null]")
  let assert Ok(empty) = e.encode(codec, [])
  decode_for_test(empty) |> should.equal([])
}

pub type Person {
  Person(name: String, age: Option(Int), nickname: Option(String))
}

pub fn person_encoder() {
  let assert Ok(record) =
    e.field(e.record(), "name", e.string(), fn(p: Person) { p.name })
  let assert Ok(record) =
    e.optional_field(record, "age", e.safe_integer(), fn(p) { p.age })
  let assert Ok(record) =
    e.field(record, "nickname", e.nullable(e.string()), fn(p) { p.nickname })
  e.finish(record)
}

pub fn person_definition() {
  let assert Ok(record) =
    s.required(
      s.record(fn(name) {
        fn(age) { fn(nickname) { Person(name, age, nickname) } }
      }),
      "name",
      s.string(),
    )
  let assert Ok(record) = s.optional(record, "age", s.safe_integer())
  let assert Ok(record) = s.required(record, "nickname", s.nullable(s.string()))
  s.finish(record, s.Strict)
}

pub fn record_getters_optional_versus_null_test() {
  let codec = e.codec(person_encoder(), person_definition())
  let person = Person("Brainy", None, None)
  let assert Ok(encoded) = e.encode(codec, person)
  decode_for_test(encoded) |> should.equal(person)
  s.to_string(s.verified_json(encoded), s.Compact)
  |> should.equal("{\"name\":\"Brainy\",\"nickname\":null}")
  let person = Person("Jokey", Some(100), Some("J"))
  let assert Ok(encoded) = e.encode(codec, person)
  decode_for_test(encoded) |> should.equal(person)
}

pub fn constraints_reject_well_typed_output_test() {
  let codec = e.codec(e.string(), s.string_constant("Brainy"))
  let assert Error(e.Contract(s.Structural(errors))) = e.encode(codec, "Jokey")
  let assert Ok(json) = s.parse("\"Jokey\"")
  s.decode(s.string_constant("Brainy"), json) |> should.equal(Error(errors))
}

pub fn record_shape_mismatch_rejected_test() {
  let assert Ok(record) =
    e.field(e.record(), "wrong", e.string(), fn(p: Person) { p.name })
  let codec = e.codec(e.finish(record), person_definition())
  e.encode(codec, Person("Brainy", None, None)) |> should.be_error
}

pub fn duplicate_fields_rejected_test() {
  let assert Ok(record) = e.field(e.record(), "name", e.string(), fn(x) { x })
  let assert Error(e.EncodingError(reason)) =
    e.field(record, "name", e.string(), fn(x) { x })
  reason |> should.equal("duplicate record key: name")
}

pub fn unsafe_integer_rejected_test() {
  e.encode_json(e.safe_integer(), 9_007_199_254_740_992) |> should.be_error
  e.encode_json(e.safe_integer(), -9_007_199_254_740_992) |> should.be_error
}

pub fn encoded_and_decoded_values_need_not_be_equal_test() {
  let codec = e.codec(e.string(), s.map(s.string(), fn(text) { text <> "!" }))
  let assert Ok(verified) = e.encode(codec, "Brainy")
  decode_for_test(verified) |> should.equal("Brainy!")
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("\"Brainy\"")
}

pub fn checked_encoding_does_not_convert_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let codec =
    e.codec(
      e.string(),
      s.map(s.string(), fn(text) {
        tick()
        text
      }),
    )
  let assert Ok(verified) = e.encode(codec, "Brainy")
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("\"Brainy\"")
  s.schema_string(s.verified_definition(verified), s.Compact)
  |> should.equal(s.schema_string(s.string(), s.Compact))
  count() |> should.equal(0)
  decode_for_test(verified) |> should.equal("Brainy")
  count() |> should.equal(1)
}

pub type Tree {
  Tree(name: String, children: List(Tree))
}

pub fn tree_encoder() {
  e.recursive(fn(self) {
    let assert Ok(record) =
      e.field(e.record(), "name", e.string(), fn(tree: Tree) { tree.name })
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
        s.string(),
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
  decode_for_test(verified) |> should.equal(tree)
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
        e.contramap(e.result(e.number(), e.array(self)), fn(value) {
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
