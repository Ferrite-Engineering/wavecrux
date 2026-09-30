#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Run the Flutter Web integration tests (integration_test/web/*) one file at a
# time via `flutter drive` against a headless Chrome driven by chromedriver.
#
# Why this is separate from run_integration_tests.sh:
#
# Web integration tests cannot run under `flutter test` — the integration_test
# package on web requires the WebDriver protocol (`flutter drive` +
# chromedriver), not the in-process VM-service path the desktop/mobile runner
# uses. The desktop runner's `flutter clean` between files (needed for the
# FFI-heavy decoder suite) is also irrelevant here: web has no native build
# bundle to go stale. So the web suite gets its own, much simpler, runner.
#
# Each test is driven through test_driver/integration_test.dart with:
#
#   flutter drive \
#     --driver=test_driver/integration_test.dart \
#     --target=integration_test/web/<name>_test.dart \
#     -d web-server --browser-name=chrome --headless \
#     --dart-define=CORS_FIXTURE_PORT=8199
#
# Prerequisites:
#   * chromedriver on PATH whose major version matches the installed Chrome.
#     If a chromedriver is already listening on $CHROMEDRIVER_PORT (4444) the
#     script reuses it; otherwise it starts one and stops it on exit.
#   * The committed web/wasm/ bundle (wellen_wasm + lxt2fst) must be present —
#     the file-picker / drag-drop tests decode a VCD through WASM. It is
#     checked into the repo, so no Rust build is needed here.
#
# Also starts `tool/cors_fixture_server.dart` (a standalone dart:io HTTP
# server, see that file's header) on $CORS_FIXTURE_PORT alongside
# chromedriver, and stops it on exit the same way — `web_url_file_load_test
# .dart`'s `?file=<url>` CORS test fetches from it. The port is threaded into
# every `flutter drive` invocation via `--dart-define=CORS_FIXTURE_PORT`
# (harmless no-op for every other test file, which doesn't read that define).
#
# Usage:
#   tool/run_web_integration_tests.sh                       # all web tests
#   tool/run_web_integration_tests.sh web_file_picker_test  # one (basename, .dart optional)
#
# Exits non-zero if any test fails.

set -u
set -o pipefail

CHROMEDRIVER_PORT="${CHROMEDRIVER_PORT:-4444}"
CORS_FIXTURE_PORT="${CORS_FIXTURE_PORT:-8199}"
WEB_DIR="integration_test/web"
DRIVER="test_driver/integration_test.dart"

# The cross-bridge suite imports a generated, base64-embedded fixture bundle
# (`integration_test/web/web_fixture_bundle.g.dart`). It is a gitignored
# `*.g.dart`, so regenerate it up front — deterministic and fast — so a fresh
# clone can run the web suite without a separate codegen step.
echo "Generating web fixture bundle (web_fixture_bundle.g.dart)..."
dart run tool/generate_web_fixture_bundle.dart

# ── Argument parsing: optional explicit test basenames ───────────────────────
REQUESTED=()
while (("$#")); do
  case "$1" in
    -h|--help)
      sed -n '1,/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      REQUESTED+=("$1")
      shift
      ;;
  esac
done

# ── Collect target files ─────────────────────────────────────────────────────
TEST_FILES=()
if [[ ${#REQUESTED[@]} -gt 0 ]]; then
  for name in "${REQUESTED[@]}"; do
    base="${name%.dart}"
    f="$WEB_DIR/$base.dart"
    if [[ -f "$f" ]]; then
      TEST_FILES+=("$f")
    else
      echo "No such web test: $f" >&2
      exit 1
    fi
  done
else
  while IFS= read -r f; do
    TEST_FILES+=("$f")
  done < <(find "$WEB_DIR" -name '*_test.dart' -type f | sort)
fi

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "No web integration test files found under $WEB_DIR" >&2
  exit 1
fi

# ── chromedriver: resolve a build whose major version matches the Chrome ──────
# A chromedriver whose major version differs from the running Chrome refuses
# session creation ("only supports Chrome version N / Current browser version is
# M") — the failure that silently blocks local web runs when Homebrew's
# chromedriver drifts ahead of the installed Chrome (observed: driver 151 vs
# Chrome 150). Detect the Chrome major and, if the on-PATH chromedriver doesn't
# match (or is absent), fetch the exactly-matching build from the
# Chrome-for-Testing archive into a gitignored `build/` cache. CI already does
# the same match in its workflow; this makes a bare `tool/…` run work locally too.
CHROMEDRIVER_BIN=""

_detect_chrome_version() {
  local candidates=() c ver
  [[ -n "${CHROME_EXECUTABLE:-}" ]] && candidates+=("$CHROME_EXECUTABLE")
  case "$(uname -s)" in
    Darwin)
      candidates+=(
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        "/Applications/Chromium.app/Contents/MacOS/Chromium"
      )
      ;;
    *) candidates+=(google-chrome google-chrome-stable chromium chromium-browser) ;;
  esac
  for c in "${candidates[@]}"; do
    if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then
      ver="$("$c" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){3}' | head -1)"
      [[ -n "$ver" ]] && { echo "$ver"; return 0; }
    fi
  done
  return 1
}

_cft_platform() {
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) echo mac-arm64 ;;
    Darwin-x86_64) echo mac-x64 ;;
    Linux-*) echo linux64 ;;
    *) return 1 ;;
  esac
}

resolve_chromedriver() {
  local chrome_ver chrome_major on_path_major slug cache bin url
  chrome_ver="$(_detect_chrome_version)" || {
    echo "  (could not detect installed Chrome; using on-PATH chromedriver as-is)" >&2
    CHROMEDRIVER_BIN="$(command -v chromedriver || true)"
    return 0
  }
  chrome_major="${chrome_ver%%.*}"
  echo "  Installed Chrome: $chrome_ver (major $chrome_major)"

  if command -v chromedriver >/dev/null 2>&1; then
    on_path_major="$(chromedriver --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
    if [[ "$on_path_major" == "$chrome_major" ]]; then
      echo "  on-PATH chromedriver matches (major $on_path_major)"
      CHROMEDRIVER_BIN="$(command -v chromedriver)"
      return 0
    fi
    echo "  on-PATH chromedriver is major $on_path_major — need $chrome_major; fetching a match"
  else
    echo "  no chromedriver on PATH — fetching one matching Chrome $chrome_major"
  fi

  slug="$(_cft_platform)" || { echo "  unsupported platform for auto-fetch" >&2; return 1; }
  cache="build/chromedriver-cache/$chrome_ver"
  bin="$cache/chromedriver"
  if [[ ! -x "$bin" ]]; then
    mkdir -p "$cache"
    url="https://storage.googleapis.com/chrome-for-testing-public/${chrome_ver}/${slug}/chromedriver-${slug}.zip"
    echo "  downloading $url"
    if ! curl -fsSL "$url" -o "$cache/chromedriver.zip"; then
      echo "  download failed (no Chrome-for-Testing build for $chrome_ver?); falling back to" >&2
      echo "  on-PATH chromedriver — session creation may fail on the version mismatch." >&2
      CHROMEDRIVER_BIN="$(command -v chromedriver || true)"
      return 0
    fi
    unzip -o -j "$cache/chromedriver.zip" "chromedriver-${slug}/chromedriver" -d "$cache" >/dev/null
    chmod +x "$bin"
  fi
  echo "  using $("$bin" --version 2>/dev/null | head -1)"
  CHROMEDRIVER_BIN="$bin"
}

# ── chromedriver lifecycle ───────────────────────────────────────────────────
STARTED_CHROMEDRIVER=0
chromedriver_up() {
  curl -s "http://localhost:$CHROMEDRIVER_PORT/status" >/dev/null 2>&1
}

if chromedriver_up; then
  echo "Reusing chromedriver already listening on :$CHROMEDRIVER_PORT"
else
  echo "Resolving a chromedriver matching the installed Chrome ..."
  resolve_chromedriver
  if [[ -z "$CHROMEDRIVER_BIN" ]]; then
    echo "chromedriver not found and could not be fetched — install one matching your Chrome major version." >&2
    exit 1
  fi
  echo "Starting chromedriver ($CHROMEDRIVER_BIN) on :$CHROMEDRIVER_PORT ..."
  "$CHROMEDRIVER_BIN" --port="$CHROMEDRIVER_PORT" >/tmp/chromedriver_webit.log 2>&1 &
  CHROMEDRIVER_PID=$!
  STARTED_CHROMEDRIVER=1
  # Wait for it to come up (max ~10s).
  for _ in $(seq 1 20); do
    chromedriver_up && break
    sleep 0.5
  done
  if ! chromedriver_up; then
    echo "chromedriver failed to start. Log:" >&2
    cat /tmp/chromedriver_webit.log >&2 || true
    exit 1
  fi
fi

cleanup() {
  if [[ $STARTED_CHROMEDRIVER -eq 1 ]]; then
    kill "$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
  fi
  if [[ $STARTED_CORS_SERVER -eq 1 ]]; then
    kill "$CORS_SERVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ── CORS fixture server lifecycle ────────────────────────────────────────────
# Serves the same `test/fixtures/vcd/scalar_basics.vcd` other web tests embed,
# over a CORS-permissive and a CORS-blocked route — `web_url_file_load_test
# .dart`'s target. See `tool/cors_fixture_server.dart` for the routes.
STARTED_CORS_SERVER=0
cors_server_up() {
  curl -s -o /dev/null -w '%{http_code}' \
    "http://localhost:$CORS_FIXTURE_PORT/cors-ok/scalar_basics.vcd" \
    2>/dev/null | grep -q '^200$'
}

if cors_server_up; then
  echo "Reusing CORS fixture server already listening on :$CORS_FIXTURE_PORT"
else
  echo "Starting CORS fixture server on :$CORS_FIXTURE_PORT ..."
  dart run tool/cors_fixture_server.dart --port "$CORS_FIXTURE_PORT" \
    >/tmp/cors_fixture_server.log 2>&1 &
  CORS_SERVER_PID=$!
  STARTED_CORS_SERVER=1
  for _ in $(seq 1 20); do
    cors_server_up && break
    sleep 0.5
  done
  if ! cors_server_up; then
    echo "CORS fixture server failed to start. Log:" >&2
    cat /tmp/cors_fixture_server.log >&2 || true
    exit 1
  fi
fi

# ── Run each file individually ───────────────────────────────────────────────
echo "Running ${#TEST_FILES[@]} web integration test file(s) on headless Chrome..."
echo

LOG_DIR="build/web_integration_test_logs"
mkdir -p "$LOG_DIR"
echo "Per-file logs: $LOG_DIR/"
echo

PASSED=()
FAILED=()
TOTAL=${#TEST_FILES[@]}
INDEX=0

for f in "${TEST_FILES[@]}"; do
  INDEX=$((INDEX + 1))
  printf '── [%d/%d] %s ' "$INDEX" "$TOTAL" "$f"
  printf '%*s\n' $((72 - ${#f})) '' | tr ' ' '─'

  log_name=$(echo "$f" | tr '/' '_').log

  if flutter drive \
      --driver="$DRIVER" \
      --target="$f" \
      -d web-server --browser-name=chrome --headless \
      --dart-define=CORS_FIXTURE_PORT="$CORS_FIXTURE_PORT" \
      2>&1 | tee "$LOG_DIR/$log_name"; then
    PASSED+=("$f")
  else
    FAILED+=("$f")
  fi
  echo
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════════════════════════════════════════════"
echo "Web integration test summary"
echo "────────────────────────────────────────────────────────────────────────────────"
echo "Passed: ${#PASSED[@]} / ${#TEST_FILES[@]}"
echo "Failed: ${#FAILED[@]}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo
  echo "Failed tests:"
  for f in "${FAILED[@]}"; do
    echo "  ✗ $f"
  done
  exit 1
fi
echo
echo "All web integration tests passed."
exit 0
