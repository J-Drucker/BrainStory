#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
revision="$(git rev-parse --short HEAD 2>/dev/null || printf unknown)"
bash scripts/build_cnt_web.sh
cargo build --manifest-path engine/web/Cargo.toml --target wasm32-unknown-unknown --release --locked
cp engine/web/target/wasm32-unknown-unknown/release/brainstory_web.wasm gui/web/brainstory_web.wasm
pushd gui >/dev/null
flutter build web --release --no-web-resources-cdn --base-href "${1:-/}" \
  --dart-define="BRAINSTORY_GIT_REVISION=$revision"
popd >/dev/null
mkdir -p dist
python3 scripts/package_web.py
