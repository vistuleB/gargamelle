import gargamelle as s
import gleam/io
import gleam/json
import gleam/list

@external(erlang, "plan_support", "measure")
@external(javascript, "./plan_support.mjs", "measure")
fn measure(run: fn() -> Nil) -> #(Int, Int)

@external(erlang, "plan_support", "transfer_size")
@external(javascript, "./plan_support.mjs", "transfer_size")
fn transfer_size(value: a, consume: fn(a) -> Nil) -> #(Int, Int, Int)

fn nested(depth, text) {
  case depth {
    0 -> text
    _ -> nested(depth - 1, "[" <> text <> "]")
  }
}

pub fn main() {
  let assert Ok(tree) =
    s.recursive("tree", fn(self) {
      s.one_of([s.text(), s.map(s.array(self), fn(_) { "tree" })])
    })
  let decoding =
    list.map([8, 32, 64], fn(depth) {
      let assert Ok(input) = s.parse(nested(depth, "\"leaf\""))
      let cost =
        measure(fn() {
          let assert Ok("tree") = s.decode(tree, input)
          Nil
        })
      json.object([
        #("kind", json.string("production-decode")),
        #("depth", json.int(depth)),
        #("microseconds", json.int(cost.0)),
        #("erlang_reductions", json.int(cost.1)),
      ])
    })
  let sizes =
    transfer_size(tree, fn(received) {
      let assert Ok(input) = s.parse("[\"leaf\"]")
      let assert Ok("tree") = s.decode(received, input)
      Nil
    })
  let transfer =
    json.object([
      #("kind", json.string("production-transfer")),
      #("sender_heap_words", json.int(sizes.0)),
      #("flat_heap_words", json.int(sizes.1)),
      #("receiver_heap_words", json.int(sizes.2)),
    ])
  list.append(decoding, [transfer])
  |> json.array(fn(value) { value })
  |> json.to_string
  |> io.println
}
