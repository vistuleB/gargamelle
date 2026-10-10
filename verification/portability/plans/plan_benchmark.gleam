import gleam/io
import gleam/json
import gleam/list
import gleam/string
import immutable_plan as p
import plan_helpers

@external(erlang, "plan_support", "measure")
@external(javascript, "./plan_support.mjs", "measure")
fn measure(run: fn() -> Nil) -> #(Int, Int)

@external(erlang, "plan_support", "transfer_size")
@external(javascript, "./plan_support.mjs", "transfer_size")
fn transfer_size(value: a, consume: fn(a) -> Nil) -> #(Int, Int, Int)

fn layers(plan, depth) {
  case depth {
    0 -> plan
    _ -> {
      let assert Ok(next) = p.any_of([plan, plan])
      layers(next, depth - 1)
    }
  }
}

fn nested(depth) {
  case depth {
    0 -> p.Text("leaf")
    _ -> p.Array([nested(depth - 1)])
  }
}

fn row(kind, depth, cost: #(Int, Int)) {
  json.object([
    #("kind", json.string(kind)),
    #("depth", json.int(depth)),
    #("microseconds", json.int(cost.0)),
    #("erlang_reductions", json.int(cost.1)),
  ])
}

pub fn main() {
  let sharing =
    list.map([8, 12, 16], fn(depth) {
      row(
        "shared-construction",
        depth,
        measure(fn() {
          let assert Ok(_) =
            p.recursive("shared", fn(self) {
              let assert Ok(base) =
                p.any_of([p.text(), p.map(p.array(self), fn(_) { "tree" })])
              Ok(layers(base, depth))
            })
          Nil
        }),
      )
    })
  let assert Ok(tree) =
    p.recursive("tree", fn(self) {
      p.any_of([p.text(), p.map(p.array(self), fn(_) { "tree" })])
    })
  let decoding =
    list.map([8, 32, 64], fn(depth) {
      let input = nested(depth)
      row(
        "deep-decode",
        depth,
        measure(fn() {
          let assert Ok(_) = p.decode(tree, input)
          Nil
        }),
      )
    })
  let transfers =
    list.map([2, 4, 6], fn(depth) {
      let assert Ok(definition) =
        p.recursive("shared", fn(self) {
          let assert Ok(base) =
            p.any_of([p.text(), p.map(p.array(self), fn(_) { "tree" })])
          Ok(layers(base, depth))
        })
      let sizes =
        transfer_size(definition, fn(received) {
          let assert Ok("leaf") = p.decode(received, p.Text("leaf"))
          Nil
        })
      json.object([
        #("kind", json.string("shared-transfer")),
        #("depth", json.int(depth)),
        #("sender_heap_words", json.int(sizes.0)),
        #("flat_heap_words", json.int(sizes.1)),
        #("receiver_heap_words", json.int(sizes.2)),
      ])
    })
  let receipt_sizes =
    list.map([8, 32, 64], fn(depth) {
      let assert Ok(sizes) = p.validation_size(tree, nested(depth))
      json.object([
        #("kind", json.string("validation-evidence")),
        #("depth", json.int(depth)),
        #("shared_heap_words", json.int(sizes.0)),
        #("flat_heap_words", json.int(sizes.1)),
      ])
    })
  let assert Ok(provider) =
    p.recursive("provider", fn(self) {
      plan_helpers.provider(self, fn(text) { text }, fn(_) { "branch" }, fn(_) {
        "index"
      })
    })
  let provider_sizes =
    transfer_size(provider, fn(received) {
      let assert Ok("leaf") =
        p.decode(
          received,
          p.Object([
            #("kind", p.Text("leaf")),
            #("value", p.Text("leaf")),
          ]),
        )
      Nil
    })
  let provider_row =
    json.object([
      #("kind", json.string("provider-transfer")),
      #("sender_heap_words", json.int(provider_sizes.0)),
      #("flat_heap_words", json.int(provider_sizes.1)),
      #("receiver_heap_words", json.int(provider_sizes.2)),
    ])
  let emissions =
    list.map([8, 12], fn(depth) {
      let assert Ok(definition) =
        p.recursive("shared", fn(self) {
          let assert Ok(base) =
            p.any_of([
              p.text(),
              p.map(p.array(self), fn(_) { "tree" }),
            ])
          Ok(layers(base, depth))
        })
      let text = p.emit(definition)
      json.object([
        #("kind", json.string("shared-emission")),
        #("depth", json.int(depth)),
        #("characters", json.int(string.length(text))),
      ])
    })
  json.to_string(
    json.array(
      list.flatten([
        sharing,
        decoding,
        receipt_sizes,
        transfers,
        [provider_row],
        emissions,
      ]),
      fn(json) { json },
    ),
  )
  |> io.println
}
