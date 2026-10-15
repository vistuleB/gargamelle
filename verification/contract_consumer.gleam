import gargamelle/boundary as gargamelle_boundary

// Fresh exported-package consumer: the semantic layer is independent of schema.
import gargamelle as s
import gargamelle/documentation as docs
import gleam/io
import gleam/list
import gleam/string

pub fn main() {
  let definition = s.array(s.string())
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
    gargamelle_boundary.new(contract, fn(names, original) {
      #(names, original)
    })
  let assert Ok(#(["Brainy", "Jokey"], original)) =
    gargamelle_boundary.forward(receiver, json)
  let assert True = original == json
  let json_receiver =
    gargamelle_boundary.json(contract, s.verified_json)
  let assert Ok(original) =
    gargamelle_boundary.forward_json(json_receiver, json)
  let assert True = original == json
  let assert Error(s.Semantic(_)) =
    gargamelle_boundary.forward_json(json_receiver, rejected)
  let assert Ok(weak) = s.verify(s.contract(definition), rejected)
  let assert Error(s.Semantic(_)) =
    gargamelle_boundary.forward_json(json_receiver, s.verified_json(weak))
  let assert Ok(verified) = s.verify(contract, json)
  let assert ["First name is <Brainy>", "Names are unique"] =
    s.contract_requirements(s.verified_contract(verified))
  let assert True =
    s.schema_string(s.verified_definition(verified), s.Compact)
    == s.schema_string(definition, s.Compact)
  let html =
    docs.render_contract(
      gargamelle_boundary.contract(receiver),
      "contract",
    )
  let assert True = string.contains(html, "First name is &lt;Brainy&gt;")
  let assert True =
    s.contract_requirements(gargamelle_boundary.json_contract(
      json_receiver,
    ))
    == s.contract_requirements(contract)
  io.println("release contract consumer passed")
}
