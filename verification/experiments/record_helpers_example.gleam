import gargamelle
import gargamelle/encoding as gargamelle_encoding
import gleam/io
import gleam/option.{type Option, None, Some}
import shared_record

pub type Person {
  Person(name: String, age: Int, nickname: Option(String), active: Bool)
}

fn constructor() {
  fn(name) {
    fn(age) {
      fn(nickname) { fn(active) { Person(name, age, nickname, active) } }
    }
  }
}

fn age_definition() {
  let assert Ok(age) =
    gargamelle.bounds(gargamelle.safe_integer(), Some(0), None)
  age
}

pub fn baseline() {
  let assert Ok(fields) =
    gargamelle.required(
      gargamelle.record(constructor()),
      "name",
      gargamelle.text(),
    )
  let assert Ok(fields) = gargamelle.required(fields, "age", age_definition())
  let assert Ok(fields) =
    gargamelle.optional(fields, "nickname", gargamelle.text())
  let assert Ok(fields) =
    gargamelle.defaulted(
      fields,
      "active",
      gargamelle.boolean(),
      gargamelle.json_bool(True),
    )
  let definition = gargamelle.finish(fields, gargamelle.Strict)
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "name",
      gargamelle_encoding.text(),
      fn(person: Person) { person.name },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "age",
      gargamelle_encoding.safe_integer(),
      fn(person) { person.age },
    )
  let assert Ok(fields) =
    gargamelle_encoding.optional_field(
      fields,
      "nickname",
      gargamelle_encoding.text(),
      fn(person) { person.nickname },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "active",
      gargamelle_encoding.boolean(),
      fn(person) { person.active },
    )
  #(definition, gargamelle_encoding.finish(fields))
}

pub fn shared() {
  shared_record.start(constructor())
  |> shared_record.required(
    "name",
    gargamelle.text(),
    gargamelle_encoding.text(),
    fn(person: Person) { person.name },
  )
  |> shared_record.required(
    "age",
    age_definition(),
    gargamelle_encoding.safe_integer(),
    fn(person) { person.age },
  )
  |> shared_record.optional(
    "nickname",
    gargamelle.text(),
    gargamelle_encoding.text(),
    fn(person) { person.nickname },
  )
  |> shared_record.defaulted(
    "active",
    gargamelle.boolean(),
    gargamelle_encoding.boolean(),
    fn(person) { person.active },
    gargamelle.json_bool(True),
  )
  |> shared_record.finish(gargamelle.Strict)
}

pub fn main() {
  let assert Ok(#(definition, encoder)) = shared()
  let assert Ok(json) = gargamelle.parse("{\"name\":\"Azrael\",\"age\":3}")
  let assert Ok(person) = gargamelle.decode(definition, json)
  let assert Ok(verified) =
    gargamelle_encoding.encode(
      gargamelle_encoding.codec(encoder, gargamelle.contract(definition)),
      person,
    )
  io.println(gargamelle.to_string(
    gargamelle.verified_json(verified),
    gargamelle.Compact,
  ))
}
