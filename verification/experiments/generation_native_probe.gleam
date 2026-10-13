import gargamelle
import generation_inputs
import gleam/io
import gleam/json
import gleam/list

pub fn main() {
  let definition = gargamelle.array(gargamelle.nullable(gargamelle.safe_integer()))
  generation_inputs.values()
  |> list.map(fn(source) {
    let assert Ok(value) = gargamelle.parse(source)
    gargamelle.validate(definition, value) == Ok(Nil)
  })
  |> json.array(json.bool)
  |> json.to_string
  |> io.println
}
