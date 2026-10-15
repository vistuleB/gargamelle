import gargamelle as s
import gargamelle/diagnostics
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn complete_structural_json_retains_branches_matches_and_keys_test() {
  let error =
    s.Structural([
      s.ValidationError(
        "union_no_match",
        "/a~1b",
        None,
        [
          #(2, [
            s.ValidationError("missing_required", "/a~1b", Some("x/y"), [], []),
          ]),
        ],
        [0, 1],
      ),
    ])
  let assert Ok(json) = diagnostics.to_json(error)
  let assert Ok(expected) =
    s.parse(
      "{\"kind\":\"structural\",\"errors\":[{\"category\":\"union_no_match\",\"path\":\"/a~1b\",\"missing_key\":null,\"matches\":[0,1],\"branches\":[{\"index\":2,\"errors\":[{\"category\":\"missing_required\",\"path\":\"/a~1b\",\"missing_key\":\"x/y\",\"matches\":[],\"branches\":[]}]}]}]}",
    )
  s.to_string(json, s.Compact) |> should.equal(s.to_string(expected, s.Compact))
  diagnostics.summary(error, 4)
  |> should.equal(
    "\"/a~1b\" [\"union_no_match\"]: No union alternative accepted\nAlternative 2\n\"/a~1b\" [\"missing_required\"]: Required field is missing: \"x/y\"",
  )
}

pub fn semantic_json_preserves_messages_and_summary_escapes_controls_test() {
  let error =
    s.Semantic([
      s.RequirementFailure(3, "Score\ncheck", [
        s.Violation("/score", "Unexpected\nscore\t😀"),
      ]),
    ])
  let assert Ok(json) = diagnostics.to_json(error)
  let assert Ok(expected) =
    s.parse(
      "{\"kind\":\"semantic\",\"requirements\":[{\"index\":3,\"description\":\"Score\\ncheck\",\"violations\":[{\"path\":\"/score\",\"message\":\"Unexpected\\nscore\\t😀\"}]}]}",
    )
  s.to_string(json, s.Compact) |> should.equal(s.to_string(expected, s.Compact))
  diagnostics.summary(error, 4)
  |> string.split("\n")
  |> list.length
  |> should.equal(2)
  diagnostics.summary(error, 1)
  |> should.equal(
    "Requirement 3: \"Score\\ncheck\"\nFurther diagnostic details omitted",
  )
}

pub type Tree {
  Leaf(String)
  Branch(List(Tree))
}

pub fn recursive_union_failure_is_bounded_without_losing_structured_details_test() {
  let assert Ok(definition) =
    s.recursive("diagnostic-tree", fn(self) {
      s.any_of([s.map(s.string(), Leaf), s.map(s.array(self), Branch)])
    })
  let input =
    list.fold(list.repeat(Nil, 30), s.json_bool(False), fn(child, _) {
      s.json_array([child])
    })
  let assert Error(errors) = s.decode(definition, input)
  let error = s.Structural(errors)
  let summary = diagnostics.summary(error, 100)
  summary
  |> string.contains("Further diagnostic details omitted")
  |> should.be_true
  string.split(summary, "\n")
  |> list.length
  |> fn(n) { n <= 101 }()
  |> should.be_true
  let assert Ok(json) = diagnostics.to_json(error)
  s.to_string(json, s.Compact)
  |> string.contains(string.repeat("/0", 30))
  |> should.be_true
  // Formatting never mutates the diagnostic tree or repeats decoding.
  s.decode(definition, input) |> should.equal(Error(errors))
}

pub fn wide_failures_and_limits_bound_output_test() {
  let errors =
    list.map(list.repeat(Nil, 1000), fn(_) {
      s.ValidationError("integer_type", "/score", None, [], [])
    })
  let error = s.Structural(errors)
  diagnostics.summary(error, 3)
  |> string.split("\n")
  |> list.length
  |> should.equal(4)
  diagnostics.summary(error, 1000)
  |> string.split("\n")
  |> list.length
  |> should.equal(101)
  diagnostics.summary(error, 0)
  |> should.equal("Further diagnostic details omitted")
  diagnostics.summary(error, -1)
  |> should.equal("Further diagnostic details omitted")
  diagnostics.summary(s.Structural([]), 0) |> should.equal("")
}

pub fn labels_are_bounded_and_unknown_categories_remain_identifiable_test() {
  let error =
    s.Structural([
      s.ValidationError(
        "future_category",
        "",
        Some(string.repeat("😀", 500)),
        [],
        [],
      ),
    ])
  let summary = diagnostics.summary(error, 1)
  string.length(summary) |> should.equal(160)
  summary |> string.contains("future_category") |> should.be_true
  summary |> string.contains("Constraint failed") |> should.be_true
  let assert Ok(json) = diagnostics.to_json(error)
  s.to_string(json, s.Compact)
  |> string.contains(string.repeat("😀", 500))
  |> should.be_true
}

pub fn structural_reports_do_not_include_submitted_values_test() {
  let assert Ok(json) = s.parse("\"submitted-secret\"")
  let assert Error(errors) =
    s.decode(s.string_constant("expected-secret"), json)
  let error = s.Structural(errors)
  let assert Ok(report) = diagnostics.to_json(error)
  s.to_string(report, s.Compact) |> string.contains("secret") |> should.be_false
  diagnostics.summary(error, 5) |> string.contains("secret") |> should.be_false
}
