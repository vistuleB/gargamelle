//// Optional HTML documentation for Gargamelle's emitted schema vocabulary.
//// This is a presentation module, not a general JSON Schema validator.

import gargamelle
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

// A JSON tree lets documentation preserve constants and defaults, including null.
type Value {
  Null
  Text(String)
  Number(Float)
  Boolean(Bool)
  Array(List(Value))
  Object(List(#(String, Value)))
}

fn decoder() {
  decode.one_of(decode.map(decode.string, Text), [
    decode.map(decode.float, Number),
    decode.map(decode.bool, Boolean),
    decode.map(decode.optional(decode.failure(Nil, "null")), fn(_) { Null }),
    decode.map(decode.list(decode.recursive(decoder)), Array),
    decode.map(decode.dict(decode.string, decode.recursive(decoder)), fn(d) {
      Object(
        dict.to_list(d) |> list.sort(fn(a, b) { string.compare(a.0, b.0) }),
      )
    }),
  ])
}

fn entries(v: Value) {
  case v {
    Object(xs) -> xs
    _ -> []
  }
}

fn values(v: Value) {
  case v {
    Array(xs) -> xs
    _ -> []
  }
}

fn get(v: Value, key: String) {
  entries(v) |> list.key_find(key) |> result.unwrap(Null)
}

fn has(v: Value, key: String) {
  list.any(entries(v), fn(pair) { pair.0 == key })
}

fn text(v: Value) {
  case v {
    Text(s) -> s
    _ -> ""
  }
}

fn encode(v: Value) -> json.Json {
  case v {
    Null -> json.null()
    Text(s) -> json.string(s)
    Number(n) -> json.float(n)
    Boolean(b) -> json.bool(b)
    Array(xs) -> json.array(xs, encode)
    Object(xs) -> json.object(list.map(xs, fn(p) { #(p.0, encode(p.1)) }))
  }
}

fn show(v: Value) {
  json.to_string(encode(v))
}

/// Escape both text and double-quoted HTML attribute values.
pub fn escape_html(s: String) -> String {
  s
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}

fn shape(s: Value) -> String {
  case s {
    Boolean(True) -> "any value"
    Boolean(False) -> "no value"
    _ ->
      case has(s, "$ref"), has(s, "const"), has(s, "enum") {
        True, _, _ -> text(get(s, "$ref"))
        _, True, _ -> show(get(s, "const"))
        _, _, True ->
          values(get(s, "enum")) |> list.map(show) |> string.join(" | ")
        _, _, _ ->
          case text(get(s, "type")) {
            "" -> "value"
            other -> other
          }
      }
  }
}

fn constraints(s: Value) {
  let bounds = [
    #("minLength", "maxLength", "characters"),
    #("minItems", "maxItems", "items"),
    #("minContains", "maxContains", "matching items"),
    #("minProperties", "maxProperties", "keys"),
    #("minimum", "maximum", "value"),
  ]
  let ranges =
    list.filter_map(bounds, fn(b) {
      case has(s, b.0) || has(s, b.1) {
        False -> Error(Nil)
        True ->
          Ok(
            b.2
            <> ": "
            <> case has(s, b.0) {
              True -> show(get(s, b.0))
              False -> "−∞"
            }
            <> " … "
            <> case has(s, b.1) {
              True -> show(get(s, b.1))
              False -> "∞"
            },
          )
      }
    })
  let extras = [
    case text(get(s, "type")), get(s, "items") {
      "array", Boolean(False) ->
        "exactly "
        <> show(get(s, "minItems"))
        <> " positions; extra positions rejected"
      _, _ -> ""
    },
    case has(s, "exclusiveMinimum") {
      True -> "value > " <> show(get(s, "exclusiveMinimum"))
      False -> ""
    },
    case has(s, "exclusiveMaximum") {
      True -> "value < " <> show(get(s, "exclusiveMaximum"))
      False -> ""
    },
    case has(s, "pattern") {
      True -> "pattern: " <> text(get(s, "pattern"))
      False -> ""
    },
    case get(s, "uniqueItems") {
      Boolean(True) -> "unique items"
      _ -> ""
    },
    case has(s, "default") {
      True -> "default: " <> show(get(s, "default"))
      False -> ""
    },
    case text(get(s, "type")) {
      "object" ->
        case get(s, "additionalProperties") {
          Boolean(False) -> "unknown fields rejected"
          Object(_) -> "values validated by map contract"
          _ ->
            "unknown fields permitted by schema; codec projects undeclared fields away"
        }
      _ -> ""
    },
  ]
  list.append(ranges, extras)
  |> list.filter(fn(s) { s != "" })
  |> string.join("; ")
}

// IDs use UTF-8 bytes as decimal components, so hostile names cannot break
// attributes or collide through replacement of punctuation.
fn token(s: String) {
  s |> bit_array.from_string |> bytes([]) |> list.reverse |> string.join("-")
}

fn bytes(bits: BitArray, acc: List(String)) -> List(String) {
  case bits {
    <<b, rest:bits>> -> bytes(rest, [int.to_string(b), ..acc])
    _ -> acc
  }
}

fn mapped(name, aliases) {
  list.key_find(aliases, name) |> result.unwrap(name)
}

fn anchor(id, name, aliases) {
  id <> "-definition-" <> token(mapped(name, aliases))
}

fn paragraph(class, value) {
  case value {
    "" -> ""
    _ -> "<p class=\"" <> class <> "\">" <> escape_html(value) <> "</p>"
  }
}

fn branch_label(s: Value, index: Int, union: String) {
  let constants =
    entries(get(s, "properties"))
    |> list.filter_map(fn(p) {
      case has(p.1, "const") {
        True -> Ok(p.0 <> " = " <> show(get(p.1, "const")))
        False -> Error(Nil)
      }
    })
  let label = case constants {
    [] -> int.to_string(index + 1)
    _ -> string.join(constants, ", ")
  }
  case union {
    "allOf" -> "requirement "
    _ -> "alternative "
  }
  <> label
}

fn node(
  s: Value,
  label: String,
  depth: Int,
  status: String,
  id: String,
  aliases: List(#(String, String)),
) -> String {
  let fields =
    entries(get(s, "properties"))
    |> list.map(fn(p) {
      node(
        p.1,
        p.0,
        depth + 1,
        case list.contains(values(get(s, "required")), Text(p.0)) {
          True -> "required"
          False -> "optional"
        },
        id,
        aliases,
      )
    })
  let items = case get(s, "items") {
    Object(_) as item -> [node(item, "each item", depth + 1, "", id, aliases)]
    _ -> []
  }
  let positions =
    values(get(s, "prefixItems"))
    |> list.index_map(fn(child, i) {
      node(
        child,
        "position " <> int.to_string(i),
        depth + 1,
        "required",
        id,
        aliases,
      )
    })
  let exclusions = case get(s, "not") {
    Object(_) as child -> [
      node(child, "must not match", depth + 1, "", id, aliases),
    ]
    _ -> []
  }
  let conditionals =
    [
      #("if", "if condition"),
      #("then", "then requirement"),
      #("else", "else requirement"),
    ]
    |> list.filter_map(fn(pair) {
      case has(s, pair.0) {
        True -> Ok(node(get(s, pair.0), pair.1, depth + 1, "", id, aliases))
        False -> Error(Nil)
      }
    })
  let membership = case get(s, "contains") {
    Object(_) as child -> [
      node(child, "matching items", depth + 1, "", id, aliases),
    ]
    _ -> []
  }
  let key_names = case get(s, "propertyNames") {
    Object(_) as key -> [
      node(key, "each property name", depth + 1, "", id, aliases),
    ]
    _ -> []
  }
  let maps = case get(s, "additionalProperties") {
    Object(_) as item -> [
      node(item, "each map value", depth + 1, "", id, aliases),
    ]
    _ -> []
  }
  let unions =
    ["oneOf", "anyOf", "allOf"]
    |> list.flat_map(fn(key) {
      values(get(s, key))
      |> list.index_map(fn(branch, i) {
        node(branch, branch_label(branch, i, key), depth + 1, "", id, aliases)
      })
    })
  let children =
    list.flatten([
      fields,
      items,
      positions,
      membership,
      key_names,
      maps,
      unions,
      conditionals,
      exclusions,
    ])
    |> string.join("")
  let kind = case has(s, "oneOf"), has(s, "anyOf"), has(s, "allOf") {
    True, _, _ -> "exactly one alternative"
    _, True, _ -> "any matching alternative"
    _, _, True -> "all requirements"
    _, _, _ -> shape(s)
  }
  let heading =
    "<code>"
    <> escape_html(label)
    <> "</code> <span class=\"type\">"
    <> escape_html(kind)
    <> "</span>"
    <> case status {
      "" -> ""
      _ -> " <span class=\"badge\">" <> status <> "</span>"
    }
  let reference = text(get(s, "$ref"))
  let link = case string.starts_with(reference, "#/$defs/") {
    True -> {
      let name =
        string.drop_start(reference, 8)
        |> string.replace("~1", "/")
        |> string.replace("~0", "~")
      "<a class=\"reference\" href=\"#"
      <> escape_html(anchor(id, name, aliases))
      <> "\">See shared structure ↗</a>"
    }
    False -> ""
  }
  let body =
    paragraph("meaning", text(get(s, "description")))
    <> paragraph("constraint", constraints(s))
    <> link
  case children {
    "" ->
      "<div class=\"node leaf\"><div>"
      <> heading
      <> "</div>"
      <> body
      <> "</div>"
    _ ->
      "<details class=\"node\""
      <> case depth < 2 {
        True -> " open"
        False -> ""
      }
      <> "><summary>"
      <> heading
      <> "</summary><div class=\"node-body\">"
      <> body
      <> "<div class=\"children\">"
      <> children
      <> "</div></div></details>"
  }
}

/// Render a definition with every shared definition visible in its own section.
/// Supply a unique article ID when embedding multiple contracts on one page.
pub fn render(definition: gargamelle.Definition(a), id: String) -> String {
  let assert Ok(html) = render_emitted(gargamelle.emit_text(definition), id, [])
  html
}

/// Render JSON emitted by Gargamelle. Aliases are optional *presentation-only*
/// pairs (omitted definition, displayed definition); they must name existing
/// definitions and point directly to a displayed definition. They do not change
/// the schema or decoding. Explain any such compression in the surrounding page.
pub fn render_emitted(
  source: String,
  id: String,
  aliases: List(#(String, String)),
) -> Result(String, String) {
  use schema <- result.try(
    json.parse(source, decoder())
    |> result.map_error(fn(_) { "Invalid schema JSON" }),
  )
  let defs = entries(get(schema, "$defs"))
  let names = list.map(defs, fn(p) { p.0 })
  let omitted = list.map(aliases, fn(p) { p.0 })
  use _ <- result.try(
    case
      list.all(aliases, fn(p) {
        list.contains(names, p.0)
        && list.contains(names, p.1)
        && !list.contains(omitted, p.1)
      })
    {
      True -> Ok(Nil)
      False ->
        Error(
          "Definition aliases must point directly to an existing displayed definition",
        )
    },
  )
  let title = case text(get(schema, "title")) {
    "" -> id
    other -> other
  }
  let root =
    Object(entries(schema) |> list.filter(fn(p) { p.0 != "description" }))
  let shared =
    defs
    |> list.filter(fn(p) { !list.contains(omitted, p.0) })
    |> list.map(fn(p) {
      "<section id=\""
      <> escape_html(anchor(id, p.0, aliases))
      <> "\" class=\"shared\">"
      <> node(p.1, p.0, 0, "", id, aliases)
      <> "</section>"
    })
    |> string.join("")
  Ok(
    "<article id=\""
    <> escape_html(id)
    <> "\"><h3>"
    <> escape_html(title)
    <> "</h3>"
    <> paragraph("lead", text(get(schema, "description")))
    <> "<div class=\"tree\">"
    <> node(root, "payload", 0, "", id, aliases)
    <> "</div>"
    <> case shared {
      "" -> ""
      _ -> "<h4>Shared definitions</h4>" <> shared
    }
    <> "</article>",
  )
}

/// A rejected example's zero-based position and ordinary validation errors.
pub type ExampleError {
  ExampleError(index: Int, errors: List(gargamelle.DataError))
}

/// Validate admitted input examples before displaying them. This never invokes
/// decoding callbacks or modifies schema acceptance. Examples are JSON inputs,
/// not decoded values; checking again at render time prevents silent drift.
pub fn render_examples(
  definition: gargamelle.Definition(a),
  id: String,
  examples: List(gargamelle.Value),
) -> Result(String, List(ExampleError)) {
  let errors =
    examples
    |> list.index_map(fn(value, index) {
      case gargamelle.validate(definition, value) {
        Ok(_) -> []
        Error(errors) -> [ExampleError(index, errors)]
      }
    })
    |> list.flatten
  case errors {
    [] -> {
      let html = render(definition, id)
      let section = case examples {
        [] -> ""
        _ ->
          "<section class=\"examples\"><h4>Checked examples</h4>"
          <> {
            examples
            |> list.map(fn(value) {
              "<pre><code>"
              <> escape_html(gargamelle.value_text(value))
              <> "</code></pre>"
            })
            |> string.join("")
          }
          <> "</section>"
      }
      Ok(string.replace(html, "</article>", section <> "</article>"))
    }
    _ -> Error(errors)
  }
}
