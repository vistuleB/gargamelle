# Native Erlang setup

The 0.2.0 source has native Erlang implementations for all core operations.
JavaScript remains the supported target while native platform, deployment and
performance verification are completed. The published 0.1.0 package is unchanged.
The current native setup is tested on macOS with OTP 29 and Gleam 1.18.1.

## Build the regex helper

Erlang uses a standalone C regex executable. Install `make` and a C compiler.
From a source checkout, run:

```sh
make -C priv/regex-src
gleam test --target erlang
```

For a downloaded dependency in a Gleam application, run from the application root:

```sh
gleam deps download
make -C build/packages/gargamelle/priv/regex-src
gleam run --target erlang
```

For a local path dependency, run `make -C priv/regex-src` in that dependency's
source directory instead. Gleam does not automatically run this Makefile.
The build creates `build/native/gargamelle_regex_port` inside the dependency.
JavaScript builds do not require it. No JavaScript runtime is needed on Erlang.

The Hex archive contains the C sources, license and provenance record. Generated
executables stay outside `priv` to keep host binaries out of source exports.
Rebuild for each deployment operating system and architecture.

## Release deployment

Install the executable as `priv/gargamelle_regex_port` in the deployed Gargamelle
OTP application, preserving its executable permissions. The binding first checks
that installed location. During development it also resolves the source `priv`
symlink and checks the dependency's `build/native` directory. Release tooling
must copy the helper explicitly; compiling Gleam alone does not install it.

A missing helper or a native crash raises an operational error. Execution budget,
stack, packet and timeout limits also raise operational errors, including within
conditional and exclusion checks. They do not become pattern syntax errors or
ordinary validation rejection.

## Compatibility and remaining verification

The engine combines QuickJS 2026-06-04 regex code with Unicode 16 tables from
2025-09-13 and two recorded local patches. The Unicode version matches the tested
Node 24 reference. JavaScript uses its host's Unicode tables; parity with other
hosts requires verification. `priv/regex-src/PROVENANCE.json` records the sources,
hashes and patches, and `LICENSE.quickjs` preserves the upstream MIT license.

Each regex operation starts a helper. The direct binding check measured about
7.5 ms per pattern/input pair, including both syntax and match helper starts.
Workloads with many patterned values need performance measurements before native
adoption. Linux, Windows, other OTP versions and release deployment remain
unverified; the current helper uses POSIX APIs. The differential corpus provides
bounded evidence rather than complete ECMAScript conformance.
