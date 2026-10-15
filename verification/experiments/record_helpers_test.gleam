import gargamelle
import gargamelle/encoding as gargamelle_encoding
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import record_helpers_example as example
import shared_record

pub fn identical_schema_and_input_results_test() {
  let #(baseline, _) = example.baseline()
  let assert Ok(#(shared, _)) = example.shared()
  for_each([baseline, shared], fn(definition) {
    gargamelle.schema_string(definition, gargamelle.Compact)
    |> should.equal(gargamelle.schema_string(baseline, gargamelle.Compact))
    for_each(
      [
        "{\"name\":\"Azrael\",\"age\":3}",
        "{\"name\":\"Azrael\",\"age\":3,\"nickname\":\"A\",\"active\":false}",
        "{\"age\":3}", "{\"name\":false,\"age\":3}",
        "{\"name\":\"Azrael\",\"age\":-1}",
        "{\"name\":\"Azrael\",\"age\":3,\"nickname\":null}",
        "{\"name\":\"Azrael\",\"age\":3,\"active\":\"yes\"}",
        "{\"name\":\"Azrael\",\"age\":3,\"extra\":true}", "[]",
      ],
      fn(source) {
        let assert Ok(json) = gargamelle.parse(source)
        gargamelle.validate(definition, json)
        |> should.equal(gargamelle.validate(baseline, json))
        gargamelle.decode(definition, json)
        |> should.equal(gargamelle.decode(baseline, json))
      },
    )
  })
  let assert Ok(json) = gargamelle.parse("{\"name\":\"Azrael\",\"age\":3}")
  gargamelle.decode(shared, json)
  |> should.equal(Ok(example.Person("Azrael", 3, None, True)))
}

pub fn identical_encoding_and_checked_errors_test() {
  let #(definition, baseline) = example.baseline()
  let assert Ok(#(_, shared)) = example.shared()
  for_each(
    [
      example.Person("Azrael", 3, None, True),
      example.Person("Brainy", 4, Some("B"), False),
      example.Person("Azrael", -1, None, True),
      example.Person("Azrael", 9_007_199_254_740_991 + 1, None, True),
    ],
    fn(person) {
      // Json is opaque; canonical strings compare admitted outputs.
      let original = gargamelle_encoding.encode_json(baseline, person)
      let generated = gargamelle_encoding.encode_json(shared, person)
      case original, generated {
        Ok(left), Ok(right) ->
          gargamelle.to_string(left, gargamelle.Compact)
          |> should.equal(gargamelle.to_string(right, gargamelle.Compact))
        Error(left), Error(right) -> left |> should.equal(right)
        _, _ -> panic as "encoding acceptance differs"
      }
      let contract = gargamelle.contract(definition)
      let original =
        gargamelle_encoding.encode(
          gargamelle_encoding.codec(baseline, contract),
          person,
        )
      let generated =
        gargamelle_encoding.encode(
          gargamelle_encoding.codec(shared, contract),
          person,
        )
      case original, generated {
        Ok(left), Ok(right) ->
          gargamelle.to_string(
            gargamelle.verified_json(left),
            gargamelle.Compact,
          )
          |> should.equal(gargamelle.to_string(
            gargamelle.verified_json(right),
            gargamelle.Compact,
          ))
        Error(left), Error(right) -> left |> should.equal(right)
        _, _ -> panic as "checked encoding acceptance differs"
      }
    },
  )
}

pub fn duplicate_errors_preserved_test() {
  let constructor = fn(first) { fn(second) { #(first, second) } }
  let assert Ok(original) =
    gargamelle.required(gargamelle.record(constructor), "x", gargamelle.string())
  let assert Error(expected) =
    gargamelle.required(original, "x", gargamelle.string())
  let assert Error(shared_record.Definition(actual)) =
    shared_record.start(constructor)
    |> shared_record.required(
      "x",
      gargamelle.string(),
      gargamelle_encoding.string(),
      fn(value: #(String, String)) { value.0 },
    )
    |> shared_record.required(
      "x",
      gargamelle.string(),
      gargamelle_encoding.string(),
      fn(value: #(String, String)) { value.1 },
    )
  actual |> should.equal(expected)
}

pub fn invalid_defaults_preserved_test() {
  let assert Ok(default) = gargamelle.json_string("invalid")
  let assert Error(expected) =
    gargamelle.defaulted(
      gargamelle.record(fn(value) { value }),
      "active",
      gargamelle.boolean(),
      default,
    )
  let assert Error(shared_record.Definition(actual)) =
    shared_record.start(fn(value) { value })
    |> shared_record.defaulted(
      "active",
      gargamelle.boolean(),
      gargamelle_encoding.boolean(),
      fn(value) { value },
      default,
    )
  actual |> should.equal(expected)
}

pub fn construction_keeps_first_error_test() {
  let assert Ok(default) = gargamelle.json_string("invalid")
  let constructor = fn(active) { fn(name) { #(active, name) } }
  let assert Error(expected) =
    gargamelle.defaulted(
      gargamelle.record(constructor),
      "active",
      gargamelle.boolean(),
      default,
    )
  let assert Error(shared_record.Definition(actual)) =
    shared_record.start(constructor)
    |> shared_record.defaulted(
      "active",
      gargamelle.boolean(),
      gargamelle_encoding.boolean(),
      fn(value: #(Bool, String)) { value.0 },
      default,
    )
    |> shared_record.required(
      "active",
      gargamelle.string(),
      gargamelle_encoding.string(),
      fn(value) { value.1 },
    )
    |> shared_record.finish(gargamelle.Strict)
  actual |> should.equal(expected)
}

pub fn construction_runs_no_value_callbacks_test() {
  let definition =
    gargamelle.map(gargamelle.boolean(), fn(_) {
      panic as "converter called during construction"
    })
  let assert Ok(#(definition, _)) =
    shared_record.start(fn(_: Bool) -> Bool {
      panic as "constructor called during construction"
    })
    |> shared_record.defaulted(
      "active",
      definition,
      gargamelle_encoding.boolean(),
      fn(_: Bool) -> Bool { panic as "getter called during construction" },
      gargamelle.json_bool(True),
    )
    |> shared_record.finish(gargamelle.Strict)
  let assert Ok(json) = gargamelle.parse("{}")
  gargamelle.validate(definition, json) |> should.equal(Ok(Nil))
  gargamelle.schema_string(definition, gargamelle.Compact)
  |> should.not_equal("")
}

pub fn mismatch_still_checked_test() {
  let assert Ok(#(definition, encoder)) =
    shared_record.start(fn(value) { value })
    |> shared_record.required(
      "name",
      gargamelle.string_constant("Azrael"),
      gargamelle_encoding.string(),
      fn(value) { value },
    )
    |> shared_record.finish(gargamelle.Strict)
  let assert Ok(_) = gargamelle_encoding.encode_json(encoder, "Brainy")
  let assert Error(gargamelle_encoding.Contract(gargamelle.Structural(errors))) =
    gargamelle_encoding.encode(
      gargamelle_encoding.codec(encoder, gargamelle.contract(definition)),
      "Brainy",
    )
  errors |> should.not_equal([])
}

fn for_each(values, callback) {
  list.each(values, callback)
}
