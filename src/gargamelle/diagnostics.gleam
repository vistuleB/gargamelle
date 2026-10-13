//// Presentation of structural and semantic contract failures.
//// Summaries are bounded; JSON output retains the complete error tree.
//// Neither operation validates data, runs callbacks, or changes acceptance.

import gargamelle
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Serialize the complete diagnostic tree as admitted JSON. Branch and requirement
/// indices are zero-based. No submitted JSON values are included. Application
/// requirement descriptions and violation messages are included verbatim; those
/// strings may themselves contain sensitive information supplied by the application.
/// Non-scalar diagnostic strings return an admission error.
pub fn to_json(
  error: gargamelle.ContractError,
) -> Result(gargamelle.Json, gargamelle.AdmissionError) {
  let value = case error {
    gargamelle.Structural(errors) ->
      json.object([
        #("kind", json.string("structural")),
        #("errors", json.array(errors, structural_json)),
      ])
    gargamelle.Semantic(failures) ->
      json.object([
        #("kind", json.string("semantic")),
        #(
          "requirements",
          json.array(failures, fn(failure) {
            json.object([
              #("index", json.int(failure.index)),
              #("description", json.string(failure.description)),
              #(
                "violations",
                json.array(failure.violations, fn(violation) {
                  json.object([
                    #("path", json.string(violation.path)),
                    #("message", json.string(violation.message)),
                  ])
                }),
              ),
            ])
          }),
        ),
      ])
  }
  gargamelle.parse(json.to_string(value))
}

fn structural_json(error: gargamelle.DataError) -> json.Json {
  json.object([
    #("category", json.string(error.category)),
    #("path", json.string(error.path)),
    #("missing_key", case error.missing_key {
      None -> json.null()
      Some(key) -> json.string(key)
    }),
    #("matches", json.array(error.matches, json.int)),
    #(
      "branches",
      json.array(error.branches, fn(branch) {
        json.object([
          #("index", json.int(branch.0)),
          #("errors", json.array(branch.1, structural_json)),
        ])
      }),
    ),
  ])
}

type Pending {
  Errors(List(gargamelle.DataError), Int)
  Branches(List(#(Int, List(gargamelle.DataError))), Int)
  Requirements(List(gargamelle.RequirementFailure))
  Violations(List(gargamelle.Violation))
}

/// Render at most `max_details` detail lines, clamped to 0..100, followed by a
/// truncation marker when information is omitted. Branch expansion stops at depth
/// eight. Each line is limited to 160 graphemes; quoted paths/messages escape line
/// breaks and control characters. The full input error remains unchanged.
/// These limits bound presentation, not validation or the size of its error tree.
/// Categories and wording may evolve before 1.0; match structured categories
/// rather than parsing summary text. Application-authored messages are not redacted.
pub fn summary(error: gargamelle.ContractError, max_details: Int) -> String {
  let pending = case error {
    gargamelle.Structural(errors) -> [Errors(errors, 0)]
    gargamelle.Semantic(failures) -> [Requirements(failures)]
  }
  render(pending, int.clamp(max_details, 0, 100), [], False)
  |> string.join("\n")
}

fn render(pending, remaining, lines, omitted) {
  case pending {
    [] ->
      list.reverse(case omitted {
        True -> ["Further diagnostic details omitted", ..lines]
        False -> lines
      })
    [Errors([], _), ..rest]
    | [Branches([], _), ..rest]
    | [Requirements([]), ..rest]
    | [Violations([]), ..rest] -> render(rest, remaining, lines, omitted)
    _ if remaining <= 0 ->
      list.reverse(["Further diagnostic details omitted", ..lines])
    [Errors([error, ..errors], depth), ..rest] -> {
      let message = case error.category {
        "missing_required" -> "Required field is missing"
        "dependent_required" -> "Required dependent field is missing"
        "string_type" -> "Expected a string"
        "integer_type" -> "Expected a safe integer"
        "number_type" -> "Expected a finite number"
        "boolean_type" -> "Expected a boolean"
        "null_type" -> "Expected null"
        "array_type" | "tuple_type" -> "Expected an array"
        "object_type" -> "Expected an object"
        "union_no_match" -> "No union alternative accepted"
        "one_of_ambiguous" -> "Multiple union alternatives accepted"
        "extra_key" -> "Unexpected field"
        "duplicate_items" -> "Array items are not unique"
        "excluded" -> "Value matches an excluded definition"
        _ -> "Constraint failed"
      }
      let missing = case error.missing_key {
        None -> ""
        Some(key) -> ": " <> quote(key)
      }
      let line =
        quote(error.path)
        <> " ["
        <> quote(error.category)
        <> "]: "
        <> message
        <> missing
      let has_branches = error.branches != []
      let next = case has_branches && depth < 8 {
        True -> [
          Branches(error.branches, depth + 1),
          Errors(errors, depth),
          ..rest
        ]
        False -> [Errors(errors, depth), ..rest]
      }
      render(
        next,
        remaining - 1,
        [bounded(line), ..lines],
        omitted || has_branches && depth >= 8,
      )
    }
    [Branches([#(index, errors), ..branches], depth), ..rest] ->
      render(
        [Errors(errors, depth), Branches(branches, depth), ..rest],
        remaining - 1,
        ["Alternative " <> int.to_string(index), ..lines],
        omitted,
      )
    [Requirements([failure, ..failures]), ..rest] ->
      render(
        [Violations(failure.violations), Requirements(failures), ..rest],
        remaining - 1,
        [
          bounded(
            "Requirement "
            <> int.to_string(failure.index)
            <> ": "
            <> quote(failure.description),
          ),
          ..lines
        ],
        omitted,
      )
    [Violations([violation, ..violations]), ..rest] ->
      render(
        [Violations(violations), ..rest],
        remaining - 1,
        [
          bounded(quote(violation.path) <> ": " <> quote(violation.message)),
          ..lines
        ],
        omitted,
      )
  }
}

fn bounded(text: String) -> String {
  case string.length(text) > 160 {
    True -> string.slice(text, 0, 159) <> "…"
    False -> text
  }
}

fn quote(text: String) -> String {
  // Limit application-controlled fields before escaping or joining them.
  json.to_string(json.string(bounded(text)))
}
