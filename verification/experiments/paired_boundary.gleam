import gargamelle/boundary as gargamelle_boundary
// Private prototype: not in src, the package archive, or public documentation.
import gargamelle
import gargamelle/encoding as gargamelle_encoding
pub opaque type PairedBoundary(a, loaded, saved) {
  PairedBoundary(
    gargamelle_boundary.Boundary(a, loaded),
    gargamelle_boundary.OutputBoundary(a, saved),
  )
}

pub fn paired_boundary(
  contract: gargamelle.Contract(a),
  encoder: gargamelle_encoding.Encoder(a),
  load_handler: fn(a, gargamelle.Json) -> loaded,
  save_handler: fn(gargamelle.VerifiedJson(a)) -> saved,
) -> PairedBoundary(a, loaded, saved) {
  let loader = gargamelle_boundary.boundary(contract, load_handler)
  let storage =
    gargamelle_boundary.json_boundary(gargamelle_boundary.boundary_contract(loader), save_handler)
  PairedBoundary(loader, gargamelle_boundary.output_boundary(encoder, storage))
}

pub fn paired_boundary_contract(
  pair: PairedBoundary(a, loaded, saved),
) -> gargamelle.Contract(a) {
  let PairedBoundary(loader, _) = pair
  gargamelle_boundary.boundary_contract(loader)
}

pub fn load(
  pair: PairedBoundary(a, loaded, saved),
  json: gargamelle.Json,
) -> Result(loaded, gargamelle.ContractError) {
  let PairedBoundary(loader, _) = pair
  gargamelle_boundary.forward(loader, json)
}

pub fn save(
  pair: PairedBoundary(a, loaded, saved),
  value: a,
) -> Result(saved, gargamelle_encoding.EncodingError) {
  let PairedBoundary(_, saver) = pair
  gargamelle_boundary.send(saver, value)
}
