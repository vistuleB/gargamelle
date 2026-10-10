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

`Plan(a, recursion)` contains a finite structural schema and a typed
converter receiving a recursion environment, a JSON-shaped prototype value and
private structural validation evidence. The converter environment contains only
typed recursive runners. Schema lookup is used by validation, not conversion;
there is no heterogeneous collection of converters.

For self recursion, the environment is opaque `Recursive(a)`. For a pair, it is
`#(Recursive(a), Recursive(b))`. Each wrapper contains a typed runner accepting a
value and its private evidence. The constructors and evidence type are private;
ordinary helpers still quantify over `Plan(a, recursion)` without spelling out
these arguments. The builder executes once. Named runner functions close over
the completed converter functions, without retaining their schemas or reference
lookups. No cell needs updating afterward.

`Definition(a)` contains the closed schema graph and a closed typed converter
receiving the value and evidence. Schema nodes and reference bindings have fresh
identities, using native references on
Erlang and Symbols on JavaScript. Display names are separate from binding keys:
an unfinished outer reference cannot become an inner reference by sharing a name.
Construction walks pass immutable memo dictionaries explicitly, keyed by node
identity and binding scope (plus the active reference path for guard checks).
These caches are local to each walk and are not retained as reference storage.
Schema validation receives its reference lookup explicitly. Schema emission tracks the
location of each nested graph, so importing a definition does not accidentally
resolve its references against an enclosing definition with the same name.

`lift` imports a completed definition into a plan and ignores the plan's converter
environment. Ordinary `map` still permits closures as outputs. `finish` accepts
only a plan whose recursion parameter is `Nil`; a recursive builder reference
cannot be finalized independently. The public `recursive` and `recursive_pair`
operations close their environments and return completed definitions.

There are no reference servers, ETS tables, permanent registries, release calls,
process-dictionary scopes, casts, or runtime inspections of user closures in the
prototype. Its reference machinery consists of finite immutable terms and
ordinary functions. The test-only counter uses a JavaScript variable or native
`atomics` resource to observe builder/converter calls; it is not reference storage.
Bounded native term-size and process-copy probes are described below. No
allocation profiler or reclamation stress test has been run.

## Evidence

| Criterion | Result |
|---|---|
| Self recursion and a pair with different output types | Twenty behavioral tests pass on each target; converters use typed functions, without casts. |
| Builder executes once | Counter assertions remain at one after repeated decode, validation and emission. Tested for both self recursion and a pair. |
| Completed values survive creator exit | Native tests transfer completed self/pair definitions and a decoded closure capturing a completed definition, then use them after creator exit. JavaScript runs the same cases directly; it does not demonstrate process transfer. |
| Construction references cannot be decoded | Eight compile-negative checks reject direct decode/finalization and finalization after mapping or wrapping a reference in a heterogeneous tuple. Four more reject access to evidence and recursive-runner constructors. |
| Ordinary mappings return closures | A mapped text definition returns a closure capturing a completed recursive definition. The closure remains usable after native handoff. |
| Composition and schema scope | Imported recursive definitions compose inside another recursive definition, including identical graph names and names containing JSON Pointer escape characters. |
| Defaults | Defaults using completed recursive definitions succeed. Defaults using unresolved references fail during construction, including an empty array of unresolved references. Default checks and emission do not execute converters. |
| Guard checks | Direct self aliases, unguarded union recursion and mutual aliases are rejected. Structural array/field recursion succeeds. |
| Callback suppression | Auxiliary constraint converters never execute. Invalid arrays execute no primary converter, including for an earlier valid element. |
| Curried records and tuples | Multi-field records, optional presence, defaults, open/closed projection and exact heterogeneous tuples compile and decode. Tuples carry independently typed pair outputs. |
| Helper inference | A separately compiled helper module tests annotated generic record/union helpers and an inferred tuple helper, used in closed, self-recursive and paired contexts. Call sites do not supply recursion functions or internal environment types. |
| Nested construction | Independent nested definitions compose through `lift`. Capturing an unfinished outer reference is rejected during construction, including below an array. |
| Remaining feature combinations | A provider helper composes tagged variants, nullable recursive children, dictionary values, bounds and descriptions. Discriminator collisions, duplicate tags and non-descending nullable/description cycles are rejected. |
| Shared construction and scope | A 26-layer graph with duplicate edges constructs on both targets. An inner definition with the same display name cannot capture an unfinished outer reference. |
| Auxiliary constraints | Conditional branches, exclusion, membership counts and property-name checks compose with recursive children. Auxiliary outputs include Int, Bool, Nil, String and a tuple; converters panic if called. Same-input recursive probes are rejected, and unresolved references beneath a disabled membership rule remain construction errors. |
| Union selection and operational failures | Ordinary unions retain first-match output. Exclusive unions reject overlapping/duplicate branches without callbacks, including late ambiguity inside an array. Converter panics propagate after validation; they are not data errors. |
| Recursive default evidence | Nested recursive defaults retain the correct branch evidence; a closure decoded from such a default survives creator exit. |
| Independent schema agreement | Ajv 2020-12 agrees with validation and decoding success on 1,142 cases per target, including provider features and auxiliary constraints. Emitted schemas and case outcomes match between targets. |

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
    use branch <- result.try(
      p.required(p.record(Branch), "children", p.array(self)),
    )
    p.any_of([p.map(p.text(), Leaf), p.finish_record(branch, p.Closed)])
  })
}
```

No environment annotation is needed at this call site. `self` is inferred as a
plan; the result is a completed definition. Curried multi-field record and tuple
builders use the same recursion parameter as their children. The convenience
`field` function delegates to the general record builder. Naming and module
organization remain undecided. The proposed example also imports `gleam/result`.

The contract change is explicit: returning a closure that captures a completed
definition is supported; using a captured construction plan as an independently
runnable definition is rejected by the compiler. Existing JavaScript code relying
on the latter behavior would require migration. This change has not been applied
to the library or published.

## Remaining decisions and work

Curried records, optional fields, heterogeneous tuples and independent nested
construction now work in the experiment. Explicitly annotated generic helpers
write `Plan(a, recursion)`; inferred helpers need no such annotation. This is one
additional public type parameter compared with `Definition(a)`. Users do not
write the schema lookup or environment tuple, but migration of existing helper
signatures still has a cost.

Tagged variants, nullable values, dictionaries, descriptions and array bounds
compose in an exported provider helper. A second helper tests conditional,
exclusion, contains and property-name constraints. Detailed errors, numeric
primitives, regex and several constructor restrictions remain outside this
experiment. The migration assessment below distinguishes tested behavior from
source inspection; the complete API has not been migrated.

## Bounded performance observations

The runner also measures construction with shared union edges at 8/12/16 layers,
and decoding at input depths 8/32/64. Measurements are printed as diagnostics;
there are no hardware-dependent timing assertions.

Before memoization, shared construction at 16 layers used approximately 5.3
million Erlang reductions. After adding node identities and scope-aware immutable
memo dictionaries, the same case used approximately 1,200 reductions. Wall times
vary with warmup and runtime conditions; these observations establish removal of
the measured repeated construction traversal, not a general speed guarantee.
The separate 26-layer behavioral case retains this sharing shape as a regression.

Before private evidence, decoding at depths 8/32/64 used approximately
1,900/22,500/85,000 Erlang reductions. With private evidence, the same cases use
approximately 500/1,900/3,800 reductions. Conversion no longer calls the structural
checker to select branches. These cases show approximately linear work for the
measured tree; failed or overlapping schema branches can still repeat structural
work during validation.

The evidence itself occupies 76/292/580 native heap words at these depths.
These are term sizes, not peak allocation or total process memory. The receipt
adds transient storage proportional to the accepted structure in this case;
it is consumed after complete validation and is not retained in the definition.
A user callback may retain its ordinary decoded values as before. It has no
access to the receipt. Standalone `validate` currently builds and discards the
same evidence; a mode that avoids retaining evidence is a possible production
optimization, not yet implemented or measured.

### Native copying and emitted size

The runner now transfers completed shared definitions at 2/4/6 layers and uses
each one in the recipient before checking normal process exit. Test-only
`erts_debug:size/1` counts sharing in the term; `flat_size/1` counts repeated
edges. The received term is measured independently. These are OTP 29 diagnostic
heap-word counts, not total process memory, wire size, allocation rates or a
supported library dependency. JavaScript returns zero sentinels for these native
measurements; the zeros mean unavailable, not zero allocation.

| Repeated union layers | Sender words with sharing | Flat words | Receiver words with sharing |
|---|---:|---:|---:|
| 2 | 143 | 384 | 351 |
| 4 | 187 | 1,476 | 1,335 |
| 6 | 231 | 5,844 | 5,271 |
| Recursive provider helper | 290 | 336 | 310 |

Before removing converter schema captures (`e817685`), the six-layer received
term occupied 36,576 words and the provider occupied 889. They now occupy
5,271/310 words. Immutable term ownership solves lifetime but does not preserve
arbitrary heap sharing across messages: repeated schemas and homogeneous
converter closures still expand during copying. Construction memoization alone
cannot fix that. The larger pre-evidence 4/8/12-layer transfer series exceeded
the diagnostic's ten-second receive timeout; its failing depth was not isolated.
The retained runner uses smaller bounded cases. This scaling risk remains
explicit; the realistic provider transfers and decodes successfully.

Emission similarly expands shared unnamed branches: the 8/12-layer cases produce
23,852/380,972 characters on both targets. Emitting references for shared nodes
could reduce this expansion, but it would change existing emitted schema text.
Do not silently change canonical emission or erase duplicate `one_of` branches:
duplicate acceptance contributes to exclusive-union rejection.

## Migration assessment

Source inspection of `src/gargamelle.gleam`, alongside the executable subset,
gives the following map. It is an implementation plan, not full parity evidence.

| Production family | Plan treatment | Remaining work |
|---|---|---|
| Primitive values, constants, enums, numeric/string bounds and patterns | Schema checks remain independent of typed conversion; a primitive plan can quantify over any recursion parameter. | Reuse actual Value, binary64/scalar rules and target externals; do not duplicate them in this experiment. Regex remains a separate blocker. |
| Maps, nullable, arrays, dictionaries, records, defaults and tuples | Typed converters compose under the same recursion parameter. Tested here. | Preserve exact construction bounds, default diagnostics, projection and field/key ordering. |
| Tagged/ordinary/exclusive unions | Homogeneous output plans carry distinct schema branches and typed converters. Tagged, ordinary and exclusive unions are tested. Validation selects the accepted converter using private evidence; duplicates still count toward exclusive rejection. | Retain duplicate branches and current discriminator/construction restrictions; test exact exclusive-union diagnostics. |
| Conditional and exclusion checks | Discard auxiliary converters; keep the base converter. Tested here with different auxiliary output types. | Preserve accumulation/order of production errors and operational-failure propagation. All same-input probe/consequence edges participate in guards. |
| Contains and property-name checks | Discard probe converters, validate strict child inputs, retain base output. Tested here. | Preserve exact shape restrictions and repeated-rule composition. Resolve every probe even if a rule is disabled or input is empty. |
| Unique items | Compare canonical admitted values, retaining base conversion. No new typed environment requirement. | Reuse production equality/canonicalization; test mapped and recursive arrays. |
| Naming, annotations and examples | Structural metadata; no recursive converter dependency. | Preserve name syntax, global conflict policy, emitted text, renderer behavior and checked-example errors. |
| DataError paths and branch details | Validation threads paths and structural errors independently of typed conversion. The environment does not contain output values. | Port the existing diagnostic traversal, including JSON Pointer escaping, rather than replacing it with this prototype's String errors. |
| Self recursion and a typed pair | Close immutable bodies once; builders receive plans. Tested here. | Public migration examples and compile-negative coverage for the actual API. |

No additional output-type obstacle was found in the remaining combinators.
This is narrower than a claim that integration is complete or mechanical.

## Private validation evidence decision

The bounded experiment is implemented. Evidence records atomic acceptance,
accepted array/dictionary/tuple children, record fields and a selected union
branch with its child evidence. Structural wrappers forward base evidence.
Auxiliary constraints discard their own evidence and never retain their typed
converters. References and imported graphs forward the resolved body's evidence.
Defaults store checked evidence at construction, alongside their immutable input;
absent fields reuse it without converting during validation or construction.

`decode` validates the entire input first, then invokes the closed converter with
its matching evidence. Maps still receive ordinary typed outputs. The evidence
contains no decoded values or functions, is private, and cannot be forged through
public constructors. Library conversion neither inspects schema data nor calls
validation or auxiliary converters. Typed recursion receives the already validated child's
evidence, keeping branch selection independent of schema lookup.

The retained tests cover late rejection/ambiguity without primary callbacks,
first-match output, duplicate exclusive branches, independently typed recursion,
defaults, creator-exit handoff, decoded closures, helpers and converter exceptions.
A one-off comparison against `e817685` found all eleven existing probe fixtures
unchanged in exact emitted text, inputs, validation and decoding acceptance.
The new exclusive-union fixtures add independently checked cases.

This is the selected conversion approach for incremental integration. Its
tradeoff is transient structural evidence and cached default evidence. Full
production diagnostics still need preservation, and standalone validation's
receipt allocation needs evaluation. Do not replace full error accumulation with
the prototype's first-error String results.

Next, connect plans and evidence to the production structural checker and emitter
in an isolated integration fixture. Preserve name/conflict policies, canonical
bytes and public error paths, and run the real typed fixtures on both targets
before changing the shipped API. Keep shared-term transfer amplification
explicit; this observation does not justify a permanent registry or manual
release API. Regex integration remains a separate backend gate.

The prototype scopes imported graphs independently and permits names outside
Gargamelle's current restricted syntax. Its same-name composition tests prove
lookup isolation, not preservation of the library's existing conflicting-name
rejection policy. Name validation and conflict handling must be decided explicitly
before migration; the experiment does not authorize either semantic change.

The prototype has its own deliberately small `Value` type and limited schema
vocabulary. It is not a JSON parser, a replacement for production diagnostics, or
a complete independent conformance suite. Regex integration, full target parity,
deployment packaging and clean consumer checks remain separate work.
