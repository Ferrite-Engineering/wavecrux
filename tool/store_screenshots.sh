#!/bin/sh
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Captures the states that integration_test/store_screenshot_stage_test.dart
# holds on screen, at the simulator's native pixel size.
#
#   tool/store_screenshots.sh <stage-test log> <simulator udid> <outdir>
#
# Watches the log for `STORE_SHOT <name> READY`, waits for the frame to settle,
# and writes <outdir>/<name>.png with `xcrun simctl io`. Exits on
# `STORE_SHOT DONE READY` or when the test run ends.
set -eu
log="$1"; udid="$2"; out="$3"
mkdir -p "$out"
seen=" "
while :; do
  if [ -f "$log" ]; then
    for name in $(grep -o 'STORE_SHOT [^ ]* READY' "$log" | awk '{print $2}'); do
      case "$seen" in
        *" $name "*) ;;
        *)
          seen="$seen$name "
          if [ "$name" = "DONE" ]; then
            echo "done: $(ls "$out" | tr '\n' ' ')"
            exit 0
          fi
          sleep 3
          xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null 2>&1 \
            && echo "captured $out/$name.png $(sips -g pixelWidth -g pixelHeight "$out/$name.png" | awk '/pixel/ {printf "%s ", $2}')"
          ;;
      esac
    done
    if grep -q 'All tests passed\|Some tests failed\|Error:' "$log"; then
      echo "test run ended without DONE"
      exit 1
    fi
  fi
  sleep 1
done
