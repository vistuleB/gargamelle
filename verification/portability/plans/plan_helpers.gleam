// Exported helper signatures quantify over the environment; callers do not
// spell out self/pair environments or supply recursion functions.
import gleam/option.{type Option, Some}
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

pub fn provider(child, leaf, branch, index) {
  use leaf_fields <- result.try(p.required(p.record(leaf), "value", p.text()))
  use children <- result.try(p.array_limits(p.array(child), 0, 2))
  use branch_fields <- result.try(p.required(
    p.record(branch),
    "children",
    p.nullable(children),
  ))
  use index_fields <- result.try(p.required(
    p.record(index),
    "entries",
    p.dictionary(child),
  ))
  p.tagged("kind", [
    p.variant("leaf", leaf_fields, p.Closed),
    p.variant("branch", branch_fields, p.Closed),
    p.variant("index", index_fields, p.Closed),
  ])
  |> result.map(p.describe(_, "Provider JSON"))
}

// Independent output types on all auxiliary plans; these converters must never
// execute. This helper also exercises references in descending constraints.
pub fn constrained_children(child: p.Plan(a, recursion)) {
  let text_probe =
    p.map(p.text(), fn(_) -> Int { panic as "membership converter" })
  use base <- result.try(p.contains(p.array(child), text_probe, 1, Some(2)))
  use yes <- result.try(p.array_limits(p.array(p.text()), 1, 2))
  use no <- result.try(p.array_limits(p.array(child), 2, 3))
  Ok(p.if_then_else(
    p.exclude(
      base,
      p.map(p.array(p.boolean()), fn(_) -> Bool {
        panic as "exclusion converter"
      }),
    ),
    p.map(p.array(p.text()), fn(_) -> Nil { panic as "condition converter" }),
    p.map(yes, fn(_) -> String { panic as "consequence converter" }),
    p.map(no, fn(_) -> #(Bool, Int) { panic as "alternative converter" }),
  ))
}

pub fn keyed_children(child: p.Plan(a, recursion)) {
  p.property_names(
    p.dictionary(child),
    p.map(p.exclude(p.text(), p.string_constant("bad/~")), fn(_) {
      panic as "key converter"
    }),
  )
}
