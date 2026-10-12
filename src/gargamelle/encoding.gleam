//// Explicit typed JSON encoding, independently of structural definitions.
////
//// `encode_json` produces admitted JSON. `encode` additionally checks a stored
//// Contract, while `send` encodes through an authoritative JSON receiving boundary.
//// Encoding and decoding need not be inverses. Getters and projections are trusted
//// application functions: exceptions propagate as operational failures.

import gargamelle as s
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// A rejected primitive encoding value.
pub type ValueProblem {
  NonFiniteNumber
  UnsafeInteger
  NonScalarString
}

/// A rejected record field declaration. Construction has no containing JSON path.
pub type FieldProblem {
  DuplicateKey
  NonScalarKey
}

/// Encoding stops at its first failure. Runtime paths are JSON Pointers into
/// the would-be encoded JSON, empty at the root. Field declaration errors identify
/// the supplied key separately; their containing location is not yet known.
/// Contract failures retain their own structural and semantic diagnostics.
/// Callback exceptions and resource failures are not caught.
pub type EncodingError {
  InvalidValue(path: String, problem: ValueProblem)
  InvalidField(name: String, problem: FieldProblem)
  Admission(path: String, error: s.AdmissionError)
  Contract(s.ContractError)
}

@external(erlang, "gargamelle_encoding_runtime", "scalar")
@external(javascript, "./encoding_runtime.mjs", "scalar")
fn scalar(text: String) -> Bool

fn at_key(error: EncodingError, key: String) -> EncodingError {
  let prefix = "/" <> escape_pointer(key)
  case error {
    InvalidValue(path, problem) -> InvalidValue(prefix <> path, problem)
    Admission(path, cause) -> Admission(prefix <> path, cause)
    InvalidField(_, _) | Contract(_) -> error
  }
}

fn escape_pointer(key: String) -> String {
  key |> string.replace("~", "~0") |> string.replace("/", "~1")
}

/// An encoding plan under recursion environment `r`. Only completed encoders,
/// `Plan(a, Nil)`, can be executed. Construction references cannot escape as
/// runnable encoders; recursive builders execute once.
pub opaque type Plan(a, r) {
  Plan(fn(r, a) -> Result(json.Json, EncodingError))
}

/// A completed immutable encoding plan.
pub type Encoder(a) =
  Plan(a, Nil)

/// Opaque environment supplied to a self-recursive encoding plan.
pub opaque type Recursive(a) {
  Recursive(fn(a) -> Result(json.Json, EncodingError))
}

/// A record encoder under construction, with explicit field getters.
pub opaque type Record(a, r) {
  Record(List(#(String, fn(r, a) -> Result(Option(json.Json), EncodingError))))
}

/// An explicit encoder and its authoritative output Contract. Equal output types
/// do not establish schema agreement; checked encoding enforces the Contract.
pub opaque type Codec(a) {
  Codec(Encoder(a), s.Contract(a))
}

/// A typed producer path through an existing JSON receiving boundary. Its
/// receiving Contract is authoritative; no second definition is stored.
pub opaque type OutputBoundary(a, response) {
  OutputBoundary(Encoder(a), s.JsonBoundary(a, response))
}

/// Encode an already admitted Gargamelle Json value. This composes arbitrary
/// metadata with typed field encoders; it does not certify a Contract. The usual
/// serialization/admission path applies, preserving canonical JSON rather than
/// original source formatting or object declaration order.
pub fn json() -> Plan(s.Json, r) {
  Plan(fn(_, value) { Ok(s.to_gleam_json(value)) })
}

/// Encode a Gleam string. Admission rejects unpaired Unicode surrogates.
pub fn text() -> Plan(String, r) {
  Plan(fn(_, value) {
    case scalar(value) {
      True -> Ok(json.string(value))
      False -> Error(InvalidValue("", NonScalarString))
    }
  })
}

/// Encode Nil as JSON null.
pub fn null() -> Plan(Nil, r) {
  Plan(fn(_, _) { Ok(json.null()) })
}

/// Encode a Boolean.
pub fn boolean() -> Plan(Bool, r) {
  Plan(fn(_, value) { Ok(json.bool(value)) })
}

/// Encode a finite binary64 Float. Reject nonfinite values before serialization.
pub fn number() -> Plan(Float, r) {
  Plan(fn(_, value) {
    case value >=. -1.7976931348623157e308 && value <=. 1.7976931348623157e308 {
      True -> Ok(json.float(value))
      False -> Error(InvalidValue("", NonFiniteNumber))
    }
  })
}

/// Encode an Int in the common safe-integer range. Reject out-of-range values.
pub fn safe_integer() -> Plan(Int, r) {
  Plan(fn(_, value) {
    case value >= -9_007_199_254_740_991 && value <= 9_007_199_254_740_991 {
      True -> Ok(json.int(value))
      False -> Error(InvalidValue("", UnsafeInteger))
    }
  })
}

/// Adapt an encoder with a trusted getter or projection. The callback runs once.
pub fn contramap(encoder: Plan(a, r), get: fn(b) -> a) -> Plan(b, r) {
  let Plan(run) = encoder
  Plan(fn(environment, value) { run(environment, get(value)) })
}

/// Encode list elements in order, stopping at the first encoding failure.
pub fn array(encoder: Plan(a, r)) -> Plan(List(a), r) {
  let Plan(run) = encoder
  Plan(fn(environment, values) {
    use encoded <- result.try(encode_elements(values, run, environment, 0, []))
    Ok(json.preprocessed_array(encoded))
  })
}

fn encode_elements(values, run, environment, index, encoded) {
  case values {
    [] -> Ok(list.reverse(encoded))
    [value, ..rest] -> {
      use item <- result.try(
        run(environment, value)
        |> result.map_error(fn(error) { at_key(error, int.to_string(index)) }),
      )
      encode_elements(rest, run, environment, index + 1, [item, ..encoded])
    }
  }
}

/// Encode None as JSON null and Some through the child encoder.
pub fn nullable(encoder: Plan(a, r)) -> Plan(Option(a), r) {
  let Plan(run) = encoder
  Plan(fn(environment, value) {
    case value {
      None -> Ok(json.null())
      Some(value) -> run(environment, value)
    }
  })
}

/// Encode the selected Result branch. A projection can adapt an application sum type.
pub fn choice(first: Plan(a, r), second: Plan(b, r)) -> Plan(Result(a, b), r) {
  let Plan(run_first) = first
  let Plan(run_second) = second
  Plan(fn(environment, value) {
    case value {
      Ok(value) -> run_first(environment, value)
      Error(value) -> run_second(environment, value)
    }
  })
}

/// Begin a record encoder. Construction invokes no getters.
pub fn record() -> Record(a, r) {
  Record([])
}

/// Add a required field with a getter. Duplicate and non-scalar keys fail construction.
pub fn field(
  record: Record(a, r),
  name: String,
  encoder: Plan(b, r),
  get: fn(a) -> b,
) -> Result(Record(a, r), EncodingError) {
  let Plan(run) = encoder
  add_field(record, name, fn(environment, value) {
    result.map(run(environment, get(value)), Some)
  })
}

/// Add a field omitted when its getter returns None. Some uses the child encoder.
pub fn optional_field(
  record: Record(a, r),
  name: String,
  encoder: Plan(b, r),
  get: fn(a) -> Option(b),
) -> Result(Record(a, r), EncodingError) {
  let Plan(run) = encoder
  add_field(record, name, fn(environment, value) {
    case get(value) {
      None -> Ok(None)
      Some(value) -> result.map(run(environment, value), Some)
    }
  })
}

fn add_field(
  record: Record(a, r),
  name: String,
  run: fn(r, a) -> Result(Option(json.Json), EncodingError),
) -> Result(Record(a, r), EncodingError) {
  let Record(fields) = record
  case scalar(name), list.any(fields, fn(field) { field.0 == name }) {
    False, _ -> Error(InvalidField(name, NonScalarKey))
    True, True -> Error(InvalidField(name, DuplicateKey))
    True, False -> Ok(Record(list.append(fields, [#(name, run)])))
  }
}

/// Complete a record encoder. Getters execute in declaration order at encoding time.
pub fn finish(record: Record(a, r)) -> Plan(a, r) {
  let Record(fields) = record
  Plan(fn(environment, value) {
    use encoded <- result.try(
      list.try_map(fields, fn(field) {
        let #(name, run) = field
        run(environment, value)
        |> result.map_error(at_key(_, name))
        |> result.map(fn(value) { #(name, value) })
      }),
    )
    Ok(
      json.object(
        list.filter_map(encoded, fn(field) {
          case field {
            #(name, Some(value)) -> Ok(#(name, value))
            #(_, None) -> Error(Nil)
          }
        }),
      ),
    )
  })
}

/// Build a completed self-recursive encoder using an immutable body. The builder runs
/// once. Recursion must descend through the input; immediate self-calls can diverge.
pub fn recursive(
  build: fn(Plan(a, Recursive(a))) ->
    Result(Plan(a, Recursive(a)), EncodingError),
) -> Result(Encoder(a), EncodingError) {
  let self =
    Plan(fn(environment: Recursive(a), value) {
      let Recursive(run) = environment
      run(value)
    })
  use body <- result.try(build(self))
  let Plan(run) = body
  Ok(Plan(fn(_, value) { run_self(run, value) }))
}

fn run_self(
  run: fn(Recursive(a), a) -> Result(json.Json, EncodingError),
  value: a,
) -> Result(json.Json, EncodingError) {
  run(Recursive(fn(child) { run_self(run, child) }), value)
}

/// Encode to admitted JSON without checking a definition or Contract. Encoding
/// serializes an intermediate JSON tree and admits its text once.
/// The result contains no certificate and claims no schema conformance.
pub fn encode_json(
  encoder: Encoder(a),
  value: a,
) -> Result(s.Json, EncodingError) {
  let Plan(run) = encoder
  use json <- result.try(run(Nil, value))
  s.parse(json.to_string(json)) |> result.map_error(Admission("", _))
}

/// Pair an encoder with a Contract without running either. This is an explicit
/// pair, not encoder derivation or a claim that encoding and decoding are inverses.
pub fn codec(encoder: Encoder(a), contract: s.Contract(a)) -> Codec(a) {
  Codec(encoder, contract)
}

/// Inspect the exact Contract used by checked encoding, without callbacks.
pub fn codec_contract(codec: Codec(a)) -> s.Contract(a) {
  let Codec(_, contract) = codec
  contract
}

/// Encode once, then verify the stored Contract once. A check-free Contract
/// validates without decoding; semantic requirements cause one decoding pass.
/// Checks inspect that decoded output, which need not equal the original input.
pub fn encode(
  codec: Codec(a),
  value: a,
) -> Result(s.VerifiedJson(a), EncodingError) {
  let Codec(encoder, contract) = codec
  use json <- result.try(encode_json(encoder, value))
  s.verify(contract, json) |> result.map_error(Contract)
}

/// Pair an encoder with an existing receiving boundary. Construction executes no
/// callbacks. The receiver's Contract is the sole acceptance authority.
pub fn output_boundary(
  encoder: Encoder(a),
  receiver: s.JsonBoundary(a, response),
) -> OutputBoundary(a, response) {
  OutputBoundary(encoder, receiver)
}

/// Inspect the exact receiving Contract without exposing its private handler.
pub fn output_contract(output: OutputBoundary(a, response)) -> s.Contract(a) {
  let OutputBoundary(_, receiver) = output
  s.json_boundary_contract(receiver)
}

/// Encode once to unverified admitted JSON, then forward through the receiving
/// boundary once. No checked encode is performed before forwarding. Invalid
/// output invokes no handler; accepted output invokes it once. Handler Results
/// remain nested, and callback exceptions remain operational failures.
pub fn send(
  output: OutputBoundary(a, response),
  value: a,
) -> Result(response, EncodingError) {
  let OutputBoundary(encoder, receiver) = output
  use json <- result.try(encode_json(encoder, value))
  s.forward_json(receiver, json) |> result.map_error(Contract)
}

/// Use a completed encoder inside a plan with any recursion environment.
pub fn lift(encoder: Encoder(a)) -> Plan(a, r) {
  let Plan(run) = encoder
  Plan(fn(_, value) { run(Nil, value) })
}
