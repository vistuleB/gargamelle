# Immutable recursion prototype

This is an isolated experiment for the proposed 0.2.0 recursion contract. It does
not change the public library, resolve its three escaping-placeholder regressions,
or establish production Erlang support.

Run from the package root:

```sh
node --test verification/portability/immutable-plans.test.mjs
```

The runner copies only the prototype and cached dependencies into a temporary
Gleam package. It uses no regex shim or production reference implementation.

## Representation

`Plan(a, Environment(recursion))` contains a finite structural schema and a typed
converter taking an explicit environment and a JSON-shaped prototype value.
The environment contains a schema lookup and typed recursive functions. It never
contains a heterogeneous collection of converters.

For self recursion, the environment supplies `fn(Value) -> a`. For a pair, it
supplies `#(fn(Value) -> a, fn(Value) -> b)`. The builder executes once and produces
the completed body or bodies. Named runner functions call those bodies, supplying
recursive functions that close over the completed bodies. The bodies do not
contain cells that need updating afterward.

`Definition(a)` contains the closed schema graph and `fn(Value) -> a`. Schema
validation receives its reference lookup explicitly. Schema emission tracks the
location of each nested graph, so importing a definition does not accidentally
resolve its references against an enclosing definition with the same name.

`lift` imports a completed definition into a plan and ignores the plan's converter
environment. Ordinary `map` still permits closures as outputs. `finish` accepts
only a plan whose recursion environment is `Nil`; a recursive builder reference
cannot be finalized independently. The public `recursive` and `recursive_pair`
operations close their environments and return completed definitions.

There are no reference servers, ETS tables, permanent registries, release calls,
process-dictionary scopes, casts, or runtime inspections of user closures in the
prototype. Its reference machinery consists of finite immutable terms and
ordinary functions. The test-only counter uses a JavaScript variable or native
`atomics` resource to observe builder/converter calls; it is not reference storage.
No allocation profiler or reclamation stress test has been run.

## Evidence

| Criterion | Result |
|---|---|
| Self recursion and a pair with different output types | Six behavioral tests pass on each target; converters use typed functions, without casts. |
| Builder executes once | Counter assertions remain at one after repeated decode, validation and emission. Tested for both self recursion and a pair. |
| Completed values survive creator exit | Native tests transfer completed self/pair definitions and a decoded closure capturing a completed definition, then use them after creator exit. JavaScript runs the same cases directly; it does not demonstrate process transfer. |
| Construction references cannot be decoded | Compile-negative tests fail with type mismatches on both targets for `decode(self, ...)` and `finish(self)`. |
| Ordinary mappings return closures | A mapped text definition returns a closure capturing a completed recursive definition. The closure remains usable after native handoff. |
| Composition and schema scope | Imported recursive definitions compose inside another recursive definition, including identical graph names and names containing JSON Pointer escape characters. |
| Defaults | Defaults using completed recursive definitions succeed. Defaults using unresolved references fail during construction. Default checks and emission do not execute converters. |
| Guard checks | Direct self aliases, unguarded union recursion and mutual aliases are rejected. Structural array/field recursion succeeds. |
| Callback suppression | Auxiliary constraint converters never execute. Invalid arrays execute no primary converter, including for an earlier valid element. |
| Independent schema agreement | Ajv 2020-12 agrees with validation and decoding success on 261 cases per target, across self recursion, both pair roots, composition and defaults. Emitted schemas and case outcomes match between targets. |

These results establish a feasible typed implementation for the tested subset.
They do not prove that all existing Gargamelle combinators can be migrated without
awkward type signatures or unacceptable performance.

## API comparison

Both examples describe a tree encoded as either a JSON string leaf or an object
with a `children` array. The current API uses runnable definitions throughout:

```gleam
import gargamelle as s
import gleam/result

pub fn tree_definition() -> Result(s.Definition(Tree), s.ConstructionError) {
  s.recursive("tree", fn(self) {
    use branch <- result.try(
      s.required(s.record(Branch), "children", s.array(self)),
    )
    s.any_of([s.map(s.text(), Leaf), s.finish(branch, s.Closed)])
  })
}
```

The prototype distinguishes plans inside the builder from its completed result:

```gleam
import immutable_plan as p

pub fn tree_definition() -> Result(p.Definition(Tree), String) {
  p.recursive("tree", fn(self) {
    p.any_of([
      p.map(p.text(), Leaf),
      p.map(p.field("children", p.array(self)), Branch),
    ])
  })
}
```

No environment annotation is needed at this call site. `self` is inferred as a
plan; the result is a completed definition. The prototype's `field` supports only
exact one-field objects. It is a testing shortcut, not a proposed replacement
for Gargamelle's full record API. Naming and module organization remain undecided.

The contract change is explicit: returning a closure that captures a completed
definition is supported; using a captured construction plan as an independently
runnable definition is rejected by the compiler. Existing JavaScript code relying
on the latter behavior would require migration. This change has not been applied
to the library or published.

## Remaining decisions and work

Before any library rewrite, extend the typing experiment to curried multi-field
records, optional fields, heterogeneous tuples and nested recursive construction.
Check whether helper functions need users to write environment types, and whether
the schema lookup can be hidden without losing inference. Validate sharing and
error-path behavior, and measure allocation/traversal cost on deeper inputs.

The prototype scopes imported graphs independently and permits names outside
Gargamelle's current restricted syntax. Its same-name composition tests prove
lookup isolation, not preservation of the library's existing conflicting-name
rejection policy. Name validation and conflict handling must be decided explicitly
before migration; the experiment does not authorize either semantic change.

The prototype has its own deliberately small `Value` type and limited schema
vocabulary. It is not a JSON parser, a replacement for production diagnostics, or
a complete independent conformance suite. Regex integration, full target parity,
deployment packaging and clean consumer checks remain separate work.
