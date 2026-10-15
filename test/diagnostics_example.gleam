import gargamelle
import gargamelle/diagnostics as gargamelle_diagnostics
import gleam/io

pub fn main() {
  let contract = gargamelle.contract(gargamelle.array(gargamelle.string()))
  let assert Ok(json) = gargamelle.parse("[\"Brainy\", false]")
  let assert Error(error) = gargamelle.decode_contract(contract, json)
  io.println(gargamelle_diagnostics.summary(error, 5))
  let assert Ok(report) = gargamelle_diagnostics.to_json(error)
  io.println(gargamelle.to_string(report, gargamelle.Compact))
}
