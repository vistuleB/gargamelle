# Paired-boundary prototype

This is a private prototype under `verification/experiments`. It adds no
package API or public documentation page and does not change main or the prepared
publication archive.

For an isolated app trial, copy `verification/experiments/paired_boundary.gleam`
into the app's source tree under an experimental module name. The prototype is
not a module exported by the Gargamelle package, so pointing a Hex dependency at
this development revision does not expose it automatically. Use the provider's
existing contract and encoder; do not redefine acceptance for the trial.

## Construction and authority

The opaque `PairedBoundary(a, loaded, saved)` stores a decoded receiving boundary and a typed
output boundary. Its constructor accepts one full contract, one encoder, and two
handlers. The output receiver obtains the full contract from the decoded receiver;
there is no second contract argument or mutation operation. The contract accessor
returns the original full contract, including semantic requirements.

The implementation is 45 formatted Gleam lines, with four functions: construction,
contract inspection, load, and save. It introduces no validation engine, registry,
certificate bypass, callback interception, or lifetime mechanism. It delegates to
the existing public APIs.

The existing registration requires three explicit constructions:

```gleam
let loader = gargamelle.boundary(contract, load_handler)
let storage = gargamelle.json_boundary(gargamelle.boundary_contract(loader), save_handler)
let saver = encoding.output_boundary(encoder, storage)
```

The prototype replaces these with:

```gleam
let registration = paired.paired_boundary(contract, encoder, load_handler, save_handler)
```

Loading and saving remain distinct operations, not an automatic transaction:

```gleam
let assert Ok(value) = paired.load(registration, json)
let assert Ok(response) = paired.save(registration, value)
```

## Scope and naming decisions

- This binds one declared contract at both sides. Existing explicit wiring already
  does so correctly; the benefit is preventing accidental separate registration
  with a weaker or drifting egress contract.
- The decoded input type and encoder input type are both `a`, following the existing
  `OutputBoundary` API. Handler response types are independent. This does not cover
  workflows requiring different input and output contracts or different decoded
  and encoder input types.
- Sharing `a` does not guarantee that encoding and decoding are inverses. Output
  semantic checks inspect reconstruction from encoded JSON. The mapping test
  deliberately shows that saving a successfully decoded value can fail.
- `PairedBoundary`, `paired_boundary`, `paired_boundary_contract`, `load`, and `save`
  are the selected names. The prototype remains in a private experimental module;
  placement in the main module is deferred until adoption. No compatibility aliases
  for `Pair`, `pair`, or `contract` were added.
- The opaque pair currently returns no individual endpoints. Some consumers may
  need to hand only a saving capability to a provider while keeping loading at the
  host. Separate endpoint accessors or a different packaging shape would need a
  concrete integration example; no speculative accessors were added.
- This does not yet earn a shipped constructor. The reduction is two registration
  calls, and the host still supplies both handlers and the explicit encoder. A real
  provider registration is needed to assess whether this is preferable to a local
  helper or the existing explicit API.

## Evidence

The experiment compiles the prototype only in temporary consumer test directories.
Five additional shared tests cover callback-free construction/inspection, structural
and semantic rejection at both handlers, independent nested application results,
non-inverse mapping behavior, and Erlang transfer after creator-process exit.
Together with the existing suite, 142 tests pass on each target. A runnable example
produces identical output on JavaScript and Erlang.

Compile-negative checks on both targets reject forwarding a `VerifiedJson` in place
of admitted JSON and constructing the opaque pair directly. JavaScript checks verify
the original contract's identity and exception propagation from conversion, encoding,
and handlers. A targeted mutant drops egress semantic requirements; two behavior
tests must fail, and the restored baseline must pass. These are API enforcement
checks, not a sandbox against hostile FFI.

The temporary Erlang consumer builds its own regex helper rather than relying on a
helper from another checkout. No new Linux qualification or release preparation was
run for this private experiment.

```sh
node --test verification/experiments/paired-boundary.test.mjs
```
