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
  UnionSchema(List(Schema), Bool)
  AllSchema(Schema, List(Schema))
  ConditionalSchema(Schema, Schema, Option(Schema))
  NotSchema(Schema)
  ContainsSchema(Schema, Int, Option(Int))
  KeysSchema(Schema)
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
  Default(Value, Evidence)
}

type Field {
  Field(String, Schema, Presence)
}

// Structural receipts are private and contain no user output values/functions.
// Transparent schema wrappers and references forward the child's receipt.
type Evidence {
  Atomic
  Children(List(Evidence))
  Fields(List(#(String, Evidence)))
  Selected(Int, Evidence)
}

// The public recursion parameter hides the private receipt argument. Callers
// quantify over recursion; they cannot construct or invoke these runners.
pub opaque type Recursive(a) {
  Recursive(fn(Value, Evidence) -> a)
}

pub opaque type Record(a, environment) {
  Record(List(Field), fn(environment, Value, Evidence) -> a)
}

pub opaque type Tuple(a, environment) {
  Tuple(List(Schema), fn(environment, Value, Evidence) -> a)
}

pub opaque type Plan(a, environment) {
  Plan(Schema, fn(environment, Value, Evidence) -> a)
}

pub opaque type Definition(a) {
  Definition(Schema, fn(Value, Evidence) -> a)
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
  Variant(String, List(Field), Policy, fn(recursion, Value, Evidence) -> a)
}

pub fn nullable(plan: Plan(a, recursion)) -> Plan(Option(a), recursion) {
  let Plan(schema, convert) = plan
  make_plan(NullableSchema(schema), fn(environment, value, evidence) {
    case value {
      Null -> None
      _ -> Some(convert(environment, value, evidence))
    }
  })
}

pub fn dictionary(
  plan: Plan(a, recursion),
) -> Plan(List(#(String, a)), recursion) {
  let Plan(schema, convert) = plan
  make_plan(DictionarySchema(schema), fn(environment, value, evidence) {
    let assert Object(properties) = value
    let assert Children(receipts) = evidence
    list.map(list.zip(properties, receipts), fn(pair) {
      #(pair.0.0, convert(environment, pair.0.1, pair.1))
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
  make_plan(StringSchema, fn(_, value, _) {
    let assert Text(text) = value
    text
  })
}

pub fn string_constant(value: String) -> Plan(String, recursion) {
  make_plan(ConstantString(value), fn(_, _, _) { value })
}

pub fn boolean() -> Plan(Bool, environment) {
  make_plan(BooleanSchema, fn(_, value, _) {
    let assert Boolean(boolean) = value
    boolean
  })
}

pub fn map(
  plan: Plan(a, environment),
  convert: fn(a) -> b,
) -> Plan(b, environment) {
  let Plan(schema, run) = plan
  make_plan(schema, fn(environment, value, evidence) {
    convert(run(environment, value, evidence))
  })
}

pub fn array(plan: Plan(a, environment)) -> Plan(List(a), environment) {
  let Plan(schema, run) = plan
  make_plan(ArraySchema(schema), fn(environment, value, evidence) {
    let assert Array(values) = value
    let assert Children(receipts) = evidence
    list.map(list.zip(values, receipts), fn(pair) {
      run(environment, pair.0, pair.1)
    })
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
  Record([], fn(_, _, _) { constructor })
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
      fn(environment, value, evidence) {
        let assert Object(properties) = value
        let assert Ok(child) = list.key_find(properties, name)
        construct(environment, value, evidence)(convert(
          environment,
          child,
          field_evidence(evidence, name),
        ))
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
      fn(environment, value, evidence) {
        let assert Object(properties) = value
        let decoded = case list.key_find(properties, name) {
          Error(_) -> None
          Ok(child) ->
            Some(convert(environment, child, field_evidence(evidence, name)))
        }
        construct(environment, value, evidence)(decoded)
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
  use receipt <- result.try(inspect(schema, default, []))
  Ok(
    Record(
      list.append(fields, [Field(name, schema, Default(default, receipt))]),
      fn(environment, value, evidence) {
        let assert Object(properties) = value
        let child = result.unwrap(list.key_find(properties, name), default)
        construct(environment, value, evidence)(convert(
          environment,
          child,
          field_evidence(evidence, name),
        ))
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
  Tuple([], fn(_, _, _) { constructor })
}

pub fn item(
  tuple: Tuple(fn(a) -> b, environment),
  child: Plan(a, environment),
) -> Tuple(b, environment) {
  let Tuple(items, construct) = tuple
  let Plan(schema, convert) = child
  let index = list.length(items)
  Tuple(list.append(items, [schema]), fn(environment, value, evidence) {
    let assert Array(values) = value
    let assert Ok(child) = values |> list.drop(index) |> list.first
    let assert Children(receipts) = evidence
    let assert Ok(receipt) = receipts |> list.drop(index) |> list.first
    construct(environment, value, evidence)(convert(environment, child, receipt))
  })
}

pub fn finish_tuple(tuple: Tuple(a, environment)) -> Plan(a, environment) {
  let Tuple(items, convert) = tuple
  make_plan(TupleSchema(items), convert)
}

pub fn any_of(
  plans: List(Plan(a, recursion)),
) -> Result(Plan(a, recursion), String) {
  union(plans, False)
}

pub fn one_of(
  plans: List(Plan(a, recursion)),
) -> Result(Plan(a, recursion), String) {
  union(plans, True)
}

fn union(
  plans: List(Plan(a, recursion)),
  exclusive: Bool,
) -> Result(Plan(a, recursion), String) {
  case plans {
    [] -> Error("empty union")
    _ -> {
      let schemas =
        list.map(plans, fn(plan) {
          let Plan(schema, _) = plan
          schema
        })
      // Capture only homogeneous typed runners, never whole plans or schemas.
      let runners =
        list.map(plans, fn(plan) {
          let Plan(_, run) = plan
          run
        })
      Ok(
        make_plan(
          UnionSchema(schemas, exclusive),
          fn(environment, value, evidence) {
            let assert Selected(index, receipt) = evidence
            let assert Ok(run) = runners |> list.drop(index) |> list.first
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

// Auxiliary plans contribute only schema checks. Their typed converters are
// discarded, even when their output types differ from the base and each other.
pub fn if_then_else(
  base: Plan(a, recursion),
  condition: Plan(b, recursion),
  consequence: Plan(c, recursion),
  alternative: Plan(d, recursion),
) -> Plan(a, recursion) {
  let Plan(schema, run) = base
  let Plan(probe, _) = condition
  let Plan(yes, _) = consequence
  let Plan(no, _) = alternative
  make_plan(AllSchema(schema, [ConditionalSchema(probe, yes, Some(no))]), run)
}

pub fn exclude(
  base: Plan(a, recursion),
  forbidden: Plan(b, recursion),
) -> Plan(a, recursion) {
  let Plan(schema, run) = base
  let Plan(probe, _) = forbidden
  make_plan(AllSchema(schema, [NotSchema(probe)]), run)
}

// Shape checks are limited to the experiment's vocabulary. The production
// constructor restrictions still require preservation during integration.
fn has_shape(schema, array: Bool) {
  case schema {
    Identified(_, child) | AnnotatedSchema(child, _) | AllSchema(child, _) ->
      has_shape(child, array)
    ArraySchema(_) | TupleSchema(_) -> array
    DictionarySchema(_) | RecordSchema(_, _) -> !array
    _ -> False
  }
}

pub fn contains(
  base: Plan(a, recursion),
  matching: Plan(b, recursion),
  minimum: Int,
  maximum: Option(Int),
) -> Result(Plan(a, recursion), String) {
  let Plan(schema, run) = base
  let Plan(probe, _) = matching
  let invalid_max = case maximum {
    Some(limit) -> limit < minimum
    None -> False
  }
  case !has_shape(schema, True) || minimum < 0 || invalid_max {
    True -> Error("invalid contains construction")
    False ->
      Ok(make_plan(
        AllSchema(schema, [ContainsSchema(probe, minimum, maximum)]),
        run,
      ))
  }
}

pub fn property_names(
  base: Plan(a, recursion),
  keys: Plan(String, recursion),
) -> Result(Plan(a, recursion), String) {
  let Plan(schema, run) = base
  let Plan(probe, _) = keys
  case has_shape(schema, False) {
    False -> Error("property names requires an object")
    True -> Ok(make_plan(AllSchema(schema, [KeysSchema(probe)]), run))
  }
}

pub fn lift(definition: Definition(a)) -> Plan(a, environment) {
  let Definition(schema, run) = definition
  make_plan(schema, fn(_, value, evidence) { run(value, evidence) })
}

pub fn finish(plan: Plan(a, Nil)) -> Definition(a) {
  let Plan(schema, run) = plan
  Definition(schema, fn(value, evidence) { run(Nil, value, evidence) })
}

pub fn recursive(
  name: String,
  build: fn(Plan(a, Recursive(a))) -> Result(Plan(a, Recursive(a)), String),
) -> Result(Definition(a), String) {
  let reference_id = fresh_identity()
  let self =
    make_plan(
      Reference(reference_id, name),
      fn(environment: Recursive(a), value, evidence) {
        let Recursive(run) = environment
        run(value, evidence)
      },
    )
  use body <- result.try(build(self))
  let Plan(schema, run) = body
  let bindings = [#(reference_id, #(name, schema))]
  let graph = identified(Graph(Reference(reference_id, name), bindings))
  use _ <- result.try(resolved(graph, [], []))
  use _ <- result.try(guard_bindings(bindings))
  Ok(Definition(graph, fn(value, evidence) { run_self(run, value, evidence) }))
}

fn run_self(run: fn(Recursive(a), Value, Evidence) -> a, value, evidence) -> a {
  run(
    Recursive(fn(child, receipt) { run_self(run, child, receipt) }),
    value,
    evidence,
  )
}

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
      fn(environment: #(Recursive(a), Recursive(b)), value, evidence) {
        let Recursive(run) = environment.0
        run(value, evidence)
      },
    )
  let second =
    make_plan(
      Reference(second_id, second_name),
      fn(environment: #(Recursive(a), Recursive(b)), value, evidence) {
        let Recursive(run) = environment.1
        run(value, evidence)
      },
    )
  use bodies <- result.try(build(first, second))
  let Plan(first_schema, first_run) = bodies.0
  let Plan(second_schema, second_run) = bodies.1
  let bindings = [
    #(first_id, #(first_name, first_schema)),
    #(second_id, #(second_name, second_schema)),
  ]
  let first_graph = identified(Graph(Reference(first_id, first_name), bindings))
  let second_graph =
    identified(Graph(Reference(second_id, second_name), bindings))
  use _ <- result.try(resolved(first_graph, [], []))
  use _ <- result.try(guard_bindings(bindings))
  let runners = #(first_run, second_run)
  Ok(#(
    Definition(first_graph, fn(value, evidence) {
      run_first(runners, value, evidence)
    }),
    Definition(second_graph, fn(value, evidence) {
      run_second(runners, value, evidence)
    }),
  ))
}

fn run_first(
  runners: #(
    fn(#(Recursive(a), Recursive(b)), Value, Evidence) -> a,
    fn(#(Recursive(a), Recursive(b)), Value, Evidence) -> b,
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
    fn(#(Recursive(a), Recursive(b)), Value, Evidence) -> a,
    fn(#(Recursive(a), Recursive(b)), Value, Evidence) -> b,
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

pub fn validate(
  definition: Definition(a),
  value: Value,
) -> Result(Nil, String) {
  let Definition(schema, _) = definition
  check(schema, value, [])
}

pub fn decode(definition: Definition(a), value: Value) -> Result(a, String) {
  let Definition(schema, run) = definition
  use evidence <- result.try(inspect(schema, value, []))
  Ok(run(value, evidence))
}

@external(erlang, "plan_support", "term_size")
@external(javascript, "./plan_support.mjs", "term_size")
fn term_size(value: a) -> #(Int, Int)

// Diagnostic surface of the isolated experiment only. Evidence stays private;
// expose heap-word counts without exposing receipts or running converters.
pub fn validation_size(
  definition: Definition(a),
  value: Value,
) -> Result(#(Int, Int), String) {
  let Definition(schema, _) = definition
  use evidence <- result.try(inspect(schema, value, []))
  Ok(term_size(evidence))
}

fn check(
  schema: Schema,
  value: Value,
  bindings: Bindings,
) -> Result(Nil, String) {
  inspect(schema, value, bindings) |> result.map(fn(_) { Nil })
}

// All user callbacks run after inspect succeeds for the entire input. Receipt
// construction is structural and does not inspect or fabricate typed outputs.
fn inspect(
  schema: Schema,
  value: Value,
  bindings: Bindings,
) -> Result(Evidence, String) {
  case schema, value {
    Identified(_, child), _ -> inspect(child, value, bindings)
    NullSchema, Null -> Ok(Atomic)
    ConstantString(expected), Text(actual) ->
      case expected == actual {
        True -> Ok(Atomic)
        False -> Error("constant")
      }
    NullableSchema(_), Null -> Ok(Atomic)
    NullableSchema(child), _ -> inspect(child, value, bindings)
    DictionarySchema(child), Object(properties) ->
      list.try_map(properties, fn(property) {
        inspect(child, property.1, bindings)
      })
      |> result.map(Children)
    AnnotatedSchema(child, _), _ -> inspect(child, value, bindings)
    ArrayLimits(minimum, maximum), Array(values) ->
      case list.length(values) >= minimum && list.length(values) <= maximum {
        True -> Ok(Atomic)
        False -> Error("array limits")
      }
    StringSchema, Text(_) | BooleanSchema, Boolean(_) -> Ok(Atomic)
    ArraySchema(child), Array(values) ->
      list.try_map(values, inspect(child, _, bindings)) |> result.map(Children)
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
      list.try_map(fields, fn(field) {
        let Field(name, child, presence) = field
        case list.key_find(properties, name), presence {
          Ok(value), _ ->
            inspect(child, value, bindings)
            |> result.map(fn(receipt) { #(name, receipt) })
          Error(_), Required -> Error("missing field")
          Error(_), Default(_, receipt) -> Ok(#(name, receipt))
          Error(_), Optional -> Ok(#(name, Atomic))
        }
      })
      |> result.map(Fields)
    }
    TupleSchema(items), Array(values) ->
      case list.length(items) == list.length(values) {
        False -> Error("tuple length")
        True ->
          list.try_map(list.zip(items, values), fn(pair) {
            inspect(pair.0, pair.1, bindings)
          })
          |> result.map(Children)
      }
    UnionSchema(children, exclusive), _ ->
      inspect_union(children, value, bindings, exclusive, 0, None)
    AllSchema(base, rules), _ -> {
      use evidence <- result.try(inspect(base, value, bindings))
      use _ <- result.try(all(list.map(rules, check(_, value, bindings))))
      Ok(evidence)
    }
    ConditionalSchema(probe, yes, no), _ ->
      case check(probe, value, bindings), no {
        Ok(_), _ -> inspect(yes, value, bindings)
        Error(_), Some(alternative) -> inspect(alternative, value, bindings)
        Error(_), None -> Ok(Atomic)
      }
    NotSchema(probe), _ ->
      case check(probe, value, bindings) {
        Ok(_) -> Error("excluded")
        Error(_) -> Ok(Atomic)
      }
    ContainsSchema(_, 0, None), Array(_) -> Ok(Atomic)
    ContainsSchema(probe, minimum, maximum), Array(values) -> {
      let count =
        list.count(values, fn(value) {
          result.is_ok(check(probe, value, bindings))
        })
      let within_max = case maximum {
        Some(limit) -> count <= limit
        None -> True
      }
      case count >= minimum && within_max {
        True -> Ok(Atomic)
        False -> Error("contains count")
      }
    }
    KeysSchema(probe), Object(properties) ->
      all(
        list.map(properties, fn(property) {
          check(probe, Text(property.0), bindings)
        }),
      )
      |> result.map(fn(_) { Atomic })
    Reference(id, _), _ -> {
      use child <- result.try(
        list.key_find(bindings, id)
        |> result.map_error(fn(_) { "unresolved reference" }),
      )
      inspect(child.1, value, bindings)
    }
    Graph(root, definitions), _ -> inspect(root, value, definitions)
    _, _ -> Error("wrong type")
  }
}

fn inspect_union(children, value, bindings, exclusive, index, selected) {
  case children, selected {
    [], None -> Error("no branch")
    [], Some(receipt) -> Ok(receipt)
    [child, ..rest], _ ->
      case inspect(child, value, bindings), selected {
        Ok(receipt), _ if !exclusive -> Ok(Selected(index, receipt))
        Ok(_), Some(_) -> Error("multiple branches")
        Ok(receipt), None ->
          inspect_union(
            rest,
            value,
            bindings,
            exclusive,
            index + 1,
            Some(Selected(index, receipt)),
          )
        Error(_), _ ->
          inspect_union(rest, value, bindings, exclusive, index + 1, selected)
      }
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

fn conditional_children(probe, yes, no) {
  case no {
    Some(alternative) -> [probe, yes, alternative]
    None -> [probe, yes]
  }
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
    TupleSchema(items) | UnionSchema(items, _) ->
      resolve_children(items, bindings, memo)
    AllSchema(base, rules) -> resolve_children([base, ..rules], bindings, memo)
    ConditionalSchema(probe, yes, no) ->
      resolve_children(conditional_children(probe, yes, no), bindings, memo)
    NotSchema(probe) | ContainsSchema(probe, _, _) | KeysSchema(probe) ->
      resolved_walk(probe, bindings, memo)
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
    UnionSchema(children, _) -> guard_children(children, bindings, path, memo)
    AllSchema(base, rules) ->
      guard_children([base, ..rules], bindings, path, memo)
    ConditionalSchema(probe, yes, no) ->
      guard_children(conditional_children(probe, yes, no), bindings, path, memo)
    NotSchema(probe) -> guard_walk(probe, bindings, path, memo)
    // Membership and key probes inspect strict child inputs. Their references
    // still participate in resolution above, but cannot cause same-input loops.
    ContainsSchema(_, _, _) | KeysSchema(_) -> Ok(memo)
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
    UnionSchema(children, exclusive) -> {
      let keyword = case exclusive {
        True -> "oneOf"
        False -> "anyOf"
      }
      json.object([
        #(keyword, emit_children(children, keyword, location, references)),
      ])
    }
    AllSchema(base, rules) ->
      json.object([
        #(
          "allOf",
          emit_children([base, ..rules], "allOf", location, references),
        ),
      ])
    ConditionalSchema(probe, yes, no) -> {
      let fields = [
        #("if", emit_schema(probe, location <> "/if", references)),
        #("then", emit_schema(yes, location <> "/then", references)),
      ]
      json.object(case no {
        None -> fields
        Some(alternative) ->
          list.append(fields, [
            #("else", emit_schema(alternative, location <> "/else", references)),
          ])
      })
    }
    NotSchema(probe) ->
      json.object([#("not", emit_schema(probe, location <> "/not", references))])
    ContainsSchema(_, 0, None) -> json.object([#("type", json.string("array"))])
    ContainsSchema(probe, minimum, maximum) -> {
      let fields = [
        #("type", json.string("array")),
        #("contains", emit_schema(probe, location <> "/contains", references)),
        #("minContains", json.int(minimum)),
      ]
      json.object(case maximum {
        None -> fields
        Some(limit) -> list.append(fields, [#("maxContains", json.int(limit))])
      })
    }
    KeysSchema(probe) ->
      json.object([
        #("type", json.string("object")),
        #(
          "propertyNames",
          emit_schema(probe, location <> "/propertyNames", references),
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
