# Browser compatibility

Compile Gargamelle for Gleam's JavaScript target to use it in a browser.
The JavaScript target does not require the native Erlang C helper.

The following desktop browsers were tested on macOS arm64 with Gleam 1.18.1:

| Browser | Tested version |
| --- | --- |
| Chrome | 155.0.8059.40 |
| Firefox | 157.0.1 |
| Safari | 27.0 |

Older releases, mobile browsers, workers, Bun and Deno remain unverified.

## Regex Unicode properties

JavaScript regex matching uses the host's Unicode tables. Native Erlang regex
uses Unicode 16 tables, with Node 24.10.0 as the tested parity reference.

The tested browsers accept U+11DB0 as `\p{L}` and `\p{Assigned}`, while the Node
Unicode 16 reference does not. A definition that depends on Unicode properties
may therefore accept different strings on different hosts.

For the core input domain and other limits, see the
[technical contract](contract.html). For Erlang installation and deployment, see
[Native Erlang setup](native-erlang.html).
