import gargamelle as s
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn admission_test() {
  s.parse("1e400") |> should.be_error
}

pub fn nullable_test() {
  let assert Ok(v) = s.parse("null")
  s.decode(s.nullable(s.nullable(s.text())), v) |> should.equal(Ok(None))
  let assert Ok(v) = s.parse("\"x\"")
  s.decode(s.nullable(s.nullable(s.text())), v)
  |> should.equal(Ok(Some(Some("x"))))
}

pub fn record_test() {
  let assert Ok(r) =
    s.record(fn(a) { fn(b) { #(a, b) } }) |> s.required("a", s.text())
  let assert Ok(r) = s.optional(r, "b", s.nullable(s.text()))
  let d = s.finish(r, s.Closed)
  let assert Ok(v) = s.parse("{\"a\":\"x\",\"b\":null}")
  s.decode(d, v) |> should.equal(Ok(#("x", Some(None))))
  let assert Ok(v) = s.parse("{\"a\":\"x\",\"b\":false}")
  s.decode(d, v) |> should.be_error
}

pub fn overlap_test() {
  let assert Ok(d) = s.one_of([s.text(), s.text()])
  let assert Ok(v) = s.parse("\"x\"")
  s.decode(d, v) |> should.be_error
}

pub fn hostile_test() {
  let assert Ok(r) = s.record(fn(x) { x }) |> s.required("__proto__", s.text())
  let d = s.finish(r, s.Closed)
  let assert Ok(v) = s.parse("{\"__proto__\":\"x\"}")
  s.decode(d, v) |> should.equal(Ok("x"))
  s.schema_string(d)
  |> should.equal(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"additionalProperties\":false,\"properties\":{\"__proto__\":{\"type\":\"string\"}},\"required\":[\"__proto__\"],\"type\":\"object\"}",
  )
}

pub fn defaults_do_not_call_callbacks_test() {
  let child =
    s.map(s.text(), fn(_) {
      panic as "must not run while constructing or emitting"
    })
  let assert Ok(v) = s.parse("\"default\"")
  let assert Ok(r) = s.record(fn(x) { x }) |> s.defaulted("a", child, v)
  let d = s.finish(r, s.Closed)
  let assert Ok(input) = s.parse("{}")
  s.validate(d, input) |> should.equal(Ok(Nil))
  s.schema_string(d) |> should.not_equal("")
}

pub fn callbacks_inspecting_values_test() {
  let assert Ok(r) =
    s.record(fn(x) {
      case x {
        "expected" -> "passed"
        _ -> panic as "wrong value"
      }
    })
    |> s.required("x", s.text())
  let d = s.finish(r, s.Closed)
  s.schema_string(d) |> should.not_equal("")
  let assert Ok(v) = s.parse("{\"x\":\"expected\"}")
  s.decode(d, v) |> should.equal(Ok("passed"))
}

pub fn constructor_failures_test() {
  s.string_enum([]) |> should.be_error
  s.string_enum(["a", "a"]) |> should.be_error
  s.any_of([]) |> should.be_error
  s.one_of([]) |> should.be_error
  s.pattern(s.text(), "[") |> should.be_error
  s.bounds(s.text(), Some(-1), None) |> should.be_error
  s.bounds(s.safe_integer(), Some(4), Some(2)) |> should.be_error
  let unsafe_integer = 9_007_199_254_740_991 + 1
  s.integer_constant(unsafe_integer) |> should.be_error
  s.bounds(s.text(), None, Some(unsafe_integer)) |> should.be_error
  let assert Ok(r) =
    s.record(fn(a) { fn(b) { #(a, b) } }) |> s.required("x", s.text())
  s.required(r, "x", s.text()) |> should.be_error
  let assert Ok(v) = s.parse("false")
  s.record(fn(x) { x }) |> s.defaulted("x", s.text(), v) |> should.be_error
}

pub fn unicode_and_intersections_test() {
  let assert Ok(d) = s.bounds(s.text(), Some(1), Some(1))
  let assert Ok(v) = s.parse("\"😀\"")
  s.decode(d, v) |> should.equal(Ok("😀"))
  let assert Ok(v) = s.parse("\"é\"")
  s.decode(d, v) |> should.be_error
  let assert Ok(d) = s.pattern(s.text(), "a")
  let assert Ok(d) = s.pattern(d, "b")
  let assert Ok(d) = s.pattern(d, "a")
  let assert Ok(v) = s.parse("\"ab\"")
  s.decode(d, v) |> should.equal(Ok("ab"))
  s.decode(d, v) |> should.equal(Ok("ab"))
  let assert Ok(v) = s.parse("\"a\"")
  s.decode(d, v) |> should.be_error
}

pub fn tagged_diagnostics_test() {
  let assert Ok(r) = s.record(fn(x) { x }) |> s.required("a/b~", s.text())
  let assert Ok(d) = s.tagged("kind", [s.variant("x", r, s.Closed)])
  let assert Ok(v) = s.parse("{}")
  s.decode(d, v)
  |> should.equal(
    Error([s.DataError("missing_required", "", Some("kind"), [], [])]),
  )
  let assert Ok(v) = s.parse("{\"kind\":4}")
  s.decode(d, v)
  |> should.equal(
    Error([s.DataError("discriminator_type", "/kind", None, [], [])]),
  )
  let assert Ok(v) = s.parse("{\"kind\":\"y\"}")
  s.decode(d, v)
  |> should.equal(
    Error([s.DataError("unknown_discriminator", "/kind", None, [], [])]),
  )
  let assert Ok(v) = s.parse("{\"kind\":\"x\",\"a/b~\":false}")
  s.decode(d, v)
  |> should.equal(Error([s.DataError("string_type", "/a~1b~0", None, [], [])]))
  let assert Ok(v) = s.parse("{\"kind\":\"x\",\"a/b~\":\"payload\"}")
  s.decode(d, v) |> should.equal(Ok("payload"))
  s.tagged("kind", [s.variant("x", r, s.Closed), s.variant("x", r, s.Closed)])
  |> should.be_error
  let assert Ok(r) = s.record(fn(x) { x }) |> s.required("kind", s.text())
  s.tagged("kind", [s.variant("x", r, s.Closed)]) |> should.be_error
}

pub fn nullable_error_path_test() {
  let assert Ok(r) =
    s.record(fn(x) { x }) |> s.required("x", s.nullable(s.text()))
  let assert Ok(v) = s.parse("{\"x\":false}")
  s.decode(s.finish(r, s.Closed), v)
  |> should.equal(Error([s.DataError("string_type", "/x", None, [], [])]))
}

pub fn all_constants_test() {
  let assert Ok(v) = s.parse("true")
  s.decode(s.boolean_constant(True), v) |> should.equal(Ok(True))
  s.decode(s.string_constant("true"), v) |> should.be_error
  let assert Ok(d) = s.integer_constant(1)
  let assert Ok(v) = s.parse("1.0")
  s.decode(d, v) |> should.equal(Ok(1))
  let assert Ok(v) = s.parse("null")
  s.decode(s.null_constant(), v) |> should.equal(Ok(Nil))
}

pub fn default_presence_test() {
  let assert Ok(default) = s.parse("\"fallback\"")
  let assert Ok(r) =
    s.record(fn(x) { x }) |> s.defaulted("x", s.text(), default)
  let d = s.finish(r, s.Closed)
  let assert Ok(v) = s.parse("{}")
  s.decode(d, v) |> should.equal(Ok("fallback"))
  let assert Ok(v) = s.parse("{\"x\":null}")
  s.decode(d, v) |> should.be_error
}
