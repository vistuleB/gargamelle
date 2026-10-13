import gargamelle
import gargamelle/boundary as gargamelle_boundary
import gargamelle/encoding as gargamelle_encoding
import gleam/io
import provider_roundtrip as provider

pub fn main() {
  let registration =
    gargamelle_boundary.paired_boundary(
      provider.evidence_contract(),
      provider.evidence_encoder(),
      fn(evidence, _) { evidence },
      fn(verified) {
        gargamelle.to_string(
          gargamelle.verified_json(verified),
          gargamelle.Compact,
        )
      },
    )
  let assert Ok(json) =
    gargamelle.parse("{\"answers\":[true,false],\"score\":1}")
  let assert Ok(evidence) = gargamelle_boundary.load(registration, json)
  let assert Ok(stored) = gargamelle_boundary.save(registration, evidence)
  io.println(stored)
  let assert Error(gargamelle_encoding.Contract(gargamelle.Semantic(_))) =
    gargamelle_boundary.save(registration, provider.Evidence([True, False], 2))
  io.println("Save rejected: score does not match answers")
}
