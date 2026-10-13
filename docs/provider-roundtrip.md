# Loading and saving through one contract

A provider result can use the same contract at ingress and egress. The provider
supplies its contract and encoder; the host registers loading and storage handlers.
The saving receiver below obtains its contract from the loading boundary, so no
second contract is declared.

The result contains answer correctness flags and a reported score. Its structural
definition requires booleans and a nonnegative safe integer. A semantic requirement
checks that the score equals the number of correct answers. Both loading and saving
reject inconsistent results before invoking their respective handlers.

```gleam
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
```

Output:

```text
{"answers":[true,false],"score":1}
Load rejected: score does not match answers
Save rejected: score does not match answers
```

The storage handler returns JSON text to keep the example self-contained. In an
application it can instead write the verified JSON to storage. Application failures
remain separate from contract rejection; handler exceptions propagate.

## Validation and transformation order

| Operation | Order |
| --- | --- |
| Loading with `forward` | Validate original admitted JSON, decode once, run semantic requirements, invoke loading handler |
| Saving with `encoding.send` | Encode to admitted JSON, validate encoded JSON, decode once when semantic requirements exist, run requirements, invoke storage handler |
| Generating JSON Schema | Emit structural acceptance rules; do not run conversions or semantic requirements |

Structural rejection skips decoding, semantic requirements, and handlers. Semantic
rejection skips the handler. Each direction performs one contract check; a complete
load/save cycle performs two checks, one at each boundary. Saving uses unchecked
encoding followed by receiving verification, rather than checked encoding followed
by another verification.

Defaults, projections, and mappings affect decoded values. Semantic requirements
inspect those decoded values, including on output: they inspect the reconstruction
from encoded JSON, not the encoder's original Gleam input. Verified JSON preserves
the admitted representation, including fields discarded during decoding.

This is a load/save workflow, not a promise that encoding and decoding are inverses.
A mapping can change a value or lose information, and an encoder must explicitly
choose the output representation. Requirements run after decoding in declaration
order; structural modifier declaration order does not interleave checks with
conversion. The [technical contract](contract.html) specifies these distinctions.
