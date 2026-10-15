# Gargamelle technical contract

This document specifies the intended public semantics of Gargamelle.
“Must” denotes a requirement, not a claim that the implementation has been
formally proved. Verification results and implementation history are separate.
Section 16 lists supported and unsupported JSON Schema keywords and their public
API restrictions.

## 1. Model and scope

A `Definition(a)` consists conceptually of a structural acceptance relation and
a conversion from accepted JSON inputs to values of type `a`. Public definitions
are opaque and constructible only through library operations. The definition is
authoritative: schema emission and decoding are derived interpretations of it.
There is no independent schema/decoder override or arbitrary predicate escape hatch.

A `Contract(a)` combines a completed `Definition(a)` with an ordered list of
semantic requirements. `contract(definition)` adds no requirements;
`require(contract, description, check)` conjoins a reject-only check of decoded
`a`. Requirements cannot transform data or weaken structural acceptance. Checks
must be deterministic, total and free of side effects, with immutable captured
context. They observe decoded data: defaulted fields are present, `Open` extra
fields are discarded, and distinctions removed by maps are unavailable.

`decode_contract` performs structural validation and conversion once, then calls
every requirement once in declaration order. Structural rejection skips all
conversion and requirement callbacks. Normal semantic rejections are collected
as ordered `RequirementFailure` values, each containing a zero-based declaration
index, description and callback-supplied `Violation` diagnostics. Violation paths
are JSON Pointers supplied by trusted application code; the library does not
infer or validate their relationship to the original JSON. `Error([])` remains
rejection and receives a root diagnostic. `ContractError` distinguishes
`Structural(List(ValidationError))` from `Semantic(List(RequirementFailure))`.
Exceptions and resource failures remain operational failures and may prevent
later checks from running. Semantic errors are not structural errors.

`validate_contract` performs validation without conversion when no requirements
exist. Otherwise it decodes once to supply the requirements and discards the
returned data. `verify` uses this operation and returns an opaque `VerifiedJson(a)`
containing original admitted JSON and the exact full contract, including its
checks and captured context. No decoded value is retained. The parameter `a`
identifies an output type, not a particular contract or its constraints.

`Boundary(a, response)` binds a full contract to a private handler. `forward`
calls `decode_contract` once and invokes the handler only on success, passing
decoded data and original JSON. `JsonBoundary(a, response)` instead uses `verify`
and passes a certificate. With semantic requirements this performs one decoding
pass; without requirements no conversion callback runs. Either kind of rejection
invokes no handler. Construction and inspection execute no callbacks.

The receiving and paired APIs are provided by `gargamelle/boundary`.
`PairedBoundary(a, loaded, saved)` binds decoded loading and typed saving handlers
to the same full contract. `load` delegates to `forward`; `save` delegates to the
module's typed output path, encoding once and forwarding once. Encoding rejection
skips verification and the saving handler. `gargamelle_encoding.EncodingError`
retains typed encoding failures or `Contract(error)` for receiving rejection.
Loading and saving need not be inverses or occur together. Saving semantic checks
inspect decoded emitted JSON, not the original encoder input. Construction and
inspection execute no callbacks.

The boundary module's `contract` and `json_contract`, and core `verified_contract`,
expose the exact retained contract. The corresponding definition accessors expose only
its structural definition for schema generation. Receiving boundaries always
check their own stored contract; a foreign certificate cannot bypass a check.
Handler responses remain generic, including nested `Result` values, and are not
checked. Admission, authorization and storage policy are separate operations.
Opaque APIs do not sandbox hostile code in the same runtime.
See [Verified JSON boundaries](boundaries.html).

Constructors compose opaque `Plan(a, r)` values, where `r` is the recursion
environment. A completed `Definition(a)` is the closed specialization
`Plan(a, Nil)`. Only completed definitions can be validated, decoded, emitted or
rendered. Ordinary definitions infer the closed environment from their use.

String arguments to schema constructors must also contain only Unicode scalar
values. Constructors returning `Result` report non-scalar arguments as construction
errors. Direct constructors such as `string_constant`, `title` and `description`
assert that precondition and fail operationally when it is violated; their return
types are unchanged. Conversion callbacks remain trusted application code.

The supported targets are JavaScript and native Erlang. Tested runtimes and setup
requirements are listed in [Browser compatibility](browser-support.html) and
[Native Erlang setup](native-erlang.html). Schemas use JSON Schema
Draft 2020-12 and declare that dialect at the root. The contract applies to the
vocabulary generated by the public constructors, not arbitrary imported schemas.

Let J be finite JSON trees represented after JavaScript JSON parsing: null,
booleans, strings, finite IEEE-754 binary64 numbers, arrays and objects with
string keys. Strings and object keys contain only Unicode scalar values.
Values containing undefined, functions, bigint, NaN, infinities,
cyclic references, accessors or arbitrary host objects are outside J. Public
`Json` is opaque; `parse` admits JSON text into this domain.

Parsing follows `JSON.parse` semantics, including rounding numeric literals,
underflow and retaining the last occurrence of a duplicate object key. Numeric
overflow to a nonfinite value is an admission error. The contract concerns the
resulting parsed value, not arbitrary-precision decimal text. Valid surrogate
pairs are preserved as their scalar value. Unpaired surrogates in final strings
or object keys are domain admission errors. Syntax and duplicate-key resolution
precede domain checking; an overwritten value does not belong to the final tree.
This domain preserves ordinary Gleam `String` outputs across targets.

## 2. Acceptance equivalence and value correctness

For every well-formed, finalized definition S and x in J, assuming sufficient
runtime resources and pure, total conversion callbacks:

```text
Valid202012(schema_json(S), x)
    ⇔ validate(S, x) = Ok(Nil)
    ⇔ ∃v. decode(S, x) = Ok(v)
```

`Valid202012` denotes the dialect’s validation semantics without coercion,
default insertion or property removal. Every comparison must use the same
parsed input value. A validator’s optional lint restrictions are not additional
acceptance rules.

For a contract C with underlying definition S and requirements R, successful
contract decoding additionally requires every check in R to return `Ok(Nil)`
for S's decoded value. Generated schemas describe S only. Schema acceptance is
necessary but insufficient for acceptance by C when R contains requirements.
Requirement descriptions document intended checks; prose is not evidence that
callbacks implement those descriptions. Schema emission must execute no checks.

For accepted input, the returned v must also satisfy S’s decoded-value contract
below. Acceptance agreement alone is insufficient. For invalid in-domain input,
validation and decoding must return structural data errors. They must not treat
callback exceptions or runtime exhaustion as rejection.

`validate` and emission must not execute conversion callbacks. `decode` must
validate the complete input before conversion. Construction must not probe
constructors or maps with fabricated values. Recursive builders receive typed
construction plans, not invented decoded outputs. Neither validation nor
conversion performed by the library mutates the admitted input.

Mappings are trusted application functions. They cannot add structural rejection
rules. Exceptions, nontermination and side effects in user functions are outside
the guarantee. Application checks such as cross-record identity, external
references and business invariants can be expressed as `Contract` requirements.
They do not become structural schema assertions.

## 3. Constructor semantics

The identifiers below describe semantic operations; public API spellings are
listed in the generated API reference. All composition must preserve section 2.

| ID | Construct | Schema/acceptance contract | Decoded-value contract |
|---|---|---|---|
| P01 | Boolean, null | Exactly the corresponding JSON type | Preserve value |
| P02 | String | String only; optional inclusive min/max length and pattern | Preserve string exactly; no trimming, case changes, or Unicode normalization |
| P03 | Safe integer | `integer` plus explicit bounds within -9007199254740991…9007199254740991; optional tighter inclusive bounds | Preserve mathematical integer; accept parsed `1.0` as 1; -0 and 0 are equivalent |
| P05 | Finite number | `number`; optional finite inclusive/exclusive endpoints, intersected on repetition | Preserve the admitted binary64 value as Float, including signed zero; comparison treats both zero signs equally |
| P04 | String enum; string, safe-integer, Boolean and null constants | Exact membership/equality, without coercion | Preserve value; optional mapping follows A02 |
| C01 | Homogeneous array | Array; every item satisfies its child; optional inclusive min/max item count | Preserve order and duplicates; decode every element |
| C02 | Record | Object; declared required/optional fields; explicit extra-field policy | Decode declared fields by wire name and combine into a typed value |
| C03 | String-key dictionary | Object; every value satisfies its child; optional inclusive min/max property count | Preserve every key and decode each value; key order has no semantic meaning |
| C04 | Nullable child | Child accepts OR input is null, including nullable enums/constants/unions | Option(a): None for null, Some(decoded child) otherwise; outer null check takes precedence |
| C05 | Any-of | At least one child accepts | Select the first successful branch in declaration order |
| C06 | One-of | Exactly one child accepts | Decode that unique branch; reject overlapping matches |
| C07 | Tagged union | Object branches with required, distinct string-constant discriminators; equivalent to their emitted one-of | Select the matching variant; discriminator is consumed, not duplicated in branch output |
| C13 | Structural exclusion | Base accepts and forbidden definition rejects the original input | Retain base output; forbidden converters never run |
| C12 | Structural conditional | Base accepts; if condition accepts, consequence accepts; otherwise optional alternative accepts | Retain base output; auxiliary converters never run |
| C11 | Array membership | Typed array/tuple body and inclusive count limits on structurally matching positions | Retain original output; never invoke matching converters |
| C10 | Property names | Dictionary/record input; each present own key satisfies every supplied string-output key definition | Retain original output and keys; never invoke key converters |
| C09 | Exact-length tuple | Array of exactly N elements; position i satisfies child i | Apply the curried typed constructor in positional order |
| C08 | Guarded recursion | Local `$defs`/`$ref` graphs; every cycle must descend through an item, tuple position, dictionary value, or record field | Preserve the declared recursive output type; mutually recursive pairs may have distinct output types |
| A01 | Description/title | Annotation only; no change in accepted inputs or decoded values | Preserve child result |
| A02 | Total map | No change to schema or acceptance | Apply mapping to successfully decoded value; mapping cannot add rejection rules |

## 4. Primitive and constraint rules

Safe integers use inclusive bounds within ±9007199254740991. These limits must
appear in the emitted schema. Parsed `1.0` is integral; integer comparisons treat
negative zero and zero equivalently. Finite numbers decode to `Float` and preserve
the admitted binary64 value, including signed zero. Number constraints use finite
inclusive/exclusive endpoints. Repetition intersects intervals; equal endpoints
with either side exclusive and inverted intervals fail construction. A valid
real interval need not contain a representable binary64 value.

String values are preserved without trimming, case conversion or normalization.
Lengths count Unicode code points, not UTF-16 units or grapheme clusters. Patterns
use ECMAScript Unicode (`u`) regular expressions with search semantics and no
implicit anchoring or additional flags. Invalid expressions fail construction.
Distinct repeated patterns are conjoined; identical patterns are deduplicated
in first-declaration order. Unicode property matching follows the runtime's
Unicode tables; see [Browser compatibility](browser-support.html) and
[Native Erlang setup](native-erlang.html) for the tested versions and differences.
Regex execution bounds are not guaranteed.

Integer bounds and size bounds are inclusive. Size limits are nonnegative safe
integers. `None` denotes an unbounded endpoint. Repetition intersects bounds;
invalid bounds and application to unsupported underlying definitions fail
construction. Naming and annotations preserve modifier support. Same-input
assertions retain their checks; modifiers do not distribute over nullable/union
alternatives or resolve recursive references. Apply a modifier to an alternative
or recursive body during construction. See the [modifier policy](advanced.html)
for supported base shapes and named-body reuse rules.

Enums are nonempty, contain distinct strings and perform no coercion. Constants
use type-sensitive equality. Integer constants must lie in the safe range.

`unique_items` applies to a homogeneous array definition, including supported
naming/annotation/assertion wrappers, and compares the
original JSON items structurally, before mapping. Object key order is irrelevant
and both numeric zero signs are equivalent. Decoded list order is unchanged.

## 5. Records, presence and tagged variants

Fields are static declarations keyed by wire name. A curried constructor consumes
actual decoded field values. Duplicate wire names fail construction. A record
explicitly chooses `Strict` (reject extras) or `Open` (accept extras and project
them away from output). Empty records still require objects. Dictionaries retain
all keys and decode their values to a Gleam list of key/value pairs; key order has
no semantic meaning. Keys including `__proto__`, `constructor`, `toString`, empty
strings and Unicode must be handled as data.

Presence is independent of nullability. For child output a:

| Field | Missing | Present null | Present non-null |
|---|---|---|---|
| Required | Reject | Child decides | Decode child |
| Optional | `None` | `Some(child output)` if accepted, otherwise reject | `Some(child output)` |
| Optional nullable | `None` | `Some(None)` | `Some(Some(child output))` |
| Defaulted | Decode declared default | Child decides; do not substitute | Decode child |

Defaults are admitted JSON values validated during construction without invoking
converters. On absence, conversion decodes that default normally. Present invalid
values never fall back to defaults. The schema’s `default` remains an annotation;
no input or external-validator mutation is permitted.

Nullable uses an outer-first null check: null produces `None`, otherwise the
child result is wrapped in `Some`. Nested nullable values may leave some output
values unreachable. Null bypasses an inner one-of, even if multiple inner branches
accept null. Non-null child errors retain their paths.

A tagged union owns a required string discriminator with distinct tags. Branches
come from record builders; arbitrary wrapped definitions are not branches.
The discriminator must not be redeclared. Variant annotations and maps are
explicit. The selected branch constructs its ordinary payload; the tag is not
injected as an extra output field. Empty variant sets and duplicate tags fail
construction. Missing, invalid or unknown tags are diagnosed before branch fields.

## 6. Structural auxiliary constraints

Auxiliary definitions contribute only their structural acceptance relations;
their conversion callbacks must never execute. Base output and type are retained.
Checks inspect the original admitted input before defaults, projection or maps.

`property_names` constrains every present own object key as a JSON string and
conjoins repeated constraints. It accepts supported record/dictionary bodies.
Keys are not renamed. An empty object satisfies the key constraint vacuously.
A String-output mapping can retain a non-string structural contract; that may
reject every actual key while still accepting the empty object.

`contains` counts array positions satisfying a matching definition, including
duplicate positions, and enforces nonnegative inclusive minimum/optional maximum
counts. It supports homogeneous arrays and exact tuples. Repeated requirements
are conjoined. Minimum zero with no maximum adds no acceptance restriction.
It neither removes unmatched elements nor alters conversion.

`if_then` requires the consequence only when the condition accepts. `if_then_else`
requires the consequence on condition acceptance and the alternative otherwise.
Condition rejection is branch selection, not a data error. Operational failure
must not select the alternative. Repeated conditionals are conjoined.

`exclude` requires the base to accept and every forbidden definition to reject.
A matching forbidden definition produces a data error at the current path.
Operational failure is not evidence of forbidden rejection. Repetition intersects
constraints without replacing previous exclusions.

## 7. Names and recursion

Names start with an ASCII letter and otherwise contain only ASCII letters,
digits, underscores or hyphens. Named definitions preserve acceptance and output
while emitting finite local `$defs`/`$ref` graphs. Distinct bodies with conflicting
names, including transitive conflicts, must not produce an ambiguous schema.

Self recursion and mutually recursive pairs use typed construction plans and retain
the declared output types; the pair’s types may differ. Builders run exactly once
and return plans under the supplied recursion environment. The result contains
completed definitions. `lift` composes a completed definition inside a builder
without giving it dependencies on that builder's recursion environment.
Every cycle must descend
into a strict input subvalue through an array item, tuple position, dictionary
value or record field. Names, references, nullable, union, annotations and
same-input constraints do not supply descent. Same-input cycles fail construction,
including syntactically reachable cycles in otherwise unreachable branches.
The guard is conservative; it is not a satisfiability proof.

Construction plans cannot be validated, decoded, emitted or rendered, even after
the builder returns. This is a type boundary, not a temporary runtime restriction.
Defaults cannot be checked against unresolved references. Captured construction
plans retain that type; capturing them in a callback output does not finalize
them. Reusing an unresolved foreign reference in another construction fails
construction. Completed definitions and closures capturing them remain usable
after transfer and creator-process exit, without reference registries or manual
release. Conflicting composed graphs fail operationally at public validation or
emission boundaries. Emission remains finite even for recursive definitions.

There is no implicit decoding depth cap, input-size cap or definition-size cap
in acceptance. Stack exhaustion, timeouts and other resource failures remain
operational failures. Linear or bounded runtime is not guaranteed for arbitrary
compositions, overlapping branches or patterns.

## 8. Schema emission and canonical serialization

`schema_json` returns an opaque JSON value describing the definition;
`schema_string` returns compact canonical JSON or its pretty-printed layout,
as selected by `JsonLayout`. Emission must not depend on
conversion callbacks or process history. The schematic forms are:

| Construct | Emitted form (schematic) |
|---|---|
| Boolean / null | `{"type":"boolean"}` / `{"type":"null"}` |
| String | `{"type":"string"}` plus supplied `minLength`, `maxLength`, `pattern` |
| Safe integer | `{"type":"integer","minimum":effective_min,"maximum":effective_max}`; always include safe bounds or tighter bounds |
| String enum | `{"type":"string","enum":[declared values]}` |
| Constant | `{"type":corresponding_type,"const":value}`; safe-integer constants use type `integer` |
| Exclusion | `allOf` containing the base and separate `not` schemas |
| Conditional | `allOf` containing the base and separate `if`/`then`/optional `else` schemas |
| Membership | Array body plus `contains`, explicit `minContains`, optional `maxContains`; repeated requirements use `allOf`; vacuous zero/no-maximum requirement omitted |
| Property names | Object body plus `propertyNames: key`; repeated constraints use `allOf`; explicit object type beside named references |
| Tuple | `{"type":"array","prefixItems":[children],"items":false,"minItems":N}`; omit `prefixItems` for N=0 |
| Array | `{"type":"array","items":child}` plus supplied `minItems`/`maxItems` |
| Record | `{"type":"object","properties":{...},"required":[...],"additionalProperties":true_or_false}`; include empty properties/required |
| Dictionary | `{"type":"object","additionalProperties":child}` plus supplied `minProperties`/`maxProperties` |
| Nullable | `{"anyOf":[child,{"type":"null"}]}` unconditionally, including nested nullable, enum and null children |
| Any-of / one-of | `{"anyOf":[children]}` / `{"oneOf":[children]}` in declaration order; no flattening or deduplication |
| Tagged union | `{"oneOf":[augmented branch records]}` in declaration order |
| Required / optional field | Include / omit wire name in record `required`; presence alone does not change child schema |
| Defaulted field | Omit wire name from `required`; attach declared JSON `default` to its child schema |
| Description/title | Attach `description`/`title` to the child schema object; outermost repeated annotation wins |
| Total map | Emit child schema unchanged |


Finite numbers emit `type: number` with `minimum`/`maximum` or
`exclusiveMinimum`/`exclusiveMaximum` as appropriate. Unique arrays add
`uniqueItems: true`. Named/reference targets are collected into root `$defs`
and represented by local `$ref` without recursive expansion. No remote or
dynamic references or implicit `$id` are introduced.

The root declares `$schema: https://json-schema.org/draft/2020-12/schema`.
Metadata is added only by the corresponding constructors. Distinct repeated
string patterns emit `allOf` pattern branches; repeated membership, property-name,
conditional and exclusion constraints preserve conjunction. Zero/no-maximum
membership may omit vacuous keywords. Annotations do not change acceptance and
outermost repeated titles/descriptions win.

Required-field arrays are sorted by lexicographic UTF-16 code-unit order; enum,
union and other semantically ordered arrays preserve declaration order. Canonical
text recursively inserts object keys in that sorted order and uses compact
`JSON.stringify` serialization without a trailing newline. JavaScript enumeration
then places array-index keys first in numeric order. Thus properties named `2`
and `10` serialize in numeric order, while the required array is `["10","2"]`.
Defaults obey the same canonicalization. All own keys must survive serialization
without invoking inherited setters or changing prototypes.

For the same finalized definition, text emission must be byte-identical:

```text
parse(schema_string(S, Compact)) = Ok(schema_json(S))  // JSON value equality
schema_string(S, Compact) = schema_string(S, Compact)            // byte equality on repeated emission
```

JSON object member order is not part of value equality. Serialization normalizes
negative zero to zero. There is no arbitrary schema importer,
surjectivity guarantee onto the output type or decode/encode inversion promise.
Defaults, projection and maps can deliberately lose the original representation.

## 9. Errors and boundaries

Admission errors concern JSON syntax, nonfinite parsed values and non-scalar
strings or object keys. Construction
errors concern invalid definitions: duplicate fields/tags/enums, empty enums or
unions, invalid bounds, constants, defaults, names, regexes or recursion graphs,
and unsupported constraint/definition combinations. Some invalid combinations
are excluded by static types. Data errors concern admitted values rejected by a
well-formed definition. Operational failures are distinct from all three.

Data paths are JSON Pointers: root is the empty string, array indices are decimal,
`~` becomes `~0` and `/` becomes `~1`. Missing required fields point to the containing
object and carry `missing_key`; undeclared keys point to that key. Errors have
categories. Union errors carry zero-based branch failures for no match and
matching indices for one-of ambiguity. Selected tagged-branch errors pass through;
nullable non-null child errors preserve their paths. English wording and error
enumeration order are not guarantees.

JavaScript decoding and emission require no filesystem or network access.
Native Erlang pattern validation requires the installed C regex helper described
in [Native Erlang setup](native-erlang.html). Core operations have no application
storage or UI dependencies. Runtime helpers may implement primitive JSON,
regex, numeric and graph operations; they must not forge generic typed values.

## 10. Optional documentation

HTML documentation is presentation of the emitted vocabulary, not an independent
validator. Text and attribute values must be escaped. Shared and recursive
references are represented finitely with links. Presentation aliases do not
change schema or decoding semantics.

Checked examples are admitted input values validated against the definition,
without executing converters. All rejected example indices and validation errors
are returned instead of rendering a successful example section. Accepted examples
are displayed as escaped canonical input JSON, not as decoded outputs. An empty
example list has the ordinary rendering behavior.

## 11. Typed encoding

`gargamelle/encoding` supplies independent opaque `Encoder(a)` plans. Primitive
encoders, field getters, projections, lists, nullable values and selected sum
branches construct a JSON representation explicitly. No encoder is inferred
from a Definition and no inverse of a decoding constructor is assumed.

`encode_json` must return admitted JSON or an encoding/admission error. It
asserts no structural or semantic acceptance rule. `Codec(a)` pairs an Encoder
with a full Contract; checked `encode` must encode once and call `verify` once.
Success retains the emitted JSON and exact accepting Contract. Requirements
inspect the decoded emitted representation, not the original encoder input.
Those values need not be equal after mapping, projection or default insertion.

`OutputBoundary(a, response)` pairs an Encoder with an existing JsonBoundary.
The receiver's Contract is authoritative. `send` must perform plain encoding
then forward once through that receiver, without pre-verifying against another
Contract. Encoding/admission rejection or receiving rejection invokes no handler.
Success invokes the receiving handler once. Responses remain generic/nested and
operational exceptions propagate.

Only completed encoding plans execute. A self-recursive builder executes once,
and its completed immutable encoder must survive creator-process exit and
transfer on Erlang without a registry, casts or manual release. `lift` adapts a
completed encoder to a construction environment. Recursion and callback
termination are trusted-code assumptions; immediate encoder recursion can diverge.
Mutual encoder pairs and resource bounds are not provided.

Encoding currently serializes an intermediate gleam/json.Json representation
and admits its text once. No fused single-pass encoding/certification or allocation
bound is claimed. Nonfinite Float and unsafe Int inputs must fail rather than be
silently normalized to null or rounded integer output. Encoding failures stop at
the first failure. InvalidValue carries a JSON Pointer into the would-be output
and a typed primitive reason. Compositions prepend escaped field names and decimal
array indices; nullable, Result and projection wrappers add no segments. String
scalar checks occur before leaf serialization so domain errors retain their
location. InvalidField identifies a rejected declaration key separately; there
is no containing output path until the builder is composed. Final admission
failure uses the root. Contract failures retain their normal structural and
semantic diagnostics. Subsequent getters and element encoders must not run after
an encoding rejection. Construction must invoke no getters,
projections, requirements or receiving handlers.
See [Typed JSON encoding](encoding.html).

## 12. JSON text layout

`to_string(json, Compact)` and `schema_string(definition, Compact)` return
canonical JSON. `Pretty` formats that same text with two-space indentation,
without changing number tokens, string escaping or key order. Empty arrays
and objects remain inline; neither format adds a trailing newline. Parsing
both formats recovers the same admitted JSON value.

## 13. Schema annotations and additional constraints

`examples` attaches admitted JSON samples as metadata without checking their
conformance or changing acceptance/conversion. Repeated annotations of the same
keyword at the same emitted node use the outermost (last supplied) value.

`default_annotation` attaches an admitted JSON annotation without checking conformance or
changing conversion. A defaulted record field emits its validated declared
default, overriding any standalone default annotation on its child.

`format_annotation` is annotation-only, including custom names. Schema/decoder agreement
assumes external validators do not enable optional format assertions. A consumer
that enables such assertions adds acceptance rules beyond this contract.

`assert_format(_, Uuid)` adds a string-only UUID syntax check using explicit
36-code-point bounds and an ASCII hexadecimal/dash pattern. Both decoder and
schema enforce those ordinary constraints. The `uuid` format keyword remains
metadata; no Format-Assertion vocabulary or optional validator switch is required.
UUID version and variant bits are not restricted, and accepted case is preserved.

`dependent_required` checks original own-key presence on object definitions.
Null is present; decoded defaults do not create input presence. Repeated trigger
rules merge their required keys. Failures use category `dependent_required`, the
object JSON Pointer, and `missing_key` for each missing dependent key.

`integer_multiple_of` requires a positive safe-integer divisor and a safe-integer
definition. Acceptance uses exact integer remainders after the base definition
accepts. Repeated divisors intersect; emission uses `multipleOf` and, when needed,
additional conjunctive `allOf` constraints. Fractional divisors and unrestricted
number definitions are excluded from this operation.

## 14. Direct JSON construction

Public `json_*` constructors retain opaque admitted `Json`. Null, Boolean and
array construction are infallible for typed inputs. String and key construction
requires Unicode scalars; Float construction requires finiteness. Int construction
requires the common safe range and rejects larger values instead of rounding.
Object construction rejects repeated keys and attributes the first bad key.
Children are already admitted and are not serialized or reparsed. Construction
does not certify a structural definition or Contract.
See [Constructing JSON values](json-values.html).

## 15. Unconstrained admitted JSON

`anything()` accepts every admitted Json and returns that original Json unchanged.
Its subschema is empty and the root contributes only the dialect annotation.
Agreement is restricted to the documented admitted domain; arbitrary runtime
objects, nonfinite numbers and non-scalar strings/keys remain excluded. Constraints
on enclosing records or arrays and explicit semantic requirements still apply.


## 16. JSON Schema 2020-12 coverage

This table describes schemas generated by Gargamelle's public constructors. It
is not a claim that Gargamelle imports or evaluates arbitrary schemas. Supported
assertions agree with structural validation only within the admitted JSON domain
and validator settings specified above. Semantic Contract requirements are
additional checks and are not represented in JSON Schema.

The keyword inventory follows the official [2020-12 Core specification](https://json-schema.org/draft/2020-12/json-schema-core)
and [Validation specification](https://json-schema.org/draft/2020-12/json-schema-validation).
“Restricted” means only the listed forms are exposed; “Unsupported” means no
public constructor or emission facility is provided for that keyword.

### Validation

| Keywords | Coverage | Public API and restrictions |
| --- | --- | --- |
| `type` | Restricted | Primitive, array and object constructors; unions and `nullable` combine types. `safe_integer` additionally enforces the safe range. No unconstrained integer constructor. |
| `enum` | Restricted | `string_enum` accepts nonempty sets of distinct strings; no general JSON enum. |
| `const` | Restricted | String, Boolean, null and safe-integer constants; no fractional, array or object constants. |
| `minimum`, `maximum` | Supported | `bounds` for safe integers; `number_bounds` for finite binary64 numbers. |
| `exclusiveMinimum`, `exclusiveMaximum` | Supported | `number_bounds` with exclusive endpoints. |
| `multipleOf` | Restricted | `integer_multiple_of` with a positive safe-integer divisor on a safe-integer definition; no fractional divisibility or unrestricted-number form. |
| `minLength`, `maxLength` | Supported | `bounds` on strings; lengths count Unicode code points. |
| `pattern` | Supported | `pattern`; ECMAScript Unicode search semantics, subject to documented runtime differences. |
| `minItems`, `maxItems` | Restricted | `bounds` on homogeneous arrays; fixed tuples emit their exact-length constraints. No general variable-length tuple bounds. |
| `uniqueItems` | Restricted | `unique_items` on homogeneous arrays; compares original JSON elements. |
| `minContains`, `maxContains` | Restricted | `contains` on homogeneous arrays or fixed tuples with explicit match counts. |
| `minProperties`, `maxProperties` | Restricted | `bounds` on dictionaries; not record property-count modifiers. |
| `required` | Supported | `required` record fields and tagged discriminators. |
| `dependentRequired` | Supported | `dependent_required` on object definitions; checks original input key presence. |

### Applicators and unevaluated locations

| Keywords | Coverage | Public API and restrictions |
| --- | --- | --- |
| `properties` | Supported | Statically declared record fields and tagged variants. |
| `additionalProperties` | Restricted | `Strict`/`Open` records emit false/true; dictionaries emit a child schema. No schema-constrained extra fields alongside declared record fields. |
| `patternProperties` | Unsupported | No pattern-selected object value definitions. |
| `propertyNames` | Supported | `property_names` on object definitions. |
| `dependentSchemas` | Unsupported | No schema dependency constructor; `dependent_required` covers key dependencies only. |
| `items` | Restricted | Homogeneous arrays use one child schema; fixed tuples prohibit trailing items. No typed prefix with a separately typed variable tail. |
| `prefixItems` | Restricted | Fixed-length tuples only. |
| `contains` | Restricted | Membership assertions on homogeneous arrays or fixed tuples; probe conversion callbacks do not run. |
| `allOf` | Restricted | Emitted to conjoin constraints and preserve repeated assertions. No general public intersection constructor. |
| `anyOf`, `oneOf` | Restricted | Nonempty alternatives sharing a decoded output type; also nullable and tagged-union forms. |
| `not` | Restricted | `exclude` adds a forbidden-input assertion to a base definition. |
| `if`, `then`, `else` | Restricted | `if_then` and `if_then_else` add assertions to a base definition; branch checks do not determine conversion. |
| `unevaluatedItems`, `unevaluatedProperties` | Unsupported | No tracking or constraints for unevaluated locations. |

### Core and schema forms

| Keywords or form | Coverage | Public API and restrictions |
| --- | --- | --- |
| `$schema` | Restricted | The root declares Draft 2020-12; no selectable dialect. |
| `$defs`, `$ref` | Restricted | Generated finite local references from `named`, `recursive` and `recursive_pair`; no arbitrary reference URIs, remote resolution or schema import. |
| `$id`, `$anchor` | Unsupported | No resource identifiers or user-declared anchors. |
| `$dynamicRef`, `$dynamicAnchor` | Unsupported | No dynamic reference resolution. |
| `$vocabulary` | Unsupported | No custom vocabulary or dialect declarations. |
| `$comment` | Unsupported | No schema comment annotation constructor. |
| Empty and Boolean schemas | Restricted | `anything()` emits an empty subschema accepting all admitted JSON. No direct Boolean-schema constructor; `exclude(anything(), anything())` can express rejection of every admitted input. |

### Annotations, formats and content

| Keywords | Coverage | Public API and restrictions |
| --- | --- | --- |
| `title`, `description` | Supported | Annotation constructors; no effect on acceptance or conversion. |
| `default` | Supported | Metadata via `default_annotation`; defaulted record fields separately validate and insert their declared defaults during decoding. |
| `examples` | Supported | Admitted JSON metadata, without automatic conformance checks. Checked HTML examples are a separate rendering operation. |
| `deprecated`, `readOnly`, `writeOnly` | Unsupported | No corresponding annotation constructors. |
| `format` | Restricted | Arbitrary annotation names via `format_annotation`; optional external format assertions must remain disabled for agreement. `assert_format(_, Uuid)` separately enforces UUID syntax through ordinary length and pattern assertions. No general Format-Assertion vocabulary support. |
| `contentEncoding`, `contentMediaType`, `contentSchema` | Unsupported | No encoded-content annotations, decoding or validation. |

A schema may combine supported keywords only through the available constructors
and their documented wrapper/modifier policy. Keyword coverage does not imply
that every combination permitted by JSON Schema has a typed Gargamelle equivalent.

## 17. Other excluded guarantees

Gargamelle does not import arbitrary schemas, derive encoders automatically,
provide migrations or promise reversible value conversion. Recursive definitions
support self-recursion and typed pairs, not arbitrary heterogeneous recursion
groups. Runtime qualification is limited to the documented JavaScript and native
Erlang matrix. Formal or machine-checked correctness, bounded resource use and
safety against hostile application code are not promised.

## 18. Compatibility from 1.0

The following commitments apply from 1.0.0 onward. Earlier releases remain
subject to the documented pre-1.0 API changes. Compatibility concerns documented
public behavior, not implementation details or generated compiler artifacts.

### Public API and runtime support

Within a major version, public module paths, function names, argument order and
types, return types, public type constructors and their fields remain compatible.
Removing or changing these requires a major release. Adding a variant to a public
non-opaque type also requires a major release because callers can match it
exhaustively. New functions and independent types may be added in minor releases.
Opaque representations, private helpers and generated JavaScript/Erlang symbols
are not public compatibility surfaces; use the public Gleam API.

Removing a supported runtime baseline, raising the minimum Gleam version, or
introducing incompatible native-helper installation requirements requires a major
release. Newly qualified runtimes may be added without one. No fixed runtime or
allocation bound is promised.

### Acceptance, conversion and handlers

Existing well-formed definitions and contracts retain their documented admission,
structural acceptance, conversion, defaults and field-projection semantics.
Callback suppression and ordering, handler invocation, and certificate retention
guarantees are also preserved. Deliberately changing these requires a major
release. Widening acceptance is not automatically compatible: it can change
`one_of`, conditional or exclusion results. New opt-in constructors or constraints
may be added in minor releases without changing existing definitions.

A correction restoring behavior already required by the published contract may
be released as a patch. Its release notes must identify changed acceptance or
outputs, affected constructions and any consumer action required. A changed
contract must not be presented as an implementation correction.

### Emitted schemas and JSON text

Generated schemas retain the documented dialect, structural acceptance rules,
explicit metadata and user-supplied definition names. Schema/decoder agreement
and the distinction between structural and semantic requirements remain binding.
Equivalent schema representations, such as a different conjunctive `allOf`
layout, may change in minor releases. Exact schema object layout, generated
reference placement, and emitted bytes are not stable across releases.

Canonical key ordering, number/string serialization and `Pretty` layout follow
the documented rules for each release. Repeated-emission determinism does not
promise byte-identical schemas or serialization across different releases.
Applications using emitted text as a persistent hash or signature must pin the
package version. Changes that violate the documented serialization rules require
a major release unless they correct a contract violation as described above.

### Diagnostics

Public error constructors and fields, existing category meanings, JSON Pointer
escaping and attribution rules, and zero-based branch/requirement indices remain
compatible. Changing these requires a major release. New string categories may
be added in minor releases for newly supported cases; consumers must handle
unknown categories. This does not permit recategorizing existing documented
failures without a major release or an explicitly identified contract correction.

`diagnostics.to_json` preserves existing report fields, value types and meanings.
Additional object fields may be added in minor releases; consumers must ignore
unknown fields. Existing fields are not removed or repurposed. Reports and
summaries do not include submitted JSON values automatically.

Human-readable messages, summary prose and unspecified error enumeration order
are not compatibility guarantees. Requirement order and branch indices continue
to follow their documented declaration order. Application-authored messages are
retained as supplied; no redaction guarantee is introduced.
