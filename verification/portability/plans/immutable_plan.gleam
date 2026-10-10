// Isolated design experiment. Not part of Gargamelle's public API.
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Value {
  Text(String)
  Boolean(Bool)
  Array(List(Value))
  Object(List(#(String, Value)))
}

type Schema {
  StringSchema
  BooleanSchema
  ArraySchema(Schema)
  RecordSchema(List(Field), Policy)
  TupleSchema(List(Schema))
  UnionSchema(List(Schema))
  AllSchema(Schema, List(Schema))
  Reference(String)
  Graph(Schema, List(#(String, Schema)))
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

pub fn text() -> Plan(String, environment) {
  Plan(StringSchema, fn(_, value) {
    let assert Text(text) = value
    text
  })
}

pub fn boolean() -> Plan(Bool, environment) {
  Plan(BooleanSchema, fn(_, value) {
    let assert Boolean(boolean) = value
    boolean
  })
}

pub fn map(
  plan: Plan(a, environment),
  convert: fn(a) -> b,
) -> Plan(b, environment) {
  let Plan(schema, run) = plan
  Plan(schema, fn(environment, value) { convert(run(environment, value)) })
}

pub fn array(plan: Plan(a, environment)) -> Plan(List(a), environment) {
  let Plan(schema, run) = plan
  Plan(ArraySchema(schema), fn(environment, value) {
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
  Plan(RecordSchema(fields, policy), convert)
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
  Plan(TupleSchema(items), convert)
}

pub fn any_of(
  plans: List(Plan(a, recursion)),
) -> Result(Plan(a, recursion), String) {
  case plans {
    [] -> Error("empty union")
    _ ->
      Ok(
        Plan(
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
  #(List(#(String, Schema)), recursion)

fn environment_schema(environment: Environment(recursion)) {
  environment.0
}

pub fn requiring(
  base: Plan(a, environment),
  rules: List(Plan(b, environment)),
) -> Plan(a, environment) {
  let Plan(schema, run) = base
  Plan(
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
  Plan(schema, fn(_, value) { run(value) })
}

pub fn finish(plan: Plan(a, Nil)) -> Definition(a) {
  let Plan(schema, run) = plan
  Definition(schema, run(#([], Nil), _))
}

pub fn recursive(
  name: String,
  build: fn(Plan(a, fn(Value) -> a)) -> Result(Plan(a, fn(Value) -> a), String),
) -> Result(Definition(a), String) {
  let self =
    Plan(Reference(name), fn(environment: Environment(fn(Value) -> a), value) {
      environment.1(value)
    })
  use body <- result.try(build(self))
  let Plan(schema, _) = body
  let bindings = [#(name, schema)]
  use _ <- result.try(resolved(Graph(Reference(name), bindings), [], []))
  use _ <- result.try(guard_bindings(bindings))
  Ok(Definition(Graph(Reference(name), bindings), run_self(body, bindings, _)))
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
  let first =
    Plan(
      Reference(first_name),
      fn(environment: Environment(#(fn(Value) -> a, fn(Value) -> b)), value) {
        environment.1.0(value)
      },
    )
  let second =
    Plan(
      Reference(second_name),
      fn(environment: Environment(#(fn(Value) -> a, fn(Value) -> b)), value) {
        environment.1.1(value)
      },
    )
  use bodies <- result.try(build(first, second))
  let Plan(first_schema, _) = bodies.0
  let Plan(second_schema, _) = bodies.1
  let bindings = [#(first_name, first_schema), #(second_name, second_schema)]
  use _ <- result.try(resolved(Graph(Reference(first_name), bindings), [], []))
  use _ <- result.try(guard_bindings(bindings))
  Ok(#(
    Definition(Graph(Reference(first_name), bindings), run_first(
      bodies,
      bindings,
      _,
    )),
    Definition(Graph(Reference(second_name), bindings), run_second(
      bodies,
      bindings,
      _,
    )),
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
  bindings: List(#(String, Schema)),
) -> Result(Nil, String) {
  case schema, value {
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
    Reference(name), _ -> {
      use child <- result.try(
        list.key_find(bindings, name)
        |> result.map_error(fn(_) { "unresolved reference" }),
      )
      check(child, value, bindings)
    }
    Graph(root, definitions), _ -> check(root, value, definitions)
    _, _ -> Error("wrong type")
  }
}

fn all(results: List(Result(Nil, String))) -> Result(Nil, String) {
  list.try_fold(results, Nil, fn(_, next) { next })
}

fn guard_bindings(bindings: List(#(String, Schema))) -> Result(Nil, String) {
  all(
    list.map(bindings, fn(binding) { guard(binding.1, bindings, [binding.0]) }),
  )
}

// Check every edge, even beneath empty/defaulted structural positions. This
// is distinct from the guard walk, which checks only non-descending cycles.
fn resolved(
  schema: Schema,
  bindings,
  seen: List(String),
) -> Result(Nil, String) {
  case schema {
    Reference(name) ->
      case list.contains(seen, name) {
        True -> Ok(Nil)
        False -> {
          use child <- result.try(
            list.key_find(bindings, name)
            |> result.map_error(fn(_) { "unresolved reference" }),
          )
          resolved(child, bindings, [name, ..seen])
        }
      }
    Graph(root, local) -> resolved(root, local, [])
    ArraySchema(child) -> resolved(child, bindings, seen)
    RecordSchema(fields, _) ->
      all(
        list.map(fields, fn(field) {
          let Field(_, child, _) = field
          resolved(child, bindings, seen)
        }),
      )
    TupleSchema(items) | UnionSchema(items) ->
      all(list.map(items, resolved(_, bindings, seen)))
    AllSchema(base, rules) ->
      all(list.map([base, ..rules], resolved(_, bindings, seen)))
    StringSchema | BooleanSchema -> Ok(Nil)
  }
}

fn guard(schema: Schema, bindings, path: List(String)) -> Result(Nil, String) {
  case schema {
    Reference(name) ->
      case list.contains(path, name) {
        True -> Error("unguarded recursion")
        False -> {
          use child <- result.try(
            list.key_find(bindings, name)
            |> result.map_error(fn(_) { "unresolved reference" }),
          )
          guard(child, bindings, [name, ..path])
        }
      }
    UnionSchema(children) -> all(list.map(children, guard(_, bindings, path)))
    AllSchema(base, rules) ->
      all(list.map([base, ..rules], guard(_, bindings, path)))
    Graph(_, definitions) -> guard_bindings(definitions)
    StringSchema
    | BooleanSchema
    | ArraySchema(_)
    | RecordSchema(_, _)
    | TupleSchema(_) -> Ok(Nil)
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
  references: List(#(String, String)),
) -> json.Json {
  case schema {
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
    Reference(name) -> {
      let assert Ok(target) = list.key_find(references, name)
      json.object([#("$ref", json.string(target))])
    }
    Graph(root, definitions) -> {
      let local =
        list.map(definitions, fn(binding) {
          #(binding.0, location <> "/$defs/" <> pointer(binding.0))
        })
      json.object([
        #(
          "$defs",
          json.object(
            list.map(definitions, fn(binding) {
              let assert Ok(target) = list.key_find(local, binding.0)
              #(binding.0, emit_schema(binding.1, target, local))
            }),
          ),
        ),
        #("allOf", emit_children([root], "allOf", location, local)),
      ])
    }
  }
}
