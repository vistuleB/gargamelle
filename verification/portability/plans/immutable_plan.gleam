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

pub opaque type Schema {
  StringSchema
  BooleanSchema
  ArraySchema(Schema)
  FieldSchema(String, Schema, Option(Value))
  UnionSchema(List(Schema))
  AllSchema(Schema, List(Schema))
  Reference(String)
  Graph(Schema, List(#(String, Schema)))
}

pub opaque type Plan(a, environment) {
  Plan(Schema, fn(environment, Value) -> a)
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

// Exact, one-field records only: sufficient to exercise a structural guard.
pub fn field(name: String, plan: Plan(a, environment)) -> Plan(a, environment) {
  let Plan(schema, run) = plan
  Plan(FieldSchema(name, schema, None), fn(environment, value) {
    let assert Object(fields) = value
    let assert Ok(child) = list.key_find(fields, name)
    run(environment, child)
  })
}

pub fn defaulted(
  name: String,
  plan: Plan(a, environment),
  default: Value,
) -> Result(Plan(a, environment), String) {
  let Plan(schema, run) = plan
  use _ <- result.try(check(schema, default, []))
  Ok(
    Plan(FieldSchema(name, schema, Some(default)), fn(environment, value) {
      let assert Object(fields) = value
      let child = result.unwrap(list.key_find(fields, name), default)
      run(environment, child)
    }),
  )
}

pub fn any_of(
  plans: List(Plan(a, Environment(recursion))),
) -> Result(Plan(a, Environment(recursion)), String) {
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
  plans: List(Plan(a, Environment(recursion))),
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
pub type Environment(recursion) =
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

pub fn finish(plan: Plan(a, Environment(Nil))) -> Definition(a) {
  let Plan(schema, run) = plan
  Definition(schema, run(#([], Nil), _))
}

pub fn recursive(
  name: String,
  build: fn(Plan(a, Environment(fn(Value) -> a))) ->
    Result(Plan(a, Environment(fn(Value) -> a)), String),
) -> Result(Definition(a), String) {
  let self =
    Plan(Reference(name), fn(environment: Environment(fn(Value) -> a), value) {
      environment.1(value)
    })
  use body <- result.try(build(self))
  let Plan(schema, _) = body
  let bindings = [#(name, schema)]
  use _ <- result.try(guard_bindings(bindings))
  Ok(Definition(Graph(Reference(name), bindings), run_self(body, bindings, _)))
}

fn run_self(body: Plan(a, Environment(fn(Value) -> a)), bindings, value) -> a {
  let Plan(_, run) = body
  run(#(bindings, fn(child) { run_self(body, bindings, child) }), value)
}

pub fn recursive_pair(
  first_name: String,
  second_name: String,
  build: fn(
    Plan(a, Environment(#(fn(Value) -> a, fn(Value) -> b))),
    Plan(b, Environment(#(fn(Value) -> a, fn(Value) -> b))),
  ) ->
    Result(
      #(
        Plan(a, Environment(#(fn(Value) -> a, fn(Value) -> b))),
        Plan(b, Environment(#(fn(Value) -> a, fn(Value) -> b))),
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
    Plan(a, Environment(#(fn(Value) -> a, fn(Value) -> b))),
    Plan(b, Environment(#(fn(Value) -> a, fn(Value) -> b))),
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
    Plan(a, Environment(#(fn(Value) -> a, fn(Value) -> b))),
    Plan(b, Environment(#(fn(Value) -> a, fn(Value) -> b))),
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
    FieldSchema(name, child, default), Object(fields) -> {
      use _ <- result.try(case list.all(fields, fn(field) { field.0 == name }) {
        True -> Ok(Nil)
        False -> Error("unknown field")
      })
      case list.key_find(fields, name), default {
        Ok(value), _ -> check(child, value, bindings)
        Error(_), Some(_) -> Ok(Nil)
        _, _ -> Error("missing field")
      }
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
    StringSchema | BooleanSchema | ArraySchema(_) | FieldSchema(_, _, _) ->
      Ok(Nil)
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
    FieldSchema(name, child, default) ->
      json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              name,
              emit_schema(
                child,
                location <> "/properties/" <> pointer(name),
                references,
              ),
            ),
          ]),
        ),
        #("additionalProperties", json.bool(False)),
        #(
          "required",
          json.array(
            case default {
              None -> [name]
              Some(_) -> []
            },
            json.string,
          ),
        ),
      ])
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
