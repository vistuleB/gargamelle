# Preparing and publishing Gargamelle

Version 0.2.0 was published on 2026-10-11 from commit `41d2948`.
The published archive checksum is recorded in `release-0.2.md`. This procedure
remains available for subsequent releases. Version 0.1.0 was
published separately and its tag must remain unchanged. Candidate preparation does
not tag, push, publish or change repository visibility. The release audit is in
[0.2.0 candidate review](release-0.2.md). The tested native matrix now includes Ubuntu 24.04 x86_64 with OTP 28.5.0.7
and 29.1.1, plus macOS arm64/OTP 29. See `linux-qualification.md`; a pass does not
qualify every platform, OTP release or deployment format.

The package was renamed from Concord to Gargamelle because Hex’s `concord`
name is owned by an unrelated Elixir package. The maintainer checked Gargamelle’s
availability. Repository visibility must be checked before publication; no visibility change is included.

MIT was selected for Gargamelle’s own code. The exported tarball includes the license,
README, package metadata, Gleam source, JavaScript runtime, native Erlang modules
and vendored regex C sources with their upstream MIT license and provenance. A clean consumer
built and ran against the extracted archive with record decoding, array decoding,
validation, schema emission and checked documentation examples. It resolved only
`gleam_stdlib` and `gleam_json`; no sibling app or npm harness was required.
The npm package is private and exists only for verification tooling. Consumers
install the Gleam package; they do not need the npm verification dependencies.

## Release checks

1. Keep `gleam.toml`, `package.json` and the root package-lock version aligned.
   Review the changelog, migration guide, README, API docs and declared runtime
   support. Preserve `LICENSE` and `priv/regex-src/LICENSE.quickjs`; verify the
   vendor provenance hashes. The optional retained official-suite fixtures have
   their own license in `verification/official/LICENSE`.
2. Install pinned dependencies with `npm ci` and `gleam deps download` on first
   setup. Run `npm run prepare:release` with Node 24, Gleam 1.18.1, OTP 29,
   `make` and a C compiler. It runs JavaScript evidence, seventeen native groups,
   docs generation, archive inspection and fresh extracted-archive consumers on
   both targets. The native deployment group tests a shipment without source
   checkouts. All checks run offline once dependencies are available.
3. Inspect `reports/release-preparation.json` and its logs. The report fingerprints
   the source and records the archive hash, members, tested versions and support
   boundaries. It must match the candidate after the final edit. The separate
   `npm run check:release` checks JavaScript evidence only. Neither command
   replaces review of `PRESERVATION.md` or qualifies untested native platforms.
4. Declare the tested native matrix in the release support statement. Linux OTP
   28.5.0.7 and 29.1.1 now pass, as does macOS arm64/OTP 29. Other OTP releases,
   platforms and deployment tooling are not qualified. Windows uses unsupported
   POSIX helper code. Native Unicode tables are version 16; parity with the
   Unicode 17 tables in Node 24.21.0 is not claimed.
5. Inspect the generated documentation under `build/dev/docs/gargamelle`. Only
   `gargamelle` and `gargamelle/documentation` are public API modules. Versioned
   0.2.0 links become available only after publication; keep the README's candidate
   and published-version statements accurate during preparation.
6. Commit the reviewed candidate. Check publishing-account access, repository
   visibility and release availability before publication. These are external
   publication checks and are not performed by the offline preparation command.
7. When publication is explicitly requested, tag the reviewed candidate `v0.2.0`
   and run `gleam publish`. Verify the Hex release and documentation, then test a
   new consumer pinned to the published version. Push only when authorized. Update
   the candidate status in the README and record the published archive/commit.

```sh
npm run prepare:release
```

The generated archive is `build/gargamelle-0.2.0.tar`. Generated native executables
are excluded; consumers build for their destination and install the helper as
specified in [Native Erlang setup](native-erlang.md).

## Support and compatibility

The supported compilation target is JavaScript. The full verification harness
uses Node 24 and Gleam 1.18.1. Native Erlang evidence covers macOS arm64/OTP 29 and Ubuntu 24.04 x86_64 with
OTP 28.5.0.7 and 29.1.1. Other native platforms and releases remain unqualified. Browser, Bun, Deno and Windows
native-helper support are not claimed. No npm runtime dependency is required by the library.

Dependency versions remain exact for this candidate because those versions
are verified. Wider version ranges should follow compatibility checks rather than
being advertised without evidence. A consuming package may encounter resolver
conflicts when requiring a different version of the same Gleam dependency.

The schema vocabulary is intentionally bounded. Agreement checks exercise emitted
schemas, not every keyword in JSON Schema 2020-12. Known validator discrepancies
and narrow oracle lint exceptions are recorded in
`verification/known-oracle-discrepancies.json` and the README.

Data rejection, admission failure and operational failure are separate outcomes.
Diagnostic wording and categories, and public APIs generally, may evolve during
0.x releases. Release preparation does not change the equation-flashcards app’s
pinned dependency or migrate any stored data.

References: [Gleam package configuration](https://gleam.run/documentation/gleam-toml-reference/)
and [Gleam commands](https://gleam.run/documentation/command-line-reference/).
