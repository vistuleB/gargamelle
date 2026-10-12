// Fresh exported-package consumer: the semantic layer is independent of schema.
import gargamelle as s
import gargamelle/documentation as docs
import gleam/io
import gleam/list
import gleam/string

pub fn main() {
  let definition = s.array(s.text())
  let expected = "Brainy"
  let contract =
    s.contract(definition)
    |> s.require("First name is <Brainy>", fn(names) {
      case names {
        [first, ..] if first == expected -> Ok(Nil)
        _ -> Error([s.Violation("/0", "Unexpected first name")])
      }
    })
    |> s.require("Names are unique", fn(names) {
      case list.length(list.unique(names)) == list.length(names) {
        True -> Ok(Nil)
        False -> Error([s.Violation("", "Duplicate names")])
      }
    })
  let assert Ok(json) = s.parse("[\"Brainy\",\"Jokey\"]")
  let assert Ok(rejected) = s.parse("[\"Jokey\",\"Jokey\"]")
  let assert Ok(_) = s.validate(definition, rejected)
  let assert Error(s.Semantic(failures)) =
    s.validate_contract(contract, rejected)
  let assert [s.RequirementFailure(0, _, _), s.RequirementFailure(1, _, _)] =
    failures
  let receiver =
    s.boundary(contract, fn(names, original) { #(names, original) })
  let assert Ok(#(["Brainy", "Jokey"], original)) = s.forward(receiver, json)
  let assert True = original == json
  let json_receiver = s.json_boundary(contract, s.verified_json)
  let assert Ok(original) = s.forward_json(json_receiver, json)
  let assert True = original == json
  let assert Error(s.Semantic(_)) = s.forward_json(json_receiver, rejected)
  let assert Ok(weak) = s.verify(s.contract(definition), rejected)
  let assert Error(s.Semantic(_)) =
    s.forward_json(json_receiver, s.verified_json(weak))
  let assert Ok(verified) = s.verify(contract, json)
  let assert ["First name is <Brainy>", "Names are unique"] =
    s.contract_requirements(s.verified_contract(verified))
  let assert True =
    s.schema_string(s.verified_definition(verified), s.Compact)
    == s.schema_string(definition, s.Compact)
  let html = docs.render_contract(s.boundary_contract(receiver), "contract")
  let assert True = string.contains(html, "First name is &lt;Brainy&gt;")
  let assert True =
    s.contract_requirements(s.json_boundary_contract(json_receiver))
    == s.contract_requirements(contract)
  io.println("release contract consumer passed")
}
