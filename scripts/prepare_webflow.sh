#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--reuse-engine" ]]; then
  if [[ ! -f gui/web/brainstory_web.wasm ]]; then
    if [[ ! -f packaging/webflow/brainstory-web.zip ]]; then
      printf '%s\n' 'Missing browser engine and Webflow release archive.' >&2
      exit 1
    fi
    unzip -p packaging/webflow/brainstory-web.zip brainstory_web.wasm \
      > gui/web/brainstory_web.wasm
  fi
  for asset in \
    gui/web/brainstory_web.wasm \
    gui/web/brainstory_cnt.js \
    gui/web/brainstory_cnt.wasm; do
    if [[ ! -f "$asset" ]]; then
      printf 'Missing browser engine asset: %s\n' "$asset" >&2
      exit 1
    fi
  done
  pushd gui >/dev/null
  flutter build web --release --no-web-resources-cdn --base-href /
  popd >/dev/null
  mkdir -p dist
  python3 scripts/package_web.py
elif [[ $# -eq 0 ]]; then
  bash scripts/build_web.sh
else
  printf 'Usage: %s [--reuse-engine]\n' "$0" >&2
  exit 2
fi

cp dist/brainstory-web.zip packaging/webflow/brainstory-web.zip
printf '%s\n' 'Webflow release updated. Commit packaging/webflow/brainstory-web.zip with the source changes.'
