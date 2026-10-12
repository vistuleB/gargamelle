import gargamelle as s
import gleeunit/should

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

pub fn decode_once_and_retain_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let definition =
    s.map(s.text(), fn(text) {
      tick()
      text <> "!"
    })
  let boundary =
    s.boundary(definition, fn(input) {
      count() |> should.equal(1)
      tick()
      input
    })
  count() |> should.equal(0)
  let assert Ok(json) = s.parse("\"Brainy\"")
  let assert Ok(verified) = s.forward(boundary, json)
  s.verified_data(verified) |> should.equal("Brainy!")
  s.verified_data(verified) |> should.equal("Brainy!")
  s.verified_json(verified) |> should.equal(json)
  count() |> should.equal(2)
}

pub fn invalid_input_skips_conversion_and_handler_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let definition =
    s.array(
      s.map(s.text(), fn(text) {
        tick()
        text
      }),
    )
  let boundary = s.boundary(definition, fn(_) { tick() })
  let assert Ok(json) = s.parse("[\"valid\", false, 42]")
  let assert Error(expected) = s.decode(definition, json)
  s.forward(boundary, json) |> should.equal(Error(expected))
  count() |> should.equal(0)
}

pub fn same_output_type_different_contract_test() {
  let first = s.boundary(s.string_constant("Brainy"), s.verified_data)
  let second = s.boundary(s.string_constant("Jokey"), s.verified_data)
  let assert Ok(json) = s.parse("\"Brainy\"")
  s.forward(first, json) |> should.equal(Ok("Brainy"))
  s.forward(second, json) |> should.be_error
  s.schema_string(s.boundary_definition(first), s.Compact)
  |> should.equal(s.schema_string(s.string_constant("Brainy"), s.Compact))
}

pub fn original_json_and_defaulted_output_test() {
  let assert Ok(default) = s.parse("\"Brainy\"")
  let assert Ok(record) =
    s.defaulted(s.record(fn(name) { name }), "name", s.text(), default)
  let boundary = s.boundary(s.finish(record, s.Open), fn(input) { input })
  let assert Ok(json) = s.parse("{\"extra\":true}")
  let assert Ok(verified) = s.forward(boundary, json)
  s.verified_data(verified) |> should.equal("Brainy")
  s.verified_json(verified) |> should.equal(json)
  s.to_string(s.verified_json(verified), s.Compact)
  |> should.equal("{\"extra\":true}")
}

pub fn handler_result_is_separate_test() {
  let boundary = s.boundary(s.text(), fn(_) { Error("application error") })
  let assert Ok(json) = s.parse("\"Brainy\"")
  s.forward(boundary, json) |> should.equal(Ok(Error("application error")))
  let assert Ok(invalid) = s.parse("false")
  s.forward(boundary, invalid) |> should.be_error
}

pub type Tree {
  Leaf(Float)
  Branch(List(Tree))
}

pub fn recursive_boundary_and_verified_transfer_test() {
  let boundary =
    handoff(fn() {
      let assert Ok(definition) =
        s.recursive("boundary-tree", fn(self) {
          s.any_of([s.map(s.number(), Leaf), s.map(s.array(self), Branch)])
        })
      s.boundary(definition, fn(input) { input })
    })
  let verified =
    handoff(fn() {
      let assert Ok(json) = s.parse("[1,[2]]")
      let assert Ok(verified) = s.forward(boundary, json)
      verified
    })
  s.verified_data(verified)
  |> should.equal(Branch([Leaf(1.0), Branch([Leaf(2.0)])]))
  s.to_string(s.verified_json(verified), s.Compact) |> should.equal("[1,[2]]")
}
