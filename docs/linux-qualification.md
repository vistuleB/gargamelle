# Linux qualification result — 2026-10-11

[Run 38132699640](https://github.com/vistuleB/gargamelle/actions/runs/38132699640)
passed both Ubuntu 24.04 x86_64 jobs at commit
`715b8f08018e29a628ea1db86ea1d383bc259c53`. Downloaded report fingerprints and log
hashes were checked against that source. This closes the Linux gate for these
recorded releases, not every OTP release or deployment format.

| Resolved setup-beam build | BEAM runtime | Reference runtime | Result |
| --- | --- | --- | --- |
| OTP 28.5.0.7 | ERTS 16.4.0.6 | Node 24.10.0 / Unicode 16 | Passed |
| OTP 29.1.1 | ERTS 17.1 | Node 24.10.0 / Unicode 16 | Passed |

Both jobs used Gleam 1.18.1. Each passed 45 JavaScript Gleam tests, 144 Node tests,
sixteen native groups, 17,788 native generated cases and 109 selected official
cases. Native process transfer/exit, twelve compile-negative checks, regex
operational failures, source-archive inspection, fresh consumers on both targets
and a deployed Gleam shipment without source checkouts all passed. The earlier
macOS arm64/OTP 29 evidence remains separate.

## Retained evidence

The qualified source fingerprint is
`b89ee2f654e30e991167eda6f9270c23cf24ee49721b0d1b848699c4bc2b7eae`.
The downloaded `release-preparation.json` reports have SHA-256 hashes:

- OTP 28: `3f491fcc6664e32fea7603ccf77ddafcc8c5294e351f33831774f489d352ea5d`.
- OTP 29: `904539635b0d6a3510524e17cc83a7ca12058d911052c454173040e8cc7dc031`.

Reports and logs were downloaded under `reports/linux-38132699640/` locally.
The workflow retains remote artifacts for fourteen days. This source document
records the result after artifact expiry; rerun the workflow for fresh evidence.
Generated artifacts are not committed. Subsequent documentation updates do not
change the qualified executable library code.

## Initial failure and compatibility decision

[Run 38132286154](https://github.com/vistuleB/gargamelle/actions/runs/38132286154)
passed fifteen of sixteen native groups on both OTP versions. The regex comparison
failed because the floating Node 24 selector installed Node 24.21.0 with Unicode
17 data. For U+11DB0, its `\p{L}` and `\p{Assigned}` results differ from the native
Unicode 16 tables. The failure reproduced locally on Node 24.21.0; all 594 cases
passed on the existing Node 24.10.0 reference. CI now pins that exact reference,
and regex assertions report the individual pattern, input and host version.
No checks were skipped and no production engine or JavaScript behavior changed.

Pinning the reference qualifies the existing Unicode 16 contract. It does not
resolve Unicode 17 parity. That gap is public in the README and native setup
guide. Updating native Unicode tables needs a separate compatibility decision and
differential validation; do not hide the difference with validator exceptions.

## Release scope recommendation

Use the tested matrix above for the 0.2.0 native support statement, together with
macOS arm64/OTP 29 and explicit destination-specific helper installation. Earlier
OTP 28 patches, other OTP majors, Linux arm64, Windows and deployment tooling
beyond the Gleam shipment are not qualified. The CI matrix continues testing
available OTP 28/29 patches, rather than establishing that every earlier patch
works. Independent preservation review and the publishing checks remain separate
from this platform result. No package was published or release tag created.
