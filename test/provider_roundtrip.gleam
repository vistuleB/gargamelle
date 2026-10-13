import gargamelle
import gargamelle/encoding
import gleam/io
import gleam/list
import gleam/option.{None, Some}

pub type Evidence {
  Evidence(answers: List(Bool), score: Int)
}

pub fn evidence_contract() -> gargamelle.Contract(Evidence) {
  let assert Ok(score) =
    gargamelle.bounds(gargamelle.safe_integer(), Some(0), None)
  let assert Ok(fields) =
    gargamelle.required(
      gargamelle.record(fn(answers) { fn(score) { Evidence(answers, score) } }),
      "answers",
      gargamelle.array(gargamelle.boolean()),
    )
  let assert Ok(fields) = gargamelle.required(fields, "score", score)
  gargamelle.contract(gargamelle.finish(fields, gargamelle.Strict))
  |> gargamelle.require(
    "Score equals the number of correct answers",
    fn(evidence) {
      case
        evidence.score
        == list.length(list.filter(evidence.answers, fn(answer) { answer }))
      {
        True -> Ok(Nil)
        False ->
          Error([gargamelle.Violation("/score", "Score does not match answers")])
      }
    },
  )
}

pub fn evidence_encoder() -> encoding.Encoder(Evidence) {
  let assert Ok(fields) =
    encoding.field(
      encoding.record(),
      "answers",
      encoding.array(encoding.boolean()),
      fn(evidence: Evidence) { evidence.answers },
    )
  let assert Ok(fields) =
    encoding.field(fields, "score", encoding.safe_integer(), fn(evidence) {
      evidence.score
    })
  encoding.finish(fields)
}

pub fn main() {
  // The provider supplies the contract and encoder; the host supplies handlers.
  let loader =
    gargamelle.boundary(evidence_contract(), fn(evidence, _) { evidence })
  let storage =
    gargamelle.json_boundary(gargamelle.boundary_contract(loader), fn(verified) {
      gargamelle.to_string(
        gargamelle.verified_json(verified),
        gargamelle.Compact,
      )
    })
  let saver = encoding.output_boundary(evidence_encoder(), storage)

  let assert Ok(json) =
    gargamelle.parse("{\"answers\":[true,false],\"score\":1}")
  let assert Ok(evidence) = gargamelle.forward(loader, json)
  let assert Ok(stored) = encoding.send(saver, evidence)
  io.println(stored)

  let assert Ok(json) =
    gargamelle.parse("{\"answers\":[true,false],\"score\":2}")
  let assert Error(gargamelle.Semantic(_)) = gargamelle.forward(loader, json)
  io.println("Load rejected: score does not match answers")
  let assert Error(encoding.Contract(gargamelle.Semantic(_))) =
    encoding.send(saver, Evidence([True, False], 2))
  io.println("Save rejected: score does not match answers")
}
