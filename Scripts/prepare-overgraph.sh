#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT/Vendor"
TARGET_DIR="$VENDOR_DIR/overgraph"
REMOTE_URL="${OVERGRAPH_GIT_URL:-https://github.com/bhensley5/overgraph.git}"

mkdir -p "$VENDOR_DIR"

if [[ -e "$TARGET_DIR/Cargo.toml" ]]; then
  exit 0
fi

if [[ -L "$TARGET_DIR" && ! -e "$TARGET_DIR" ]]; then
  rm "$TARGET_DIR"
fi

candidate_paths=()
if [[ -n "${OVERGRAPH_PATH:-}" ]]; then
  candidate_paths+=("${OVERGRAPH_PATH}")
fi
candidate_paths+=(
  "$ROOT/../overgraph"
  "/Users/jason/dev/labs/AI/rust/overgraph"
)

for candidate in "${candidate_paths[@]}"; do
  if [[ -e "$candidate/Cargo.toml" ]]; then
    rm -rf "$TARGET_DIR"
    ln -s "$candidate" "$TARGET_DIR"
    echo "Linked overgraph from $candidate"
    exit 0
  fi
done

rm -rf "$TARGET_DIR"
git clone --depth 1 "$REMOTE_URL" "$TARGET_DIR"
echo "Cloned overgraph into $TARGET_DIR"
