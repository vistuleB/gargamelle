import gargamelle
import gargamelle/encoding
import gleam/io
import provider_roundtrip as provider

pub fn main() {
  let registration =
    gargamelle.paired_boundary(
      provider.evidence_contract(),
      encoding.encode_json(provider.evidence_encoder(), _),
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
  let assert Ok(evidence) = gargamelle.load(registration, json)
  let assert Ok(stored) = gargamelle.save(registration, evidence)
  io.println(stored)
  let assert Error(gargamelle.ContractRejected(gargamelle.Semantic(_))) =
    gargamelle.save(registration, provider.Evidence([True, False], 2))
  io.println("Save rejected: score does not match answers")
}
