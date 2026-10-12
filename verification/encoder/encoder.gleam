//// Isolated encoder experiment; not part of the shipped Gargamelle API.

import gargamelle as s
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type EncodingError {
  EncodingError(String)
  Admission(s.AdmissionError)
  Contract(s.ContractError)
}

pub opaque type Plan(a, r) {
  Plan(fn(r, a) -> Result(json.Json, EncodingError))
}

pub type Encoder(a) =
  Plan(a, Nil)

pub opaque type Recursive(a) {
  Recursive(fn(a) -> Result(json.Json, EncodingError))
}

pub opaque type Record(a, r) {
  Record(List(#(String, fn(r, a) -> Result(Option(json.Json), EncodingError))))
}

pub opaque type Codec(a) {
  Codec(Encoder(a), s.Definition(a))
}

pub fn text() -> Plan(String, r) {
  Plan(fn(_, value) { Ok(json.string(value)) })
}

pub fn boolean() -> Plan(Bool, r) {
  Plan(fn(_, value) { Ok(json.bool(value)) })
}

pub fn number() -> Plan(Float, r) {
  Plan(fn(_, value) {
    case value >=. -1.7976931348623157e308 && value <=. 1.7976931348623157e308 {
      True -> Ok(json.float(value))
      False -> Error(EncodingError("number must be finite"))
    }
  })
}

pub fn safe_integer() -> Plan(Int, r) {
  Plan(fn(_, value) {
    case value >= -9_007_199_254_740_991 && value <= 9_007_199_254_740_991 {
      True -> Ok(json.int(value))
      False -> Error(EncodingError("integer outside the safe-integer range"))
    }
  })
}

pub fn contramap(encoder: Plan(a, r), get: fn(b) -> a) -> Plan(b, r) {
  let Plan(run) = encoder
  Plan(fn(environment, value) { run(environment, get(value)) })
}

pub fn array(encoder: Plan(a, r)) -> Plan(List(a), r) {
  let Plan(run) = encoder
  Plan(fn(environment, values) {
    use encoded <- result.try(list.try_map(values, run(environment, _)))
    Ok(json.preprocessed_array(encoded))
  })
}

pub fn nullable(encoder: Plan(a, r)) -> Plan(Option(a), r) {
  let Plan(run) = encoder
  Plan(fn(environment, value) {
    case value {
      None -> Ok(json.null())
      Some(value) -> run(environment, value)
    }
  })
}

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

pub fn record() -> Record(a, r) {
  Record([])
}

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
  use _ <- result.try(
    s.parse(json.to_string(json.string(name)))
    |> result.map_error(Admission),
  )
  case list.any(fields, fn(field) { field.0 == name }) {
    True -> Error(EncodingError("duplicate record key: " <> name))
    False -> Ok(Record(list.append(fields, [#(name, run)])))
  }
}

pub fn finish(record: Record(a, r)) -> Plan(a, r) {
  let Record(fields) = record
  Plan(fn(environment, value) {
    use encoded <- result.try(
      list.try_map(fields, fn(field) {
        let #(name, run) = field
        result.map(run(environment, value), fn(value) { #(name, value) })
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

pub fn encode_json(
  encoder: Encoder(a),
  value: a,
) -> Result(s.Json, EncodingError) {
  let Plan(run) = encoder
  use json <- result.try(run(Nil, value))
  s.parse(json.to_string(json)) |> result.map_error(Admission)
}

pub fn codec(encoder: Encoder(a), definition: s.Definition(a)) -> Codec(a) {
  Codec(encoder, definition)
}

/// Validate the encoded JSON without conversion or decoded-value allocation.
pub fn encode(
  codec: Codec(a),
  value: a,
) -> Result(s.VerifiedJson(a), EncodingError) {
  let Codec(encoder, definition) = codec
  use json <- result.try(encode_json(encoder, value))
  s.verify(s.contract(definition), json) |> result.map_error(Contract)
}
