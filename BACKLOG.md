# Backlog

This file captures near-term ideas for the Swift bridge and CLI, plus the
solutions already considered so we do not re-open the same design questions
from scratch.

## Release posture

- Keep the package at Beta quality for now.
- Keep the public Swift API JSON-oriented.
- Avoid expanding the public surface unless the Rust bridge can support it
  cleanly and efficiently.

## Temporal follow-ups

- Add more temporal examples beyond neighbor lookups.
- Consider exposing temporal options on more graph operations if the Rust engine
  already supports them.
- Evaluate whether a friendlier Swift name should supplement `atEpoch`.

Considered solutions:

- Keep `atEpoch` in the library because it matches the existing underlying
  request model.
- Expose `--asof` in the CLI as an ergonomic alias because it reads better in
  scripts and docs.

## Geo / radius queries

Goal:

- Eventually support queries like “find nodes near `(lat, lon)` within
  `radiusMeters`”.

Current status:

- No public geo API yet.
- No obvious native geo primitive is exposed through the current Rust bridge.
- Internal sketches live in
  `Sources/OvergraphSwiftBridge/GeoInternals.swift`.

Candidate public API shape:

- `GeoPoint(latitude:longitude:)`
- `nearbyNodes(center:radiusMeters:typeID:limit:)`

Considered backend strategies:

- Bounding-box prefilter on numeric `latitude` and `longitude` properties, then
  Haversine distance post-filter.
  Reasonable first implementation if the engine exposes property-range queries
  cleanly through the Swift bridge.
- Dedicated geo index in Overgraph.
  Best long-term design if geo becomes a primary workload.
- Dense-vector approximation.
  Not preferred for the first geo release because it is less obvious and less
  correct for a “radius on earth” semantic.

Decision for now:

- Do not ship a public geo API until the backend query primitive is clear.

## Script and REPL ergonomics

- Add script variables or capture of returned IDs so example scripts do not have
  to assume a fresh empty database.
- Consider multi-line JSON5 input for large property payloads.
- Consider a quieter script mode that suppresses raw inserted IDs unless asked.

Considered solutions:

- Keep current scripts simple and deterministic for now by assuming fresh
  databases.
- Defer variables until there is a clear minimal design that does not bloat the
  CLI parser.

## Error surface

- Replace or supplement `BridgeError.message(String)` with more structured error
  cases.
- Clarify which errors are stable contract versus passthrough engine failures.

Considered solutions:

- Keep the current stringly bridge error in Beta because it preserves upstream
  engine detail with minimal translation risk.
- Revisit typed cases once the public API surface settles further.

## Documentation

- Add DocC once the symbol docs and tutorial flow are stable enough.
- Convert the existing walkthrough scripts into doc-ready examples that avoid
  hard-coded allocated IDs where possible.
- Add a short “library vs CLI” boundary section so JSON5 support is not confused
  with library behavior.

## Testing

- Add tests for use-after-close and double-close semantics.
- Add CLI tests for `--asof` / `--at-epoch`.
- Add persistence reopen coverage.
- Add JSON5-focused CLI tests for comments, trailing commas, and single-quoted
  strings.
