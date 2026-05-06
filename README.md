# Overgraph Swift Bridge

Swift Package wrapper around a small Rust FFI shim for `overgraph`, plus a Swift CLI REPL.

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

## Examples

Example scripts live in `Examples/`:

- `01-social-graph.walkthrough.og`: create a small people graph and run neighbor queries
- `02-knowledge-graph.walkthrough.og`: create mixed node types and query by key, type, and edge type
- `03-lifecycle-and-cleanup.walkthrough.og`: create tasks, inspect dependencies, then delete edges and nodes

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

The Rust bridge uses JSON payloads over a small C ABI so the Swift layer can stay ergonomic while avoiding a large hand-written struct-by-struct FFI surface.
