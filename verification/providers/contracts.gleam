// Consumer integration adapters. Compiled only with the supplied provider sources.
import gargamelle as s
import gleam/result
import providers_cloze as cloze
import providers_diagram_labeling as diagram

fn check(result: Result(a, String)) -> Result(Nil, List(s.Violation)) {
  result
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(message) { [s.Violation("", message)] })
}

pub fn cloze_historical() {
  s.contract(cloze.result_definition())
  |> s.require(
    "Recorded alternatives, correctness flags and totals agree",
    fn(value) { check(cloze.validate_evidence(value)) },
  )
}

pub fn cloze_current(card: cloze.Content) {
  cloze_historical()
  |> s.require("New evidence matches the current card", fn(value) {
    check(cloze.validate_evidence_context(value, card))
  })
}

pub fn cloze_session(signature: String, ids: List(String)) {
  s.contract(cloze.session_definition())
  |> s.require(
    "Session signature and blank IDs match current content",
    fn(value) { check(cloze.validate_session(value, signature, ids)) },
  )
}

pub fn diagram_historical() {
  s.contract(diagram.result_definition())
  |> s.require("Recorded labels, correctness flags and totals agree", fn(value) {
    check(diagram.validate_result(value))
  })
}

pub fn diagram_current(targets: List(#(String, String)), labels: List(String)) {
  diagram_historical()
  |> s.require(
    "New evidence matches current diagram targets and labels",
    fn(value) { check(diagram.validate_result_context(value, targets, labels)) },
  )
}

pub fn diagram_session(
  signature: String,
  targets: List(String),
  labels: List(String),
) {
  s.contract(diagram.session_definition())
  |> s.require(
    "Session signature and placements match current diagram",
    fn(value) {
      check(diagram.validate_session_for(value, signature, targets, labels))
    },
  )
}
