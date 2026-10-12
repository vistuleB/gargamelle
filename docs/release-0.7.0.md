# 0.7.0 release record

The candidate is isolated on codex/json-070. Main remains the published 0.6.0
checkout. The maintainer publishes; no package publication or tag move is performed
by the agent.

Scope: direct admitted JSON constructors with typed errors, an identity definition
for arbitrary admitted JSON, JSON pass-through encoding, and one-way standard JSON
conversion. Constructor policy decisions are in json-construction-design.md.

The latest main cleanup is incorporated: shortened README introduction, no shipped
verification fixtures, and one top-level Gleam namespace. Archive tests compile
both public JSON guide examples and a separate positive/rejection consumer on both
targets. Public guides distinguish admission from Contract acceptance and encoding
from decoding identity.

Final source qualification is recorded in ignored release-preparation, browser,
Linux, and release-handoff-0.7.0 reports. Only reports for the final fingerprint
qualify the candidate; retained tests are evidence, not proof.

Deferred: encoder direct-construction optimization, record-builder ergonomics,
additional schema features, and mutual encoder recursion. OTP parser compatibility
and performance evaluation is reserved for potential 0.8.0 work.
