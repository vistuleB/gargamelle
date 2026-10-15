import gargamelle as s
import gargamelle/boundary as gargamelle_boundary
import gargamelle/encoding as gargamelle_encoding
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
    gargamelle_encoding.encode(
      gargamelle_encoding.codec(
        gargamelle_encoding.string(),
        s.contract(s.string()),
      ),
      "Brainy\n😀",
    )
  decode_for_test(text) |> should.equal("Brainy\n😀")
  let assert Ok(number) =
    gargamelle_encoding.encode(
      gargamelle_encoding.codec(
        gargamelle_encoding.number(),
        s.contract(s.number()),
      ),
      1.25,
    )
  decode_for_test(number) |> should.equal(1.25)
  let assert Ok(boolean) =
    gargamelle_encoding.encode(
      gargamelle_encoding.codec(
        gargamelle_encoding.boolean(),
        s.contract(s.boolean()),
      ),
      True,
    )
  decode_for_test(boolean) |> should.equal(True)
  let assert Ok(integer) =
    gargamelle_encoding.encode(
      gargamelle_encoding.codec(
        gargamelle_encoding.safe_integer(),
        s.contract(s.safe_integer()),
      ),
      9_007_199_254_740_991,
    )
  decode_for_test(integer) |> should.equal(9_007_199_254_740_991)
}

pub fn arrays_nullable_and_empty_test() {
  let codec =
    gargamelle_encoding.codec(
      gargamelle_encoding.array(
        gargamelle_encoding.nullable(gargamelle_encoding.string()),
      ),
      s.contract(s.array(s.nullable(s.string()))),
    )
  let assert Ok(value) =
    gargamelle_encoding.encode(codec, [Some("Brainy"), None])
  decode_for_test(value) |> should.equal([Some("Brainy"), None])
  s.to_string(s.verified_json(value), s.Compact)
  |> should.equal("[\"Brainy\",null]")
  let assert Ok(empty) = gargamelle_encoding.encode(codec, [])
  decode_for_test(empty) |> should.equal([])
}

pub type Person {
  Person(name: String, age: Option(Int), nickname: Option(String))
}

pub fn person_encoder() {
  let assert Ok(record) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "name",
      gargamelle_encoding.string(),
      fn(p: Person) { p.name },
    )
  let assert Ok(record) =
    gargamelle_encoding.optional_field(
      record,
      "age",
      gargamelle_encoding.safe_integer(),
      fn(p) { p.age },
    )
  let assert Ok(record) =
    gargamelle_encoding.field(
      record,
      "nickname",
      gargamelle_encoding.nullable(gargamelle_encoding.string()),
      fn(p) { p.nickname },
    )
  gargamelle_encoding.finish(record)
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
  let codec =
    gargamelle_encoding.codec(person_encoder(), s.contract(person_definition()))
  let person = Person("Brainy", None, None)
  let assert Ok(encoded) = gargamelle_encoding.encode(codec, person)
  decode_for_test(encoded) |> should.equal(person)
  s.to_string(s.verified_json(encoded), s.Compact)
  |> should.equal("{\"name\":\"Brainy\",\"nickname\":null}")
  let person = Person("Jokey", Some(100), Some("J"))
  let assert Ok(encoded) = gargamelle_encoding.encode(codec, person)
  decode_for_test(encoded) |> should.equal(person)
}

pub fn constraints_reject_well_typed_output_test() {
  let codec =
    gargamelle_encoding.codec(
      gargamelle_encoding.string(),
      s.contract(s.string_constant("Brainy")),
    )
  let assert Error(gargamelle_encoding.Contract(s.Structural(errors))) =
    gargamelle_encoding.encode(codec, "Jokey")
  let assert Ok(json) = s.parse("\"Jokey\"")
  s.decode(s.string_constant("Brainy"), json) |> should.equal(Error(errors))
}

pub fn record_shape_mismatch_rejected_test() {
  let assert Ok(record) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "wrong",
      gargamelle_encoding.string(),
      fn(p: Person) { p.name },
    )
  let codec =
    gargamelle_encoding.codec(
      gargamelle_encoding.finish(record),
      s.contract(person_definition()),
    )
  gargamelle_encoding.encode(codec, Person("Brainy", None, None))
  |> should.be_error
}

pub fn duplicate_fields_rejected_test() {
  let assert Ok(record) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "name",
      gargamelle_encoding.string(),
      fn(x) { x },
    )
  let assert Error(gargamelle_encoding.InvalidField(
    name,
    gargamelle_encoding.DuplicateKey,
  )) =
    gargamelle_encoding.field(
      record,
      "name",
      gargamelle_encoding.string(),
      fn(x) { x },
    )
  name |> should.equal("name")
}

pub fn unsafe_integer_rejected_test() {
  gargamelle_encoding.encode_json(
    gargamelle_encoding.safe_integer(),
    9_007_199_254_740_991 + 1,
  )
  |> should.be_error
  gargamelle_encoding.encode_json(
    gargamelle_encoding.safe_integer(),
    -9_007_199_254_740_991 - 1,
  )
  |> should.be_error
}

pub fn encoded_and_decoded_values_need_not_be_equal_test() {
  let codec =
    gargamelle_encoding.codec(
      gargamelle_encoding.string(),
      s.contract(s.map(s.string(), fn(text) { text <> "!" })),
    )
  let assert Ok(verified) = gargamelle_encoding.encode(codec, "Brainy")
  decode_for_test(verified) |> should.equal("Brainy!")
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("\"Brainy\"")
}

pub fn checked_encoding_does_not_convert_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let codec =
    gargamelle_encoding.codec(
      gargamelle_encoding.string(),
      s.contract(
        s.map(s.string(), fn(text) {
          tick()
          text
        }),
      ),
    )
  let assert Ok(verified) = gargamelle_encoding.encode(codec, "Brainy")
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
  gargamelle_encoding.recursive(fn(self) {
    let assert Ok(record) =
      gargamelle_encoding.field(
        gargamelle_encoding.record(),
        "name",
        gargamelle_encoding.string(),
        fn(tree: Tree) { tree.name },
      )
    let assert Ok(record) =
      gargamelle_encoding.field(
        record,
        "children",
        gargamelle_encoding.array(self),
        fn(tree) { tree.children },
      )
    Ok(gargamelle_encoding.finish(record))
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
      gargamelle_encoding.codec(encoder, s.contract(definition))
    })
  let tree = Tree("Brainy", [Tree("Jokey", []), Tree("Grouchy", [])])
  let verified =
    handoff(fn() {
      let assert Ok(value) = gargamelle_encoding.encode(codec, tree)
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
    gargamelle_encoding.recursive(fn(self) {
      tick()
      Ok(
        gargamelle_encoding.contramap(
          gargamelle_encoding.result(
            gargamelle_encoding.number(),
            gargamelle_encoding.array(self),
          ),
          fn(value) {
            case value {
              Number(n) -> Ok(n)
              Numbers(ns) -> Error(ns)
            }
          },
        ),
      )
    })
  let assert Ok(json) =
    gargamelle_encoding.encode_json(
      encoder,
      Numbers([Number(1.25), Numbers([])]),
    )
  s.to_string(json, s.Compact) |> should.equal("[1.25,[]]")
  gargamelle_encoding.encode_json(encoder, Number(2.0)) |> should.be_ok
  count() |> should.equal(1)
}

pub fn original_encoding_without_definition_test() {
  let assert Ok(json) =
    gargamelle_encoding.encode_json(
      person_encoder(),
      Person("Brainy", None, None),
    )
  s.to_string(json, s.Pretty)
  |> should.equal("{\n  \"name\": \"Brainy\",\n  \"nickname\": null\n}")
}

pub fn output_encodes_decodes_checks_and_handles_once_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let encoder =
    gargamelle_encoding.contramap(gargamelle_encoding.string(), fn(text) {
      count() |> should.equal(0)
      tick()
      text
    })
  let contract =
    s.contract(
      s.map(s.string(), fn(text) {
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
    gargamelle_boundary.json(contract, fn(verified) {
      count() |> should.equal(3)
      tick()
      Ok(s.to_string(s.verified_json(verified), s.Compact))
    })
  let output = gargamelle_boundary.output(encoder, receiver)
  gargamelle_boundary.send(output, "Brainy")
  |> should.equal(Ok(Ok("\"Brainy\"")))
  count() |> should.equal(4)
  s.contract_requirements(gargamelle_boundary.output_contract(output))
  |> should.equal(["Decoded name"])
}

pub fn structural_output_rejection_skips_conversion_and_handler_test() {
  let contract =
    s.contract(
      s.map(s.string_constant("Brainy"), fn(_) { panic as "Rejected conversion" }),
    )
    |> s.require("Never reached", fn(_) { panic as "Rejected requirement" })
  let receiver =
    gargamelle_boundary.json(contract, fn(_) { panic as "Rejected handler" })
  let output =
    gargamelle_boundary.output(gargamelle_encoding.string(), receiver)
  let assert Error(gargamelle_encoding.Contract(s.Structural(_))) =
    gargamelle_boundary.send(output, "Jokey")
}

pub fn semantic_output_rejection_collects_failures_and_skips_handler_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    s.contract(s.string())
    |> s.require("First", fn(_) {
      tick()
      Error([s.Violation("", "First failure")])
    })
    |> s.require("Second", fn(_) {
      tick()
      Error([s.Violation("", "Second failure")])
    })
  let receiver =
    gargamelle_boundary.json(contract, fn(_) { panic as "Rejected handler" })
  let assert Error(gargamelle_encoding.Contract(s.Semantic(failures))) =
    gargamelle_boundary.send(
      gargamelle_boundary.output(gargamelle_encoding.string(), receiver),
      "Brainy",
    )
  let assert [
    s.RequirementFailure(0, "First", _),
    s.RequirementFailure(1, "Second", _),
  ] = failures
  count() |> should.equal(2)
}

pub fn checked_encoding_retains_full_contract_and_original_json_test() {
  let contract =
    s.contract(s.map(s.string(), fn(text) { text <> "!" }))
    |> s.require("Post-conversion check", fn(text) {
      case text == "Brainy!" {
        True -> Ok(Nil)
        False -> Error([s.Violation("", "Unexpected name")])
      }
    })
  let codec = gargamelle_encoding.codec(gargamelle_encoding.string(), contract)
  let assert Ok(verified) = gargamelle_encoding.encode(codec, "Brainy")
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("\"Brainy\"")
  s.contract_requirements(s.verified_contract(verified))
  |> should.equal(s.contract_requirements(gargamelle_encoding.contract(codec)))
  gargamelle_encoding.encode(codec, "Jokey") |> should.be_error
}

pub fn completed_encoders_lift_into_recursive_plans_test() {
  let name: gargamelle_encoding.Encoder(String) = gargamelle_encoding.string()
  let assert Ok(encoder) =
    gargamelle_encoding.recursive(fn(self) {
      let assert Ok(record) =
        gargamelle_encoding.field(
          gargamelle_encoding.record(),
          "name",
          gargamelle_encoding.lift(name),
          fn(tree: Tree) { tree.name },
        )
      let assert Ok(record) =
        gargamelle_encoding.field(
          record,
          "children",
          gargamelle_encoding.array(self),
          fn(tree) { tree.children },
        )
      Ok(gargamelle_encoding.finish(record))
    })
  let assert Ok(json) =
    gargamelle_encoding.encode_json(
      encoder,
      Tree("Brainy", [Tree("Jokey", [])]),
    )
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
      gargamelle_boundary.output(
        encoder,
        gargamelle_boundary.json(contract, s.verified_json),
      )
    })
  let assert Ok(json) =
    gargamelle_boundary.send(output, Tree("Brainy", [Tree("Jokey", [])]))
  let assert Ok(definition) = tree_definition()
  s.decode(definition, json)
  |> should.equal(Ok(Tree("Brainy", [Tree("Jokey", [])])))
  gargamelle_boundary.send(output, Tree("Jokey", [])) |> should.be_error
}

pub fn null_encoding_test() {
  let assert Ok(json) =
    gargamelle_encoding.encode_json(gargamelle_encoding.null(), Nil)
  s.to_string(json, s.Compact) |> should.equal("null")
  let assert Ok(verified) =
    gargamelle_encoding.encode(
      gargamelle_encoding.codec(
        gargamelle_encoding.null(),
        s.contract(s.null()),
      ),
      Nil,
    )
  decode_for_test(verified) |> should.equal(Nil)
}
