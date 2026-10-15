import gargamelle as s
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import integration_inputs
import schema_fixtures

fn names() {
  list.append(schema_fixtures.names(), [
    "number",
    "numeric_bounds",
    "tuple",
    "contains",
    "keys",
    "condition",
    "exclude",
    "unique",
    "named",
    "recursive",
    "mutual",
  ])
}

fn definition(name: String) -> s.Definition(String) {
  case name {
    "number" -> s.map(s.number(), fn(_) { "number" })
    "numeric_bounds" -> {
      let assert Ok(d) =
        s.number_bounds(
          s.number(),
          Some(s.Exclusive(-0.0)),
          Some(s.Inclusive(2.5)),
        )
      s.map(d, fn(_) { "bounded-number" })
    }
    "tuple" ->
      s.tuple(fn(label) {
        fn(enabled) {
          label
          <> case enabled {
            True -> ":true"
            False -> ":false"
          }
        }
      })
      |> s.element(s.string())
      |> s.element(s.boolean())
      |> s.finish_tuple
    "contains" -> {
      let assert Ok(d) =
        s.contains(s.array(s.string()), s.string_constant("x"), 1, Some(2))
      s.map(d, string.join(_, ","))
    }
    "keys" -> {
      let assert Ok(keys) = s.pattern(s.string(), "^[a-z]+$")
      let assert Ok(d) = s.property_names(s.dictionary(s.number()), keys)
      s.map(d, fn(entries) {
        list.map(entries, fn(entry) { entry.0 }) |> string.join(",")
      })
    }
    "condition" -> {
      let assert Ok(yes) = s.bounds(s.array(s.string()), Some(1), Some(2))
      let assert Ok(no) = s.bounds(s.array(s.boolean()), Some(1), Some(1))
      let assert Ok(base) =
        s.any_of([
          s.map(s.array(s.string()), string.join(_, ",")),
          s.map(s.array(s.boolean()), fn(_) { "booleans" }),
        ])
      s.if_then_else(base, s.array(s.string()), yes, no)
    }
    "exclude" -> s.exclude(s.string(), s.string_constant("blocked"))
    "unique" -> {
      let assert Ok(d) = s.unique_items(s.array(s.nullable(s.number())))
      s.map(d, fn(_) { "unique" })
    }
    "named" -> {
      let assert Ok(a) = s.named("common", s.string())
      let assert Ok(b) = s.named("common", s.string())
      let assert Ok(d) = s.any_of([a, b])
      d
    }
    "recursive" -> {
      let assert Ok(d) =
        s.recursive("tree", fn(self) {
          s.one_of([
            s.string(),
            s.map(s.array(self), fn(xs) { "[" <> string.join(xs, ",") <> "]" }),
          ])
        })
      d
    }
    "mutual" -> {
      let assert Ok(#(first, _)) =
        s.recursive_pair("first", "second", fn(a, b) {
          let assert Ok(second) =
            s.any_of([s.string(), s.map(s.array(a), string.join(_, ","))])
          Ok(#(s.map(s.array(b), string.join(_, ";")), second))
        })
      first
    }
    _ -> schema_fixtures.definition(name)
  }
}

fn error_json(error: s.DataError) -> json.Json {
  json.object([
    #("category", json.string(error.category)),
    #("path", json.string(error.path)),
    #("missing_key", case error.missing_key {
      Some(key) -> json.string(key)
      None -> json.null()
    }),
    #(
      "branches",
      json.array(error.branches, fn(branch) {
        json.object([
          #("index", json.int(branch.0)),
          #("errors", json.array(branch.1, error_json)),
        ])
      }),
    ),
    #("matches", json.array(error.matches, json.int)),
  ])
}

fn entry(definition, input) {
  let assert Ok(value) = s.parse(input)
  let decoded = s.decode(definition, value)
  let errors = case decoded {
    Ok(_) -> []
    Error(errors) -> errors
  }
  json.object([
    #("input", json.string(input)),
    #("accepted", json.bool(result.is_ok(s.validate(definition, value)))),
    #("decoded", case decoded {
      Ok(output) -> json.string(output)
      Error(_) -> json.null()
    }),
    #("errors", json.array(errors, error_json)),
  ])
}

pub fn main() {
  names()
  |> list.map(fn(name) {
    let d = definition(name)
    json.object([
      #("name", json.string(name)),
      #("schema", json.string(s.schema_string(d, s.Compact))),
      #("cases", json.array(integration_inputs.values(), entry(d, _))),
    ])
  })
  |> json.array(fn(value) { value })
  |> json.to_string
  |> io.println
}
