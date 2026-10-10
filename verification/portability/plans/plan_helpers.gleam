// Exported helper signatures quantify over the environment; callers do not
// spell out self/pair environments or supply recursion functions.
import gleam/option.{type Option}
import gleam/result
import immutable_plan as p

pub fn named_children(
  child: p.Plan(a, environment),
) -> Result(p.Plan(#(String, Option(Bool), List(a)), environment), String) {
  use fields <- result.try(p.required(
    p.record(fn(name) {
      fn(enabled) { fn(children) { #(name, enabled, children) } }
    }),
    "name",
    p.text(),
  ))
  use fields <- result.try(p.optional(fields, "enabled", p.boolean()))
  use fields <- result.try(p.required(fields, "children", p.array(child)))
  Ok(p.finish_record(fields, p.Closed))
}

// Inferred signature: the compiler generalizes the same environment parameter.
pub fn packet(child) {
  p.tuple(fn(label) { fn(enabled) { fn(value) { #(label, enabled, value) } } })
  |> p.item(p.text())
  |> p.item(p.boolean())
  |> p.item(child)
  |> p.finish_tuple
}

pub fn text_or(
  child: p.Plan(String, environment),
) -> Result(p.Plan(String, environment), String) {
  p.any_of([p.text(), child])
}
