//// Receiving, typed output, and paired boundaries bound to authoritative contracts.
//// These optional APIs check JSON before invoking private handlers. Admission,
//// application policy, and operational failures remain separate.

import gargamelle
import gargamelle/encoding as gargamelle_encoding
import gleam/result

/// A contract and a private handler invoked only after successful decoding and
/// semantic checks. Construct with `new`, inspect with `contract`,
/// and submit JSON with `forward`.
pub opaque type Boundary(a, response) {
  Boundary(gargamelle.Contract(a), fn(a, gargamelle.Json) -> response)
}

/// A contract and a private handler receiving verified JSON. Semantic checks
/// require decoding once; contracts without checks validate without conversion.
/// Construct with `json`, inspect with `json_contract`, and
/// submit admitted JSON with `forward_json`.
pub opaque type JsonBoundary(a, response) {
  JsonBoundary(
    gargamelle.Contract(a),
    fn(gargamelle.VerifiedJson(a)) -> response,
  )
}

/// Bind a handler to its authoritative contract. Construction runs no callbacks.
pub fn new(
  contract: gargamelle.Contract(a),
  handler: fn(a, gargamelle.Json) -> response,
) -> Boundary(a, response) {
  Boundary(contract, handler)
}

/// Return the receiving contract without exposing its handler.
pub fn contract(boundary: Boundary(a, response)) -> gargamelle.Contract(a) {
  let Boundary(contract, _) = boundary
  contract
}

/// Return the receiving contract's structural definition for schema generation.
pub fn definition(boundary: Boundary(a, response)) -> gargamelle.Definition(a) {
  gargamelle.contract_definition(contract(boundary))
}

/// Decode and check the stored contract once, then invoke the handler once.
/// Rejection invokes no handler. Callback exceptions propagate operationally.
/// A Result response remains nested; output is not checked.
pub fn forward(
  boundary: Boundary(a, response),
  json: gargamelle.Json,
) -> Result(response, gargamelle.ContractError) {
  let Boundary(contract, handler) = boundary
  use data <- result.try(gargamelle.decode_contract(contract, json))
  Ok(handler(data, json))
}

/// Bind a JSON receiving handler to its authoritative contract.
pub fn json(
  contract: gargamelle.Contract(a),
  handler: fn(gargamelle.VerifiedJson(a)) -> response,
) -> JsonBoundary(a, response) {
  JsonBoundary(contract, handler)
}

/// Return the receiving contract without exposing its handler.
pub fn json_contract(
  boundary: JsonBoundary(a, response),
) -> gargamelle.Contract(a) {
  let JsonBoundary(contract, _) = boundary
  contract
}

/// Return the receiving contract's structural definition for schema generation.
pub fn json_definition(
  boundary: JsonBoundary(a, response),
) -> gargamelle.Definition(a) {
  gargamelle.contract_definition(json_contract(boundary))
}

/// Verify the stored contract once, then invoke the handler once. Semantic
/// requirements cause one decoding pass; without them no converter runs.
/// Admission and application policy are separate. Certificates from other
/// contracts cannot bypass this check. Exceptions propagate operationally.
pub fn forward_json(
  boundary: JsonBoundary(a, response),
  json: gargamelle.Json,
) -> Result(response, gargamelle.ContractError) {
  let JsonBoundary(contract, handler) = boundary
  use verified <- result.try(gargamelle.verify(contract, json))
  Ok(handler(verified))
}

/// A typed producer path through an existing JSON receiving boundary. Its
/// receiving Contract is authoritative; no second definition is stored.
pub opaque type OutputBoundary(a, response) {
  OutputBoundary(gargamelle_encoding.Encoder(a), JsonBoundary(a, response))
}

/// Pair an encoder with an existing receiving boundary. Construction executes no
/// callbacks. The receiver's Contract is the sole acceptance authority.
pub fn output(
  encoder: gargamelle_encoding.Encoder(a),
  receiver: JsonBoundary(a, response),
) -> OutputBoundary(a, response) {
  OutputBoundary(encoder, receiver)
}

/// Inspect the exact receiving Contract without exposing its private handler.
pub fn output_contract(
  output: OutputBoundary(a, response),
) -> gargamelle.Contract(a) {
  let OutputBoundary(_, receiver) = output
  json_contract(receiver)
}

/// Return the receiving contract's structural definition without running callbacks.
pub fn output_definition(
  output: OutputBoundary(a, response),
) -> gargamelle.Definition(a) {
  gargamelle.contract_definition(output_contract(output))
}

/// Encode once to unverified admitted JSON, then forward through the receiving
/// boundary once. No checked encode is performed before forwarding. Invalid
/// output invokes no handler; accepted output invokes it once. Handler Results
/// remain nested, and callback exceptions remain operational failures.
pub fn send(
  output: OutputBoundary(a, response),
  value: a,
) -> Result(response, gargamelle_encoding.EncodingError) {
  let OutputBoundary(encoder, receiver) = output
  use json <- result.try(gargamelle_encoding.encode_json(encoder, value))
  forward_json(receiver, json) |> result.map_error(gargamelle_encoding.Contract)
}

/// Decoded loading and typed saving bound to one authoritative full contract.
/// Handler response types are independent; encoding and decoding need not be inverses.
pub opaque type PairedBoundary(a, loaded, saved) {
  PairedBoundary(Boundary(a, loaded), OutputBoundary(a, saved))
}

/// Register decoded ingress and typed egress against one full contract.
/// Construction executes no encoder, converter, requirement, or handler callbacks.
pub fn paired(
  shared_contract: gargamelle.Contract(a),
  encoder: gargamelle_encoding.Encoder(a),
  load_handler: fn(a, gargamelle.Json) -> loaded,
  save_handler: fn(gargamelle.VerifiedJson(a)) -> saved,
) -> PairedBoundary(a, loaded, saved) {
  let loader = new(shared_contract, load_handler)
  let receiver = json(contract(loader), save_handler)
  PairedBoundary(loader, output(encoder, receiver))
}

/// Inspect the exact full contract shared by both directions without callbacks.
pub fn paired_contract(
  pair: PairedBoundary(a, loaded, saved),
) -> gargamelle.Contract(a) {
  let PairedBoundary(loader, _) = pair
  contract(loader)
}

/// Return the structural definition shared by both directions without callbacks.
pub fn paired_definition(
  pair: PairedBoundary(a, loaded, saved),
) -> gargamelle.Definition(a) {
  gargamelle.contract_definition(paired_contract(pair))
}

/// Decode and check once before invoking the loading handler. Application Results
/// remain nested; rejection skips the handler and operational exceptions propagate.
pub fn load(
  pair: PairedBoundary(a, loaded, saved),
  json: gargamelle.Json,
) -> Result(loaded, gargamelle.ContractError) {
  let PairedBoundary(loader, _) = pair
  forward(loader, json)
}

/// Encode once and check the stored contract once before invoking the saving
/// handler. Semantic requirements inspect reconstructed output, not encoder input.
/// Check-free contracts do not decode. Application Results remain nested;
/// rejection skips the handler and operational exceptions propagate.
pub fn save(
  pair: PairedBoundary(a, loaded, saved),
  value: a,
) -> Result(saved, gargamelle_encoding.EncodingError) {
  let PairedBoundary(_, output) = pair
  send(output, value)
}
