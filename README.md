# Overgraph Swift Bridge

Current status: Beta-quality package surface, JSON-oriented bridge, evolving docs.

Swift Package wrapper around a small Rust FFI shim for `overgraph`, plus a Swift CLI REPL.
The public Swift API intentionally sticks with a small JSON-based interface for
this Beta phase.

## Layout

- `Vendor/overgraph`: resolved local checkout or downloaded upstream repo
- `rust-bridge/`: Rust `staticlib` exposing a small C ABI
- `Sources/COvergraphBridge/`: C header imported by Swift
- `Sources/OvergraphSwiftBridge/`: Swift-native API wrapper
- `Sources/OvergraphCLI/`: ArgumentParser-based CLI and REPL
- `Tests/OvergraphSwiftBridgeTests/`: end-to-end package test

## Build

1. Resolve `overgraph`:

```sh
make overgraph
```

2. Build the Rust bridge and Swift package:

```sh
make build
```

3. Test:

```sh
make test
```

If you already have a local checkout, set `OVERGRAPH_PATH=/path/to/overgraph` and `make overgraph` will symlink it into `Vendor/overgraph`. If no local checkout is found, the prepare script clones [overgraph](https://github.com/bhensley5/overgraph.git).

## CLI

Start an interactive REPL:

```sh
make repl DB=./example-db
```

Or run directly:

```sh
swift run overgraph-cli --db ./example-db
```

One-shot command example:

```sh
swift run overgraph-cli --db ./example-db --execute 'stats'
```

Run a script file:

```sh
swift run --disable-sandbox overgraph-cli --db ./example-db --run-script Examples/01-social-graph.walkthrough.og
```

`--props` input in the CLI accepts JSON5 syntax, so comments, trailing commas, single-quoted strings, and unquoted object keys are allowed at the REPL layer. The underlying Rust bridge still receives normalized standard JSON.

Temporal CLI input is also human-friendly. Wherever the CLI accepts a date, you
can use raw epoch milliseconds, epoch seconds, `now`, `today`, `yesterday`,
`tomorrow`, `YYYY-MM-DD`, or ISO-style timestamps such as
`2024-06-01T12:30:00Z`.

## Examples

Example scripts live in `Examples/`:

- `01-social-graph.walkthrough.og`: create a small people graph and run neighbor queries
- `02-knowledge-graph.walkthrough.og`: create mixed node types and query by key, type, and edge type
- `03-lifecycle-and-cleanup.walkthrough.og`: create tasks, inspect dependencies, then delete edges and nodes
- `04-temporal-edges.walkthrough.og`: create valid-time edges and query them with `--asof` / `--at-epoch`
- `05-decay-scoring.walkthrough.og`: compare raw neighbor ranking with time-decayed ranking

Current note: scripts that create edges assume a fresh empty database so the allocated node IDs are predictable.

## Current API Surface

- Open and close a database
- Upsert nodes and edges
- Fetch nodes and edges by ID
- Fetch node by `(typeID, key)`
- Fetch nodes by type
- Query neighbors
- Read database stats
- Delete nodes and edges

The REPL currently supports:

- `stats`
- `get-node`
- `get-edge`
- `get-node-by-key`
- `nodes-by-type`
- `neighbors`
- `upsert-node`
- `upsert-edge`
- `delete-node`
- `delete-edge`

Temporal note:

- Edge writes support `validFrom` and `validTo`
- `neighbors` supports point-in-time reads with `atEpoch`
- The CLI exposes this as `--at-epoch <epoch-ms>` and `--asof <epoch-ms>`

## Decay scoring

For neighbor-style queries, Overgraph can apply exponential time decay to edge
weights.

- Formula: `score = weight * exp(-lambda * age_hours)`
- `age_hours = (reference_time - valid_from) / 3_600_000`
- `reference_time` is `atEpoch` if provided, otherwise the current time

Practical effect:

- `lambda = 0` means no decay
- larger `lambda` makes older edges lose score faster
- with equal base weights, newer edges rank higher when decay is enabled

In the CLI, use:

```sh
neighbors 1 --asof 2024-06-15 --decay-lambda 0.1
```

The decay example script in `Examples/05-decay-scoring.walkthrough.og` shows the
difference between raw ranking and time-decayed ranking.

The Rust bridge uses JSON payloads over a small C ABI so the Swift layer can stay ergonomic while avoiding a large hand-written struct-by-struct FFI surface.
