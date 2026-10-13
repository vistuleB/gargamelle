import gargamelle
import gargamelle/encoding as gargamelle_encoding
import gleam/io
import paired_boundary as paired
import provider_roundtrip as provider

pub fn main() {
  let registration =
    paired.paired_boundary(
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
  let assert Ok(evidence) = paired.load(registration, json)
  let assert Ok(stored) = paired.save(registration, evidence)
  io.println(stored)
  let assert Error(gargamelle_encoding.Contract(gargamelle.Semantic(_))) =
    paired.save(registration, provider.Evidence([True, False], 2))
  io.println("Save rejected: score does not match answers")
}
