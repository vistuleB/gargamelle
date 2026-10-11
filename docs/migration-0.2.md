# Migrating to 0.2.0

Version 0.2.0 was released on 2026-10-11.
The published 0.1.0 package is unchanged. JavaScript remains the supported target
on the verified Node reference. Native tests and a Gleam deployment
shipment pass on macOS arm64/OTP 29 and Ubuntu 24.04 x86_64 with OTP 28.5.0.7
and 29.1.1. Native regex uses Unicode 16; parity with Node 24.21.0/Unicode 17 is
not claimed.
The native implementation requires an explicit build; see
[Native Erlang setup](native-erlang.html).

## Strings and keys

JSON strings and object keys must contain Unicode scalar values. Unpaired
surrogates fail admission; valid surrogate pairs are preserved. Schema text
arguments have the same requirement. `Result` constructors return construction
errors for invalid text; direct constructors assert the precondition.

## Recursive construction

Ordinary definitions still use `Definition(a)`. Constructors now compose
`Plan(a, r)`, and `Definition(a)` is its completed `Plan(a, Nil)` specialization.
Most code needs no new annotations. For example, this definition has the same
shape in 0.1.0 and 0.2.0:

```gleam
pub type Tree {
  Leaf(String)
  Branch(List(Tree))
}

pub fn tree() -> Result(s.Definition(Tree), s.ConstructionError) {
  s.recursive("tree", fn(self) {
    s.any_of([s.map(s.text(), Leaf), s.map(s.array(self), Branch)])
  })
}
```

Examples below assume `import gargamelle as s` and, where needed,
`import gleam/result`.

Inside a builder, an existing completed definition needs `lift`:

```gleam
// 0.1.0
s.recursive("tree", fn(self) {
  s.any_of([leaf, s.map(s.array(self), Branch)])
})

// 0.2.0: leaf is an existing Definition(Tree).
s.recursive("tree", fn(self) {
  s.any_of([s.lift(leaf), s.map(s.array(self), Branch)])
})
```

A generic helper used both inside and outside recursive builders carries the
same recursion parameter through its signature:

```gleam
// 0.1.0
pub fn children(child: s.Definition(a)) -> s.Definition(List(a)) {
  s.array(child)
}

// 0.2.0
pub fn children(child: s.Plan(a, r)) -> s.Plan(List(a), r) {
  s.array(child)
}
```

Annotated unfinished builders change from `Record(a)`, `Tuple(a)` and `Variant(a)`
to `Record(a, r)`, `Tuple(a, r)` and `Variant(a, r)`. Keep `Definition(a)` on
helpers that intentionally accept and return only completed definitions.

`recursive` supplies `Plan(a, Recursive(a))`. `recursive_pair` supplies two plans
under `#(Recursive(a), Recursive(b))` and returns two completed definitions;
their output types may differ. Builder inference usually avoids those annotations.

## Captured references

In 0.1.0, a builder reference had type `Definition(a)` and could escape as a
runnable reference. In 0.2.0 it remains a construction plan even after the builder
returns. Passing it to decode, validate, schema emission or the documentation
renderer does not compile. Store the completed result returned by `recursive`
or `recursive_pair` when later execution is needed.

Mapping callbacks may still return closures, including closures capturing
completed definitions. Completed definitions own immutable recursion bodies and
bindings; they require no registry installation or release operation. There is
no restriction on ordinary closure outputs. A closure returning a construction
plan does not make that plan independently executable.

Names, recursive descent guards, decoded-value behavior, callback suppression,
defaults, canonical schema text and structured data errors retain their existing
contracts. Defaults involving unresolved recursive references still fail
construction; add those defaults after the recursive definition is completed.
