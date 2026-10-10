import gleam/io
import gleam/json
import gleam/list
import immutable_plan as p

@external(erlang, "plan_support", "measure")
@external(javascript, "./plan_support.mjs", "measure")
fn measure(run: fn() -> Nil) -> #(Int, Int)

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
  json.to_string(json.array(list.append(sharing, decoding), fn(json) { json }))
  |> io.println
}
