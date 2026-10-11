# Linux and OTP qualification

The workflow `.github/workflows/native-qualification.yml` runs independent
Ubuntu 24.04 x86_64 jobs for OTP 28 and OTP 29, using Gleam 1.18.1 and Node 24.10.0 (Unicode 16).
It runs on main pushes, pull requests and manual dispatch. It has read-only
repository permissions, does not retain checkout credentials and cannot publish
the package. The first hosted run failed the native regex comparison because the floating
Node 24 selection resolved to Node 24.21.0 with Unicode 17. The native tables
are pinned to Unicode 16; CI now pins the previously verified Node 24.10.0.
See [the initial run](https://github.com/vistuleB/gargamelle/actions/runs/38132286154).
The failure remains retained; selecting a matching reference does not establish
parity with Unicode 17.

Each job fetches the pinned dependencies, then runs `npm run prepare:release`:
the JavaScript gate, seventeen native groups, docs generation, source archive
inspection and fresh archive consumers on both targets. The native groups include
the 17,788 generated cases, all 109 selected official cases, process lifetime and
operational failures, and a Gleam shipment with source checkouts removed.
Reports and failure logs are retained as separate fourteen-day artifacts per OTP
job, including failed runs. A failed job must not qualify its platform.

## Version policy and review

OTP 28 and 29 are candidates for a supported range, not a declaration that every
release in those majors works. The setup action resolves an available patch
release within each major. Evidence records the actual BEAM system version, OTP
major, compiler, Node runtime, architecture and source fingerprint. Review the
resolved versions and logs before choosing a minimum supported release. Neither
Windows nor Linux arm64 is exercised by this matrix.

Actions are pinned to commits resolved from their official repositories on
2026-10-11. The setup inputs and Ubuntu/OTP combination follow the
[setup-beam documentation](https://github.com/erlef/setup-beam). The other actions
are [checkout](https://github.com/actions/checkout),
[setup-node](https://github.com/actions/setup-node) and
[upload-artifact](https://github.com/actions/upload-artifact). Dependency download
steps use the network; verification itself uses local pinned dependencies.

Review `reports/release-preparation.json`, the per-target logs and
`reports/native-official-evidence.json` from both jobs. A preparation report
qualifies only its recorded platform, versions and source. It does not establish
all deployment formats, exhaustive regex conformance or application throughput.
Update the public support statement only after both jobs pass and the declared
range is reviewed. Local macOS arm64/OTP 29 evidence remains separate from the hosted Linux jobs.

The corrected [run 38132699640](https://github.com/vistuleB/gargamelle/actions/runs/38132699640)
passed on OTP 28.5.0.7 and 29.1.1. Report fingerprints and log hashes were checked
after download. See [the qualification record](linux-qualification.md) for the
verified matrix, retained hashes, initial failure and remaining boundaries.
