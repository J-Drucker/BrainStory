#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v emcc >/dev/null 2>&1; then
  echo "emcc is required. Run this script from an activated emsdk shell." >&2
  exit 1
fi

source_root="engine/vendor/libeep/src"
sources=(
  engine/web/cnt_bridge.c
  "$source_root/libavr/avr.c"
  "$source_root/libavr/avrcfg.c"
  "$source_root/libcnt/cnt.c"
  "$source_root/libcnt/cntutils.c"
  "$source_root/libcnt/evt.c"
  "$source_root/libcnt/raw3.c"
  "$source_root/libcnt/rej.c"
  "$source_root/libcnt/riff64.c"
  "$source_root/libcnt/riff.c"
  "$source_root/libcnt/seg.c"
  "$source_root/libcnt/trg.c"
  "$source_root/libeep/eepio.c"
  "$source_root/libeep/eepmem.c"
  "$source_root/libeep/eepmisc.c"
  "$source_root/libeep/eepraw.c"
  "$source_root/libeep/val.c"
  "$source_root/libeep/var_string.c"
  "$source_root/v4/eep.c"
)

emcc "${sources[@]}" \
  -I"$source_root" \
  -DLIBEEP_VERSION_MAJOR=3 \
  -DLIBEEP_VERSION_MINOR=3 \
  -DLIBEEP_VERSION_PATCH=179 \
  -O3 \
  -sMODULARIZE=1 \
  -sEXPORT_NAME=createBrainStoryCntModule \
  -sENVIRONMENT=worker,node \
  -sALLOW_MEMORY_GROWTH=1 \
  -sEXPORTED_FUNCTIONS='["_malloc","_free","_bs_cnt_open","_bs_cnt_close","_bs_cnt_channel_count","_bs_cnt_sample_rate","_bs_cnt_sample_count","_bs_cnt_channel_label","_bs_cnt_samples","_bs_cnt_trigger_count","_bs_cnt_trigger"]' \
  -sEXPORTED_RUNTIME_METHODS='["FS","UTF8ToString","stringToUTF8","lengthBytesUTF8","HEAPF32","HEAPU8"]' \
  -o gui/web/brainstory_cnt.js

node scripts/test_cnt_web.cjs
