# Migrating to 0.5.0

Receiving boundaries and JSON certificates now enforce a full `Contract(a)`.
A `Definition(a)` continues to describe structural acceptance, decoding and
JSON Schema generation. Its API and structural semantics are unchanged.

## Structural-only contracts

Wrap a definition with `contract(definition)` when constructing a boundary or
calling `verify`. No semantic checks are added. JSON-only verification continues
to skip conversion callbacks in this case.

| Operation | Previous argument | New argument |
| --- | --- | --- |
| `boundary` | `Definition(a)` | `Contract(a)` |
| `json_boundary` | `Definition(a)` | `Contract(a)` |
| `verify` | `Definition(a)` | `Contract(a)` |

`forward`, `forward_json` and `verify` now return `ContractError` on rejection.
Structural failures are wrapped in `Structural(errors)`. Semantic failures are
reported separately in `Semantic(failures)`.

## Semantic requirements

`require(contract, description, check)` appends a check of decoded `a` returning
`Result(Nil, List(Violation))`. Checks cannot transform the value. They must be
pure and total, with immutable captured context. Checks run once in declaration
order after structural success; normal failures are collected. Exceptions remain
operational failures.

`decode_contract` returns decoded data after all checks pass. `validate_contract`
and `verify` decode once if checks exist, then discard decoded data. A typed
boundary passes that already checked decoded value to its handler.

## Inspection and documentation

`boundary_contract`, `json_boundary_contract` and `verified_contract` expose the
full contract. Existing `*_definition` accessors remain structural accessors for
schema generation. `contract_requirements` returns descriptions in declaration
order; `documentation.render_contract` includes them after structural HTML.

Generated JSON Schema describes the underlying definition only. Semantic checks
are additional acceptance conditions, not schema keywords. Requirement prose
records intended behavior; it does not prove that a check implements that prose.
`VerifiedJson(a)` retains the exact contract and original JSON, not decoded `a`.
The type parameter does not identify particular constraints or captured context.
