// Authored fixtures for an independent external oracle. Not a public schema importer.
import gargamelle as s
import gleam/list
import gleam/option.{None, Some}

pub fn names() -> List(String) {
  [
    "string",
    "boolean",
    "null",
    "integer",
    "bounded_integer",
    "bounded_string",
    "pattern_string",
    "patterns",
    "enum",
    "nullable_enum",
    "nullable_null",
    "nullable_nullable",
    "nullable_overlap",
    "overlap",
    "any_order",
    "closed_record",
    "open_record",
    "optional",
    "defaulted",
    "hostile",
    "integer_keys",
    "empty_record",
    "array",
    "dictionary",
    "tagged",
  ]
}

pub fn definition(name: String) -> s.Definition(String) {
  case name {
    "string" -> s.string()
    "boolean" ->
      s.map(s.boolean(), fn(b) {
        case b {
          True -> "true"
          False -> "false"
        }
      })
    "null" -> s.map(s.null(), fn(_) { "null" })
    "integer" -> s.map(s.safe_integer(), int_text)
    "bounded_integer" -> {
      let assert Ok(d) = s.bounds(s.safe_integer(), Some(-2), Some(3))
      s.map(d, int_text)
    }
    "bounded_string" -> {
      let assert Ok(d) = s.bounds(s.string(), Some(1), Some(3))
      d
    }
    "pattern_string" -> {
      let assert Ok(d) = s.pattern(s.string(), "^a.$")
      d
    }
    "patterns" -> {
      let assert Ok(d) = s.pattern(s.string(), "a")
      let assert Ok(d) = s.pattern(d, "b")
      let assert Ok(d) = s.pattern(d, "a")
      d
    }
    "enum" -> {
      let assert Ok(d) = s.string_enum(["a", "b"])
      d
    }
    "nullable_enum" -> {
      let assert Ok(d) = s.string_enum(["a", "b"])
      s.map(s.nullable(d), show_option)
    }
    "nullable_null" -> s.map(s.nullable(s.null()), fn(_) { "None" })
    "nullable_nullable" ->
      s.map(s.nullable(s.nullable(s.string())), fn(o) {
        case o {
          None -> "None"
          Some(x) -> "Some(" <> show_option(x) <> ")"
        }
      })
    "nullable_overlap" -> {
      let n = s.map(s.null(), fn(_) { "null" })
      let assert Ok(d) = s.one_of([n, n])
      s.map(s.nullable(d), show_option)
    }
    "overlap" -> {
      let assert Ok(d) = s.one_of([s.string(), s.string()])
      d
    }
    "any_order" -> {
      let assert Ok(d) =
        s.any_of([
          s.map(s.string(), fn(_) { "first" }),
          s.map(s.string(), fn(_) { "second" }),
        ])
      d
    }
    "closed_record" | "open_record" -> {
      let assert Ok(r) =
        s.record(fn(a) { fn(b) { a <> ":" <> show_option(b) } })
        |> s.required("a", s.string())
      let assert Ok(r) = s.optional(r, "b", s.string())
      s.finish(r, case name {
        "open_record" -> s.Open
        _ -> s.Strict
      })
    }
    "optional" -> {
      let assert Ok(r) = s.record(show_option) |> s.optional("a", s.string())
      s.finish(r, s.Strict)
    }
    "defaulted" -> {
      let assert Ok(v) = s.parse("\"fallback\"")
      let assert Ok(r) =
        s.record(fn(x) { x }) |> s.defaulted("a", s.string(), v)
      s.finish(r, s.Strict)
    }
    "hostile" -> {
      let assert Ok(r) =
        s.record(fn(x) { x }) |> s.required("__proto__", s.string())
      s.finish(r, s.Strict)
    }
    "integer_keys" -> {
      let assert Ok(r) =
        s.record(fn(x) { fn(y) { x <> y } }) |> s.required("10", s.string())
      let assert Ok(r) = s.required(r, "2", s.string())
      s.finish(r, s.Strict)
    }
    "empty_record" -> s.finish(s.record("empty"), s.Strict)
    "array" -> {
      let assert Ok(d) = s.bounds(s.array(s.string()), Some(1), Some(3))
      s.map(d, fn(xs) { list.fold(xs, "", fn(a, b) { a <> "[" <> b <> "]" }) })
    }
    "dictionary" -> {
      let assert Ok(d) = s.bounds(s.dictionary(s.string()), Some(1), Some(3))
      s.map(d, fn(xs) {
        list.fold(xs, "", fn(a, b) { a <> b.0 <> "=" <> b.1 <> ";" })
      })
    }
    "tagged" -> {
      let assert Ok(a) =
        s.record(fn(x) { "a:" <> x }) |> s.required("value", s.string())
      let b = s.record("b")
      let assert Ok(d) =
        s.tagged("kind", [
          s.variant("a", a, s.Strict),
          s.variant("b", b, s.Strict),
        ])
      d
    }
    _ -> panic as "Unknown authored fixture"
  }
}

fn show_option(o) {
  case o {
    None -> "None"
    Some(x) -> "Some(" <> x <> ")"
  }
}

@external(erlang, "gargamelle_runtime", "int_text")
@external(javascript, "./runtime.mjs", "int_text")
fn int_text(i: Int) -> String

pub fn fixture_schema(name: String) -> String {
  s.schema_string(definition(name), s.Compact)
}

pub fn fixture_decode(
  name: String,
  text: String,
) -> Result(Result(String, List(s.DataError)), s.AdmissionError) {
  case s.parse(text) {
    Error(e) -> Error(e)
    Ok(v) -> Ok(s.decode(definition(name), v))
  }
}
