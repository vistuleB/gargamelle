//// Typed JSON decoding and JSON Schema 2020-12 emission from one definition.
////
//// Parse JSON with `parse`, then call `validate` or `decode`. Validation never
//// invokes user converters; decoding invokes them only after structural success.
//// Converters are trusted application code: exceptions are operational failures.
//// JavaScript is the supported target; Node 24 is the verified runtime.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// Values can enter only through the JSON parser. Runtime helpers preserve own keys.
/// An admitted JSON value. Construct values through `parse`; arbitrary runtime
/// objects cannot enter the validation boundary.
pub opaque type Value {
  JNull
  JBool(Bool)
  JNumber(Float)
  JString(String)
  JArray(List(Value))
  JObject(List(#(String, Value)))
}

/// JSON syntax or nonfinite-number admission failure.
pub type AdmissionError {
  AdmissionError(String)
}

/// An invalid definition, constraint, default, or reference graph.
pub type ConstructionError {
  ConstructionError(String)
}

/// A structural validation failure. `path` is a JSON Pointer (empty at the root).
/// `branches` contains indexed union errors and `matches` identifies matching
/// branches. Categories and diagnostic wording may evolve before version 1.0.
pub type DataError {
  DataError(
    category: String,
    path: String,
    missing_key: Option(String),
    branches: List(#(Int, List(DataError))),
    matches: List(Int),
  )
}

/// Treatment of undeclared record keys. `Closed` rejects them; `Open` accepts
/// them but omits them from the constructed output.
pub type Policy {
  Closed
  Open
}

/// A finite numeric endpoint. Inclusive endpoints accept equality.
pub type NumberBound {
  Inclusive(Float)
  Exclusive(Float)
}

type Identity

type Context

type Node {
  IdentifiedNode(Identity, Node)
  ContextNode(Context, Node)
  BooleanNode
  NullNode
  StringNode(Option(Int), Option(Int), List(String))
  IntegerNode(Int, Int)
  NumberNode(Option(NumberBound), Option(NumberBound))
  ConstNode(Value, String)
  EnumNode(List(String))
  ArrayNode(Node, Option(Int), Option(Int))
  TupleNode(List(Node))
  ContainsNode(Node, List(Membership))
  ConditionalNode(Node, List(Condition))
  ExcludeNode(Node, List(Node))
  DictNode(Node, Option(Int), Option(Int))
  RecordNode(List(Field), Policy)
  PropertyNamesNode(Node, List(Node))
  NullableNode(Node)
  UnionNode(List(Node), Bool)
  TaggedNode(String, List(#(String, Node, Option(String))))
  NamedNode(String, Node)
  ReferenceNode(String, Cell(Node))
  UniqueNode(Node)
  AnnotatedNode(Node, String, String)
}

// Cells contain only library nodes or typed conversion functions, never values
// fabricated for definition-author callbacks. They are private to construction.
// Per-traversal identity tracking avoids rescanning shared/recursive nodes.
type Seen(a) {
  Seen(fn(a) -> Bool)
}

@external(erlang, "gargamelle_runtime", "identity_tracker")
@external(javascript, "./runtime.mjs", "identity_tracker")
fn new_seen(
  make: fn(fn(a) -> Bool) -> Seen(a),
  key: fn(a) -> Identity,
) -> Seen(a)

fn seen_before(seen: Seen(a), value: a) -> Bool {
  let Seen(visit) = seen
  visit(value)
}

type Cell(a) {
  Cell(fn() -> Result(a, ConstructionError), fn(a) -> Nil, fn() -> Nil)
}

@external(erlang, "gargamelle_runtime", "recursive_cell")
@external(javascript, "./runtime.mjs", "recursive_cell")
fn new_cell(
  make: fn(fn() -> Result(a, ConstructionError), fn(a) -> Nil, fn() -> Nil) ->
    Cell(a),
  missing: ConstructionError,
) -> Cell(a)

fn read_cell(cell: Cell(a)) -> Result(a, ConstructionError) {
  let Cell(read, _, _) = cell
  read()
}

fn bind_cell(cell: Cell(a), value: a) -> Nil {
  let Cell(_, bind, _) = cell
  bind(value)
}

fn reject_cell(cell: Cell(a)) -> Nil {
  let Cell(_, _, reject) = cell
  reject()
}

type Condition {
  Condition(Node, Node, Option(Node))
}

type Membership {
  Membership(Node, Int, Option(Int))
}

type Field {
  Field(String, Node, Presence)
}

type Presence {
  Required
  Optional
  Default(Value)
}

/// A structural acceptance contract paired with a typed conversion function.
pub opaque type Definition(a) {
  Definition(Node, fn(Value) -> a)
}

@external(erlang, "gargamelle_runtime", "fresh_identity")
@external(javascript, "./runtime.mjs", "fresh_identity")
fn fresh_identity() -> Identity

@external(erlang, "gargamelle_runtime", "with_construction")
@external(javascript, "./runtime.mjs", "with_construction")
fn with_construction(build: fn() -> a) -> #(a, Context)

@external(erlang, "gargamelle_runtime", "with_context")
@external(javascript, "./runtime.mjs", "with_context")
fn with_context(context: Context, run: fn() -> a) -> a

@external(erlang, "gargamelle_runtime", "with_walk")
@external(javascript, "./runtime.mjs", "with_walk")
fn with_walk(run: fn() -> a) -> a

fn identified(n: Node) -> Node {
  case n {
    IdentifiedNode(_, _) -> n
    _ -> IdentifiedNode(fresh_identity(), n)
  }
}

fn identity(n: Node) -> Identity {
  case n {
    IdentifiedNode(id, _) -> id
    ContextNode(_, child) -> identity(child)
    _ -> panic as "Library node has no identity"
  }
}

fn bare(n: Node) -> Node {
  case n {
    IdentifiedNode(_, child) | ContextNode(_, child) -> bare(child)
    _ -> n
  }
}

fn definition(n: Node, convert: fn(Value) -> a) -> Definition(a) {
  Definition(identified(n), convert)
}

fn contextual(context: Context, def: Definition(a)) -> Definition(a) {
  let Definition(n, convert) = def
  Definition(ContextNode(context, n), fn(v) {
    with_context(context, fn() { convert(v) })
  })
}

/// An unfinished record consuming a curried constructor one field at a time.
pub opaque type Record(a) {
  Record(List(Field), fn(Value) -> a)
}

/// An unfinished exact-length tuple consuming a curried constructor by position.
pub opaque type Tuple(a) {
  Tuple(List(Node), fn(Value) -> a)
}

/// A record branch for `tagged`, with its discriminator supplied automatically.
pub opaque type Variant(a) {
  Variant(String, List(Field), Policy, fn(Value) -> a, Option(String))
}

/// Admit JSON text without invoking a definition or converter. Duplicate object
/// keys use the parser’s last value; numeric values use IEEE-754 binary64.
pub fn parse(text: String) -> Result(Value, AdmissionError) {
  parse_runtime(text, fn() { JNull }, JBool, JNumber, JString, JArray, JObject)
}

@external(javascript, "./runtime.mjs", "parse")
fn parse_runtime(
  text: String,
  null: fn() -> Value,
  boolean: fn(Bool) -> Value,
  number: fn(Float) -> Value,
  string: fn(String) -> Value,
  array: fn(List(Value)) -> Value,
  object: fn(List(#(String, Value))) -> Value,
) -> Result(Value, AdmissionError)

/// Serialize an admitted value as canonical JSON text. Negative zero becomes `0`.
pub fn value_text(value: Value) -> String {
  canonical(json.to_string(json_value(value)))
}

fn json_value(v: Value) -> json.Json {
  case v {
    JNull -> json.null()
    JBool(b) -> json.bool(b)
    JNumber(n) -> json.float(n)
    JString(s) -> json.string(s)
    JArray(xs) -> json.array(xs, json_value)
    JObject(xs) -> json.object(list.map(xs, fn(p) { #(p.0, json_value(p.1)) }))
  }
}

@external(javascript, "./runtime.mjs", "canonical")
fn canonical(text: String) -> String

@external(javascript, "./runtime.mjs", "codepoints")
fn codepoints(text: String) -> Int

@external(javascript, "./runtime.mjs", "pattern_valid")
fn pattern_valid(text: String) -> Bool

@external(javascript, "./runtime.mjs", "pattern_matches")
fn pattern_matches(pattern: String, text: String) -> Bool

@external(javascript, "./runtime.mjs", "sorted")
fn sorted(values: List(String)) -> List(String)

@external(erlang, "gargamelle_runtime", "integer")
@external(javascript, "./runtime.mjs", "integer")
fn integer(value: Float) -> Bool

@external(erlang, "gargamelle_runtime", "finite")
@external(javascript, "./runtime.mjs", "finite")
fn finite(value: Float) -> Bool

@external(erlang, "gargamelle_runtime", "as_int")
@external(javascript, "./runtime.mjs", "as_int")
fn as_int(value: Float) -> Int

@external(erlang, "gargamelle_runtime", "as_float")
@external(javascript, "./runtime.mjs", "as_float")
fn as_float(value: Int) -> Float

/// Accept JSON booleans.
pub fn boolean() -> Definition(Bool) {
  definition(BooleanNode, fn(v) {
    case v {
      JBool(b) -> b
      _ -> panic as "validated boolean"
    }
  })
}

/// Accept JSON null and decode it to `Nil`.
pub fn null() -> Definition(Nil) {
  definition(NullNode, fn(_) { Nil })
}

/// Accept JSON strings.
pub fn text() -> Definition(String) {
  definition(StringNode(None, None, []), fn(v) {
    case v {
      JString(s) -> s
      _ -> panic as "validated string"
    }
  })
}

/// Accept integral numbers between -9007199254740991 and 9007199254740991.
pub fn safe_integer() -> Definition(Int) {
  definition(IntegerNode(-9_007_199_254_740_991, 9_007_199_254_740_991), fn(v) {
    case v {
      JNumber(n) -> as_int(n)
      _ -> panic as "validated integer"
    }
  })
}

/// Decode any admitted finite IEEE-754 number to Float, including integers.
/// JSON parsing may round or underflow; decoding preserves the parsed value.
pub fn number() -> Definition(Float) {
  definition(NumberNode(None, None), fn(v) {
    case v {
      JNumber(n) -> n
      _ -> panic as "validated number"
    }
  })
}

fn endpoint(bound: NumberBound) -> Float {
  case bound {
    Inclusive(x) | Exclusive(x) -> x
  }
}

fn stricter_bound(
  a: Option(NumberBound),
  b: Option(NumberBound),
  lower: Bool,
) -> Option(NumberBound) {
  case a, b {
    None, x | x, None -> x
    Some(x), Some(y) -> {
      let xv = endpoint(x)
      let yv = endpoint(y)
      case xv >=. yv && xv <=. yv {
        True ->
          Some(case x, y {
            Exclusive(_), _ | _, Exclusive(_) -> Exclusive(xv)
            _, _ -> Inclusive(xv)
          })
        False ->
          Some(case lower && xv >. yv || !lower && xv <. yv {
            True -> x
            False -> y
          })
      }
    }
  }
}

fn valid_number_bounds(
  lower: Option(NumberBound),
  upper: Option(NumberBound),
) -> Bool {
  let endpoints = list.filter_map([lower, upper], option.to_result(_, Nil))
  list.all(endpoints, fn(b) { finite(endpoint(b)) })
  && case lower, upper {
    Some(a), Some(b) -> {
      let lo = endpoint(a)
      let hi = endpoint(b)
      lo <. hi
      || lo >=. hi
      && lo <=. hi
      && case a, b {
        Inclusive(_), Inclusive(_) -> True
        _, _ -> False
      }
    }
    _, _ -> True
  }
}

/// Intersect a number definition's interval with finite inclusive/exclusive
/// bounds. Reject inverted intervals and exclusive equal endpoints.
pub fn number_bounds(
  def: Definition(Float),
  lower: Option(NumberBound),
  upper: Option(NumberBound),
) -> Result(Definition(Float), ConstructionError) {
  case valid_number_bounds(lower, upper) {
    False -> Error(ConstructionError("invalid number bounds"))
    True -> {
      let Definition(n, d) = def
      use next <- result.try(number_bound_node(n, lower, upper))
      Ok(definition(next, d))
    }
  }
}

fn number_bound_node(
  n: Node,
  lower: Option(NumberBound),
  upper: Option(NumberBound),
) -> Result(Node, ConstructionError) {
  case n {
    IdentifiedNode(_, child) ->
      result.map(number_bound_node(child, lower, upper), identified)
    ContextNode(context, child) ->
      result.map(number_bound_node(child, lower, upper), ContextNode(context, _))
    AnnotatedNode(child, k, v) ->
      result.map(number_bound_node(child, lower, upper), AnnotatedNode(_, k, v))
    NumberNode(lo, hi) -> {
      let lo = stricter_bound(lo, lower, True)
      let hi = stricter_bound(hi, upper, False)
      case valid_number_bounds(lo, hi) {
        True -> Ok(NumberNode(lo, hi))
        False -> Error(ConstructionError("empty number interval"))
      }
    }
    _ -> Error(ConstructionError("number bounds require a number definition"))
  }
}

fn number_ok(
  x: Float,
  lo: Option(NumberBound),
  hi: Option(NumberBound),
) -> Bool {
  let low = case lo {
    None -> True
    Some(Inclusive(b)) -> x >=. b
    Some(Exclusive(b)) -> x >. b
  }
  let high = case hi {
    None -> True
    Some(Inclusive(b)) -> x <=. b
    Some(Exclusive(b)) -> x <. b
  }
  low && high
}

/// Accept one of the supplied strings. Empty or duplicate alternatives fail construction.
pub fn string_enum(
  values: List(String),
) -> Result(Definition(String), ConstructionError) {
  case values == [] || list.length(list.unique(values)) != list.length(values) {
    True -> Error(ConstructionError("empty or duplicate enum"))
    False ->
      Ok(
        definition(EnumNode(values), fn(v) {
          case v {
            JString(s) -> s
            _ -> panic as "validated enum"
          }
        }),
      )
  }
}

/// Accept exactly this string.
pub fn string_constant(v: String) -> Definition(String) {
  definition(ConstNode(JString(v), "string"), fn(_) { v })
}

/// Accept exactly this boolean.
pub fn boolean_constant(v: Bool) -> Definition(Bool) {
  definition(ConstNode(JBool(v), "boolean"), fn(_) { v })
}

/// Accept exactly null.
pub fn null_constant() -> Definition(Nil) {
  definition(ConstNode(JNull, "null"), fn(_) { Nil })
}

/// Accept exactly this safe integer; reject constants outside the safe range.
pub fn integer_constant(v: Int) -> Result(Definition(Int), ConstructionError) {
  case
    v < -9_007_199_254_740_991
    || v > 9_007_199_254_740_991
    || !integer(as_float(v))
  {
    True -> Error(ConstructionError("unsafe integer"))
    False ->
      Ok(definition(ConstNode(JNumber(as_float(v)), "integer"), fn(_) { v }))
  }
}

/// Transform decoded output without changing schema acceptance. The callback
/// runs only during successful decoding and must return the declared output type.
pub fn map(def: Definition(a), f: fn(a) -> b) -> Definition(b) {
  let Definition(n, d) = def
  definition(n, fn(v) { f(d(v)) })
}

/// Accept null as `None`, or decode the child as `Some`. This does not make
/// a record field optional.
pub fn nullable(def: Definition(a)) -> Definition(Option(a)) {
  let Definition(n, d) = def
  definition(NullableNode(n), fn(v) {
    case v {
      JNull -> None
      _ -> Some(d(v))
    }
  })
}

/// Accept homogeneous arrays and decode every element in input order.
pub fn array(def: Definition(a)) -> Definition(List(a)) {
  let Definition(n, d) = def
  definition(ArrayNode(n, None, None), fn(v) {
    case v {
      JArray(xs) -> list.map(xs, d)
      _ -> panic as "validated array"
    }
  })
}

/// Start an exact-length positional array with a curried typed constructor.
pub fn tuple(constructor: a) -> Tuple(a) {
  Tuple([], fn(_) { constructor })
}

/// Append one required position, consuming one constructor argument.
pub fn element(t: Tuple(fn(a) -> b), child: Definition(a)) -> Tuple(b) {
  let Tuple(nodes, construct) = t
  let Definition(node, convert) = child
  let index = list.length(nodes)
  Tuple(list.append(nodes, [node]), fn(v) {
    let assert JArray(values) = v as "validated tuple"
    let assert Ok(value) = list.first(list.drop(values, index))
      as "validated tuple position"
    construct(v)(convert(value))
  })
}

/// Close a tuple. Short arrays and extra positions are rejected.
pub fn finish_tuple(t: Tuple(a)) -> Definition(a) {
  let Tuple(nodes, convert) = t
  definition(TupleNode(nodes), convert)
}

/// Require between minimum and maximum structurally matching array items.
/// Preserve the original decoder; matching-definition converters never run.
pub fn contains(
  def: Definition(a),
  matching: Definition(b),
  minimum: Int,
  maximum: Option(Int),
) -> Result(Definition(a), ConstructionError) {
  let Definition(node, convert) = def
  let Definition(match_node, _) = matching
  case bad_bounds(Some(minimum), maximum, True) {
    True -> Error(ConstructionError("invalid contains bounds"))
    False -> {
      use next <- result.try(contains_node(
        node,
        Membership(match_node, minimum, maximum),
      ))
      Ok(definition(next, convert))
    }
  }
}

fn array_node(node: Node) -> Bool {
  case node {
    IdentifiedNode(_, child) | ContextNode(_, child) -> array_node(child)
    ArrayNode(_, _, _) | TupleNode(_) -> True
    AnnotatedNode(child, _, _)
    | NamedNode(_, child)
    | UniqueNode(child)
    | ContainsNode(child, _) -> array_node(child)
    _ -> False
  }
}

fn contains_node(
  node: Node,
  membership: Membership,
) -> Result(Node, ConstructionError) {
  case node {
    IdentifiedNode(_, child) ->
      result.map(contains_node(child, membership), identified)
    ContextNode(context, child) ->
      result.map(contains_node(child, membership), ContextNode(context, _))
    AnnotatedNode(child, key, value) ->
      result.map(contains_node(child, membership), AnnotatedNode(_, key, value))
    ContainsNode(child, checks) ->
      Ok(ContainsNode(child, list.append(checks, [membership])))
    _ ->
      case array_node(node) {
        True -> Ok(ContainsNode(identified(node), [membership]))
        False ->
          Error(ConstructionError("contains requires an array definition"))
      }
  }
}

/// Validate the consequence only when the structural condition accepts input.
/// Retain the base output; condition/consequence converters never run.
pub fn if_then(
  def: Definition(a),
  condition: Definition(b),
  consequence: Definition(c),
) -> Definition(a) {
  let Definition(probe, _) = condition
  let Definition(yes, _) = consequence
  add_condition(def, Condition(probe, yes, None))
}

/// Validate exactly the selected structural branch, retaining the base decoder.
pub fn if_then_else(
  def: Definition(a),
  condition: Definition(b),
  consequence: Definition(c),
  alternative: Definition(d),
) -> Definition(a) {
  let Definition(probe, _) = condition
  let Definition(yes, _) = consequence
  let Definition(no, _) = alternative
  add_condition(def, Condition(probe, yes, Some(no)))
}

fn add_condition(def: Definition(a), condition: Condition) -> Definition(a) {
  let Definition(node, convert) = def
  let next = case bare(node) {
    ConditionalNode(base, checks) ->
      ConditionalNode(base, list.append(checks, [condition]))
    _ -> ConditionalNode(node, [condition])
  }
  definition(next, convert)
}

/// Reject input accepted by a forbidden structural definition.
/// Preserve the base output; forbidden-definition converters never run.
pub fn exclude(def: Definition(a), forbidden: Definition(b)) -> Definition(a) {
  let Definition(node, convert) = def
  let Definition(probe, _) = forbidden
  let next = case bare(node) {
    ExcludeNode(base, checks) -> ExcludeNode(base, list.append(checks, [probe]))
    _ -> ExcludeNode(node, [probe])
  }
  definition(next, convert)
}

/// Accept objects whose values satisfy the child definition. Decode to a Gleam
/// list of key/value pairs, preserving original keys rather than a JS object.
pub fn dictionary(def: Definition(a)) -> Definition(List(#(String, a))) {
  let Definition(n, d) = def
  definition(DictNode(n, None, None), fn(v) {
    case v {
      JObject(xs) -> list.map(xs, fn(p) { #(p.0, d(p.1)) })
      _ -> panic as "validated dictionary"
    }
  })
}

/// Constrain every own object key without changing decoded values or keys.
/// The key definition is used for validation only; its converter never runs.
pub fn property_names(
  def: Definition(a),
  keys: Definition(String),
) -> Result(Definition(a), ConstructionError) {
  let Definition(node, convert) = def
  let Definition(key, _) = keys
  use next <- result.try(property_names_node(node, key))
  Ok(definition(next, convert))
}

fn object_node(node: Node) -> Bool {
  case node {
    IdentifiedNode(_, child) | ContextNode(_, child) -> object_node(child)
    DictNode(_, _, _) | RecordNode(_, _) -> True
    NamedNode(_, child)
    | AnnotatedNode(child, _, _)
    | PropertyNamesNode(child, _) -> object_node(child)
    _ -> False
  }
}

fn property_names_node(
  node: Node,
  key: Node,
) -> Result(Node, ConstructionError) {
  case node {
    IdentifiedNode(_, child) ->
      result.map(property_names_node(child, key), identified)
    ContextNode(context, child) ->
      result.map(property_names_node(child, key), ContextNode(context, _))
    AnnotatedNode(child, name, value) ->
      result.map(property_names_node(child, key), AnnotatedNode(_, name, value))
    PropertyNamesNode(child, keys) ->
      Ok(PropertyNamesNode(child, list.append(keys, [key])))
    _ ->
      case object_node(node) {
        True -> Ok(PropertyNamesNode(identified(node), [key]))
        False ->
          Error(ConstructionError(
            "property_names requires an object definition",
          ))
      }
  }
}

fn valid_name(name: String) -> Bool {
  pattern_matches("^[A-Za-z][A-Za-z0-9_-]*$", name)
  && !pattern_matches("[^A-Za-z0-9_-]", name)
}

fn make_reference(
  name: String,
) -> #(Definition(a), Cell(Node), Cell(fn(Value) -> a)) {
  let nodes =
    new_cell(
      Cell,
      ConstructionError("unfinalized recursive reference: " <> name),
    )
  let converters =
    new_cell(Cell, ConstructionError("unfinalized recursive decoder: " <> name))
  let def =
    definition(ReferenceNode(name, nodes), fn(value) {
      let assert Ok(convert) = read_cell(converters)
        as "Recursive definition is not finalized"
      convert(value)
    })
  #(def, nodes, converters)
}

fn bind_reference(
  nodes: Cell(Node),
  converters: Cell(fn(Value) -> a),
  def: Definition(a),
) -> Nil {
  let Definition(node, convert) = def
  bind_cell(nodes, node)
  bind_cell(converters, convert)
}

/// Build a guarded self-recursive definition. The builder runs once with a
/// typed definition placeholder, never an invented decoded value.
pub fn recursive(
  name: String,
  build: fn(Definition(a)) -> Result(Definition(a), ConstructionError),
) -> Result(Definition(a), ConstructionError) {
  let #(built, context) =
    with_construction(fn() {
      case valid_name(name) {
        False -> Error(ConstructionError("invalid definition name"))
        True -> {
          let #(reference, nodes, converters) = make_reference(name)
          use body <- result.try(build(reference))
          bind_reference(nodes, converters, body)
          let Definition(root, _) = reference
          case guard_graph(root) {
            Ok(_) -> Ok(reference)
            Error(error) -> {
              reject_cell(nodes)
              reject_cell(converters)
              Error(error)
            }
          }
        }
      }
    })
  result.map(built, contextual(context, _))
}

/// Build two mutually recursive definitions with distinct names and independent
/// output types. References may cross only through guarded data structure edges.
pub fn recursive_pair(
  first_name: String,
  second_name: String,
  build: fn(Definition(a), Definition(b)) ->
    Result(#(Definition(a), Definition(b)), ConstructionError),
) -> Result(#(Definition(a), Definition(b)), ConstructionError) {
  let #(built, context) =
    with_construction(fn() {
      case
        valid_name(first_name)
        && valid_name(second_name)
        && first_name != second_name
      {
        False ->
          Error(ConstructionError("invalid or duplicate recursive names"))
        True -> {
          let #(first, first_nodes, first_convert) = make_reference(first_name)
          let #(second, second_nodes, second_convert) =
            make_reference(second_name)
          use bodies <- result.try(build(first, second))
          bind_reference(first_nodes, first_convert, bodies.0)
          bind_reference(second_nodes, second_convert, bodies.1)
          let Definition(first_root, _) = first
          let Definition(second_root, _) = second
          case
            result.try(guard_graph(first_root), fn(_) {
              guard_graph(second_root)
            })
          {
            Ok(_) -> Ok(#(first, second))
            Error(error) -> {
              reject_cell(first_nodes)
              reject_cell(first_convert)
              reject_cell(second_nodes)
              reject_cell(second_convert)
              Error(error)
            }
          }
        }
      }
    })
  result.map(built, fn(pair) {
    #(contextual(context, pair.0), contextual(context, pair.1))
  })
}

// Named definitions reuse finite structures; recursive definitions use explicit
// references whose complete graph is checked before returning to the caller.
/// Name a definition for local `$defs`/`$ref` reuse. Names must start with an
/// ASCII letter and contain only ASCII letters, digits, underscores or hyphens.
/// Conflicting names fail when the composed graph is validated or emitted.
pub fn named(
  name: String,
  def: Definition(a),
) -> Result(Definition(a), ConstructionError) {
  let Definition(node, convert) = def
  case valid_name(name) {
    True -> Ok(definition(NamedNode(name, node), convert))
    False -> Error(ConstructionError("invalid definition name"))
  }
}

/// Require structurally distinct JSON items in a direct homogeneous array
/// definition. Uniqueness is checked before mapping, not on decoded outputs.
pub fn unique_items(
  def: Definition(List(a)),
) -> Result(Definition(List(a)), ConstructionError) {
  let Definition(node, convert) = def
  case bare(node) {
    ArrayNode(_, _, _) -> Ok(definition(UniqueNode(node), convert))
    _ -> Error(ConstructionError("unique_items requires an array definition"))
  }
}

/// Add a schema description without changing validation or decoding.
pub fn description(def: Definition(a), s: String) -> Definition(a) {
  let Definition(n, d) = def
  definition(AnnotatedNode(n, "description", s), d)
}

/// Add a schema title without changing validation or decoding.
pub fn title(def: Definition(a), s: String) -> Definition(a) {
  let Definition(n, d) = def
  definition(AnnotatedNode(n, "title", s), d)
}

/// Start a record with a curried constructor. Each field consumes one argument;
/// call `finish` after supplying all fields. Multi-argument constructors need currying.
pub fn record(constructor: a) -> Record(a) {
  Record([], fn(_) { constructor })
}

fn add_field(
  r: Record(fn(a) -> b),
  name: String,
  child: Definition(a),
  presence: Presence,
) -> Result(Record(b), ConstructionError) {
  let Record(fs, construct) = r
  let Definition(node, convert) = child
  case
    list.any(fs, fn(f) {
      let Field(k, _, _) = f
      k == name
    })
  {
    True -> Error(ConstructionError("duplicate field: " <> name))
    False ->
      Ok(
        Record(list.append(fs, [Field(name, node, presence)]), fn(v) {
          let value = case member(v, name), presence {
            Some(x), _ -> x
            None, Default(x) -> x
            _, _ -> panic as "validated field"
          }
          construct(v)(convert(value))
        }),
      )
  }
}

/// Add a required field. Duplicate field names fail construction.
pub fn required(
  r: Record(fn(a) -> b),
  name: String,
  child: Definition(a),
) -> Result(Record(b), ConstructionError) {
  add_field(r, name, child, Required)
}

/// Add a field with an admitted JSON default validated during construction.
/// When absent, decode the default with the child converter. A present invalid
/// value still fails; defaults do not mutate the input or bypass validation.
pub fn defaulted(
  r: Record(fn(a) -> b),
  name: String,
  child: Definition(a),
  value: Value,
) -> Result(Record(b), ConstructionError) {
  use <- with_walk
  let Definition(n, _) = child
  // Defaults are checked during construction. A recursive placeholder cannot
  // yet supply its acceptance contract; reject it rather than invent a value.
  use _ <- result.try(collect_definitions_result(
    [n],
    [],
    new_seen(Seen, identity),
  ))
  case check(n, value, "") {
    [] -> add_field(r, name, child, Default(value))
    _ -> Error(ConstructionError("invalid default"))
  }
}

/// Add an optional field, consuming an `Option(a)` constructor argument.
/// Absence is `None`; present values must satisfy the child, including null.
pub fn optional(
  r: Record(fn(Option(a)) -> b),
  name: String,
  child: Definition(a),
) -> Result(Record(b), ConstructionError) {
  let Record(fs, construct) = r
  let Definition(n, d) = child
  case
    list.any(fs, fn(f) {
      let Field(k, _, _) = f
      k == name
    })
  {
    True -> Error(ConstructionError("duplicate field: " <> name))
    False ->
      Ok(
        Record(list.append(fs, [Field(name, n, Optional)]), fn(v) {
          construct(v)(option.map(member(v, name), d))
        }),
      )
  }
}

/// Finish a typed record with the chosen undeclared-key policy.
pub fn finish(r: Record(a), policy: Policy) -> Definition(a) {
  let Record(fs, d) = r
  definition(RecordNode(fs, policy), d)
}

/// Finish a tagged record branch. Do not declare the discriminator as a field.
pub fn variant(tag: String, r: Record(a), policy: Policy) -> Variant(a) {
  let Record(fs, d) = r
  Variant(tag, fs, policy, d, None)
}

/// Describe a tagged branch without changing its acceptance contract.
pub fn variant_description(v: Variant(a), s: String) -> Variant(a) {
  let Variant(t, f, p, d, _) = v
  Variant(t, f, p, d, Some(s))
}

/// Transform a tagged branch’s decoded output without changing its schema.
pub fn variant_map(v: Variant(a), f: fn(a) -> b) -> Variant(b) {
  let Variant(t, fs, p, d, s) = v
  Variant(t, fs, p, fn(x) { f(d(x)) }, s)
}

/// Construct a discriminated union of record variants. Empty lists, duplicate
/// tags and fields redeclaring the discriminator are construction errors.
pub fn tagged(
  discriminator: String,
  variants: List(Variant(a)),
) -> Result(Definition(a), ConstructionError) {
  let tags =
    list.map(variants, fn(v) {
      let Variant(t, _, _, _, _) = v
      t
    })
  case
    variants == []
    || list.length(list.unique(tags)) != list.length(tags)
    || list.any(variants, fn(v) {
      let Variant(_, fs, _, _, _) = v
      list.any(fs, fn(f) {
        let Field(k, _, _) = f
        k == discriminator
      })
    })
  {
    True ->
      Error(ConstructionError(
        "empty/duplicate tags or redeclared discriminator",
      ))
    False -> {
      let branches =
        list.map(variants, fn(v) {
          let Variant(t, fs, p, _, s) = v
          #(
            t,
            identified(RecordNode(
              list.append(fs, [
                Field(
                  discriminator,
                  identified(ConstNode(JString(t), "string")),
                  Required,
                ),
              ]),
              p,
            )),
            s,
          )
        })
      Ok(
        definition(TaggedNode(discriminator, branches), fn(value) {
          let assert Some(JString(tag)) = member(value, discriminator)
          let assert Ok(Variant(_, _, _, d, _)) =
            list.find(variants, fn(v) {
              let Variant(t, _, _, _, _) = v
              t == tag
            })
          d(value)
        }),
      )
    }
  }
}

/// Accept one or more matching branches and decode with the first matching
/// branch in list order. Empty unions fail construction.
pub fn any_of(
  defs: List(Definition(a)),
) -> Result(Definition(a), ConstructionError) {
  union(defs, False)
}

/// Accept exactly one structurally matching branch and decode with it.
/// Overlapping matches are rejected. Empty unions fail construction.
pub fn one_of(
  defs: List(Definition(a)),
) -> Result(Definition(a), ConstructionError) {
  union(defs, True)
}

fn union(
  defs: List(Definition(a)),
  exclusive: Bool,
) -> Result(Definition(a), ConstructionError) {
  case defs {
    [] -> Error(ConstructionError("empty union"))
    _ ->
      Ok(
        definition(
          UnionNode(
            list.map(defs, fn(d) {
              let Definition(n, _) = d
              n
            }),
            exclusive,
          ),
          fn(v) {
            let assert Ok(Definition(_, convert)) =
              list.find(defs, fn(d) {
                let Definition(n, _) = d
                check(n, v, "") == []
              })
            convert(v)
          },
        ),
      )
  }
}

fn max_lower(a: Option(Int), b: Option(Int)) -> Option(Int) {
  case a, b {
    None, x | x, None -> x
    Some(x), Some(y) ->
      Some(case x > y {
        True -> x
        False -> y
      })
  }
}

fn min_upper(a: Option(Int), b: Option(Int)) -> Option(Int) {
  case a, b {
    None, x | x, None -> x
    Some(x), Some(y) ->
      Some(case x < y {
        True -> x
        False -> y
      })
  }
}

fn bad_bounds(lo: Option(Int), hi: Option(Int), size: Bool) -> Bool {
  case lo, hi {
    Some(a), Some(b) if a > b -> True
    _, _ ->
      list.any(list.filter_map([lo, hi], option.to_result(_, Nil)), fn(x) {
        !integer(as_float(x))
        || x < -9_007_199_254_740_991
        || x > 9_007_199_254_740_991
        || size
        && x < 0
      })
  }
}

/// Intersect inclusive integer bounds, Unicode code-point string lengths,
/// homogeneous array lengths or dictionary key counts. `None` leaves a side
/// unbounded. Unsupported definitions and invalid intervals fail construction.
pub fn bounds(
  def: Definition(a),
  lower: Option(Int),
  upper: Option(Int),
) -> Result(Definition(a), ConstructionError) {
  let Definition(n, d) = def
  use next <- result.try(bound_node(n, lower, upper))
  Ok(definition(next, d))
}

fn bound_node(
  n: Node,
  lo: Option(Int),
  hi: Option(Int),
) -> Result(Node, ConstructionError) {
  case n {
    IdentifiedNode(_, child) ->
      result.map(bound_node(child, lo, hi), identified)
    ContextNode(context, child) ->
      result.map(bound_node(child, lo, hi), ContextNode(context, _))
    AnnotatedNode(child, k, v) ->
      result.map(bound_node(child, lo, hi), AnnotatedNode(_, k, v))
    ContainsNode(child, checks) ->
      result.map(bound_node(child, lo, hi), ContainsNode(_, checks))
    PropertyNamesNode(child, keys) ->
      result.map(bound_node(child, lo, hi), PropertyNamesNode(_, keys))
    IntegerNode(a, b) -> {
      let l = max_lower(Some(a), lo)
      let h = min_upper(Some(b), hi)
      case
        bad_bounds(l, h, False)
        || bad_bounds(lo, hi, False)
        || list.any(list.filter_map([lo, hi], option.to_result(_, Nil)), fn(x) {
          x < -9_007_199_254_740_991 || x > 9_007_199_254_740_991
        })
      {
        True -> Error(ConstructionError("invalid integer bounds"))
        False -> {
          let assert Some(x) = l
          let assert Some(y) = h
          Ok(IntegerNode(x, y))
        }
      }
    }
    StringNode(a, b, p) ->
      sizes(
        max_lower(a, lo),
        min_upper(b, hi),
        fn(x, y) { StringNode(x, y, p) },
        lo,
        hi,
      )
    ArrayNode(c, a, b) ->
      sizes(
        max_lower(a, lo),
        min_upper(b, hi),
        fn(x, y) { ArrayNode(c, x, y) },
        lo,
        hi,
      )
    DictNode(c, a, b) ->
      sizes(
        max_lower(a, lo),
        min_upper(b, hi),
        fn(x, y) { DictNode(c, x, y) },
        lo,
        hi,
      )
    _ -> Error(ConstructionError("bounds unsupported for this definition"))
  }
}

fn sizes(lo, hi, make, raw_lo, raw_hi) {
  case bad_bounds(lo, hi, True) || bad_bounds(raw_lo, raw_hi, True) {
    True -> Error(ConstructionError("invalid size bounds"))
    False -> Ok(make(lo, hi))
  }
}

/// Intersect an unanchored ECMAScript Unicode regular expression with a string
/// definition. Anchor explicitly for whole-string matching. Invalid expressions
/// and unsupported underlying definitions fail construction.
pub fn pattern(
  def: Definition(String),
  p: String,
) -> Result(Definition(String), ConstructionError) {
  let Definition(n, d) = def
  case pattern_valid(p) {
    False -> Error(ConstructionError("invalid regex"))
    True -> result.map(pattern_node(n, p), fn(next) { definition(next, d) })
  }
}

fn pattern_node(n: Node, p: String) -> Result(Node, ConstructionError) {
  case n {
    IdentifiedNode(_, child) -> result.map(pattern_node(child, p), identified)
    ContextNode(context, child) ->
      result.map(pattern_node(child, p), ContextNode(context, _))
    StringNode(a, b, ps) ->
      Ok(StringNode(a, b, list.unique(list.append(ps, [p]))))
    AnnotatedNode(c, k, v) ->
      result.map(pattern_node(c, p), AnnotatedNode(_, k, v))
    _ -> Error(ConstructionError("pattern requires string definition"))
  }
}

/// Validate an admitted value without invoking constructors or map callbacks.
/// Unfinished/conflicting reference graphs and resource exhaustion are operational
/// failures rather than data errors.
pub fn validate(
  def: Definition(a),
  value: Value,
) -> Result(Nil, List(DataError)) {
  with_walk(fn() {
    let Definition(n, _) = def
    // Even an empty array must not make an escaped, rejected placeholder usable.
    let assert Ok(_) =
      collect_definitions_result([n], [], new_seen(Seen, identity))
      as "Definition contains an unfinalized recursive reference or conflicting names"
    case check(n, value, "") {
      [] -> Ok(Nil)
      errors -> Error(errors)
    }
  })
}

/// Validate first, then construct the typed output. Invalid input returns data
/// errors without running converters. Exceptions from trusted callbacks propagate.
pub fn decode(def: Definition(a), value: Value) -> Result(a, List(DataError)) {
  use _ <- result.try(validate(def, value))
  let Definition(_, d) = def
  Ok(d(value))
}

fn member(v: Value, k: String) -> Option(Value) {
  case v {
    JObject(xs) ->
      case list.key_find(xs, k) {
        Ok(x) -> Some(x)
        Error(_) -> None
      }
    _ -> None
  }
}

fn path(parent: String, key: String) -> String {
  parent <> "/" <> string.replace(string.replace(key, "~", "~0"), "/", "~1")
}

fn err(category: String, p: String) -> List(DataError) {
  [DataError(category, p, None, [], [])]
}

fn size_ok(n: Int, lo: Option(Int), hi: Option(Int)) -> Bool {
  let low = case lo {
    Some(x) -> n >= x
    None -> True
  }
  let high = case hi {
    Some(x) -> n <= x
    None -> True
  }
  low && high
}

fn check(n: Node, v: Value, p: String) -> List(DataError) {
  case n, v {
    IdentifiedNode(_, child), _ -> check(child, v, p)
    ContextNode(context, child), _ ->
      with_context(context, fn() { check(child, v, p) })
    ReferenceNode(_, cell), _ -> {
      let assert Ok(child) = read_cell(cell)
        as "Recursive definition is not finalized"
      check(child, v, p)
    }
    NamedNode(_, child), _ -> check(child, v, p)
    UniqueNode(child), JArray(xs) -> {
      let values = list.map(xs, value_text)
      list.append(
        check(child, v, p),
        case list.length(list.unique(values)) == list.length(values) {
          True -> []
          False -> err("duplicate_items", p)
        },
      )
    }
    UniqueNode(child), _ -> check(child, v, p)
    AnnotatedNode(child, _, _), _ -> check(child, v, p)
    BooleanNode, JBool(_) | NullNode, JNull -> []
    StringNode(lo, hi, patterns), JString(s) ->
      case
        size_ok(codepoints(s), lo, hi)
        && list.all(patterns, pattern_matches(_, s))
      {
        True -> []
        False -> err("string_constraint", p)
      }
    IntegerNode(lo, hi), JNumber(x) ->
      case integer(x) && x >=. as_float(lo) && x <=. as_float(hi) {
        True -> []
        False -> err("integer_constraint", p)
      }
    NumberNode(lo, hi), JNumber(x) ->
      case number_ok(x, lo, hi) {
        True -> []
        False -> err("number_constraint", p)
      }
    ConstNode(expected, _), _ ->
      case constant_equal(expected, v) {
        True -> []
        False -> err("constant", p)
      }
    EnumNode(values), JString(s) ->
      case list.contains(values, s) {
        True -> []
        False -> err("enum", p)
      }
    ArrayNode(child, lo, hi), JArray(xs) ->
      case size_ok(list.length(xs), lo, hi) {
        False -> err("array_size", p)
        True ->
          list.index_map(xs, fn(x, i) { check(child, x, path(p, int_text(i))) })
          |> list.flatten
      }
    ExcludeNode(base, checks), _ ->
      list.append(
        check(base, v, p),
        list.flat_map(checks, fn(probe) {
          case check(probe, v, "") == [] {
            True -> err("excluded", p)
            False -> []
          }
        }),
      )
    ConditionalNode(base, checks), _ ->
      list.append(
        check(base, v, p),
        list.flat_map(checks, fn(condition) {
          let Condition(probe, yes, no) = condition
          case check(probe, v, "") == [] {
            True -> check(yes, v, p)
            False ->
              case no {
                Some(alternative) -> check(alternative, v, p)
                None -> []
              }
          }
        }),
      )
    ContainsNode(child, checks), _ -> {
      let errors = check(child, v, p)
      case v {
        JArray(items) ->
          list.append(
            errors,
            list.flat_map(checks, fn(membership) {
              let Membership(matching, minimum, maximum) = membership
              case minimum, maximum {
                0, None -> []
                _, _ -> {
                  let count =
                    list.count(items, fn(item) {
                      check(matching, item, "") == []
                    })
                  case size_ok(count, Some(minimum), maximum) {
                    True -> []
                    False -> err("contains_count", p)
                  }
                }
              }
            }),
          )
        _ -> errors
      }
    }
    PropertyNamesNode(child, keys), _ -> {
      let errors = check(child, v, p)
      case v {
        JObject(entries) ->
          list.append(
            errors,
            list.flat_map(entries, fn(pair) {
              list.flat_map(keys, fn(key) {
                check(key, JString(pair.0), path(p, pair.0))
              })
            }),
          )
        _ -> errors
      }
    }
    TupleNode(children), JArray(xs) ->
      case list.length(children) == list.length(xs) {
        False -> err("tuple_size", p)
        True ->
          list.zip(children, xs)
          |> list.index_map(fn(pair, i) {
            check(pair.0, pair.1, path(p, int_text(i)))
          })
          |> list.flatten
      }
    DictNode(child, lo, hi), JObject(xs) ->
      case size_ok(list.length(xs), lo, hi) {
        False -> err("property_count", p)
        True -> list.flat_map(xs, fn(x) { check(child, x.1, path(p, x.0)) })
      }
    RecordNode(fs, policy), JObject(xs) -> {
      let fields =
        list.flat_map(fs, fn(f) {
          let Field(k, child, presence) = f
          case member(v, k), presence {
            Some(x), _ -> check(child, x, path(p, k))
            None, Required -> [
              DataError("missing_required", p, Some(k), [], []),
            ]
            _, _ -> []
          }
        })
      let extras = case policy {
        Open -> []
        Closed ->
          list.flat_map(xs, fn(x) {
            case
              list.any(fs, fn(f) {
                let Field(k, _, _) = f
                k == x.0
              })
            {
              True -> []
              False -> err("extra_key", path(p, x.0))
            }
          })
      }
      list.append(fields, extras)
    }
    NullableNode(_), JNull -> []
    NullableNode(child), _ -> check(child, v, p)
    UnionNode(children, exclusive), _ -> {
      let outcomes = list.index_map(children, fn(c, i) { #(i, check(c, v, p)) })
      let matches =
        list.filter_map(outcomes, fn(x) {
          case x.1 {
            [] -> Ok(x.0)
            _ -> Error(Nil)
          }
        })
      case matches {
        [] -> [DataError("union_no_match", p, None, outcomes, [])]
        [_] -> []
        _ ->
          case exclusive {
            True -> [DataError("one_of_ambiguous", p, None, [], matches)]
            False -> []
          }
      }
    }
    TaggedNode(k, branches), JObject(_) ->
      case member(v, k) {
        None -> [DataError("missing_required", p, Some(k), [], [])]
        Some(JString(tag)) ->
          case list.find(branches, fn(b) { b.0 == tag }) {
            Error(_) -> err("unknown_discriminator", path(p, k))
            Ok(#(_, child, _)) -> check(child, v, p)
          }
        Some(_) -> err("discriminator_type", path(p, k))
      }
    RecordNode(_, _), _ | DictNode(_, _, _), _ | TaggedNode(_, _), _ ->
      err("object_type", p)
    BooleanNode, _ -> err("boolean_type", p)
    NullNode, _ -> err("null_type", p)
    StringNode(_, _, _), _ | EnumNode(_), _ -> err("string_type", p)
    IntegerNode(_, _), _ -> err("integer_type", p)
    NumberNode(_, _), _ -> err("number_type", p)
    TupleNode(_), _ -> err("tuple_type", p)
    ArrayNode(_, _, _), _ -> err("array_type", p)
  }
}

// Numeric equality must identify both zero signs on every target. OTP's exact
// term equality distinguishes them, whereas JSON Schema equality does not.
fn constant_equal(a: Value, b: Value) -> Bool {
  case a, b {
    JNumber(x), JNumber(y) -> x >=. y && x <=. y
    _, _ -> a == b
  }
}

@external(erlang, "gargamelle_runtime", "int_text")
@external(javascript, "./runtime.mjs", "int_text")
fn int_text(n: Int) -> String

/// Emit a JSON Schema 2020-12 document as Gargamelle’s opaque `Value`, not
/// `gleam/json.Json`. Unfinished or conflicting reference graphs fail operationally.
pub fn emit_json(def: Definition(a)) -> Value {
  with_walk(fn() {
    let Definition(n, _) = def
    put(
      emit_with_definitions(n),
      "$schema",
      JString("https://json-schema.org/draft/2020-12/schema"),
    )
  })
}

/// Emit canonical JSON Schema 2020-12 text, including finite local references.
pub fn emit_text(def: Definition(a)) -> String {
  value_text(emit_json(def))
}

fn put(v: Value, k: String, x: Value) -> Value {
  let assert JObject(xs) = v
  JObject(list.append(list.filter(xs, fn(p) { p.0 != k }), [#(k, x)]))
}

fn obj(xs: List(#(String, Value))) -> Value {
  JObject(xs)
}

fn typ(t: String) -> Value {
  obj([#("type", JString(t))])
}

fn emit_bound(v: Value, k: String, b: Option(Int)) -> Value {
  case b {
    None -> v
    Some(x) -> put(v, k, JNumber(as_float(x)))
  }
}

fn same_reference(a: Node, b: Node) -> Bool {
  identity(a) == identity(b)
}

fn node_children(n: Node) -> Result(List(Node), ConstructionError) {
  case n {
    IdentifiedNode(_, child) -> node_children(child)
    ContextNode(context, child) ->
      with_context(context, fn() {
        result.map(node_children(child), fn(children) {
          list.map(children, ContextNode(context, _))
        })
      })
    ReferenceNode(_, cell) -> result.map(read_cell(cell), fn(child) { [child] })
    NamedNode(_, child)
    | ArrayNode(child, _, _)
    | DictNode(child, _, _)
    | NullableNode(child)
    | AnnotatedNode(child, _, _)
    | UniqueNode(child) -> Ok([child])
    RecordNode(fields, _) ->
      Ok(
        list.map(fields, fn(f) {
          let Field(_, child, _) = f
          child
        }),
      )
    ExcludeNode(base, checks) -> Ok([base, ..checks])
    ConditionalNode(base, checks) ->
      Ok([
        base,
        ..list.flat_map(checks, fn(condition) {
          let Condition(probe, yes, no) = condition
          case no {
            Some(alternative) -> [probe, yes, alternative]
            None -> [probe, yes]
          }
        })
      ])
    ContainsNode(child, checks) ->
      Ok([
        child,
        ..list.map(checks, fn(m) {
          let Membership(node, _, _) = m
          node
        })
      ])
    PropertyNamesNode(child, keys) -> Ok([child, ..keys])
    TupleNode(children) | UnionNode(children, _) -> Ok(children)
    TaggedNode(_, branches) -> Ok(list.map(branches, fn(b) { b.1 }))
    _ -> Ok([])
  }
}

fn merge_definition(
  name: String,
  child: Node,
  definitions: List(#(String, Node)),
) -> Result(List(#(String, Node)), ConstructionError) {
  case list.key_find(definitions, name) {
    Error(_) -> Ok([#(name, child), ..definitions])
    Ok(existing) ->
      case
        same_reference(existing, child)
        || value_text(emit(existing)) == value_text(emit(child))
      {
        True -> Ok(definitions)
        False ->
          Error(ConstructionError(
            "Conflicting named schema definitions: " <> name,
          ))
      }
  }
}

fn collect_definitions_result(
  pending: List(Node),
  definitions: List(#(String, Node)),
  seen: Seen(Node),
) -> Result(List(#(String, Node)), ConstructionError) {
  case pending {
    [] -> Ok(definitions)
    [node, ..rest] ->
      case seen_before(seen, node) {
        True -> collect_definitions_result(rest, definitions, seen)
        False ->
          case node_children(node) {
            Error(error) -> Error(error)
            Ok(children) -> {
              let merged = case bare(node), children {
                NamedNode(name, _), [child] | ReferenceNode(name, _), [child] ->
                  merge_definition(name, child, definitions)
                _, _ -> Ok(definitions)
              }
              case merged {
                Error(error) -> Error(error)
                Ok(next) ->
                  collect_definitions_result(
                    list.append(children, rest),
                    next,
                    seen,
                  )
              }
            }
          }
      }
  }
}

// These wrappers check the same input. Arrays, dictionary values and record
// fields instead descend into a strict child value and therefore break cycles.
fn same_input_children(n: Node) -> Result(List(Node), ConstructionError) {
  case n {
    IdentifiedNode(_, child) -> same_input_children(child)
    ContextNode(context, child) ->
      with_context(context, fn() {
        result.map(same_input_children(child), fn(children) {
          list.map(children, ContextNode(context, _))
        })
      })
    ContainsNode(child, _) | PropertyNamesNode(child, _) -> Ok([child])
    ArrayNode(_, _, _) | TupleNode(_) | DictNode(_, _, _) | RecordNode(_, _) ->
      Ok([])
    _ -> node_children(n)
  }
}

// Per-finalization DFS state: active nodes detect back edges; fully checked
// nodes skip shared subgraphs. State is shared across all definition roots.
type Guard(a) {
  Guard(fn(a) -> Int, fn(a) -> Nil)
}

@external(erlang, "gargamelle_runtime", "recursion_guard")
@external(javascript, "./runtime.mjs", "recursion_guard")
fn new_guard(
  make: fn(fn(a) -> Int, fn(a) -> Nil) -> Guard(a),
  key: fn(a) -> Identity,
) -> Guard(a)

fn guard_same_input(
  n: Node,
  state: Guard(Node),
) -> Result(Nil, ConstructionError) {
  let Guard(enter, finish) = state
  case enter(n) {
    1 -> Error(ConstructionError("non-progressing recursive definition"))
    2 -> Ok(Nil)
    _ -> {
      use children <- result.try(same_input_children(n))
      use _ <- result.try(
        list.try_fold(children, Nil, fn(_, child) {
          guard_same_input(child, state)
        }),
      )
      finish(n)
      Ok(Nil)
    }
  }
}

fn guard_graph(root: Node) -> Result(Nil, ConstructionError) {
  with_walk(fn() {
    use definitions <- result.try(collect_definitions_result(
      [root],
      [],
      new_seen(Seen, identity),
    ))
    let state = new_guard(Guard, identity)
    list.try_fold(
      [root, ..list.map(definitions, fn(pair) { pair.1 })],
      Nil,
      fn(_, n) { guard_same_input(n, state) },
    )
  })
}

fn collect_definitions(
  n: Node,
  _: List(#(String, Node)),
) -> List(#(String, Node)) {
  let assert Ok(definitions) =
    collect_definitions_result([n], [], new_seen(Seen, identity))
    as "Conflicting named schema definitions or unfinalized recursive reference"
  definitions
}

fn emit_with_definitions(n: Node) -> Value {
  case collect_definitions(n, []) {
    [] -> emit(n)
    definitions ->
      put(
        emit(n),
        "$defs",
        obj(list.map(definitions, fn(pair) { #(pair.0, emit(pair.1)) })),
      )
  }
}

fn emit_number_bound(
  schema: Value,
  bound: Option(NumberBound),
  inclusive_key: String,
  exclusive_key: String,
) -> Value {
  case bound {
    None -> schema
    Some(Inclusive(x)) -> put(schema, inclusive_key, JNumber(x))
    Some(Exclusive(x)) -> put(schema, exclusive_key, JNumber(x))
  }
}

fn emit(n: Node) -> Value {
  case n {
    IdentifiedNode(_, child) -> emit(child)
    ContextNode(context, child) -> with_context(context, fn() { emit(child) })
    NamedNode(name, _) | ReferenceNode(name, _) ->
      obj([#("$ref", JString("#/$defs/" <> name))])
    UniqueNode(c) -> put(emit(c), "uniqueItems", JBool(True))
    BooleanNode -> typ("boolean")
    NullNode -> typ("null")
    StringNode(lo, hi, patterns) -> {
      let base =
        typ("string")
        |> emit_bound("minLength", lo)
        |> emit_bound("maxLength", hi)
      case patterns {
        [] -> base
        [p] -> put(base, "pattern", JString(p))
        _ ->
          put(
            base,
            "allOf",
            JArray(
              list.map(patterns, fn(p) {
                put(typ("string"), "pattern", JString(p))
              }),
            ),
          )
      }
    }
    IntegerNode(lo, hi) ->
      typ("integer")
      |> emit_bound("minimum", Some(lo))
      |> emit_bound("maximum", Some(hi))
    NumberNode(lo, hi) ->
      typ("number")
      |> emit_number_bound(lo, "minimum", "exclusiveMinimum")
      |> emit_number_bound(hi, "maximum", "exclusiveMaximum")
    ConstNode(v, t) -> put(typ(t), "const", v)
    EnumNode(vs) -> put(typ("string"), "enum", JArray(list.map(vs, JString)))
    ArrayNode(c, lo, hi) ->
      typ("array")
      |> put("items", emit(c))
      |> emit_bound("minItems", lo)
      |> emit_bound("maxItems", hi)
    ExcludeNode(base, checks) ->
      obj([
        #(
          "allOf",
          JArray([
            emit(base),
            ..list.map(checks, fn(probe) { obj([#("not", emit(probe))]) })
          ]),
        ),
      ])
    ConditionalNode(base, checks) -> {
      let branches =
        list.map(checks, fn(condition) {
          let Condition(probe, yes, no) = condition
          let schema = obj([#("if", emit(probe)), #("then", emit(yes))])
          case no {
            Some(alternative) -> put(schema, "else", emit(alternative))
            None -> schema
          }
        })
      obj([#("allOf", JArray([emit(base), ..branches]))])
    }
    ContainsNode(child, checks) -> {
      let schemas =
        list.filter_map(checks, fn(membership) {
          let Membership(matching, minimum, maximum) = membership
          case minimum, maximum {
            0, None -> Error(Nil)
            _, _ ->
              Ok(
                typ("array")
                |> put("contains", emit(matching))
                |> emit_bound("minContains", Some(minimum))
                |> emit_bound("maxContains", maximum),
              )
          }
        })
      let base = emit(child) |> put("type", JString("array"))
      case schemas {
        [] -> base
        [JObject(fields)] ->
          list.fold(fields, base, fn(schema, field) {
            put(schema, field.0, field.1)
          })
        _ -> put(base, "allOf", JArray(schemas))
      }
    }
    PropertyNamesNode(child, keys) -> {
      let key_schema = case keys {
        [key] -> emit(key)
        _ -> obj([#("allOf", JArray(list.map(keys, emit)))])
      }
      emit(child)
      |> put("type", JString("object"))
      |> put("propertyNames", key_schema)
    }
    TupleNode(children) -> {
      let schema =
        typ("array")
        |> put("items", JBool(False))
        |> emit_bound("minItems", Some(list.length(children)))
      case children {
        [] -> schema
        _ -> put(schema, "prefixItems", JArray(list.map(children, emit)))
      }
    }
    DictNode(c, lo, hi) ->
      typ("object")
      |> put("additionalProperties", emit(c))
      |> emit_bound("minProperties", lo)
      |> emit_bound("maxProperties", hi)
    RecordNode(fs, policy) -> {
      let properties =
        list.map(fs, fn(f) {
          let Field(k, c, p) = f
          #(k, case p {
            Default(v) -> put(emit(c), "default", v)
            _ -> emit(c)
          })
        })
      let required =
        list.filter_map(fs, fn(f) {
          let Field(k, _, p) = f
          case p {
            Required -> Ok(k)
            _ -> Error(Nil)
          }
        })
        |> sorted
        |> list.map(JString)
      typ("object")
      |> put("properties", JObject(properties))
      |> put("required", JArray(required))
      |> put("additionalProperties", JBool(policy == Open))
    }
    NullableNode(c) -> obj([#("anyOf", JArray([emit(c), typ("null")]))])
    UnionNode(cs, exclusive) ->
      obj([
        #(
          case exclusive {
            True -> "oneOf"
            False -> "anyOf"
          },
          JArray(list.map(cs, emit)),
        ),
      ])
    TaggedNode(_, bs) ->
      obj([
        #(
          "oneOf",
          JArray(
            list.map(bs, fn(b) {
              case b.2 {
                None -> emit(b.1)
                Some(s) -> put(emit(b.1), "description", JString(s))
              }
            }),
          ),
        ),
      ])
    AnnotatedNode(c, k, v) -> put(emit(c), k, JString(v))
  }
}
