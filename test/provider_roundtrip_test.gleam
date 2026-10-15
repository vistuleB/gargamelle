import gargamelle as s
import gargamelle/boundary as gargamelle_boundary
import gargamelle/encoding as gargamelle_encoding
import gleeunit/should
import provider_roundtrip as provider

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

pub fn shared_contract_rejects_both_directions_without_handlers_test() {
  let #(loaded, load_count) = counter(fn(tick, count) { #(tick, count) })
  let #(stored, store_count) = counter(fn(tick, count) { #(tick, count) })
  let #(checked, check_count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    provider.evidence_contract()
    |> s.require("Count checks", fn(_) {
      checked()
      Ok(Nil)
    })
  let loader =
    gargamelle_boundary.new(contract, fn(data, _) {
      loaded()
      data
    })
  let receiver =
    gargamelle_boundary.json(gargamelle_boundary.contract(loader), fn(verified) {
      stored()
      s.to_string(s.verified_json(verified), s.Compact)
    })
  let saver = gargamelle_boundary.output(provider.evidence_encoder(), receiver)
  s.contract_requirements(gargamelle_boundary.output_contract(saver))
  |> should.equal(s.contract_requirements(gargamelle_boundary.contract(loader)))

  let assert Ok(valid) = s.parse("{\"answers\":[true,false],\"score\":1}")
  let assert Ok(data) = gargamelle_boundary.forward(loader, valid)
  data |> should.equal(provider.Evidence([True, False], 1))
  gargamelle_boundary.send(saver, data)
  |> should.equal(Ok("{\"answers\":[true,false],\"score\":1}"))
  load_count() |> should.equal(1)
  store_count() |> should.equal(1)
  check_count() |> should.equal(2)

  let assert Ok(invalid) = s.parse("{\"answers\":[true,false],\"score\":2}")
  let assert Error(s.Semantic(failures)) =
    gargamelle_boundary.forward(loader, invalid)
  gargamelle_boundary.send(saver, provider.Evidence([True, False], 2))
  |> should.equal(Error(gargamelle_encoding.Contract(s.Semantic(failures))))
  failures
  |> should.equal([
    s.RequirementFailure(0, "Score equals the number of correct answers", [
      s.Violation("/score", "Score does not match answers"),
    ]),
  ])
  check_count() |> should.equal(4)

  let assert Ok(invalid) = s.parse("{\"answers\":[true],\"score\":-1}")
  let assert Error(s.Structural(errors)) =
    gargamelle_boundary.forward(loader, invalid)
  gargamelle_boundary.send(saver, provider.Evidence([True], -1))
  |> should.equal(Error(gargamelle_encoding.Contract(s.Structural(errors))))
  check_count() |> should.equal(4)
  load_count() |> should.equal(1)
  store_count() |> should.equal(1)
}

pub fn output_checks_reconstructed_value_and_retains_encoded_json_test() {
  let contract =
    s.contract(s.map(s.text(), fn(text) { text <> "!" }))
    |> s.require("Decoded value ends with exclamation", fn(text) {
      case text == "Brainy!" {
        True -> Ok(Nil)
        False -> Error([s.Violation("", "Unexpected decoded value")])
      }
    })
  let loader =
    gargamelle_boundary.new(contract, fn(data, original) {
      #(data, s.to_string(original, s.Compact))
    })
  let storage =
    gargamelle_boundary.json(gargamelle_boundary.contract(loader), fn(verified) {
      s.to_string(s.verified_json(verified), s.Compact)
    })
  let saver = gargamelle_boundary.output(gargamelle_encoding.text(), storage)
  let assert Ok(json) = s.parse("\"Brainy\"")
  gargamelle_boundary.forward(loader, json)
  |> should.equal(Ok(#("Brainy!", "\"Brainy\"")))
  gargamelle_boundary.send(saver, "Brainy") |> should.equal(Ok("\"Brainy\""))
  // The decoded value is not automatically an inverse encoder input.
  gargamelle_boundary.send(saver, "Brainy!") |> should.be_error
}
