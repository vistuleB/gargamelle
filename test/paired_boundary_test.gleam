import gargamelle as s
import gargamelle/encoding as e
import gleeunit/should
import provider_roundtrip as provider

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

pub fn construction_and_inspection_run_no_callbacks_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let definition =
    s.map(s.text(), fn(text) {
      tick()
      text
    })
  let contract =
    s.contract(definition)
    |> s.require("Registered check", fn(_) {
      tick()
      Ok(Nil)
    })
  let encoder =
    e.contramap(e.text(), fn(text) {
      tick()
      text
    })
  let pair =
    s.paired_boundary(
      contract,
      e.encode_json(encoder, _),
      fn(_, _) { tick() },
      fn(_) { tick() },
    )
  let inspected = s.paired_boundary_contract(pair)
  s.contract_requirements(inspected) |> should.equal(["Registered check"])
  s.schema_string(s.contract_definition(inspected), s.Compact)
  |> should.equal(s.schema_string(definition, s.Compact))
  count() |> should.equal(0)
}

pub fn one_registered_contract_rejects_before_either_handler_test() {
  let #(load_tick, loads) = counter(fn(tick, count) { #(tick, count) })
  let #(save_tick, saves) = counter(fn(tick, count) { #(tick, count) })
  let #(check_tick, checks) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    provider.evidence_contract()
    |> s.require("Count", fn(_) {
      check_tick()
      Ok(Nil)
    })
  let pair =
    s.paired_boundary(
      contract,
      e.encode_json(provider.evidence_encoder(), _),
      fn(data, _) {
        load_tick()
        data
      },
      fn(verified) {
        save_tick()
        s.to_string(s.verified_json(verified), s.Compact)
      },
    )
  let assert Ok(json) = s.parse("{\"answers\":[true,false],\"score\":2}")
  let assert Error(s.Semantic(failures)) = s.load(pair, json)
  s.save(pair, provider.Evidence([True, False], 2))
  |> should.equal(Error(s.ContractRejected(s.Semantic(failures))))
  checks() |> should.equal(2)
  loads() |> should.equal(0)
  saves() |> should.equal(0)

  let assert Ok(json) = s.parse("{\"answers\":[true,false],\"score\":-1}")
  let assert Error(s.Structural(errors)) = s.load(pair, json)
  s.save(pair, provider.Evidence([True, False], -1))
  |> should.equal(Error(s.ContractRejected(s.Structural(errors))))
  checks() |> should.equal(2)
  loads() |> should.equal(0)
  saves() |> should.equal(0)

  let assert Ok(json) = s.parse("{\"answers\":[true,false],\"score\":1}")
  let assert Ok(value) = s.load(pair, json)
  s.save(pair, value)
  |> should.equal(Ok("{\"answers\":[true,false],\"score\":1}"))
  checks() |> should.equal(4)
  loads() |> should.equal(1)
  saves() |> should.equal(1)
}

pub fn independent_responses_preserve_nested_application_results_test() {
  let pair =
    s.paired_boundary(
      s.contract(s.text()),
      e.encode_json(e.text(), _),
      fn(_, _) { Error("load application failure") },
      fn(_) { Error(42) },
    )
  let assert Ok(json) = s.parse("\"Brainy\"")
  s.load(pair, json) |> should.equal(Ok(Error("load application failure")))
  s.save(pair, "Brainy") |> should.equal(Ok(Error(42)))
}

pub fn same_contract_does_not_imply_inverse_conversion_test() {
  let contract =
    s.contract(s.map(s.text(), fn(text) { text <> "!" }))
    |> s.require("Decoded value", fn(text) {
      case text == "Brainy!" {
        True -> Ok(Nil)
        False -> Error([s.Violation("", "Unexpected value")])
      }
    })
  let pair =
    s.paired_boundary(
      contract,
      e.encode_json(e.text(), _),
      fn(value, original) { #(value, s.to_string(original, s.Compact)) },
      fn(verified) { s.to_string(s.verified_json(verified), s.Compact) },
    )
  let assert Ok(json) = s.parse("\"Brainy\"")
  s.load(pair, json) |> should.equal(Ok(#("Brainy!", "\"Brainy\"")))
  s.save(pair, "Brainy") |> should.equal(Ok("\"Brainy\""))
  s.save(pair, "Brainy!") |> should.be_error
}

pub fn pair_survives_transfer_and_creator_exit_test() {
  let pair =
    handoff(fn() {
      s.paired_boundary(
        provider.evidence_contract(),
        e.encode_json(provider.evidence_encoder(), _),
        fn(data, _) { data },
        fn(verified) { s.to_string(s.verified_json(verified), s.Compact) },
      )
    })
  let assert Ok(json) = s.parse("{\"answers\":[true,false],\"score\":1}")
  let assert Ok(value) = handoff(fn() { s.load(pair, json) })
  value |> should.equal(provider.Evidence([True, False], 1))
  handoff(fn() { s.save(pair, value) })
  |> should.equal(Ok("{\"answers\":[true,false],\"score\":1}"))
}

pub fn unchecked_encoding_failure_keeps_its_type_and_skips_checks_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    s.contract(s.text())
    |> s.require("Must not run", fn(_) {
      tick()
      Ok(Nil)
    })
  let pair =
    s.paired_boundary(
      contract,
      fn(_) { Error("encoding refused") },
      fn(_, _) { tick() },
      fn(_) { tick() },
    )
  s.save(pair, "Brainy")
  |> should.equal(Error(s.EncodingFailed("encoding refused")))
  count() |> should.equal(0)
}

pub fn check_free_saving_does_not_decode_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    s.contract(
      s.map(s.text(), fn(text) {
        tick()
        text
      }),
    )
  let pair =
    s.paired_boundary(
      contract,
      e.encode_json(e.text(), _),
      fn(value, _) { value },
      fn(verified) { s.verified_json(verified) },
    )
  let assert Ok(json) = s.save(pair, "Brainy")
  s.to_string(json, s.Compact) |> should.equal("\"Brainy\"")
  count() |> should.equal(0)
  s.load(pair, json) |> should.equal(Ok("Brainy"))
  count() |> should.equal(1)
}
