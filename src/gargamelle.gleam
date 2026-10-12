//// Typed JSON decoding and JSON Schema 2020-12 emission from one definition.
////
//// Parse JSON with `parse`, then call `validate` or `decode`. Validation never
//// invokes user converters; decoding invokes them only after structural success.
//// `Contract` adds semantic requirements above a structural definition. Boundaries
//// enforce their stored contract before invoking handlers. `verify` retains
//// original JSON and the accepting contract; semantic requirements decode once.
//// Converters are trusted application code: exceptions are operational failures.
//// JavaScript and Erlang targets are supported on the
//// [tested runtimes](https://hexdocs.pm/gargamelle/0.6.0/native-erlang.html).
//// Explicit typed encoders are provided by `gargamelle/encoding`.
//// The Erlang target requires a separately compiled C regex helper.

import gleam/bit_array
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// An opaque JSON value obtained through `parse` or `schema_json`.
/// Numbers are finite binary64 values; strings and keys contain Unicode scalars.
/// This type is distinct from `gleam/json.Json`; arbitrary runtime objects cannot
/// enter the validation boundary.
pub opaque type Json {
  JNull
  JBool(Bool)
  JNumber(Float)
  JString(String)
  JArray(List(Json))
  JObject(List(#(String, Json)))
}

/// JSON text layout. `Compact` uses canonical JSON; `Pretty` adds two-space
/// indentation without changing numbers, escaping or key order. Neither adds
/// a trailing newline. Empty arrays and objects stay on one line.
pub type JsonFormat {
  Compact
  Pretty
}

/// JSON syntax, nonfinite-number or non-scalar-string admission failure.
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

/// A semantic violation. `path` is a JSON Pointer, empty for the whole input.
/// Locations and messages are supplied by trusted semantic checks.
pub type Violation {
  Violation(path: String, message: String)
}

/// Failures of one semantic requirement, indexed in declaration order.
pub type RequirementFailure {
  RequirementFailure(
    index: Int,
    description: String,
    violations: List(Violation),
  )
}

/// Structural decoding rejection or rejection by semantic requirements.
/// Exceptions and resource failures are operational failures, not these values.
pub type ContractError {
  Structural(List(DataError))
  Semantic(List(RequirementFailure))
}

/// Treatment of undeclared record keys. `Strict` rejects them; `Open` accepts
/// them but omits them from the constructed output.
pub type RecordPolicy {
  Strict
  Open
}

/// Supported asserted formats. Assertions are emitted as ordinary schema
/// constraints as well as format metadata; optional format checking is unnecessary.
pub type FormatAssertion {
  Uuid
}

/// A finite numeric endpoint. Inclusive endpoints accept equality.
pub type NumberBound {
  Inclusive(Float)
  Exclusive(Float)
}

type Identity

type WalkIdentity =
  #(Option(Identity), Identity)

type Bindings =
  List(#(Identity, Node))

type Node {
  IdentifiedNode(Identity, Node)
  BoundNode(Bindings, Node)
  BooleanNode
  NullNode
  StringNode(Option(Int), Option(Int), List(String))
  IntegerNode(Int, Int)
  IntegerMultiplesNode(Node, List(Int))
  NumberNode(Option(NumberBound), Option(NumberBound))
  ConstNode(Json, String)
  EnumNode(List(String))
  ArrayNode(Node, Option(Int), Option(Int))
  TupleNode(List(Node))
  ContainsNode(Node, List(Membership))
  ConditionalNode(Node, List(Condition))
  ExcludeNode(Node, List(Node))
  DictNode(Node, Option(Int), Option(Int))
  RecordNode(List(Field), RecordPolicy)
  PropertyNamesNode(Node, List(Node))
  DependentRequiredNode(Node, List(#(String, List(String))))
  NullableNode(Node)
  UnionNode(List(Node), Bool)
  TaggedNode(String, List(#(String, Node, Option(String))))
  NamedNode(String, Node)
  ReferenceNode(String, Identity)
  UniqueNode(Node)
  AnnotatedNode(Node, String, Json)
}

// Reference bindings are finite immutable schema terms; typed converters live
// in a separate recursion environment. Scoped walk state is temporary only.
// Per-traversal identity tracking avoids rescanning shared/recursive nodes.
type Seen(a) {
  Seen(fn(a) -> Bool)
}

@external(erlang, "gargamelle_runtime", "identity_tracker")
@external(javascript, "./runtime.mjs", "identity_tracker")
fn new_seen(
  make: fn(fn(a) -> Bool) -> Seen(a),
  scope: fn(a) -> Identity,
  key: fn(a) -> Identity,
) -> Seen(a)

fn seen_before(seen: Seen(a), value: a) -> Bool {
  let Seen(visit) = seen
  visit(value)
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
  Default(Json, Evidence)
}

/// A composable acceptance contract and typed conversion under recursion `r`.
/// Only completed definitions, `Plan(a, Nil)`, can be validated, decoded or emitted.
/// Recursive builder references remain construction plans after the builder returns.
pub opaque type Plan(a, r) {
  Plan(Node, fn(r, Json, Evidence) -> a)
}

/// A completed definition, usable for validation, decoding and emission.
pub type Definition(a) =
  Plan(a, Nil)

/// A completed structural definition and additional checks of decoded values.
/// Checks must be deterministic, total and free of side effects, with immutable
/// bound context. They cannot transform the decoded value or the original JSON.
pub opaque type Contract(a) {
  Contract(Definition(a), List(Requirement(a)))
}

type Requirement(a) {
  Requirement(String, fn(a) -> Result(Nil, List(Violation)))
}

/// JSON accepted by the stored full contract, created by `verify`.
/// Semantic requirements cause one decoding pass; no decoded value is retained.
/// Access the JSON and contract with `verified_json` and `verified_contract`.
/// The parameter `a` identifies the definition's output type, not a particular
/// contract or its constraints.
/// Use a receiving boundary to enforce which contract checks a handler's input.
pub opaque type VerifiedJson(a) {
  VerifiedJson(Json, Contract(a))
}

/// A contract and a private handler invoked only after successful decoding and
/// semantic checks. Construct with `boundary`, inspect with `boundary_contract`,
/// and submit JSON with `forward`.
pub opaque type Boundary(a, response) {
  Boundary(Contract(a), fn(a, Json) -> response)
}

/// A contract and a private handler receiving verified JSON. Semantic checks
/// require decoding once; contracts without checks validate without conversion.
/// Construct with `json_boundary`, inspect with `json_boundary_contract`, and
/// submit admitted JSON with `forward_json`.
pub opaque type JsonBoundary(a, response) {
  JsonBoundary(Contract(a), fn(VerifiedJson(a)) -> response)
}

/// The opaque recursion environment supplied to a self-recursive plan.
/// User code cannot construct or execute this environment.
pub opaque type Recursive(a) {
  Recursive(fn(Json, Evidence) -> a)
}

type Evidence {
  Atomic
  Children(List(Evidence))
  Fields(List(#(String, Evidence)))
  Selected(Int, Evidence)
}

@external(erlang, "gargamelle_runtime", "fresh_identity")
@external(javascript, "./runtime.mjs", "fresh_identity")
fn fresh_identity() -> Identity

@external(erlang, "gargamelle_runtime", "with_walk")
@external(javascript, "./runtime.mjs", "with_walk")
fn with_walk(run: fn() -> a) -> a

fn identified(n: Node) -> Node {
  case n {
    IdentifiedNode(_, _) -> n
    _ -> IdentifiedNode(fresh_identity(), n)
  }
}

fn identity(n: Node) -> WalkIdentity {
  scoped_identity(n, None)
}

fn scoped_identity(n: Node, scope: Option(Identity)) -> WalkIdentity {
  case n {
    IdentifiedNode(id, _) -> #(scope, id)
    BoundNode(bindings, child) -> {
      let next = case bindings {
        [] -> None
        [#(id, _), ..] -> Some(id)
      }
      scoped_identity(child, next)
    }
    _ -> panic as "Library node has no identity"
  }
}

// Foreign walk adapters receive primitive identities, not Gleam Option values.
fn node_identity(n: Node) -> Identity {
  identity(n).1
}

fn walk_scope(n: Node) -> Identity {
  let #(scope, id) = identity(n)
  case scope {
    None -> id
    Some(scope) -> scope
  }
}

fn bare(n: Node) -> Node {
  case n {
    IdentifiedNode(_, child) | BoundNode(_, child) -> bare(child)
    _ -> n
  }
}

fn definition(n: Node, convert: fn(r, Json, Evidence) -> a) -> Plan(a, r) {
  Plan(identified(n), convert)
}

/// An unfinished record consuming a curried constructor one field at a time.
pub opaque type Record(a, r) {
  Record(List(Field), fn(r, Json, Evidence) -> a)
}

/// An unfinished exact-length tuple consuming a curried constructor by position.
pub opaque type Tuple(a, r) {
  Tuple(List(Node), fn(r, Json, Evidence) -> a)
}

/// A record branch for `tagged`, with its discriminator supplied automatically.
pub opaque type Variant(a, r) {
  Variant(
    String,
    List(Field),
    RecordPolicy,
    fn(r, Json, Evidence) -> a,
    Option(String),
  )
}

/// Admit JSON text without invoking a definition or converter. Duplicate object
/// keys use the parser’s last value; numeric values use IEEE-754 binary64.
/// String values and object keys must contain only Unicode scalar values.
pub fn parse(text: String) -> Result(Json, AdmissionError) {
  parse_runtime(text, fn() { JNull }, JBool, JNumber, JString, JArray, JObject)
}

// Schema text must inhabit the same String domain as admitted JSON. Constructors
// with Result return ConstructionError; direct constructors assert this precondition.
fn scalar_argument(text: String) -> Result(Nil, ConstructionError) {
  parse(json.to_string(json.string(text)))
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) { ConstructionError("non-scalar string argument") })
}

@external(erlang, "gargamelle_runtime", "parse")
@external(javascript, "./runtime.mjs", "parse")
fn parse_runtime(
  text: String,
  null: fn() -> Json,
  boolean: fn(Bool) -> Json,
  number: fn(Float) -> Json,
  string: fn(String) -> Json,
  array: fn(List(Json)) -> Json,
  object: fn(List(#(String, Json))) -> Json,
) -> Result(Json, AdmissionError)

/// Serialize any admitted JSON value in the chosen layout. Negative zero
/// becomes `0`. `Compact` is canonical; `Pretty` changes only whitespace.
pub fn to_string(value: Json, format: JsonFormat) -> String {
  let compact = canonical(json.to_string(json_value(value)))
  case format {
    Compact -> compact
    Pretty -> {
      let assert Ok(text) =
        pretty_bytes(bit_array.from_string(compact), "", False, False, [])
        |> bit_array.to_string
      text
    }
  }
}

// Walk canonical UTF-8 bytes so combining marks cannot merge a quote with a
// grapheme. Only ASCII punctuation outside strings changes; token bytes survive.
fn pretty_bytes(
  input: BitArray,
  indent: String,
  quoted: Bool,
  escaped: Bool,
  pieces: List(BitArray),
) -> BitArray {
  case input {
    <<>> -> bit_array.concat(list.reverse(pieces))
    <<byte, rest:bits>> -> {
      case quoted {
        True -> {
          let next_quoted = escaped || byte != 34
          let next_escaped = !escaped && byte == 92
          pretty_bytes(rest, indent, next_quoted, next_escaped, [
            <<byte>>,
            ..pieces
          ])
        }
        False ->
          case byte, rest {
            34, _ ->
              pretty_bytes(rest, indent, True, False, [<<byte>>, ..pieces])
            123, <<125, tail:bits>> | 91, <<93, tail:bits>> ->
              pretty_bytes(tail, indent, False, False, [
                <<
                  byte,
                  case byte {
                    123 -> 125
                    _ -> 93
                  },
                >>,
                ..pieces
              ])
            123, _ | 91, _ -> {
              let next = indent <> "  "
              let chunk = <<byte, "\n":utf8, next:utf8>>
              pretty_bytes(rest, next, False, False, [chunk, ..pieces])
            }
            125, _ | 93, _ -> {
              let next = string.drop_end(indent, 2)
              let chunk = <<"\n":utf8, next:utf8, byte>>
              pretty_bytes(rest, next, False, False, [chunk, ..pieces])
            }
            44, _ ->
              pretty_bytes(rest, indent, False, False, [
                <<",\n":utf8, indent:utf8>>,
                ..pieces
              ])
            58, _ ->
              pretty_bytes(rest, indent, False, False, [<<": ":utf8>>, ..pieces])
            _, _ ->
              pretty_bytes(rest, indent, False, False, [<<byte>>, ..pieces])
          }
      }
    }
    _ -> panic as "Canonical JSON contains a partial byte"
  }
}

fn json_value(v: Json) -> json.Json {
  case v {
    JNull -> json.null()
    JBool(b) -> json.bool(b)
    JNumber(n) -> json.float(n)
    JString(s) -> json.string(s)
    JArray(xs) -> json.array(xs, json_value)
    JObject(xs) -> json.object(list.map(xs, fn(p) { #(p.0, json_value(p.1)) }))
  }
}

@external(erlang, "gargamelle_runtime", "canonical")
@external(javascript, "./runtime.mjs", "canonical")
fn canonical(text: String) -> String

@external(erlang, "gargamelle_runtime", "codepoints")
@external(javascript, "./runtime.mjs", "codepoints")
fn codepoints(text: String) -> Int

@external(erlang, "gargamelle_regex", "pattern_valid")
@external(javascript, "./runtime.mjs", "pattern_valid")
fn pattern_valid(text: String) -> Bool

@external(erlang, "gargamelle_regex", "pattern_matches")
@external(javascript, "./runtime.mjs", "pattern_matches")
fn pattern_matches(pattern: String, text: String) -> Bool

@external(erlang, "gargamelle_runtime", "sorted")
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
pub fn boolean() -> Plan(Bool, r) {
  definition(BooleanNode, fn(_, v, _) {
    case v {
      JBool(b) -> b
      _ -> panic as "validated boolean"
    }
  })
}

/// Accept JSON null and decode it to `Nil`.
pub fn null() -> Plan(Nil, r) {
  definition(NullNode, fn(_, _, _) { Nil })
}

/// Accept JSON strings.
pub fn text() -> Plan(String, r) {
  definition(StringNode(None, None, []), fn(_, v, _) {
    case v {
      JString(s) -> s
      _ -> panic as "validated string"
    }
  })
}

/// Accept integral numbers between -9007199254740991 and 9007199254740991.
pub fn safe_integer() -> Plan(Int, r) {
  definition(
    IntegerNode(-9_007_199_254_740_991, 9_007_199_254_740_991),
    fn(_, v, _) {
      case v {
        JNumber(n) -> as_int(n)
        _ -> panic as "validated integer"
      }
    },
  )
}

/// Decode any admitted finite IEEE-754 number to Float, including integers.
/// JSON parsing may round or underflow; decoding preserves the parsed value.
pub fn number() -> Plan(Float, r) {
  definition(NumberNode(None, None), fn(_, v, _) {
    case v {
      JNumber(n) -> n
      _ -> panic as "validated number"
    }
  })
}

/// Require safe-integer inputs divisible by a positive safe-integer divisor.
/// This exact integer policy does not accept fractional divisors or number()
/// definitions. Apply before naming. Repeated constraints intersect.
pub fn integer_multiple_of(
  def: Plan(a, r),
  divisor: Int,
) -> Result(Plan(a, r), ConstructionError) {
  case divisor > 0 && divisor <= 9_007_199_254_740_991 {
    False -> Error(ConstructionError("divisor must be a positive safe integer"))
    True -> {
      let Plan(node, convert) = def
      use next <- result.try(integer_multiple_node(node, divisor))
      Ok(definition(next, convert))
    }
  }
}

fn integer_multiple_node(node: Node, divisor: Int) {
  case node {
    IdentifiedNode(_, child) ->
      result.map(integer_multiple_node(child, divisor), identified)
    BoundNode(bindings, child) ->
      result.map(integer_multiple_node(child, divisor), BoundNode(bindings, _))
    AnnotatedNode(child, key, value) ->
      result.map(integer_multiple_node(child, divisor), AnnotatedNode(
        _,
        key,
        value,
      ))
    IntegerMultiplesNode(child, divisors) ->
      Ok(IntegerMultiplesNode(
        child,
        list.unique(list.append(divisors, [divisor])),
      ))
    IntegerNode(_, _) -> Ok(IntegerMultiplesNode(identified(node), [divisor]))
    _ ->
      Error(ConstructionError(
        "integer_multiple_of requires a safe-integer definition",
      ))
  }
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
  def: Plan(Float, r),
  lower: Option(NumberBound),
  upper: Option(NumberBound),
) -> Result(Plan(Float, r), ConstructionError) {
  case valid_number_bounds(lower, upper) {
    False -> Error(ConstructionError("invalid number bounds"))
    True -> {
      let Plan(n, d) = def
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
    BoundNode(bindings, child) ->
      result.map(number_bound_node(child, lower, upper), BoundNode(bindings, _))
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
) -> Result(Plan(String, r), ConstructionError) {
  use _ <- result.try(
    list.try_fold(values, Nil, fn(_, text) { scalar_argument(text) }),
  )
  case values == [] || list.length(list.unique(values)) != list.length(values) {
    True -> Error(ConstructionError("empty or duplicate enum"))
    False ->
      Ok(
        definition(EnumNode(values), fn(_, v, _) {
          case v {
            JString(s) -> s
            _ -> panic as "validated enum"
          }
        }),
      )
  }
}

/// Accept exactly this string.
pub fn string_constant(v: String) -> Plan(String, r) {
  let assert Ok(_) = scalar_argument(v)
    as "String argument must contain Unicode scalar values"
  definition(ConstNode(JString(v), "string"), fn(_, _, _) { v })
}

/// Accept exactly this boolean.
pub fn boolean_constant(v: Bool) -> Plan(Bool, r) {
  definition(ConstNode(JBool(v), "boolean"), fn(_, _, _) { v })
}

/// Accept exactly null.
pub fn null_constant() -> Plan(Nil, r) {
  definition(ConstNode(JNull, "null"), fn(_, _, _) { Nil })
}

/// Accept exactly this safe integer; reject constants outside the safe range.
pub fn integer_constant(v: Int) -> Result(Plan(Int, r), ConstructionError) {
  case
    v < -9_007_199_254_740_991
    || v > 9_007_199_254_740_991
    || !integer(as_float(v))
  {
    True -> Error(ConstructionError("unsafe integer"))
    False ->
      Ok(
        definition(ConstNode(JNumber(as_float(v)), "integer"), fn(_, _, _) { v }),
      )
  }
}

/// Transform decoded output without changing schema acceptance. The callback
/// runs only during successful decoding and must return the declared output type.
pub fn map(def: Plan(a, r), f: fn(a) -> b) -> Plan(b, r) {
  let Plan(n, d) = def
  definition(n, fn(environment, v, evidence) { f(d(environment, v, evidence)) })
}

/// Accept null as `None`, or decode the child as `Some`. This does not make
/// a record field optional.
pub fn nullable(def: Plan(a, r)) -> Plan(Option(a), r) {
  let Plan(n, d) = def
  definition(NullableNode(n), fn(environment, v, evidence) {
    case v {
      JNull -> None
      _ -> Some(d(environment, v, evidence))
    }
  })
}

/// Accept homogeneous arrays and decode every element in input order.
pub fn array(def: Plan(a, r)) -> Plan(List(a), r) {
  let Plan(n, d) = def
  definition(ArrayNode(n, None, None), fn(environment, v, evidence) {
    case v {
      JArray(xs) -> {
        let assert Children(receipts) = evidence
        list.map(list.zip(xs, receipts), fn(pair) {
          d(environment, pair.0, pair.1)
        })
      }
      _ -> panic as "validated array"
    }
  })
}

/// Start an exact-length positional array with a curried typed constructor.
pub fn tuple(constructor: a) -> Tuple(a, r) {
  Tuple([], fn(_, _, _) { constructor })
}

/// Append one required position, consuming one constructor argument.
pub fn element(t: Tuple(fn(a) -> b, r), child: Plan(a, r)) -> Tuple(b, r) {
  let Tuple(nodes, construct) = t
  let Plan(node, convert) = child
  let index = list.length(nodes)
  Tuple(list.append(nodes, [node]), fn(environment, v, evidence) {
    let assert JArray(values) = v as "validated tuple"
    let assert Ok(value) = list.first(list.drop(values, index))
      as "validated tuple position"
    let assert Children(receipts) = evidence
    let assert Ok(receipt) = list.first(list.drop(receipts, index))
    construct(environment, v, evidence)(convert(environment, value, receipt))
  })
}

/// Close a tuple. Short arrays and extra positions are rejected.
pub fn finish_tuple(t: Tuple(a, r)) -> Plan(a, r) {
  let Tuple(nodes, convert) = t
  definition(TupleNode(nodes), convert)
}

/// Require between minimum and maximum structurally matching array items.
/// Preserve the original decoder; matching-definition converters never run.
pub fn contains(
  def: Plan(a, r),
  matching: Plan(b, r),
  minimum: Int,
  maximum: Option(Int),
) -> Result(Plan(a, r), ConstructionError) {
  let Plan(node, convert) = def
  let Plan(match_node, _) = matching
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
    IdentifiedNode(_, child) | BoundNode(_, child) -> array_node(child)
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
    BoundNode(bindings, child) ->
      result.map(contains_node(child, membership), BoundNode(bindings, _))
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
  def: Plan(a, r),
  condition: Plan(b, r),
  consequence: Plan(c, r),
) -> Plan(a, r) {
  let Plan(probe, _) = condition
  let Plan(yes, _) = consequence
  add_condition(def, Condition(probe, yes, None))
}

/// Validate exactly the selected structural branch, retaining the base decoder.
pub fn if_then_else(
  def: Plan(a, r),
  condition: Plan(b, r),
  consequence: Plan(c, r),
  alternative: Plan(d, r),
) -> Plan(a, r) {
  let Plan(probe, _) = condition
  let Plan(yes, _) = consequence
  let Plan(no, _) = alternative
  add_condition(def, Condition(probe, yes, Some(no)))
}

fn add_condition(def: Plan(a, r), condition: Condition) -> Plan(a, r) {
  let Plan(node, convert) = def
  let next = case bare(node) {
    ConditionalNode(base, checks) ->
      ConditionalNode(base, list.append(checks, [condition]))
    _ -> ConditionalNode(node, [condition])
  }
  definition(next, convert)
}

/// Reject input accepted by a forbidden structural definition.
/// Preserve the base output; forbidden-definition converters never run.
pub fn exclude(def: Plan(a, r), forbidden: Plan(b, r)) -> Plan(a, r) {
  let Plan(node, convert) = def
  let Plan(probe, _) = forbidden
  let next = case bare(node) {
    ExcludeNode(base, checks) -> ExcludeNode(base, list.append(checks, [probe]))
    _ -> ExcludeNode(node, [probe])
  }
  definition(next, convert)
}

/// Accept objects whose values satisfy the child definition. Decode to a Gleam
/// list of key/value pairs, preserving original keys rather than a JS object.
pub fn dictionary(def: Plan(a, r)) -> Plan(List(#(String, a)), r) {
  let Plan(n, d) = def
  definition(DictNode(n, None, None), fn(environment, v, evidence) {
    case v {
      JObject(xs) -> {
        let assert Children(receipts) = evidence
        list.map(list.zip(xs, receipts), fn(pair) {
          #(pair.0.0, d(environment, pair.0.1, pair.1))
        })
      }
      _ -> panic as "validated dictionary"
    }
  })
}

/// Constrain every own object key without changing decoded values or keys.
/// The key definition is used for validation only; its converter never runs.
pub fn property_names(
  def: Plan(a, r),
  keys: Plan(String, r),
) -> Result(Plan(a, r), ConstructionError) {
  let Plan(node, convert) = def
  let Plan(key, _) = keys
  use next <- result.try(property_names_node(node, key))
  Ok(definition(next, convert))
}

fn object_node(node: Node) -> Bool {
  case node {
    IdentifiedNode(_, child) | BoundNode(_, child) -> object_node(child)
    DictNode(_, _, _) | RecordNode(_, _) -> True
    NamedNode(_, child)
    | AnnotatedNode(child, _, _)
    | PropertyNamesNode(child, _)
    | DependentRequiredNode(child, _)
    | ConditionalNode(child, _)
    | ExcludeNode(child, _) -> object_node(child)
    _ -> False
  }
}

/// When `trigger` is present in the original object, require every listed key.
/// Null counts as present; decoded defaults do not create input presence.
/// Repeated rules for the same trigger merge their keys. Duplicate keys are
/// normalized, and empty lists and self-dependencies are allowed.
pub fn dependent_required(
  def: Plan(a, r),
  trigger: String,
  required: List(String),
) -> Result(Plan(a, r), ConstructionError) {
  use _ <- result.try(scalar_argument(trigger))
  use _ <- result.try(list.try_each(required, scalar_argument))
  let Plan(node, convert) = def
  use next <- result.try(dependency_node(node, trigger, list.unique(required)))
  Ok(definition(next, convert))
}

fn dependency_node(node: Node, trigger: String, required: List(String)) {
  case node {
    IdentifiedNode(_, child) ->
      result.map(dependency_node(child, trigger, required), identified)
    BoundNode(bindings, child) ->
      result.map(dependency_node(child, trigger, required), BoundNode(
        bindings,
        _,
      ))
    AnnotatedNode(child, key, value) ->
      result.map(dependency_node(child, trigger, required), AnnotatedNode(
        _,
        key,
        value,
      ))
    DependentRequiredNode(child, rules) -> {
      let existing = result.unwrap(list.key_find(rules, trigger), [])
      Ok(DependentRequiredNode(
        child,
        list.append(list.filter(rules, fn(rule) { rule.0 != trigger }), [
          #(trigger, list.unique(list.append(existing, required))),
        ]),
      ))
    }
    _ ->
      case object_node(node) {
        True ->
          Ok(DependentRequiredNode(identified(node), [#(trigger, required)]))
        False ->
          Error(ConstructionError(
            "dependent_required requires an object definition",
          ))
      }
  }
}

fn property_names_node(
  node: Node,
  key: Node,
) -> Result(Node, ConstructionError) {
  case node {
    IdentifiedNode(_, child) ->
      result.map(property_names_node(child, key), identified)
    BoundNode(bindings, child) ->
      result.map(property_names_node(child, key), BoundNode(bindings, _))
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

/// Compose a completed definition inside a recursive builder.
/// Its converter ignores the builder environment and retains its own recursion.
pub fn lift(def: Definition(a)) -> Plan(a, r) {
  let Plan(node, run) = def
  definition(node, fn(_, value, evidence) { run(Nil, value, evidence) })
}

/// Build a guarded self-recursive definition, running the builder once.
/// The supplied plan can compose inside the builder but cannot be decoded,
/// validated or emitted independently, including after construction completes.
pub fn recursive(
  name: String,
  build: fn(Plan(a, Recursive(a))) ->
    Result(Plan(a, Recursive(a)), ConstructionError),
) -> Result(Definition(a), ConstructionError) {
  use _ <- result.try(case valid_name(name) {
    True -> Ok(Nil)
    False -> Error(ConstructionError("invalid definition name"))
  })
  let reference_id = fresh_identity()
  let self =
    definition(
      ReferenceNode(name, reference_id),
      fn(environment: Recursive(a), value, evidence) {
        let Recursive(run) = environment
        run(value, evidence)
      },
    )
  use body <- result.try(build(self))
  let Plan(schema, run) = body
  let bindings = [#(reference_id, schema)]
  let graph = BoundNode(bindings, identified(ReferenceNode(name, reference_id)))
  use _ <- result.try(guard_graph(graph))
  Ok(Plan(graph, fn(_, value, evidence) { run_self(run, value, evidence) }))
}

fn run_self(run: fn(Recursive(a), Json, Evidence) -> a, value, evidence) -> a {
  run(
    Recursive(fn(child, receipt) { run_self(run, child, receipt) }),
    value,
    evidence,
  )
}

/// Build two guarded recursive definitions with independent output types.
/// Both builder plans share a typed pair environment; return both bodies once.
pub fn recursive_pair(
  first_name: String,
  second_name: String,
  build: fn(
    Plan(a, #(Recursive(a), Recursive(b))),
    Plan(b, #(Recursive(a), Recursive(b))),
  ) ->
    Result(
      #(
        Plan(a, #(Recursive(a), Recursive(b))),
        Plan(b, #(Recursive(a), Recursive(b))),
      ),
      ConstructionError,
    ),
) -> Result(#(Definition(a), Definition(b)), ConstructionError) {
  use _ <- result.try(
    case
      !valid_name(first_name)
      || !valid_name(second_name)
      || first_name == second_name
    {
      True -> Error(ConstructionError("invalid or duplicate recursive names"))
      False -> Ok(Nil)
    },
  )
  let first_id = fresh_identity()
  let second_id = fresh_identity()
  let first =
    definition(
      ReferenceNode(first_name, first_id),
      fn(environment: #(Recursive(a), Recursive(b)), value, evidence) {
        let Recursive(run) = environment.0
        run(value, evidence)
      },
    )
  let second =
    definition(
      ReferenceNode(second_name, second_id),
      fn(environment: #(Recursive(a), Recursive(b)), value, evidence) {
        let Recursive(run) = environment.1
        run(value, evidence)
      },
    )
  use bodies <- result.try(build(first, second))
  let Plan(first_schema, first_run) = bodies.0
  let Plan(second_schema, second_run) = bodies.1
  let bindings = [
    #(first_id, first_schema),
    #(second_id, second_schema),
  ]
  let first_graph =
    BoundNode(bindings, identified(ReferenceNode(first_name, first_id)))
  let second_graph =
    BoundNode(bindings, identified(ReferenceNode(second_name, second_id)))
  use _ <- result.try(guard_graph(first_graph))
  use _ <- result.try(guard_graph(second_graph))
  let runners = #(first_run, second_run)
  Ok(#(
    Plan(first_graph, fn(_, value, evidence) {
      run_first(runners, value, evidence)
    }),
    Plan(second_graph, fn(_, value, evidence) {
      run_second(runners, value, evidence)
    }),
  ))
}

fn run_first(
  runners: #(
    fn(#(Recursive(a), Recursive(b)), Json, Evidence) -> a,
    fn(#(Recursive(a), Recursive(b)), Json, Evidence) -> b,
  ),
  value,
  evidence,
) -> a {
  runners.0(
    #(
      Recursive(fn(child, receipt) { run_first(runners, child, receipt) }),
      Recursive(fn(child, receipt) { run_second(runners, child, receipt) }),
    ),
    value,
    evidence,
  )
}

fn run_second(
  runners: #(
    fn(#(Recursive(a), Recursive(b)), Json, Evidence) -> a,
    fn(#(Recursive(a), Recursive(b)), Json, Evidence) -> b,
  ),
  value,
  evidence,
) -> b {
  runners.1(
    #(
      Recursive(fn(child, receipt) { run_first(runners, child, receipt) }),
      Recursive(fn(child, receipt) { run_second(runners, child, receipt) }),
    ),
    value,
    evidence,
  )
}

// Named definitions reuse finite structures; recursive definitions use explicit
// references whose complete graph is checked before returning to the caller.
/// Name a definition for local `$defs`/`$ref` reuse. Names must start with an
/// ASCII letter and contain only ASCII letters, digits, underscores or hyphens.
/// Conflicting names fail when the composed graph is validated or emitted.
pub fn named(
  name: String,
  def: Plan(a, r),
) -> Result(Plan(a, r), ConstructionError) {
  let Plan(node, convert) = def
  case valid_name(name) {
    True -> Ok(definition(NamedNode(name, node), convert))
    False -> Error(ConstructionError("invalid definition name"))
  }
}

/// Require structurally distinct JSON items in a direct homogeneous array
/// definition. Uniqueness is checked before mapping, not on decoded outputs.
pub fn unique_items(
  def: Plan(List(a), r),
) -> Result(Plan(List(a), r), ConstructionError) {
  let Plan(node, convert) = def
  case bare(node) {
    ArrayNode(_, _, _) -> Ok(definition(UniqueNode(node), convert))
    _ -> Error(ConstructionError("unique_items requires an array definition"))
  }
}

/// Add a schema description without changing validation or decoding.
pub fn description(def: Plan(a, r), s: String) -> Plan(a, r) {
  let assert Ok(_) = scalar_argument(s)
    as "String argument must contain Unicode scalar values"
  let Plan(n, d) = def
  definition(AnnotatedNode(n, "description", JString(s)), d)
}

/// Add a schema title without changing validation or decoding.
pub fn title(def: Plan(a, r), s: String) -> Plan(a, r) {
  let assert Ok(_) = scalar_argument(s)
    as "String argument must contain Unicode scalar values"
  let Plan(n, d) = def
  definition(AnnotatedNode(n, "title", JString(s)), d)
}

/// Attach the JSON Schema `examples` annotation without affecting acceptance or
/// conversion. Examples are admitted JSON, but need not satisfy the definition.
/// A later call replaces an earlier examples annotation at the same schema node.
pub fn examples(def: Plan(a, r), values: List(Json)) -> Plan(a, r) {
  let Plan(node, convert) = def
  definition(AnnotatedNode(node, "examples", JArray(values)), convert)
}

/// Attach a JSON Schema `default` annotation without inserting values during
/// decoding or checking this sample against the definition. `defaulted` is the
/// separate record-field operation for validated defaults applied on absence.
/// A defaulted field's declared default takes precedence over child annotations.
pub fn default(def: Plan(a, r), value: Json) -> Plan(a, r) {
  let Plan(node, convert) = def
  definition(AnnotatedNode(node, "default", value), convert)
}

/// Attach a JSON Schema `format` annotation, such as "email" or "uuid".
/// This does not check the format, change acceptance or invoke converters.
/// Custom names are allowed. Names must contain only Unicode scalar values.
pub fn format(def: Plan(a, r), name: String) -> Plan(a, r) {
  let assert Ok(_) = scalar_argument(name)
    as "String argument must contain Unicode scalar values"
  let Plan(node, convert) = def
  definition(AnnotatedNode(node, "format", JString(name)), convert)
}

/// Assert a supported format on string inputs, preserving the base converter.
/// UUID accepts the 36-character, case-insensitive hexadecimal/dash syntax,
/// including nil UUIDs, without a URN prefix or whitespace. Version/variant bits
/// are not restricted. Nonstrings remain governed by the base definition.
pub fn assert_format(
  def: Plan(a, r),
  assertion: FormatAssertion,
) -> Plan(a, r) {
  case assertion {
    Uuid -> {
      let assert Ok(uuid) =
        pattern(
          text(),
          "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$",
        )
      let assert Ok(uuid) = bounds(uuid, Some(36), Some(36))
      if_then(def, text(), format(uuid, "uuid"))
    }
  }
}

/// Start a record with a curried constructor. Each field consumes one argument;
/// call `finish` after supplying all fields. Multi-argument constructors need currying.
pub fn record(constructor: a) -> Record(a, r) {
  Record([], fn(_, _, _) { constructor })
}

fn add_field(
  r: Record(fn(a) -> b, r),
  name: String,
  child: Plan(a, r),
  presence: Presence,
) -> Result(Record(b, r), ConstructionError) {
  use _ <- result.try(scalar_argument(name))
  let Record(fs, construct) = r
  let Plan(node, convert) = child
  case
    list.any(fs, fn(f) {
      let Field(k, _, _) = f
      k == name
    })
  {
    True -> Error(ConstructionError("duplicate field: " <> name))
    False ->
      Ok(
        Record(
          list.append(fs, [Field(name, node, presence)]),
          fn(environment, v, evidence) {
            let value = case member(v, name), presence {
              Some(x), _ -> x
              None, Default(x, _) -> x
              _, _ -> panic as "validated field"
            }
            let receipt = field_evidence(evidence, name)
            construct(environment, v, evidence)(convert(
              environment,
              value,
              receipt,
            ))
          },
        ),
      )
  }
}

/// Add a required field. Duplicate field names fail construction.
pub fn required(
  r: Record(fn(a) -> b, r),
  name: String,
  child: Plan(a, r),
) -> Result(Record(b, r), ConstructionError) {
  add_field(r, name, child, Required)
}

/// Add a field with an admitted JSON default validated during construction.
/// When absent, decode the default with the child converter. A present invalid
/// value still fails; defaults do not mutate the input or bypass validation.
pub fn defaulted(
  r: Record(fn(a) -> b, r),
  name: String,
  child: Plan(a, r),
  value: Json,
) -> Result(Record(b, r), ConstructionError) {
  use <- with_walk
  let Plan(n, _) = child
  // Defaults are checked during construction. A recursive placeholder cannot
  // yet supply its acceptance contract; reject it rather than invent a value.
  use _ <- result.try(collect_definitions_result(
    [n],
    [],
    new_seen(Seen, walk_scope, node_identity),
  ))
  let inspected = inspect(n, value, "", [])
  case inspected.0 {
    [] -> add_field(r, name, child, Default(value, inspected.1))
    _ -> Error(ConstructionError("invalid default"))
  }
}

/// Add an optional field, consuming an `Option(a)` constructor argument.
/// Absence is `None`; present values must satisfy the child, including null.
pub fn optional(
  r: Record(fn(Option(a)) -> b, r),
  name: String,
  child: Plan(a, r),
) -> Result(Record(b, r), ConstructionError) {
  use _ <- result.try(scalar_argument(name))
  let Record(fs, construct) = r
  let Plan(n, d) = child
  case
    list.any(fs, fn(f) {
      let Field(k, _, _) = f
      k == name
    })
  {
    True -> Error(ConstructionError("duplicate field: " <> name))
    False ->
      Ok(
        Record(
          list.append(fs, [Field(name, n, Optional)]),
          fn(environment, v, evidence) {
            construct(environment, v, evidence)(
              option.map(member(v, name), fn(value) {
                d(environment, value, field_evidence(evidence, name))
              }),
            )
          },
        ),
      )
  }
}

/// Finish a typed record with the chosen undeclared-key policy.
pub fn finish(r: Record(a, r), policy: RecordPolicy) -> Plan(a, r) {
  let Record(fs, d) = r
  definition(RecordNode(fs, policy), d)
}

/// Finish a tagged record branch. Do not declare the discriminator as a field.
pub fn variant(
  tag: String,
  r: Record(a, r),
  policy: RecordPolicy,
) -> Variant(a, r) {
  let assert Ok(_) = scalar_argument(tag)
    as "String argument must contain Unicode scalar values"
  let Record(fs, d) = r
  Variant(tag, fs, policy, d, None)
}

/// Describe a tagged branch without changing its acceptance contract.
pub fn variant_description(v: Variant(a, r), s: String) -> Variant(a, r) {
  let assert Ok(_) = scalar_argument(s)
    as "String argument must contain Unicode scalar values"
  let Variant(t, f, p, d, _) = v
  Variant(t, f, p, d, Some(s))
}

/// Transform a tagged branch’s decoded output without changing its schema.
pub fn variant_map(v: Variant(a, r), f: fn(a) -> b) -> Variant(b, r) {
  let Variant(t, fs, p, d, s) = v
  Variant(
    t,
    fs,
    p,
    fn(environment, x, evidence) { f(d(environment, x, evidence)) },
    s,
  )
}

/// Construct a discriminated union of record variants. Empty lists, duplicate
/// tags and fields redeclaring the discriminator are construction errors.
pub fn tagged(
  discriminator: String,
  variants: List(Variant(a, r)),
) -> Result(Plan(a, r), ConstructionError) {
  use _ <- result.try(scalar_argument(discriminator))
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
      let runners =
        list.map(variants, fn(v) {
          let Variant(tag, _, _, run, _) = v
          #(tag, run)
        })
      Ok(
        definition(
          TaggedNode(discriminator, branches),
          fn(environment, value, evidence) {
            let assert Some(JString(tag)) = member(value, discriminator)
            let assert Ok(run) = list.key_find(runners, tag)
            run(environment, value, evidence)
          },
        ),
      )
    }
  }
}

/// Accept one or more matching branches and decode with the first matching
/// branch in list order. Empty unions fail construction.
pub fn any_of(defs: List(Plan(a, r))) -> Result(Plan(a, r), ConstructionError) {
  union(defs, False)
}

/// Accept exactly one structurally matching branch and decode with it.
/// Overlapping matches are rejected. Empty unions fail construction.
pub fn one_of(defs: List(Plan(a, r))) -> Result(Plan(a, r), ConstructionError) {
  union(defs, True)
}

fn union(
  defs: List(Plan(a, r)),
  exclusive: Bool,
) -> Result(Plan(a, r), ConstructionError) {
  case defs {
    [] -> Error(ConstructionError("empty union"))
    _ -> {
      let nodes =
        list.map(defs, fn(d) {
          let Plan(n, _) = d
          n
        })
      let runners =
        list.map(defs, fn(d) {
          let Plan(_, run) = d
          run
        })
      Ok(
        definition(
          UnionNode(nodes, exclusive),
          fn(environment, value, evidence) {
            let assert Selected(index, receipt) = evidence
            let assert Ok(run) = list.first(list.drop(runners, index))
            run(environment, value, receipt)
          },
        ),
      )
    }
  }
}

fn field_evidence(evidence, name) {
  let assert Fields(fields) = evidence
  let assert Ok(receipt) = list.key_find(fields, name)
  receipt
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
  def: Plan(a, r),
  lower: Option(Int),
  upper: Option(Int),
) -> Result(Plan(a, r), ConstructionError) {
  let Plan(n, d) = def
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
    BoundNode(bindings, child) ->
      result.map(bound_node(child, lo, hi), BoundNode(bindings, _))
    AnnotatedNode(child, k, v) ->
      result.map(bound_node(child, lo, hi), AnnotatedNode(_, k, v))
    ContainsNode(child, checks) ->
      result.map(bound_node(child, lo, hi), ContainsNode(_, checks))
    PropertyNamesNode(child, keys) ->
      result.map(bound_node(child, lo, hi), PropertyNamesNode(_, keys))
    DependentRequiredNode(child, rules) ->
      result.map(bound_node(child, lo, hi), DependentRequiredNode(_, rules))
    IntegerMultiplesNode(child, divisors) ->
      result.map(bound_node(child, lo, hi), IntegerMultiplesNode(_, divisors))
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
  def: Plan(String, r),
  p: String,
) -> Result(Plan(String, r), ConstructionError) {
  use _ <- result.try(scalar_argument(p))
  let Plan(n, d) = def
  case pattern_valid(p) {
    False -> Error(ConstructionError("invalid regex"))
    True -> result.map(pattern_node(n, p), fn(next) { definition(next, d) })
  }
}

fn pattern_node(n: Node, p: String) -> Result(Node, ConstructionError) {
  case n {
    IdentifiedNode(_, child) -> result.map(pattern_node(child, p), identified)
    BoundNode(bindings, child) ->
      result.map(pattern_node(child, p), BoundNode(bindings, _))
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
  value: Json,
) -> Result(Nil, List(DataError)) {
  case inspect_definition(def, value).0 {
    [] -> Ok(Nil)
    errors -> Error(errors)
  }
}

/// Validate the entire input before running typed conversion. Invalid inputs
/// run no converters; exceptions from trusted callbacks propagate.
pub fn decode(def: Definition(a), value: Json) -> Result(a, List(DataError)) {
  let inspected = inspect_definition(def, value)
  case inspected.0 {
    [] -> {
      let Plan(_, run) = def
      Ok(run(Nil, value, inspected.1))
    }
    errors -> Error(errors)
  }
}

/// Wrap a completed definition without adding semantic requirements.
pub fn contract(definition: Definition(a)) -> Contract(a) {
  Contract(definition, [])
}

/// Add a requirement without running it. Checks inspect decoded values, so
/// projected extra fields and distinctions removed by maps are unavailable.
/// Description strings must contain Unicode scalar values.
pub fn require(
  contract: Contract(a),
  description: String,
  check: fn(a) -> Result(Nil, List(Violation)),
) -> Contract(a) {
  let assert Ok(_) = scalar_argument(description)
  let Contract(definition, requirements) = contract
  Contract(
    definition,
    list.append(requirements, [Requirement(description, check)]),
  )
}

/// Return the structural definition. Its schema does not describe arbitrary
/// semantic requirements and is not sufficient to establish contract acceptance.
pub fn contract_definition(contract: Contract(a)) -> Definition(a) {
  let Contract(definition, _) = contract
  definition
}

/// Return every requirement description in declaration order, without callbacks.
pub fn contract_requirements(contract: Contract(a)) -> List(String) {
  let Contract(_, requirements) = contract
  list.map(requirements, fn(requirement) {
    let Requirement(description, _) = requirement
    description
  })
}

fn check_requirements(requirements: List(Requirement(a)), data: a) {
  requirements
  |> list.index_map(fn(requirement, index) {
    let Requirement(description, check) = requirement
    case check(data) {
      Ok(Nil) -> []
      Error(violations) -> {
        let violations = case violations {
          [] -> [Violation("", "Requirement rejected without a diagnostic")]
          _ -> violations
        }
        [RequirementFailure(index, description, violations)]
      }
    }
  })
  |> list.flatten
  |> fn(failures) {
    case failures {
      [] -> Ok(Nil)
      _ -> Error(Semantic(failures))
    }
  }
}

/// Decode once, then run each semantic requirement once in declaration order.
/// Structural rejection skips all checks. Semantic failures are collected;
/// exceptions propagate and may prevent later checks from running.
pub fn decode_contract(
  contract: Contract(a),
  json: Json,
) -> Result(a, ContractError) {
  let Contract(definition, requirements) = contract
  use data <- result.try(
    decode(definition, json) |> result.map_error(Structural),
  )
  use _ <- result.try(check_requirements(requirements, data))
  Ok(data)
}

/// Check contract acceptance. A contract without semantic requirements validates
/// without conversion; otherwise decoding occurs once to supply the checks.
pub fn validate_contract(
  contract: Contract(a),
  json: Json,
) -> Result(Nil, ContractError) {
  let Contract(definition, requirements) = contract
  case requirements {
    [] -> validate(definition, json) |> result.map_error(Structural)
    _ -> decode_contract(contract, json) |> result.map(fn(_) { Nil })
  }
}

/// Bind a handler to its authoritative contract. Construction runs no callbacks.
pub fn boundary(
  contract: Contract(a),
  handler: fn(a, Json) -> response,
) -> Boundary(a, response) {
  Boundary(contract, handler)
}

/// Return the receiving contract without exposing its handler.
pub fn boundary_contract(boundary: Boundary(a, response)) -> Contract(a) {
  let Boundary(contract, _) = boundary
  contract
}

/// Return the receiving contract's structural definition for schema generation.
pub fn boundary_definition(boundary: Boundary(a, response)) -> Definition(a) {
  contract_definition(boundary_contract(boundary))
}

/// Decode and check the stored contract once, then invoke the handler once.
/// Rejection invokes no handler. Callback exceptions propagate operationally.
/// A Result response remains nested; output is not checked.
pub fn forward(
  boundary: Boundary(a, response),
  json: Json,
) -> Result(response, ContractError) {
  let Boundary(contract, handler) = boundary
  use data <- result.try(decode_contract(contract, json))
  Ok(handler(data, json))
}

/// Bind a JSON receiving handler to its authoritative contract.
pub fn json_boundary(
  contract: Contract(a),
  handler: fn(VerifiedJson(a)) -> response,
) -> JsonBoundary(a, response) {
  JsonBoundary(contract, handler)
}

/// Return the receiving contract without exposing its handler.
pub fn json_boundary_contract(
  boundary: JsonBoundary(a, response),
) -> Contract(a) {
  let JsonBoundary(contract, _) = boundary
  contract
}

/// Return the receiving contract's structural definition for schema generation.
pub fn json_boundary_definition(
  boundary: JsonBoundary(a, response),
) -> Definition(a) {
  contract_definition(json_boundary_contract(boundary))
}

/// Verify the stored contract once, then invoke the handler once. Semantic
/// requirements cause one decoding pass; without them no converter runs.
/// Admission and application policy are separate. Certificates from other
/// contracts cannot bypass this check. Exceptions propagate operationally.
pub fn forward_json(
  boundary: JsonBoundary(a, response),
  json: Json,
) -> Result(response, ContractError) {
  let JsonBoundary(contract, handler) = boundary
  use verified <- result.try(verify(contract, json))
  Ok(handler(verified))
}

/// Verify a full contract and retain original JSON and that exact contract.
/// No decoded value is retained. Semantic checks require decoding once;
/// contracts without them validate without conversion.
pub fn verify(
  contract: Contract(a),
  json: Json,
) -> Result(VerifiedJson(a), ContractError) {
  use _ <- result.try(validate_contract(contract, json))
  Ok(VerifiedJson(json, contract))
}

/// Return original admitted JSON without validation, decoding or serialization.
pub fn verified_json(verified: VerifiedJson(a)) -> Json {
  let VerifiedJson(json, _) = verified
  json
}

/// Return the exact contract, including checks and captured context, that accepted
/// the stored JSON. The output type parameter alone does not identify guarantees.
pub fn verified_contract(verified: VerifiedJson(a)) -> Contract(a) {
  let VerifiedJson(_, contract) = verified
  contract
}

/// Return the checked contract's underlying structural definition.
pub fn verified_definition(verified: VerifiedJson(a)) -> Definition(a) {
  contract_definition(verified_contract(verified))
}

fn inspect_definition(def: Definition(a), value: Json) {
  with_walk(fn() {
    let Plan(n, _) = def
    let assert Ok(_) =
      collect_definitions_result(
        [n],
        [],
        new_seen(Seen, walk_scope, node_identity),
      )
      as "Definition contains an unfinalized recursive reference or conflicting names"
    inspect(n, value, "", [])
  })
}

fn member(v: Json, k: String) -> Option(Json) {
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

fn atomic(errors: List(DataError)) {
  #(errors, Atomic)
}

fn inspected_children(outcomes: List(#(List(DataError), Evidence))) {
  #(
    list.flat_map(outcomes, fn(pair) { pair.0 }),
    Children(list.map(outcomes, fn(pair) { pair.1 })),
  )
}

fn with_errors(base: #(List(DataError), Evidence), errors: List(DataError)) {
  #(list.append(base.0, errors), base.1)
}

fn inspect(
  n: Node,
  v: Json,
  p: String,
  bindings: Bindings,
) -> #(List(DataError), Evidence) {
  case n, v {
    IdentifiedNode(_, child), _ -> inspect(child, v, p, bindings)
    BoundNode(local, child), _ -> inspect(child, v, p, local)
    ReferenceNode(_, id), _ -> {
      let assert Ok(child) = list.key_find(bindings, id)
        as "Recursive definition is not finalized"
      inspect(child, v, p, bindings)
    }
    NamedNode(_, child), _ | AnnotatedNode(child, _, _), _ ->
      inspect(child, v, p, bindings)
    UniqueNode(child), JArray(xs) -> {
      let base = inspect(child, v, p, bindings)
      let values = list.map(xs, fn(value) { to_string(value, Compact) })
      with_errors(
        base,
        case list.length(list.unique(values)) == list.length(values) {
          True -> []
          False -> err("duplicate_items", p)
        },
      )
    }
    UniqueNode(child), _ -> inspect(child, v, p, bindings)
    BooleanNode, JBool(_) | NullNode, JNull -> atomic([])
    StringNode(lo, hi, patterns), JString(s) ->
      atomic(
        case
          codepoints(s) |> size_ok(lo, hi)
          && list.all(patterns, pattern_matches(_, s))
        {
          True -> []
          False -> err("string_constraint", p)
        },
      )
    IntegerNode(lo, hi), JNumber(x) ->
      atomic(case integer(x) && x >=. as_float(lo) && x <=. as_float(hi) {
        True -> []
        False -> err("integer_constraint", p)
      })
    IntegerMultiplesNode(child, divisors), _ -> {
      let outcome = inspect(child, v, p, bindings)
      case v, outcome.0 {
        JNumber(x), [] ->
          with_errors(
            outcome,
            case list.all(divisors, fn(divisor) { as_int(x) % divisor == 0 }) {
              True -> []
              False -> err("integer_multiple_of", p)
            },
          )
        _, _ -> outcome
      }
    }
    NumberNode(lo, hi), JNumber(x) ->
      atomic(case number_ok(x, lo, hi) {
        True -> []
        False -> err("number_constraint", p)
      })
    ConstNode(expected, _), _ ->
      atomic(case constant_equal(expected, v) {
        True -> []
        False -> err("constant", p)
      })
    EnumNode(values), JString(s) ->
      atomic(case list.contains(values, s) {
        True -> []
        False -> err("enum", p)
      })
    ArrayNode(child, lo, hi), JArray(xs) ->
      case size_ok(list.length(xs), lo, hi) {
        False -> atomic(err("array_size", p))
        True ->
          list.index_map(xs, fn(x, i) {
            inspect(child, x, path(p, int_text(i)), bindings)
          })
          |> inspected_children
      }
    ExcludeNode(base, checks), _ -> {
      let outcome = inspect(base, v, p, bindings)
      with_errors(
        outcome,
        list.flat_map(checks, fn(probe) {
          case inspect(probe, v, "", bindings).0 == [] {
            True -> err("excluded", p)
            False -> []
          }
        }),
      )
    }
    ConditionalNode(base, checks), _ -> {
      let outcome = inspect(base, v, p, bindings)
      with_errors(
        outcome,
        list.flat_map(checks, fn(condition) {
          let Condition(probe, yes, no) = condition
          case inspect(probe, v, "", bindings).0 == [] {
            True -> inspect(yes, v, p, bindings).0
            False ->
              case no {
                Some(alternative) -> inspect(alternative, v, p, bindings).0
                None -> []
              }
          }
        }),
      )
    }
    DependentRequiredNode(child, rules), _ -> {
      let outcome = inspect(child, v, p, bindings)
      with_errors(outcome, case v {
        JObject(_) ->
          list.flat_map(rules, fn(rule) {
            case member(v, rule.0) {
              None -> []
              Some(_) ->
                list.filter_map(rule.1, fn(name) {
                  case member(v, name) {
                    Some(_) -> Error(Nil)
                    None ->
                      Ok(DataError("dependent_required", p, Some(name), [], []))
                  }
                })
            }
          })
        _ -> []
      })
    }
    ContainsNode(child, checks), _ -> {
      let outcome = inspect(child, v, p, bindings)
      case v {
        JArray(items) ->
          with_errors(
            outcome,
            list.flat_map(checks, fn(membership) {
              let Membership(matching, minimum, maximum) = membership
              case minimum, maximum {
                0, None -> []
                _, _ -> {
                  let count =
                    list.count(items, fn(item) {
                      inspect(matching, item, "", bindings).0 == []
                    })
                  case size_ok(count, Some(minimum), maximum) {
                    True -> []
                    False -> err("contains_count", p)
                  }
                }
              }
            }),
          )
        _ -> outcome
      }
    }
    PropertyNamesNode(child, keys), _ -> {
      let outcome = inspect(child, v, p, bindings)
      case v {
        JObject(entries) ->
          with_errors(
            outcome,
            list.flat_map(entries, fn(pair) {
              list.flat_map(keys, fn(key) {
                inspect(key, JString(pair.0), path(p, pair.0), bindings).0
              })
            }),
          )
        _ -> outcome
      }
    }
    TupleNode(children), JArray(xs) ->
      case list.length(children) == list.length(xs) {
        False -> atomic(err("tuple_size", p))
        True ->
          list.zip(children, xs)
          |> list.index_map(fn(pair, i) {
            inspect(pair.0, pair.1, path(p, int_text(i)), bindings)
          })
          |> inspected_children
      }
    DictNode(child, lo, hi), JObject(xs) ->
      case size_ok(list.length(xs), lo, hi) {
        False -> atomic(err("property_count", p))
        True ->
          list.map(xs, fn(x) { inspect(child, x.1, path(p, x.0), bindings) })
          |> inspected_children
      }
    RecordNode(fs, policy), JObject(xs) -> {
      let outcomes =
        list.map(fs, fn(f) {
          let Field(k, child, presence) = f
          let outcome = case member(v, k), presence {
            Some(x), _ -> inspect(child, x, path(p, k), bindings)
            None, Required ->
              atomic([DataError("missing_required", p, Some(k), [], [])])
            None, Default(_, receipt) -> #([], receipt)
            None, Optional -> atomic([])
          }
          #(outcome.0, #(k, outcome.1))
        })
      let extras = case policy {
        Open -> []
        Strict ->
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
      #(
        list.append(list.flat_map(outcomes, fn(pair) { pair.0 }), extras),
        Fields(list.map(outcomes, fn(pair) { pair.1 })),
      )
    }
    NullableNode(_), JNull -> atomic([])
    NullableNode(child), _ -> inspect(child, v, p, bindings)
    UnionNode(children, exclusive), _ -> {
      let outcomes =
        list.index_map(children, fn(c, i) { #(i, inspect(c, v, p, bindings)) })
      let matches =
        list.filter_map(outcomes, fn(x) {
          case x.1.0 {
            [] -> Ok(x.0)
            _ -> Error(Nil)
          }
        })
      case matches {
        [] ->
          atomic([
            DataError(
              "union_no_match",
              p,
              None,
              list.map(outcomes, fn(pair) { #(pair.0, pair.1.0) }),
              [],
            ),
          ])
        [index, ..rest] ->
          case exclusive && rest != [] {
            True ->
              atomic([DataError("one_of_ambiguous", p, None, [], matches)])
            False -> {
              let assert Ok(outcome) = list.first(list.drop(outcomes, index))
              #([], Selected(index, outcome.1.1))
            }
          }
      }
    }
    TaggedNode(k, branches), JObject(_) ->
      case member(v, k) {
        None -> atomic([DataError("missing_required", p, Some(k), [], [])])
        Some(JString(tag)) ->
          case list.find(branches, fn(b) { b.0 == tag }) {
            Error(_) -> atomic(err("unknown_discriminator", path(p, k)))
            Ok(#(_, child, _)) -> inspect(child, v, p, bindings)
          }
        Some(_) -> atomic(err("discriminator_type", path(p, k)))
      }
    RecordNode(_, _), _ | DictNode(_, _, _), _ | TaggedNode(_, _), _ ->
      atomic(err("object_type", p))
    BooleanNode, _ -> atomic(err("boolean_type", p))
    NullNode, _ -> atomic(err("null_type", p))
    StringNode(_, _, _), _ | EnumNode(_), _ -> atomic(err("string_type", p))
    IntegerNode(_, _), _ -> atomic(err("integer_type", p))
    NumberNode(_, _), _ -> atomic(err("number_type", p))
    TupleNode(_), _ -> atomic(err("tuple_type", p))
    ArrayNode(_, _, _), _ -> atomic(err("array_type", p))
  }
}

// Numeric equality must identify both zero signs on every target. OTP's exact
// term equality distinguishes them, whereas JSON Schema equality does not.
fn constant_equal(a: Json, b: Json) -> Bool {
  case a, b {
    JNumber(x), JNumber(y) -> x >=. y && x <=. y
    _, _ -> a == b
  }
}

@external(erlang, "gargamelle_runtime", "int_text")
@external(javascript, "./runtime.mjs", "int_text")
fn int_text(n: Int) -> String

/// Return a JSON Schema 2020-12 document as Gargamelle’s opaque `Json`, not
/// `gleam/json.Json`. Unfinished or conflicting reference graphs fail operationally.
pub fn schema_json(def: Definition(a)) -> Json {
  with_walk(fn() {
    let Plan(n, _) = def
    put(
      emit_with_definitions(n),
      "$schema",
      JString("https://json-schema.org/draft/2020-12/schema"),
    )
  })
}

/// Return a JSON Schema 2020-12 string in the chosen layout, including local references.
pub fn schema_string(def: Definition(a), format: JsonFormat) -> String {
  to_string(schema_json(def), format)
}

fn put(v: Json, k: String, x: Json) -> Json {
  let assert JObject(xs) = v
  JObject(list.append(list.filter(xs, fn(p) { p.0 != k }), [#(k, x)]))
}

// Object modifiers may be separated by other wrappers. Preserve earlier
// assertions and any existing conjunction instead of replacing a keyword.
fn conjoin_object_keyword(schema: Json, key: String, value: Json) -> Json {
  let assert JObject(fields) = schema
  case list.key_find(fields, key) {
    Error(_) -> schema |> put("type", JString("object")) |> put(key, value)
    Ok(_) -> {
      let clauses = case list.key_find(fields, "allOf") {
        Ok(JArray(clauses)) -> clauses
        _ -> []
      }
      put(
        schema,
        "allOf",
        JArray(list.append(clauses, [typ("object") |> put(key, value)])),
      )
    }
  }
}

fn obj(xs: List(#(String, Json))) -> Json {
  JObject(xs)
}

fn typ(t: String) -> Json {
  obj([#("type", JString(t))])
}

fn emit_bound(v: Json, k: String, b: Option(Int)) -> Json {
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
    BoundNode(bindings, child) -> node_children_in(child, bindings)
    ReferenceNode(name, _) ->
      Error(ConstructionError("unfinalized recursive reference: " <> name))
    NamedNode(_, child)
    | ArrayNode(child, _, _)
    | DictNode(child, _, _)
    | NullableNode(child)
    | AnnotatedNode(child, _, _)
    | DependentRequiredNode(child, _)
    | IntegerMultiplesNode(child, _)
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

fn node_children_in(
  n: Node,
  bindings: Bindings,
) -> Result(List(Node), ConstructionError) {
  case n {
    IdentifiedNode(_, child) -> node_children_in(child, bindings)
    BoundNode(local, child) -> node_children_in(child, local)
    ReferenceNode(name, id) ->
      list.key_find(bindings, id)
      |> result.map(fn(child) { [BoundNode(bindings, child)] })
      |> result.map_error(fn(_) {
        ConstructionError("unfinalized recursive reference: " <> name)
      })
    _ ->
      node_children(n)
      |> result.map(fn(children) { list.map(children, BoundNode(bindings, _)) })
  }
}

fn same_input_children_in(
  n: Node,
  bindings: Bindings,
) -> Result(List(Node), ConstructionError) {
  case n {
    IdentifiedNode(_, child) -> same_input_children_in(child, bindings)
    BoundNode(local, child) -> same_input_children_in(child, local)
    ContainsNode(child, _)
    | PropertyNamesNode(child, _)
    | DependentRequiredNode(child, _) -> Ok([BoundNode(bindings, child)])
    ArrayNode(_, _, _) | TupleNode(_) | DictNode(_, _, _) | RecordNode(_, _) ->
      Ok([])
    _ -> node_children_in(n, bindings)
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
        || to_string(emit(existing), Compact) == to_string(emit(child), Compact)
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
    BoundNode(bindings, child) -> same_input_children_in(child, bindings)
    ContainsNode(child, _)
    | PropertyNamesNode(child, _)
    | DependentRequiredNode(child, _) -> Ok([child])
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
  scope: fn(a) -> Identity,
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
      new_seen(Seen, walk_scope, node_identity),
    ))
    let state = new_guard(Guard, walk_scope, node_identity)
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
    collect_definitions_result(
      [n],
      [],
      new_seen(Seen, walk_scope, node_identity),
    )
    as "Conflicting named schema definitions or unfinalized recursive reference"
  definitions
}

fn emit_with_definitions(n: Node) -> Json {
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
  schema: Json,
  bound: Option(NumberBound),
  inclusive_key: String,
  exclusive_key: String,
) -> Json {
  case bound {
    None -> schema
    Some(Inclusive(x)) -> put(schema, inclusive_key, JNumber(x))
    Some(Exclusive(x)) -> put(schema, exclusive_key, JNumber(x))
  }
}

fn emit(n: Node) -> Json {
  case n {
    IdentifiedNode(_, child) -> emit(child)
    BoundNode(_, child) -> emit(child)
    NamedNode(name, _) | ReferenceNode(name, _) ->
      obj([#("$ref", JString("#/$defs/" <> name))])
    UniqueNode(c) -> put(emit(c), "uniqueItems", JBool(True))
    IntegerMultiplesNode(child, divisors) -> {
      let assert [first, ..rest] = divisors
      let schema = put(emit(child), "multipleOf", JNumber(as_float(first)))
      case rest {
        [] -> schema
        _ ->
          put(
            schema,
            "allOf",
            JArray(
              list.map(rest, fn(divisor) {
                obj([#("multipleOf", JNumber(as_float(divisor)))])
              }),
            ),
          )
      }
    }
    DependentRequiredNode(child, rules) ->
      conjoin_object_keyword(
        emit(child),
        "dependentRequired",
        obj(
          list.map(rules, fn(rule) {
            #(rule.0, JArray(list.map(rule.1, JString)))
          }),
        ),
      )
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
      conjoin_object_keyword(emit(child), "propertyNames", key_schema)
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
            Default(v, _) -> put(emit(c), "default", v)
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
    AnnotatedNode(c, k, v) -> put(emit(c), k, v)
  }
}
