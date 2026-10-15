import gargamelle as s
import gargamelle/boundary as gargamelle_boundary
import gleeunit/should

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

pub fn decode_once_and_pass_both_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let definition =
    s.map(s.text(), fn(text) {
      tick()
      text <> "!"
    })
  let boundary =
    gargamelle_boundary.new(s.contract(definition), fn(data, json) {
      count() |> should.equal(1)
      tick()
      #(data, json)
    })
  count() |> should.equal(0)
  let assert Ok(json) = s.parse("\"Brainy\"")
  gargamelle_boundary.forward(boundary, json)
  |> should.equal(Ok(#("Brainy!", json)))
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
  let boundary =
    gargamelle_boundary.new(s.contract(definition), fn(_, _) { tick() })
  let assert Ok(json) = s.parse("[\"valid\", false, 42]")
  let assert Error(expected) = s.decode(definition, json)
  gargamelle_boundary.forward(boundary, json)
  |> should.equal(Error(s.Structural(expected)))
  count() |> should.equal(0)
}

pub fn same_output_type_different_contract_test() {
  let first =
    gargamelle_boundary.new(
      s.contract(s.string_constant("Brainy")),
      fn(data, _) { data },
    )
  let second =
    gargamelle_boundary.new(s.contract(s.string_constant("Jokey")), fn(data, _) {
      data
    })
  let assert Ok(json) = s.parse("\"Brainy\"")
  gargamelle_boundary.forward(first, json) |> should.equal(Ok("Brainy"))
  gargamelle_boundary.forward(second, json) |> should.be_error
  s.schema_string(gargamelle_boundary.boundary_definition(first), s.Compact)
  |> should.equal(s.schema_string(s.string_constant("Brainy"), s.Compact))
}

pub fn original_json_and_defaulted_output_test() {
  let assert Ok(default) = s.parse("\"Brainy\"")
  let assert Ok(record) =
    s.defaulted(s.record(fn(name) { name }), "name", s.text(), default)
  let boundary =
    gargamelle_boundary.new(
      s.contract(s.finish(record, s.Open)),
      fn(data, json) { #(data, json) },
    )
  let assert Ok(json) = s.parse("{\"extra\":true}")
  let assert Ok(#(data, original)) = gargamelle_boundary.forward(boundary, json)
  data |> should.equal("Brainy")
  original |> should.equal(json)
  s.to_string(original, s.Compact)
  |> should.equal("{\"extra\":true}")
}

pub fn handler_result_is_separate_test() {
  let boundary =
    gargamelle_boundary.new(s.contract(s.text()), fn(_, _) {
      Error("application error")
    })
  let assert Ok(json) = s.parse("\"Brainy\"")
  gargamelle_boundary.forward(boundary, json)
  |> should.equal(Ok(Error("application error")))
  let assert Ok(invalid) = s.parse("false")
  gargamelle_boundary.forward(boundary, invalid) |> should.be_error
}

pub type Tree {
  Leaf(Float)
  Branch(List(Tree))
}

pub fn recursive_boundary_and_output_transfer_test() {
  let boundary =
    handoff(fn() {
      let assert Ok(definition) =
        s.recursive("boundary-tree", fn(self) {
          s.any_of([s.map(s.number(), Leaf), s.map(s.array(self), Branch)])
        })
      gargamelle_boundary.new(s.contract(definition), fn(data, json) {
        #(data, json)
      })
    })
  let #(data, original) =
    handoff(fn() {
      let assert Ok(json) = s.parse("[1,[2]]")
      let assert Ok(output) = gargamelle_boundary.forward(boundary, json)
      output
    })
  data
  |> should.equal(Branch([Leaf(1.0), Branch([Leaf(2.0)])]))
  s.to_string(original, s.Compact) |> should.equal("[1,[2]]")
}

pub fn verify_without_conversion_and_exact_contract_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let definition =
    s.map(s.string_constant("Brainy"), fn(text) {
      tick()
      text <> "!"
    })
  let assert Ok(json) = s.parse("\"Brainy\"")
  let assert Ok(verified) = s.verify(s.contract(definition), json)
  s.verified_json(verified) |> should.equal(json)
  s.schema_string(s.verified_definition(verified), s.Compact)
  |> should.equal(s.schema_string(definition, s.Compact))
  count() |> should.equal(0)
  let assert Ok(other) = s.parse("\"Jokey\"")
  let assert Error(expected) = s.validate(definition, other)
  s.verify(s.contract(definition), other)
  |> should.equal(Error(s.Structural(expected)))
  count() |> should.equal(0)
  s.decode(s.verified_definition(verified), s.verified_json(verified))
  |> should.equal(Ok("Brainy!"))
  count() |> should.equal(1)
}

pub fn verified_json_and_definition_transfer_test() {
  let verified =
    handoff(fn() {
      let assert Ok(definition) =
        s.recursive("verified-tree", fn(self) {
          s.any_of([s.map(s.number(), Leaf), s.map(s.array(self), Branch)])
        })
      let assert Ok(json) = s.parse("[1,[2]]")
      let assert Ok(verified) = s.verify(s.contract(definition), json)
      verified
    })
  s.decode(s.verified_definition(verified), s.verified_json(verified))
  |> should.equal(Ok(Branch([Leaf(1.0), Branch([Leaf(2.0)])])))
}
