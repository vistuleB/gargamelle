import gargamelle as s
import gleeunit/should

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

pub fn receiver_verifies_without_conversion_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let definition = s.map(s.text(), fn(_) { panic as "must not decode" })
  let receiver =
    s.json_boundary(definition, fn(verified) {
      tick()
      verified
    })
  let assert Ok(json) = s.parse("\"Brainy\"")
  let assert Ok(verified) = s.forward_json(receiver, json)
  s.verified_json(verified) |> should.equal(json)
  s.schema_string(s.verified_definition(verified), s.Compact)
  |> should.equal(s.schema_string(
    s.json_boundary_definition(receiver),
    s.Compact,
  ))
  count() |> should.equal(1)
}

pub fn invalid_input_preserves_errors_and_skips_handler_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let definition = s.array(s.text())
  let receiver = s.json_boundary(definition, fn(_) { tick() })
  let assert Ok(json) = s.parse("[false,42]")
  let assert Error(expected) = s.validate(definition, json)
  s.forward_json(receiver, json) |> should.equal(Error(expected))
  count() |> should.equal(0)
}

pub fn receiver_contract_is_authoritative_test() {
  let assert Ok(json) = s.parse("\"Jokey\"")
  let assert Ok(other_certificate) = s.verify(s.text(), json)
  let receiver =
    s.json_boundary(s.string_constant("Brainy"), fn(verified) {
      s.verified_json(verified)
    })
  s.forward_json(receiver, s.verified_json(other_certificate))
  |> should.be_error
  s.schema_string(s.json_boundary_definition(receiver), s.Compact)
  |> should.equal(s.schema_string(s.string_constant("Brainy"), s.Compact))
}

pub fn application_errors_and_process_transfer_test() {
  let receiver =
    handoff(fn() {
      s.json_boundary(s.string_constant("Brainy"), fn(_) {
        Error("storage failure")
      })
    })
  let assert Ok(json) = s.parse("\"Brainy\"")
  s.forward_json(receiver, json) |> should.equal(Ok(Error("storage failure")))
}
