# Contract design decisions for review

## Scope

0.5.0 adds reject-only semantic requirements above `Definition`. Definitions retain
their structural schema/decoder equivalence guarantee. Typed encoder integration
is reserved for 0.6.0. No duplex transport or certificate-reuse shortcut is added.

## Decisions

- Boundaries and `verify` take `Contract(a)` directly. Structural-only callers
  explicitly wrap a definition. Compatibility overloads are omitted so acceptance
  authority has one public representation.
- Requirements observe decoded values. Open extra fields and distinctions erased
  by maps are unavailable. Original admitted JSON remains available to handlers
  and certificates. Checks of source-only distinctions require a different design.
- Every normal check runs once in declaration order and all rejections are
  collected. Operational exceptions propagate and may stop subsequent callbacks.
- Diagnostics retain a zero-based requirement index and its description. Paths
  are trusted callback-supplied JSON Pointers. Empty failure lists synthesize a
  root diagnostic rather than silently becoming acceptance.
- Descriptions must contain Unicode scalars. They need not be unique or nonempty;
  indices distinguish requirements and rendering preserves duplicates.
- A check-free JSON boundary performs validation without conversion. Semantic
  requirements cause one decoding pass, whose output is discarded after checking.
  Typed boundaries reuse the decoded value for their handler. No decoded value
  is retained in a certificate.
- Certificates retain the exact full contract, including immutable captured
  context. Receiving boundaries nevertheless check their own contract. Equal
  output types do not establish equal acceptance rules.
- Schema emission exposes only structural acceptance. HTML contract rendering
  lists every additional requirement with escaped prose and invokes no callbacks.
  Requirement prose is not proof of callback correctness.
- Captured provider context must distinguish permanent historical guarantees from
  current-card guarantees. A new answer key must not invalidate historical evidence.

## Initial evidence

Shared tests cover structural callback suppression, ordered checks and failures,
empty rejection, original Open-record JSON, certificate authority, Erlang process
transfer, typed/JSON receiver agreement, and callback-free documentation. JavaScript
checks additionally distinguish semantic rejection from operational exceptions.
The isolated provider probe compiles all five production providers from their
source-of-truth files. Temporary cloze and diagram sources split permanent
historical checks from independent current-context predicates; each requirement
runs once without repeating historical predicates. Both receiver types agree
across accepted, semantic-rejected and structural-rejected samples. The probe
also checks session context, verbatim versions 1–3 and foreign certificates.
The app checkout and dependency pin remain unchanged. Production adoption belongs
to the app maintainer. Fresh archive consumers exercise the Contract layer on
both targets; platform release qualification remains a separate gate.
