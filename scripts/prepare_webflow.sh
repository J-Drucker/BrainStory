#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build_web.sh
cp dist/brainstory-web.zip packaging/webflow/brainstory-web.zip
printf '%s\n' 'Webflow release updated. Commit packaging/webflow/brainstory-web.zip with the source changes.'
