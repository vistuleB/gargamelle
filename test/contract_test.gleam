import gargamelle as s
import gargamelle/boundary as gargamelle_boundary
import gargamelle/documentation as docs
import gleam/string
import gleeunit/should

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

pub fn structural_rejection_skips_all_callbacks_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    s.contract(
      s.map(s.text(), fn(text) {
        tick()
        text
      }),
    )
    |> s.require("Check", fn(_) {
      tick()
      Ok(Nil)
    })
  let receiver = gargamelle_boundary.boundary(contract, fn(_, _) { tick() })
  let assert Ok(json) = s.parse("false")
  let assert Error(errors) = s.validate(s.text(), json)
  gargamelle_boundary.forward(receiver, json)
  |> should.equal(Error(s.Structural(errors)))
  count() |> should.equal(0)
}

pub fn conversion_checks_and_handler_run_once_in_order_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    s.contract(
      s.map(s.text(), fn(text) {
        count() |> should.equal(0)
        tick()
        text
      }),
    )
    |> s.require("First", fn(text) {
      text |> should.equal("Brainy")
      count() |> should.equal(1)
      tick()
      Ok(Nil)
    })
    |> s.require("Second", fn(_) {
      count() |> should.equal(2)
      tick()
      Ok(Nil)
    })
  let receiver =
    gargamelle_boundary.boundary(contract, fn(text, _) {
      count() |> should.equal(3)
      tick()
      text
    })
  let assert Ok(json) = s.parse("\"Brainy\"")
  gargamelle_boundary.forward(receiver, json) |> should.equal(Ok("Brainy"))
  count() |> should.equal(4)
}

pub fn semantic_failures_are_collected_and_skip_handler_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    s.contract(s.text())
    |> s.require("First", fn(_) {
      tick()
      Error([s.Violation("", "First failure")])
    })
    |> s.require("Accepted", fn(_) {
      tick()
      Ok(Nil)
    })
    |> s.require("Third", fn(_) {
      tick()
      Error([s.Violation("/field", "Third failure")])
    })
  let receiver =
    gargamelle_boundary.boundary(contract, fn(_, _) {
      panic as "Rejected handler"
    })
  let assert Ok(json) = s.parse("\"Brainy\"")
  gargamelle_boundary.forward(receiver, json)
  |> should.equal(
    Error(
      s.Semantic([
        s.RequirementFailure(0, "First", [s.Violation("", "First failure")]),
        s.RequirementFailure(2, "Third", [
          s.Violation("/field", "Third failure"),
        ]),
      ]),
    ),
  )
  count() |> should.equal(3)
}

pub fn empty_failure_is_still_rejection_test() {
  let contract =
    s.contract(s.text()) |> s.require("Reject", fn(_) { Error([]) })
  let assert Ok(json) = s.parse("\"Brainy\"")
  s.validate_contract(contract, json)
  |> should.equal(
    Error(
      s.Semantic([
        s.RequirementFailure(0, "Reject", [
          s.Violation("", "Requirement rejected without a diagnostic"),
        ]),
      ]),
    ),
  )
}

pub fn json_checks_decode_once_and_preserve_original_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let assert Ok(record) =
    s.record(fn(name) { name }) |> s.required("name", s.text())
  let definition =
    s.finish(record, s.Open)
    |> s.map(fn(name) {
      tick()
      name
    })
  let contract =
    s.contract(definition)
    |> s.require("Name", fn(name) {
      name |> should.equal("Brainy")
      Ok(Nil)
    })
  let receiver =
    gargamelle_boundary.json_boundary(contract, fn(verified) { verified })
  let assert Ok(json) = s.parse("{\"name\":\"Brainy\",\"extra\":42}")
  let assert Ok(verified) = gargamelle_boundary.forward_json(receiver, json)
  count() |> should.equal(1)
  s.verified_json(verified) |> should.equal(json)
  s.contract_requirements(s.verified_contract(verified))
  |> should.equal(["Name"])
  s.schema_string(s.verified_definition(verified), s.Compact)
  |> should.equal(s.schema_string(definition, s.Compact))
}

pub fn semantic_contract_is_authoritative_and_transferable_test() {
  let receiver =
    handoff(fn() {
      let expected = "Brainy"
      let contract =
        s.contract(s.text())
        |> s.require("Expected name", fn(name) {
          case name == expected {
            True -> Ok(Nil)
            False -> Error([s.Violation("", "Unexpected name")])
          }
        })
      gargamelle_boundary.json_boundary(contract, fn(verified) {
        s.verified_json(verified)
      })
    })
  let assert Ok(other_json) = s.parse("\"Jokey\"")
  let assert Ok(other) = s.verify(s.contract(s.text()), other_json)
  gargamelle_boundary.forward_json(receiver, s.verified_json(other))
  |> should.be_error
  let assert Ok(json) = s.parse("\"Brainy\"")
  gargamelle_boundary.forward_json(receiver, json) |> should.equal(Ok(json))
}

pub fn typed_and_json_receivers_enforce_same_contract_test() {
  let contract =
    s.contract(s.text())
    |> s.require("Expected name", fn(name) {
      case name == "Brainy" {
        True -> Ok(Nil)
        False -> Error([s.Violation("", "Unexpected name")])
      }
    })
  let typed = gargamelle_boundary.boundary(contract, fn(_, json) { json })
  let json_only = gargamelle_boundary.json_boundary(contract, s.verified_json)
  let assert Ok(accepted) = s.parse("\"Brainy\"")
  let assert Ok(rejected) = s.parse("\"Jokey\"")
  let assert Ok(invalid) = s.parse("false")
  gargamelle_boundary.forward(typed, accepted)
  |> should.equal(gargamelle_boundary.forward_json(json_only, accepted))
  gargamelle_boundary.forward(typed, rejected)
  |> should.equal(gargamelle_boundary.forward_json(json_only, rejected))
  gargamelle_boundary.forward(typed, invalid)
  |> should.equal(gargamelle_boundary.forward_json(json_only, invalid))
}

pub fn contract_documentation_lists_every_requirement_without_callbacks_test() {
  let definition = s.map(s.text(), fn(_) { panic as "No conversion" })
  let contract =
    s.contract(definition)
    |> s.require("Check <one>", fn(_) { panic as "No check" })
    |> s.require("Check <one>", fn(_) { panic as "No check" })
  s.contract_requirements(contract)
  |> should.equal(["Check <one>", "Check <one>"])
  s.schema_string(s.contract_definition(contract), s.Compact)
  |> should.equal(s.schema_string(definition, s.Compact))
  let html = docs.render_contract(contract, "requirements")
  string.contains(html, "<li>Check &lt;one&gt;</li><li>Check &lt;one&gt;</li>")
  |> should.be_true
  string.contains(html, "Additional semantic requirements") |> should.be_true
}
