import gargamelle
import gargamelle/boundary as gargamelle_boundary
import gargamelle/encoding as gargamelle_encoding
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

pub fn evidence_encoder() -> gargamelle_encoding.Encoder(Evidence) {
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "answers",
      gargamelle_encoding.array(gargamelle_encoding.boolean()),
      fn(evidence: Evidence) { evidence.answers },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "score",
      gargamelle_encoding.safe_integer(),
      fn(evidence) { evidence.score },
    )
  gargamelle_encoding.finish(fields)
}

pub fn main() {
  // The provider supplies the contract and encoder; the host supplies handlers.
  let loader =
    gargamelle_boundary.boundary(evidence_contract(), fn(evidence, _) {
      evidence
    })
  let storage =
    gargamelle_boundary.json_boundary(
      gargamelle_boundary.boundary_contract(loader),
      fn(verified) {
        gargamelle.to_string(
          gargamelle.verified_json(verified),
          gargamelle.Compact,
        )
      },
    )
  let saver = gargamelle_boundary.output_boundary(evidence_encoder(), storage)

  let assert Ok(json) =
    gargamelle.parse("{\"answers\":[true,false],\"score\":1}")
  let assert Ok(evidence) = gargamelle_boundary.forward(loader, json)
  let assert Ok(stored) = gargamelle_boundary.send(saver, evidence)
  io.println(stored)

  let assert Ok(json) =
    gargamelle.parse("{\"answers\":[true,false],\"score\":2}")
  let assert Error(gargamelle.Semantic(_)) =
    gargamelle_boundary.forward(loader, json)
  io.println("Load rejected: score does not match answers")
  let assert Error(gargamelle_encoding.Contract(gargamelle.Semantic(_))) =
    gargamelle_boundary.send(saver, Evidence([True, False], 2))
  io.println("Save rejected: score does not match answers")
}
