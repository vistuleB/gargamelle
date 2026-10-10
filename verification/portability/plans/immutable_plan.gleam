// Isolated design experiment. Not part of Gargamelle's public API.
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Value {
  Null
  Text(String)
  Boolean(Bool)
  Array(List(Value))
  Object(List(#(String, Value)))
}

type Identity

@external(erlang, "plan_support", "fresh_identity")
@external(javascript, "./plan_support.mjs", "fresh_identity")
fn fresh_identity() -> Identity

type Bindings =
  List(#(Identity, #(String, Schema)))

type Schema {
  Identified(Identity, Schema)
  NullSchema
  ConstantString(String)
  NullableSchema(Schema)
  DictionarySchema(Schema)
  AnnotatedSchema(Schema, String)
  ArrayLimits(Int, Int)
  StringSchema
  BooleanSchema
  ArraySchema(Schema)
  RecordSchema(List(Field), Policy)
  TupleSchema(List(Schema))
  UnionSchema(List(Schema))
  AllSchema(Schema, List(Schema))
  Reference(Identity, String)
  Graph(Schema, Bindings)
}

pub type Policy {
  Closed
  Open
}

type Presence {
  Required
  Optional
  Default(Value)
}

type Field {
  Field(String, Schema, Presence)
}

pub opaque type Record(a, environment) {
  Record(List(Field), fn(Environment(environment), Value) -> a)
}

pub opaque type Tuple(a, environment) {
  Tuple(List(Schema), fn(Environment(environment), Value) -> a)
}

pub opaque type Plan(a, environment) {
  Plan(Schema, fn(Environment(environment), Value) -> a)
}

pub opaque type Definition(a) {
  Definition(Schema, fn(Value) -> a)
}

fn identified(schema: Schema) -> Schema {
  case schema {
    Identified(_, _) -> schema
    _ -> Identified(fresh_identity(), schema)
  }
}

fn make_plan(schema, convert) {
  Plan(identified(schema), convert)
}

pub opaque type Variant(a, recursion) {
  Variant(String, List(Field), Policy, fn(Environment(recursion), Value) -> a)
}

pub fn nullable(plan: Plan(a, recursion)) -> Plan(Option(a), recursion) {
  let Plan(schema, convert) = plan
  make_plan(NullableSchema(schema), fn(environment, value) {
    case value {
      Null -> None
      _ -> Some(convert(environment, value))
    }
  })
}

pub fn dictionary(
  plan: Plan(a, recursion),
) -> Plan(List(#(String, a)), recursion) {
  let Plan(schema, convert) = plan
  make_plan(DictionarySchema(schema), fn(environment, value) {
    let assert Object(properties) = value
    list.map(properties, fn(property) {
      #(property.0, convert(environment, property.1))
    })
  })
}

pub fn describe(
  plan: Plan(a, recursion),
  description: String,
) -> Plan(a, recursion) {
  let Plan(schema, convert) = plan
  make_plan(AnnotatedSchema(schema, description), convert)
}

pub fn array_limits(
  plan: Plan(List(a), recursion),
  minimum: Int,
  maximum: Int,
) -> Result(Plan(List(a), recursion), String) {
  case minimum < 0 || maximum < minimum {
    True -> Error("invalid array limits")
    False -> {
      let Plan(schema, convert) = plan
      Ok(make_plan(AllSchema(schema, [ArrayLimits(minimum, maximum)]), convert))
    }
  }
}

pub fn variant(
  tag: String,
  record: Record(a, recursion),
  policy: Policy,
) -> Variant(a, recursion) {
  let Record(fields, convert) = record
  Variant(tag, fields, policy, convert)
}

pub fn tagged(
  discriminator: String,
  variants: List(Variant(a, recursion)),
) -> Result(Plan(a, recursion), String) {
  use plans <- result.try(
    list.try_fold(variants, [], fn(plans, variant) {
      let Variant(tag, fields, policy, convert) = variant
      use _ <- result.try(unique_field(fields, discriminator))
      use _ <- result.try(
        case
          list.length(
            list.filter(variants, fn(other) {
              let Variant(other_tag, _, _, _) = other
              other_tag == tag
            }),
          )
          > 1
        {
          True -> Error("duplicate tag")
          False -> Ok(Nil)
        },
      )
      Ok(
        list.append(plans, [
          make_plan(
            RecordSchema(
              [Field(discriminator, ConstantString(tag), Required), ..fields],
              policy,
            ),
            convert,
          ),
        ]),
      )
    }),
  )
  any_of(plans)
}

pub fn text() -> Plan(String, environment) {
  make_plan(StringSchema, fn(_, value) {
    let assert Text(text) = value
    text
  })
}

pub fn boolean() -> Plan(Bool, environment) {
  make_plan(BooleanSchema, fn(_, value) {
    let assert Boolean(boolean) = value
    boolean
  })
}

pub fn map(
  plan: Plan(a, environment),
  convert: fn(a) -> b,
) -> Plan(b, environment) {
  let Plan(schema, run) = plan
  make_plan(schema, fn(environment, value) { convert(run(environment, value)) })
}

pub fn array(plan: Plan(a, environment)) -> Plan(List(a), environment) {
  let Plan(schema, run) = plan
  make_plan(ArraySchema(schema), fn(environment, value) {
    let assert Array(values) = value
    list.map(values, run(environment, _))
  })
}

pub fn field(name: String, plan: Plan(a, environment)) -> Plan(a, environment) {
  let assert Ok(record) = required(record(fn(value) { value }), name, plan)
  finish_record(record, Closed)
}

pub fn defaulted(
  name: String,
  plan: Plan(a, environment),
  default: Value,
) -> Result(Plan(a, environment), String) {
  use record <- result.try(default_field(
    record(fn(value) { value }),
    name,
    plan,
    default,
  ))
  Ok(finish_record(record, Closed))
}

pub fn record(constructor: a) -> Record(a, environment) {
  Record([], fn(_, _) { constructor })
}

fn unique_field(fields, name) -> Result(Nil, String) {
  case
    list.any(fields, fn(field) {
      let Field(key, _, _) = field
      key == name
    })
  {
    True -> Error("duplicate field")
    False -> Ok(Nil)
  }
}

pub fn required(
  record: Record(fn(a) -> b, environment),
  name: String,
  child: Plan(a, environment),
) -> Result(Record(b, environment), String) {
  let Record(fields, construct) = record
  use _ <- result.try(unique_field(fields, name))
  let Plan(schema, convert) = child
  Ok(
    Record(
      list.append(fields, [Field(name, schema, Required)]),
      fn(environment, value) {
        let assert Object(properties) = value
        let assert Ok(child) = list.key_find(properties, name)
        construct(environment, value)(convert(environment, child))
      },
    ),
  )
}

pub fn optional(
  record: Record(fn(Option(a)) -> b, environment),
  name: String,
  child: Plan(a, environment),
) -> Result(Record(b, environment), String) {
  let Record(fields, construct) = record
  use _ <- result.try(unique_field(fields, name))
  let Plan(schema, convert) = child
  Ok(
    Record(
      list.append(fields, [Field(name, schema, Optional)]),
      fn(environment, value) {
        let assert Object(properties) = value
        let decoded = case list.key_find(properties, name) {
          Error(_) -> None
          Ok(child) -> Some(convert(environment, child))
        }
        construct(environment, value)(decoded)
      },
    ),
  )
}

pub fn default_field(
  record: Record(fn(a) -> b, environment),
  name: String,
  child: Plan(a, environment),
  default: Value,
) -> Result(Record(b, environment), String) {
  let Record(fields, construct) = record
  use _ <- result.try(unique_field(fields, name))
  let Plan(schema, convert) = child
  use _ <- result.try(resolved(schema, [], []))
  use _ <- result.try(check(schema, default, []))
  Ok(
    Record(
      list.append(fields, [Field(name, schema, Default(default))]),
      fn(environment, value) {
        let assert Object(properties) = value
        let child = result.unwrap(list.key_find(properties, name), default)
        construct(environment, value)(convert(environment, child))
      },
    ),
  )
}

pub fn finish_record(
  record: Record(a, environment),
  policy: Policy,
) -> Plan(a, environment) {
  let Record(fields, convert) = record
  make_plan(RecordSchema(fields, policy), convert)
}

pub fn tuple(constructor: a) -> Tuple(a, environment) {
  Tuple([], fn(_, _) { constructor })
}

pub fn item(
  tuple: Tuple(fn(a) -> b, environment),
  child: Plan(a, environment),
) -> Tuple(b, environment) {
  let Tuple(items, construct) = tuple
  let Plan(schema, convert) = child
  let index = list.length(items)
  Tuple(list.append(items, [schema]), fn(environment, value) {
    let assert Array(values) = value
    let assert Ok(child) = values |> list.drop(index) |> list.first
    construct(environment, value)(convert(environment, child))
  })
}

pub fn finish_tuple(tuple: Tuple(a, environment)) -> Plan(a, environment) {
  let Tuple(items, convert) = tuple
  make_plan(TupleSchema(items), convert)
}

pub fn any_of(
  plans: List(Plan(a, recursion)),
) -> Result(Plan(a, recursion), String) {
  case plans {
    [] -> Error("empty union")
    _ ->
      Ok(
        make_plan(
          UnionSchema(
            list.map(plans, fn(plan) {
              let Plan(schema, _) = plan
              schema
            }),
          ),
          fn(environment, value) { choose(plans, environment, value) },
        ),
      )
  }
}

fn choose(
  plans: List(Plan(a, recursion)),
  environment: Environment(recursion),
  value: Value,
) -> a {
  let assert [Plan(schema, run), ..rest] = plans
  // The schema environment is supplied by the closed runner below. This
  // requires it explicitly, rather than consulting process-local state.
  case check(schema, value, environment_schema(environment)) {
    Ok(_) -> run(environment, value)
    Error(_) -> choose(rest, environment, value)
  }
}

// Every converter environment carries a schema lookup plus typed recursion.
// This alias keeps references explicit and avoids heterogeneous converter maps.
type Environment(recursion) =
  #(Bindings, recursion)

fn environment_schema(environment: Environment(recursion)) {
  environment.0
}

pub fn requiring(
  base: Plan(a, environment),
  rules: List(Plan(b, environment)),
) -> Plan(a, environment) {
  let Plan(schema, run) = base
  make_plan(
    AllSchema(
      schema,
      list.map(rules, fn(rule) {
        let Plan(schema, _) = rule
        schema
      }),
    ),
    run,
  )
}

pub fn lift(definition: Definition(a)) -> Plan(a, environment) {
  let Definition(schema, run) = definition
  make_plan(schema, fn(_, value) { run(value) })
}

pub fn finish(plan: Plan(a, Nil)) -> Definition(a) {
  let Plan(schema, run) = plan
  Definition(schema, run(#([], Nil), _))
}

pub fn recursive(
  name: String,
  build: fn(Plan(a, fn(Value) -> a)) -> Result(Plan(a, fn(Value) -> a), String),
) -> Result(Definition(a), String) {
  let reference_id = fresh_identity()
  let self =
    make_plan(
      Reference(reference_id, name),
      fn(environment: Environment(fn(Value) -> a), value) {
        environment.1(value)
      },
    )
  use body <- result.try(build(self))
  let Plan(schema, _) = body
  let bindings = [#(reference_id, #(name, schema))]
  let graph = identified(Graph(Reference(reference_id, name), bindings))
  use _ <- result.try(resolved(graph, [], []))
  use _ <- result.try(guard_bindings(bindings))
  Ok(Definition(graph, run_self(body, bindings, _)))
}

fn run_self(body: Plan(a, fn(Value) -> a), bindings, value) -> a {
  let Plan(_, run) = body
  run(#(bindings, fn(child) { run_self(body, bindings, child) }), value)
}

pub fn recursive_pair(
  first_name: String,
  second_name: String,
  build: fn(
    Plan(a, #(fn(Value) -> a, fn(Value) -> b)),
    Plan(b, #(fn(Value) -> a, fn(Value) -> b)),
  ) ->
    Result(
      #(
        Plan(a, #(fn(Value) -> a, fn(Value) -> b)),
        Plan(b, #(fn(Value) -> a, fn(Value) -> b)),
      ),
      String,
    ),
) -> Result(#(Definition(a), Definition(b)), String) {
  use _ <- result.try(case first_name == second_name {
    True -> Error("duplicate name")
    False -> Ok(Nil)
  })
  let first_id = fresh_identity()
  let second_id = fresh_identity()
  let first =
    make_plan(
      Reference(first_id, first_name),
      fn(environment: Environment(#(fn(Value) -> a, fn(Value) -> b)), value) {
        environment.1.0(value)
      },
    )
  let second =
    make_plan(
      Reference(second_id, second_name),
      fn(environment: Environment(#(fn(Value) -> a, fn(Value) -> b)), value) {
        environment.1.1(value)
      },
    )
  use bodies <- result.try(build(first, second))
  let Plan(first_schema, _) = bodies.0
  let Plan(second_schema, _) = bodies.1
  let bindings = [
    #(first_id, #(first_name, first_schema)),
    #(second_id, #(second_name, second_schema)),
  ]
  let first_graph = identified(Graph(Reference(first_id, first_name), bindings))
  let second_graph =
    identified(Graph(Reference(second_id, second_name), bindings))
  use _ <- result.try(resolved(first_graph, [], []))
  use _ <- result.try(guard_bindings(bindings))
  Ok(#(
    Definition(first_graph, run_first(bodies, bindings, _)),
    Definition(second_graph, run_second(bodies, bindings, _)),
  ))
}

fn run_first(
  bodies: #(
    Plan(a, #(fn(Value) -> a, fn(Value) -> b)),
    Plan(b, #(fn(Value) -> a, fn(Value) -> b)),
  ),
  bindings,
  value,
) -> a {
  let Plan(_, run) = bodies.0
  run(
    #(
      bindings,
      #(fn(child) { run_first(bodies, bindings, child) }, fn(child) {
        run_second(bodies, bindings, child)
      }),
    ),
    value,
  )
}

fn run_second(
  bodies: #(
    Plan(a, #(fn(Value) -> a, fn(Value) -> b)),
    Plan(b, #(fn(Value) -> a, fn(Value) -> b)),
  ),
  bindings,
  value,
) -> b {
  let Plan(_, run) = bodies.1
  run(
    #(
      bindings,
      #(fn(child) { run_first(bodies, bindings, child) }, fn(child) {
        run_second(bodies, bindings, child)
      }),
    ),
    value,
  )
}

pub fn validate(
  definition: Definition(a),
  value: Value,
) -> Result(Nil, String) {
  let Definition(schema, _) = definition
  check(schema, value, [])
}

pub fn decode(definition: Definition(a), value: Value) -> Result(a, String) {
  use _ <- result.try(validate(definition, value))
  let Definition(_, run) = definition
  Ok(run(value))
}

fn check(
  schema: Schema,
  value: Value,
  bindings: Bindings,
) -> Result(Nil, String) {
  case schema, value {
    Identified(_, child), _ -> check(child, value, bindings)
    NullSchema, Null -> Ok(Nil)
    ConstantString(expected), Text(actual) ->
      case expected == actual {
        True -> Ok(Nil)
        False -> Error("constant")
      }
    NullableSchema(_), Null -> Ok(Nil)
    NullableSchema(child), _ -> check(child, value, bindings)
    DictionarySchema(child), Object(properties) ->
      all(
        list.map(properties, fn(property) { check(child, property.1, bindings) }),
      )
    AnnotatedSchema(child, _), _ -> check(child, value, bindings)
    ArrayLimits(minimum, maximum), Array(values) ->
      case list.length(values) >= minimum && list.length(values) <= maximum {
        True -> Ok(Nil)
        False -> Error("array limits")
      }
    StringSchema, Text(_) | BooleanSchema, Boolean(_) -> Ok(Nil)
    ArraySchema(child), Array(values) ->
      all(list.map(values, check(child, _, bindings)))
    RecordSchema(fields, policy), Object(properties) -> {
      use _ <- result.try(
        case
          policy == Open
          || list.all(properties, fn(property) {
            list.any(fields, fn(field) {
              let Field(name, _, _) = field
              name == property.0
            })
          })
        {
          True -> Ok(Nil)
          False -> Error("unknown field")
        },
      )
      all(
        list.map(fields, fn(field) {
          let Field(name, schema, presence) = field
          case list.key_find(properties, name), presence {
            Ok(value), _ -> check(schema, value, bindings)
            Error(_), Required -> Error("missing field")
            Error(_), _ -> Ok(Nil)
          }
        }),
      )
    }
    TupleSchema(items), Array(values) ->
      case list.length(items) == list.length(values) {
        False -> Error("tuple length")
        True ->
          all(
            list.map(list.zip(items, values), fn(pair) {
              check(pair.0, pair.1, bindings)
            }),
          )
      }
    UnionSchema(children), _ ->
      case
        list.any(children, fn(child) {
          result.is_ok(check(child, value, bindings))
        })
      {
        True -> Ok(Nil)
        False -> Error("no branch")
      }
    AllSchema(base, rules), _ ->
      all(list.map([base, ..rules], check(_, value, bindings)))
    Reference(id, _), _ -> {
      use child <- result.try(
        list.key_find(bindings, id)
        |> result.map_error(fn(_) { "unresolved reference" }),
      )
      check(child.1, value, bindings)
    }
    Graph(root, definitions), _ -> check(root, value, definitions)
    _, _ -> Error("wrong type")
  }
}

fn all(results: List(Result(Nil, String))) -> Result(Nil, String) {
  list.try_fold(results, Nil, fn(_, next) { next })
}

fn guard_bindings(bindings: Bindings) -> Result(Nil, String) {
  all(
    list.map(bindings, fn(binding) { guard(binding.1.1, bindings, [binding.0]) }),
  )
}

type Scope {
  Unbound
  Bound(Identity)
}

fn scope(bindings: Bindings) -> Scope {
  case bindings {
    [] -> Unbound
    [#(id, _), ..] -> Bound(id)
  }
}

type ResolutionMemo =
  Dict(#(Scope, Identity), Nil)

type GuardMemo =
  Dict(#(Scope, Identity, List(Identity)), Nil)

// Check every edge, even beneath empty/defaulted structural positions. This
// is distinct from the guard walk, which checks only non-descending cycles.
fn resolved(
  schema: Schema,
  bindings: Bindings,
  _seen: List(Identity),
) -> Result(Nil, String) {
  resolved_walk(schema, bindings, dict.new()) |> result.map(fn(_) { Nil })
}

fn resolve_children(children, bindings, memo) {
  list.try_fold(children, memo, fn(memo, child) {
    resolved_walk(child, bindings, memo)
  })
}

fn resolved_walk(
  schema: Schema,
  bindings: Bindings,
  memo: ResolutionMemo,
) -> Result(ResolutionMemo, String) {
  case schema {
    Identified(id, child) -> {
      let key = #(scope(bindings), id)
      case dict.has_key(memo, key) {
        True -> Ok(memo)
        False -> resolved_walk(child, bindings, dict.insert(memo, key, Nil))
      }
    }
    Reference(id, _) -> {
      use child <- result.try(
        list.key_find(bindings, id)
        |> result.map_error(fn(_) { "unresolved reference" }),
      )
      resolved_walk(child.1, bindings, memo)
    }
    Graph(root, local) -> resolved_walk(root, local, memo)
    ArraySchema(child)
    | NullableSchema(child)
    | DictionarySchema(child)
    | AnnotatedSchema(child, _) -> resolved_walk(child, bindings, memo)
    RecordSchema(fields, _) ->
      resolve_children(
        list.map(fields, fn(field) {
          let Field(_, child, _) = field
          child
        }),
        bindings,
        memo,
      )
    TupleSchema(items) | UnionSchema(items) ->
      resolve_children(items, bindings, memo)
    AllSchema(base, rules) -> resolve_children([base, ..rules], bindings, memo)
    StringSchema
    | BooleanSchema
    | NullSchema
    | ConstantString(_)
    | ArrayLimits(_, _) -> Ok(memo)
  }
}

fn guard(
  schema: Schema,
  bindings: Bindings,
  path: List(Identity),
) -> Result(Nil, String) {
  guard_walk(schema, bindings, path, dict.new()) |> result.map(fn(_) { Nil })
}

fn guard_children(children, bindings, path, memo) {
  list.try_fold(children, memo, fn(memo, child) {
    guard_walk(child, bindings, path, memo)
  })
}

fn guard_walk(
  schema: Schema,
  bindings: Bindings,
  path: List(Identity),
  memo: GuardMemo,
) -> Result(GuardMemo, String) {
  case schema {
    Identified(id, child) -> {
      let key = #(scope(bindings), id, path)
      case dict.has_key(memo, key) {
        True -> Ok(memo)
        False -> {
          use memo <- result.try(guard_walk(child, bindings, path, memo))
          Ok(dict.insert(memo, key, Nil))
        }
      }
    }
    Reference(id, _) ->
      case list.contains(path, id) {
        True -> Error("unguarded recursion")
        False -> {
          use child <- result.try(
            list.key_find(bindings, id)
            |> result.map_error(fn(_) { "unresolved reference" }),
          )
          guard_walk(child.1, bindings, [id, ..path], memo)
        }
      }
    UnionSchema(children) -> guard_children(children, bindings, path, memo)
    AllSchema(base, rules) ->
      guard_children([base, ..rules], bindings, path, memo)
    Graph(_, definitions) -> {
      use _ <- result.try(guard_bindings(definitions))
      Ok(memo)
    }
    NullableSchema(child) | AnnotatedSchema(child, _) ->
      guard_walk(child, bindings, path, memo)
    StringSchema
    | BooleanSchema
    | ArraySchema(_)
    | RecordSchema(_, _)
    | TupleSchema(_) -> Ok(memo)
    NullSchema | ConstantString(_) | ArrayLimits(_, _) | DictionarySchema(_) ->
      Ok(memo)
  }
}

pub fn emit(definition: Definition(a)) -> String {
  let Definition(schema, _) = definition
  json.to_string(emit_schema(schema, "#", []))
}

fn pointer(text: String) -> String {
  text |> string.replace("~", "~0") |> string.replace("/", "~1")
}

fn emit_children(children, keyword, location, references) {
  json.array(
    list.index_map(children, fn(child, index) {
      emit_schema(
        child,
        location <> "/" <> keyword <> "/" <> int.to_string(index),
        references,
      )
    }),
    fn(json) { json },
  )
}

fn emit_schema(
  schema: Schema,
  location: String,
  references: List(#(Identity, String)),
) -> json.Json {
  case schema {
    Identified(_, child) -> emit_schema(child, location, references)
    NullSchema -> json.object([#("type", json.string("null"))])
    ConstantString(text) -> json.object([#("const", json.string(text))])
    NullableSchema(child) ->
      json.object([
        #(
          "anyOf",
          emit_children([NullSchema, child], "anyOf", location, references),
        ),
      ])
    DictionarySchema(child) ->
      json.object([
        #("type", json.string("object")),
        #(
          "additionalProperties",
          emit_schema(child, location <> "/additionalProperties", references),
        ),
      ])
    AnnotatedSchema(child, description) ->
      json.object([
        #("description", json.string(description)),
        #("allOf", emit_children([child], "allOf", location, references)),
      ])
    ArrayLimits(minimum, maximum) ->
      json.object([
        #("type", json.string("array")),
        #("minItems", json.int(minimum)),
        #("maxItems", json.int(maximum)),
      ])
    StringSchema -> json.object([#("type", json.string("string"))])
    BooleanSchema -> json.object([#("type", json.string("boolean"))])
    ArraySchema(child) ->
      json.object([
        #("type", json.string("array")),
        #("items", emit_schema(child, location <> "/items", references)),
      ])
    RecordSchema(fields, policy) ->
      json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object(
            list.map(fields, fn(field) {
              let Field(name, child, _) = field
              #(
                name,
                emit_schema(
                  child,
                  location <> "/properties/" <> pointer(name),
                  references,
                ),
              )
            }),
          ),
        ),
        #("additionalProperties", json.bool(policy == Open)),
        #(
          "required",
          json.array(
            list.filter_map(fields, fn(field) {
              let Field(name, _, presence) = field
              case presence {
                Required -> Ok(name)
                _ -> Error(Nil)
              }
            }),
            json.string,
          ),
        ),
      ])
    TupleSchema(items) -> {
      let fields = [
        #("type", json.string("array")),
        #("minItems", json.int(list.length(items))),
        #("maxItems", json.int(list.length(items))),
      ]
      json.object(case items {
        [] -> fields
        _ ->
          list.append(fields, [
            #(
              "prefixItems",
              emit_children(items, "prefixItems", location, references),
            ),
          ])
      })
    }
    UnionSchema(children) ->
      json.object([
        #("anyOf", emit_children(children, "anyOf", location, references)),
      ])
    AllSchema(base, rules) ->
      json.object([
        #(
          "allOf",
          emit_children([base, ..rules], "allOf", location, references),
        ),
      ])
    Reference(id, _) -> {
      let assert Ok(target) = list.key_find(references, id)
      json.object([#("$ref", json.string(target))])
    }
    Graph(root, definitions) -> {
      let local =
        list.map(definitions, fn(binding) {
          #(binding.0, location <> "/$defs/" <> pointer(binding.1.0))
        })
      json.object([
        #(
          "$defs",
          json.object(
            list.map(definitions, fn(binding) {
              let assert Ok(target) = list.key_find(local, binding.0)
              #(binding.1.0, emit_schema(binding.1.1, target, local))
            }),
          ),
        ),
        #("allOf", emit_children([root], "allOf", location, local)),
      ])
    }
  }
}
