#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --manifest-path engine/web/Cargo.toml --target wasm32-unknown-unknown --release --locked
cp engine/web/target/wasm32-unknown-unknown/release/brainstory_web.wasm gui/web/brainstory_web.wasm
pushd gui >/dev/null
flutter build web --release --no-web-resources-cdn --base-href "${1:-/}"
popd >/dev/null
mkdir -p dist
python3 scripts/package_web.py
