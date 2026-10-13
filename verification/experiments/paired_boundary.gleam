// Private prototype: not in src, the package archive, or public documentation.
import gargamelle
import gargamelle/encoding

pub opaque type Pair(a, loaded, saved) {
  Pair(gargamelle.Boundary(a, loaded), encoding.OutputBoundary(a, saved))
}

pub fn pair(
  contract: gargamelle.Contract(a),
  encoder: encoding.Encoder(a),
  load_handler: fn(a, gargamelle.Json) -> loaded,
  save_handler: fn(gargamelle.VerifiedJson(a)) -> saved,
) -> Pair(a, loaded, saved) {
  let loader = gargamelle.boundary(contract, load_handler)
  let storage =
    gargamelle.json_boundary(gargamelle.boundary_contract(loader), save_handler)
  Pair(loader, encoding.output_boundary(encoder, storage))
}

pub fn contract(pair: Pair(a, loaded, saved)) -> gargamelle.Contract(a) {
  let Pair(loader, _) = pair
  gargamelle.boundary_contract(loader)
}

pub fn load(
  pair: Pair(a, loaded, saved),
  json: gargamelle.Json,
) -> Result(loaded, gargamelle.ContractError) {
  let Pair(loader, _) = pair
  gargamelle.forward(loader, json)
}

pub fn save(
  pair: Pair(a, loaded, saved),
  value: a,
) -> Result(saved, encoding.EncodingError) {
  let Pair(_, saver) = pair
  encoding.send(saver, value)
}
