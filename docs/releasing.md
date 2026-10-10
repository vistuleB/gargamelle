# Preparing and publishing Gargamelle

The 0.1.0 working tree is a release candidate, not a published Hex release.

The package was renamed from Concord to Gargamelle because Hex’s `concord`
name is owned by an unrelated Elixir package. The maintainer checked Gargamelle’s
availability. The repository remains private; no visibility change is included.

MIT was selected for Gargamelle’s own code. The exported tarball includes the license,
README, package metadata, Gleam source and JavaScript runtime. A clean consumer
built and ran against the extracted archive with record decoding, array decoding,
validation, schema emission and checked documentation examples. It resolved only
`gleam_stdlib` and `gleam_json`; no sibling app or npm harness was required.
The npm package is private and exists only for verification tooling. Consumers
install the Gleam package; they do not need the npm verification dependencies.

## Release checks

1. Confirm the license choice and include its text in `LICENSE` and its SPDX
   identifier in `gleam.toml`. Retain the separate JSON Schema test-suite license
   in `verification/official/LICENSE` when distributing those fixtures.
2. Keep `gleam.toml`, `package.json` and the root package-lock version aligned.
   Review the changelog, README, public API docs and supported runtime statement.
3. Run `npm ci` and `gleam deps download` when setting up the repository, then
   `npm run verify` and `npm run check:release`. The latter checks current evidence;
   it does not replace review of the preservation argument in `PRESERVATION.md`.
4. Run `gleam docs build` and inspect the generated API pages. Only `gargamelle` and
   `gargamelle/documentation` are public; `schema_fixtures` is internal test support.
5. Run `gleam export hex-tarball`. Inspect the archive for metadata, Gleam source,
   `runtime.mjs`, README and license; exclude credentials and build artifacts.
   Extract its contents and build/run a new JavaScript consumer using that extracted
   package as a path dependency. It must work without the app checkout or npm tools.
6. Verify that the Hex name is available and that the publishing account can own it.
   Package names are global. Repository visibility and source links should be
   reviewed before publishing; this preparation does not change visibility.
7. Commit the reviewed candidate and tag it `v0.1.0`. Regenerate evidence after a
   commit if the report needs to identify that exact commit.
8. When publication is explicitly requested, run `gleam publish`. This uploads the
   package and generated documentation. Verify the Hex release, then test a new
   consumer with `gargamelle = "== 0.1.0"` and update the README’s availability statement.

## Support and compatibility

The supported compilation target is JavaScript. The full verification harness
uses Node 24 and Gleam 1.18.1 or later. Browser, Erlang, Bun and Deno support is not
claimed. No npm runtime dependency is required by the library.

Dependency versions remain exact for this first candidate because those versions
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
