import gargamelle as s
import gleam/io
import gleam/json
import gleam/list
import regex_inputs

@external(erlang, "plan_support", "measure")
@external(javascript, "./plan_support.mjs", "measure")
fn measure(run: fn() -> Nil) -> #(Int, Int)

fn field(patterned, pattern) {
  case patterned {
    False -> s.string()
    True -> {
      let assert Ok(definition) = s.pattern(s.string(), pattern)
      definition
    }
  }
}

fn provider(patterned) {
  let assert Ok(record) =
    s.record(fn(_) { fn(_) { fn(_) { fn(_) { Nil } } } })
    |> s.required("id", field(patterned, "^[A-Za-z][A-Za-z0-9_-]*$"))
  let assert Ok(record) =
    s.required(record, "url", field(patterned, "^https://[^\\s]+$"))
  let assert Ok(record) =
    s.required(
      record,
      "time",
      field(patterned, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$"),
    )
  let assert Ok(record) =
    s.required(record, "title", field(patterned, "^[\\p{L}\\p{N} .'-]+$"))
  s.array(s.finish(record, s.Strict))
}

fn samples(run) {
  // One warmup; three measured operations. No timing threshold.
  run()
  list.map([1, 2, 3], fn(_) { json.int(measure(run).0) })
}

pub fn main() {
  let construction =
    samples(fn() {
      provider(True)
      Nil
    })
  let rows =
    list.map(regex_inputs.values(), fn(row) {
      let #(name, patterned, count, accepted, text) = row
      let definition = provider(patterned)
      let assert Ok(input) = s.parse(text)
      let decode_run = fn() {
        case s.decode(definition, input), accepted {
          Ok(values), True -> {
            let assert True = list.length(values) == count
          }
          Error(errors), False -> {
            let assert True = list.length(errors) == 1
          }
          _, _ -> panic as "unexpected decoded workload result"
        }
        Nil
      }
      let validate_run = fn() {
        case s.validate(definition, input), accepted {
          Ok(Nil), True -> Nil
          Error(errors), False -> {
            let assert True = list.length(errors) == 1
            Nil
          }
          _, _ -> panic as "unexpected validation workload result"
        }
      }
      json.object([
        #("name", json.string(name)),
        #("patterned", json.bool(patterned)),
        #("records", json.int(count)),
        #("accepted", json.bool(accepted)),
        #("decode_us", json.array(samples(decode_run), fn(x) { x })),
        #("validate_us", json.array(samples(validate_run), fn(x) { x })),
      ])
    })
  json.object([
    #("construct_four_patterns_us", json.array(construction, fn(x) { x })),
    #("workloads", json.array(rows, fn(x) { x })),
  ])
  |> json.to_string
  |> io.println
}
