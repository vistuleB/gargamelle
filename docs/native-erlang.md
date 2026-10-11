# Native Erlang setup

## Tested runtimes

JavaScript is tested on Node 24.10.0 and the desktop versions listed in
[Browser compatibility](browser-support.html). Erlang implements all core operations.
The tested native runtimes are macOS arm64 with OTP 29 and Ubuntu 24.04
x86_64 with OTP 28.5.0.7 and 29.1.1, using Gleam 1.18.1. Deployment is tested
with Gleam shipments. Other platforms, OTP releases and deployment tools remain
unverified. The helper uses POSIX APIs; Windows is not supported.

## Build the regex helper

Erlang uses a standalone C regex executable. Install `make` and a C compiler.
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

Rebuild the helper for each deployment operating system and architecture.

## Release deployment

Install the executable as `priv/gargamelle_regex_port` in the deployed Gargamelle
OTP application, preserving its executable permissions. The binding first checks
that installed location. During development it also resolves the source `priv`
symlink and checks the dependency's `build/native` directory. Release tooling
must copy the helper explicitly; compiling Gleam alone does not install it.

For a downloaded dependency, a minimal Gleam shipment is:

```sh
gleam deps download
make -C build/packages/gargamelle/priv/regex-src
gleam export erlang-shipment
cp build/packages/gargamelle/build/native/gargamelle_regex_port build/erlang-shipment/gargamelle/priv/
chmod +x build/erlang-shipment/gargamelle/priv/gargamelle_regex_port
sh build/erlang-shipment/entrypoint.sh run
```

For a path dependency, copy the helper from that dependency's `build/native`
directory.

A missing helper or a native crash raises an operational error. Execution budget,
stack, packet and timeout limits also raise operational errors, including within
conditional and exclusion checks. They do not become pattern syntax errors or
ordinary validation rejection.

## Regex compatibility

The native regex engine uses Unicode 16 tables and is tested against Node
24.10.0. JavaScript uses its host's Unicode tables, so Unicode property patterns
can match differently on hosts with newer tables, including Node 24.21.0.
See [Browser compatibility](browser-support.html) for a concrete example.
