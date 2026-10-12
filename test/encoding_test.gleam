import gargamelle as s
import gargamelle/encoding as e
import gleam/option.{type Option, None, Some}
import gleeunit/should

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

// Explicit decoding only in round-trip tests; checked encoding does not do this.
fn decode_for_test(verified: s.VerifiedJson(a)) -> a {
  let assert Ok(data) =
    s.decode(s.verified_definition(verified), s.verified_json(verified))
  data
}

pub fn primitive_roundtrips_test() {
  let assert Ok(text) =
    e.encode(e.codec(e.text(), s.contract(s.text())), "Brainy\n😀")
  decode_for_test(text) |> should.equal("Brainy\n😀")
  let assert Ok(number) =
    e.encode(e.codec(e.number(), s.contract(s.number())), 1.25)
  decode_for_test(number) |> should.equal(1.25)
  let assert Ok(boolean) =
    e.encode(e.codec(e.boolean(), s.contract(s.boolean())), True)
  decode_for_test(boolean) |> should.equal(True)
  let assert Ok(integer) =
    e.encode(
      e.codec(e.safe_integer(), s.contract(s.safe_integer())),
      9_007_199_254_740_991,
    )
  decode_for_test(integer) |> should.equal(9_007_199_254_740_991)
}

pub fn arrays_nullable_and_empty_test() {
  let codec =
    e.codec(
      e.array(e.nullable(e.text())),
      s.contract(s.array(s.nullable(s.text()))),
    )
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
  let codec = e.codec(person_encoder(), s.contract(person_definition()))
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
  let codec = e.codec(e.text(), s.contract(s.string_constant("Brainy")))
  let assert Error(e.Contract(s.Structural(errors))) = e.encode(codec, "Jokey")
  let assert Ok(json) = s.parse("\"Jokey\"")
  s.decode(s.string_constant("Brainy"), json) |> should.equal(Error(errors))
}

pub fn record_shape_mismatch_rejected_test() {
  let assert Ok(record) =
    e.field(e.record(), "wrong", e.text(), fn(p: Person) { p.name })
  let codec = e.codec(e.finish(record), s.contract(person_definition()))
  e.encode(codec, Person("Brainy", None, None)) |> should.be_error
}

pub fn duplicate_fields_rejected_test() {
  let assert Ok(record) = e.field(e.record(), "name", e.text(), fn(x) { x })
  let assert Error(e.EncodingError(reason)) =
    e.field(record, "name", e.text(), fn(x) { x })
  reason |> should.equal("duplicate record key: name")
}

pub fn unsafe_integer_rejected_test() {
  e.encode_json(e.safe_integer(), 9_007_199_254_740_991 + 1) |> should.be_error
  e.encode_json(e.safe_integer(), -9_007_199_254_740_991 - 1) |> should.be_error
}

pub fn encoded_and_decoded_values_need_not_be_equal_test() {
  let codec =
    e.codec(e.text(), s.contract(s.map(s.text(), fn(text) { text <> "!" })))
  let assert Ok(verified) = e.encode(codec, "Brainy")
  decode_for_test(verified) |> should.equal("Brainy!")
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("\"Brainy\"")
}

pub fn checked_encoding_does_not_convert_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let codec =
    e.codec(
      e.text(),
      s.contract(
        s.map(s.text(), fn(text) {
          tick()
          text
        }),
      ),
    )
  let assert Ok(verified) = e.encode(codec, "Brainy")
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("\"Brainy\"")
  s.schema_string(s.verified_definition(verified), s.Compact)
  |> should.equal(s.schema_string(s.text(), s.Compact))
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
      e.codec(encoder, s.contract(definition))
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

pub fn output_encodes_decodes_checks_and_handles_once_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let encoder =
    e.contramap(e.text(), fn(text) {
      count() |> should.equal(0)
      tick()
      text
    })
  let contract =
    s.contract(
      s.map(s.text(), fn(text) {
        count() |> should.equal(1)
        tick()
        text <> "!"
      }),
    )
    |> s.require("Decoded name", fn(text) {
      text |> should.equal("Brainy!")
      count() |> should.equal(2)
      tick()
      Ok(Nil)
    })
  let receiver =
    s.json_boundary(contract, fn(verified) {
      count() |> should.equal(3)
      tick()
      Ok(s.to_string(s.verified_json(verified), s.Compact))
    })
  let output = e.output_boundary(encoder, receiver)
  e.send(output, "Brainy") |> should.equal(Ok(Ok("\"Brainy\"")))
  count() |> should.equal(4)
  s.contract_requirements(e.output_contract(output))
  |> should.equal(["Decoded name"])
}

pub fn structural_output_rejection_skips_conversion_and_handler_test() {
  let contract =
    s.contract(
      s.map(s.string_constant("Brainy"), fn(_) { panic as "Rejected conversion" }),
    )
    |> s.require("Never reached", fn(_) { panic as "Rejected requirement" })
  let receiver = s.json_boundary(contract, fn(_) { panic as "Rejected handler" })
  let output = e.output_boundary(e.text(), receiver)
  let assert Error(e.Contract(s.Structural(_))) = e.send(output, "Jokey")
}

pub fn semantic_output_rejection_collects_failures_and_skips_handler_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    s.contract(s.text())
    |> s.require("First", fn(_) {
      tick()
      Error([s.Violation("", "First failure")])
    })
    |> s.require("Second", fn(_) {
      tick()
      Error([s.Violation("", "Second failure")])
    })
  let receiver = s.json_boundary(contract, fn(_) { panic as "Rejected handler" })
  let assert Error(e.Contract(s.Semantic(failures))) =
    e.send(e.output_boundary(e.text(), receiver), "Brainy")
  let assert [
    s.RequirementFailure(0, "First", _),
    s.RequirementFailure(1, "Second", _),
  ] = failures
  count() |> should.equal(2)
}

pub fn checked_encoding_retains_full_contract_and_original_json_test() {
  let contract =
    s.contract(s.map(s.text(), fn(text) { text <> "!" }))
    |> s.require("Post-conversion check", fn(text) {
      case text == "Brainy!" {
        True -> Ok(Nil)
        False -> Error([s.Violation("", "Unexpected name")])
      }
    })
  let codec = e.codec(e.text(), contract)
  let assert Ok(verified) = e.encode(codec, "Brainy")
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("\"Brainy\"")
  s.contract_requirements(s.verified_contract(verified))
  |> should.equal(s.contract_requirements(e.codec_contract(codec)))
  e.encode(codec, "Jokey") |> should.be_error
}

pub fn completed_encoders_lift_into_recursive_plans_test() {
  let name: e.Encoder(String) = e.text()
  let assert Ok(encoder) =
    e.recursive(fn(self) {
      let assert Ok(record) =
        e.field(e.record(), "name", e.lift(name), fn(tree: Tree) { tree.name })
      let assert Ok(record) =
        e.field(record, "children", e.array(self), fn(tree) { tree.children })
      Ok(e.finish(record))
    })
  let assert Ok(json) =
    e.encode_json(encoder, Tree("Brainy", [Tree("Jokey", [])]))
  s.to_string(json, s.Compact)
  |> should.equal(
    "{\"children\":[{\"children\":[],\"name\":\"Jokey\"}],\"name\":\"Brainy\"}",
  )
}

pub fn recursive_output_boundary_survives_creator_process_test() {
  let output =
    handoff(fn() {
      let assert Ok(encoder) = tree_encoder()
      let assert Ok(definition) = tree_definition()
      let expected = "Brainy"
      let contract =
        s.contract(definition)
        |> s.require("Root name", fn(tree) {
          case tree.name == expected {
            True -> Ok(Nil)
            False -> Error([s.Violation("/name", "Unexpected root")])
          }
        })
      e.output_boundary(encoder, s.json_boundary(contract, s.verified_json))
    })
  let assert Ok(json) = e.send(output, Tree("Brainy", [Tree("Jokey", [])]))
  let assert Ok(definition) = tree_definition()
  s.decode(definition, json)
  |> should.equal(Ok(Tree("Brainy", [Tree("Jokey", [])])))
  e.send(output, Tree("Jokey", [])) |> should.be_error
}

pub fn null_encoding_test() {
  let assert Ok(json) = e.encode_json(e.null(), Nil)
  s.to_string(json, s.Compact) |> should.equal("null")
  let assert Ok(verified) =
    e.encode(e.codec(e.null(), s.contract(s.null())), Nil)
  decode_for_test(verified) |> should.equal(Nil)
}
