#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE_DIR="$ROOT/rust-bridge"
ARTIFACT_LIB_DIR="$ROOT/BridgeArtifacts/lib"

"$ROOT/Scripts/prepare-overgraph.sh"
cargo build --manifest-path "$CRATE_DIR/Cargo.toml"

mkdir -p "$ARTIFACT_LIB_DIR"
cp "$CRATE_DIR/target/debug/libovergraph_swift_bridge.a" "$ARTIFACT_LIB_DIR/"
