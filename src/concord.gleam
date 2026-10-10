import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// Values can enter only through the JSON parser. Runtime helpers preserve own keys.
pub opaque type Value {
  JNull
  JBool(Bool)
  JNumber(Float)
  JString(String)
  JArray(List(Value))
  JObject(List(#(String, Value)))
}

pub type AdmissionError {
  AdmissionError(String)
}

pub type ConstructionError {
  ConstructionError(String)
}

pub type DataError {
  DataError(
    category: String,
    path: String,
    missing_key: Option(String),
    branches: List(#(Int, List(DataError))),
    matches: List(Int),
  )
}

pub type Policy {
  Closed
  Open
}

/// A finite numeric endpoint. Inclusive endpoints accept equality.
pub type NumberBound {
  Inclusive(Float)
  Exclusive(Float)
}

type Node {
  BooleanNode
  NullNode
  StringNode(Option(Int), Option(Int), List(String))
  IntegerNode(Int, Int)
  NumberNode(Option(NumberBound), Option(NumberBound))
  ConstNode(Value, String)
  EnumNode(List(String))
  ArrayNode(Node, Option(Int), Option(Int))
  TupleNode(List(Node))
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

@external(javascript, "./runtime.mjs", "identity_tracker")
fn new_seen(make: fn(fn(a) -> Bool) -> Seen(a)) -> Seen(a)

fn seen_before(seen: Seen(a), value: a) -> Bool {
  let Seen(visit) = seen
  visit(value)
}

type Cell(a) {
  Cell(fn() -> Result(a, ConstructionError), fn(a) -> Nil, fn() -> Nil)
}

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

type Field {
  Field(String, Node, Presence)
}

type Presence {
  Required
  Optional
  Default(Value)
}

pub opaque type Definition(a) {
  Definition(Node, fn(Value) -> a)
}

pub opaque type Record(a) {
  Record(List(Field), fn(Value) -> a)
}

pub opaque type Tuple(a) {
  Tuple(List(Node), fn(Value) -> a)
}

pub opaque type Variant(a) {
  Variant(String, List(Field), Policy, fn(Value) -> a, Option(String))
}

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

@external(javascript, "./runtime.mjs", "integer")
fn integer(value: Float) -> Bool

@external(javascript, "./runtime.mjs", "finite")
fn finite(value: Float) -> Bool

@external(javascript, "./runtime.mjs", "as_int")
fn as_int(value: Float) -> Int

@external(javascript, "./runtime.mjs", "as_float")
fn as_float(value: Int) -> Float

pub fn boolean() -> Definition(Bool) {
  Definition(BooleanNode, fn(v) {
    case v {
      JBool(b) -> b
      _ -> panic as "validated boolean"
    }
  })
}

pub fn null() -> Definition(Nil) {
  Definition(NullNode, fn(_) { Nil })
}

pub fn text() -> Definition(String) {
  Definition(StringNode(None, None, []), fn(v) {
    case v {
      JString(s) -> s
      _ -> panic as "validated string"
    }
  })
}

pub fn safe_integer() -> Definition(Int) {
  Definition(IntegerNode(-9_007_199_254_740_991, 9_007_199_254_740_991), fn(v) {
    case v {
      JNumber(n) -> as_int(n)
      _ -> panic as "validated integer"
    }
  })
}

/// Decode any admitted finite IEEE-754 number to Float, including integers.
/// JSON parsing may round or underflow; decoding preserves the parsed value.
pub fn number() -> Definition(Float) {
  Definition(NumberNode(None, None), fn(v) {
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
      case xv == yv {
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
      || lo == hi
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
      Ok(Definition(next, d))
    }
  }
}

fn number_bound_node(
  n: Node,
  lower: Option(NumberBound),
  upper: Option(NumberBound),
) -> Result(Node, ConstructionError) {
  case n {
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

pub fn string_enum(
  values: List(String),
) -> Result(Definition(String), ConstructionError) {
  case values == [] || list.length(list.unique(values)) != list.length(values) {
    True -> Error(ConstructionError("empty or duplicate enum"))
    False ->
      Ok(
        Definition(EnumNode(values), fn(v) {
          case v {
            JString(s) -> s
            _ -> panic as "validated enum"
          }
        }),
      )
  }
}

pub fn string_constant(v: String) -> Definition(String) {
  Definition(ConstNode(JString(v), "string"), fn(_) { v })
}

pub fn boolean_constant(v: Bool) -> Definition(Bool) {
  Definition(ConstNode(JBool(v), "boolean"), fn(_) { v })
}

pub fn null_constant() -> Definition(Nil) {
  Definition(ConstNode(JNull, "null"), fn(_) { Nil })
}

pub fn integer_constant(v: Int) -> Result(Definition(Int), ConstructionError) {
  case
    v < -9_007_199_254_740_991
    || v > 9_007_199_254_740_991
    || !integer(as_float(v))
  {
    True -> Error(ConstructionError("unsafe integer"))
    False ->
      Ok(Definition(ConstNode(JNumber(as_float(v)), "integer"), fn(_) { v }))
  }
}

pub fn map(def: Definition(a), f: fn(a) -> b) -> Definition(b) {
  let Definition(n, d) = def
  Definition(n, fn(v) { f(d(v)) })
}

pub fn nullable(def: Definition(a)) -> Definition(Option(a)) {
  let Definition(n, d) = def
  Definition(NullableNode(n), fn(v) {
    case v {
      JNull -> None
      _ -> Some(d(v))
    }
  })
}

pub fn array(def: Definition(a)) -> Definition(List(a)) {
  let Definition(n, d) = def
  Definition(ArrayNode(n, None, None), fn(v) {
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
  Definition(TupleNode(nodes), convert)
}

pub fn dictionary(def: Definition(a)) -> Definition(List(#(String, a))) {
  let Definition(n, d) = def
  Definition(DictNode(n, None, None), fn(v) {
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
  Ok(Definition(next, convert))
}

fn object_node(node: Node) -> Bool {
  case node {
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
    AnnotatedNode(child, name, value) ->
      result.map(property_names_node(child, key), AnnotatedNode(_, name, value))
    PropertyNamesNode(child, keys) ->
      Ok(PropertyNamesNode(child, list.append(keys, [key])))
    _ ->
      case object_node(node) {
        True -> Ok(PropertyNamesNode(node, [key]))
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
    Definition(ReferenceNode(name, nodes), fn(value) {
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
}

/// Build two mutually recursive definitions with distinct names and independent
/// output types. References may cross only through guarded data structure edges.
pub fn recursive_pair(
  first_name: String,
  second_name: String,
  build: fn(Definition(a), Definition(b)) ->
    Result(#(Definition(a), Definition(b)), ConstructionError),
) -> Result(#(Definition(a), Definition(b)), ConstructionError) {
  case
    valid_name(first_name)
    && valid_name(second_name)
    && first_name != second_name
  {
    False -> Error(ConstructionError("invalid or duplicate recursive names"))
    True -> {
      let #(first, first_nodes, first_convert) = make_reference(first_name)
      let #(second, second_nodes, second_convert) = make_reference(second_name)
      use bodies <- result.try(build(first, second))
      bind_reference(first_nodes, first_convert, bodies.0)
      bind_reference(second_nodes, second_convert, bodies.1)
      let Definition(first_root, _) = first
      let Definition(second_root, _) = second
      case
        result.try(guard_graph(first_root), fn(_) { guard_graph(second_root) })
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
}

// Named definitions reuse finite structures; recursive definitions use explicit
// references whose complete graph is checked before returning to the caller.
pub fn named(
  name: String,
  def: Definition(a),
) -> Result(Definition(a), ConstructionError) {
  let Definition(node, convert) = def
  case valid_name(name) {
    True -> Ok(Definition(NamedNode(name, node), convert))
    False -> Error(ConstructionError("invalid definition name"))
  }
}

pub fn unique_items(
  def: Definition(List(a)),
) -> Result(Definition(List(a)), ConstructionError) {
  let Definition(node, convert) = def
  case node {
    ArrayNode(_, _, _) -> Ok(Definition(UniqueNode(node), convert))
    _ -> Error(ConstructionError("unique_items requires an array definition"))
  }
}

pub fn description(def: Definition(a), s: String) -> Definition(a) {
  let Definition(n, d) = def
  Definition(AnnotatedNode(n, "description", s), d)
}

pub fn title(def: Definition(a), s: String) -> Definition(a) {
  let Definition(n, d) = def
  Definition(AnnotatedNode(n, "title", s), d)
}

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

pub fn required(
  r: Record(fn(a) -> b),
  name: String,
  child: Definition(a),
) -> Result(Record(b), ConstructionError) {
  add_field(r, name, child, Required)
}

pub fn defaulted(
  r: Record(fn(a) -> b),
  name: String,
  child: Definition(a),
  value: Value,
) -> Result(Record(b), ConstructionError) {
  let Definition(n, _) = child
  // Defaults are checked during construction. A recursive placeholder cannot
  // yet supply its acceptance contract; reject it rather than invent a value.
  use _ <- result.try(collect_definitions_result([n], [], new_seen(Seen)))
  case check(n, value, "") {
    [] -> add_field(r, name, child, Default(value))
    _ -> Error(ConstructionError("invalid default"))
  }
}

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

pub fn finish(r: Record(a), policy: Policy) -> Definition(a) {
  let Record(fs, d) = r
  Definition(RecordNode(fs, policy), d)
}

pub fn variant(tag: String, r: Record(a), policy: Policy) -> Variant(a) {
  let Record(fs, d) = r
  Variant(tag, fs, policy, d, None)
}

pub fn variant_description(v: Variant(a), s: String) -> Variant(a) {
  let Variant(t, f, p, d, _) = v
  Variant(t, f, p, d, Some(s))
}

pub fn variant_map(v: Variant(a), f: fn(a) -> b) -> Variant(b) {
  let Variant(t, fs, p, d, s) = v
  Variant(t, fs, p, fn(x) { f(d(x)) }, s)
}

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
            RecordNode(
              list.append(fs, [
                Field(discriminator, ConstNode(JString(t), "string"), Required),
              ]),
              p,
            ),
            s,
          )
        })
      Ok(
        Definition(TaggedNode(discriminator, branches), fn(value) {
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

pub fn any_of(
  defs: List(Definition(a)),
) -> Result(Definition(a), ConstructionError) {
  union(defs, False)
}

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
        Definition(
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

pub fn bounds(
  def: Definition(a),
  lower: Option(Int),
  upper: Option(Int),
) -> Result(Definition(a), ConstructionError) {
  let Definition(n, d) = def
  use next <- result.try(bound_node(n, lower, upper))
  Ok(Definition(next, d))
}

fn bound_node(
  n: Node,
  lo: Option(Int),
  hi: Option(Int),
) -> Result(Node, ConstructionError) {
  case n {
    AnnotatedNode(child, k, v) ->
      result.map(bound_node(child, lo, hi), AnnotatedNode(_, k, v))
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

pub fn pattern(
  def: Definition(String),
  p: String,
) -> Result(Definition(String), ConstructionError) {
  let Definition(n, d) = def
  case pattern_valid(p) {
    False -> Error(ConstructionError("invalid regex"))
    True -> result.map(pattern_node(n, p), fn(next) { Definition(next, d) })
  }
}

fn pattern_node(n: Node, p: String) -> Result(Node, ConstructionError) {
  case n {
    StringNode(a, b, ps) ->
      Ok(StringNode(a, b, list.unique(list.append(ps, [p]))))
    AnnotatedNode(c, k, v) ->
      result.map(pattern_node(c, p), AnnotatedNode(_, k, v))
    _ -> Error(ConstructionError("pattern requires string definition"))
  }
}

pub fn validate(
  def: Definition(a),
  value: Value,
) -> Result(Nil, List(DataError)) {
  let Definition(n, _) = def
  // Even an empty array must not make an escaped, rejected placeholder usable.
  let assert Ok(_) = collect_definitions_result([n], [], new_seen(Seen))
    as "Definition contains an unfinalized recursive reference or conflicting names"
  case check(n, value, "") {
    [] -> Ok(Nil)
    errors -> Error(errors)
  }
}

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
      case expected == v {
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

@external(javascript, "./runtime.mjs", "int_text")
fn int_text(n: Int) -> String

pub fn emit_json(def: Definition(a)) -> Value {
  let Definition(n, _) = def
  put(
    emit_with_definitions(n),
    "$schema",
    JString("https://json-schema.org/draft/2020-12/schema"),
  )
}

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

@external(javascript, "./runtime.mjs", "same_reference")
fn same_reference(a: a, b: a) -> Bool

fn node_children(n: Node) -> Result(List(Node), ConstructionError) {
  case n {
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
              let merged = case node, children {
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
    PropertyNamesNode(child, _) -> Ok([child])
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

@external(javascript, "./runtime.mjs", "recursion_guard")
fn new_guard(make: fn(fn(a) -> Int, fn(a) -> Nil) -> Guard(a)) -> Guard(a)

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
  use definitions <- result.try(collect_definitions_result(
    [root],
    [],
    new_seen(Seen),
  ))
  let state = new_guard(Guard)
  list.try_fold(
    [root, ..list.map(definitions, fn(pair) { pair.1 })],
    Nil,
    fn(_, n) { guard_same_input(n, state) },
  )
}

fn collect_definitions(
  n: Node,
  _: List(#(String, Node)),
) -> List(#(String, Node)) {
  let assert Ok(definitions) =
    collect_definitions_result([n], [], new_seen(Seen))
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
