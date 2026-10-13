// Private prototype: not in src, the package archive, or public documentation.
import gargamelle
import gargamelle/encoding

pub opaque type PairedBoundary(a, loaded, saved) {
  PairedBoundary(
    gargamelle.Boundary(a, loaded),
    encoding.OutputBoundary(a, saved),
  )
}

pub fn paired_boundary(
  contract: gargamelle.Contract(a),
  encoder: encoding.Encoder(a),
  load_handler: fn(a, gargamelle.Json) -> loaded,
  save_handler: fn(gargamelle.VerifiedJson(a)) -> saved,
) -> PairedBoundary(a, loaded, saved) {
  let loader = gargamelle.boundary(contract, load_handler)
  let storage =
    gargamelle.json_boundary(gargamelle.boundary_contract(loader), save_handler)
  PairedBoundary(loader, encoding.output_boundary(encoder, storage))
}

pub fn paired_boundary_contract(
  pair: PairedBoundary(a, loaded, saved),
) -> gargamelle.Contract(a) {
  let PairedBoundary(loader, _) = pair
  gargamelle.boundary_contract(loader)
}

pub fn load(
  pair: PairedBoundary(a, loaded, saved),
  json: gargamelle.Json,
) -> Result(loaded, gargamelle.ContractError) {
  let PairedBoundary(loader, _) = pair
  gargamelle.forward(loader, json)
}

pub fn save(
  pair: PairedBoundary(a, loaded, saved),
  value: a,
) -> Result(saved, encoding.EncodingError) {
  let PairedBoundary(_, saver) = pair
  encoding.send(saver, value)
}
