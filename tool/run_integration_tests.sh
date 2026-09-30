#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Run integration tests one file at a time.
#
# Why this script exists:
#
# `flutter test integration_test/<dir>/` on desktop (macOS, Linux, Windows)
# does not reliably run more than one integration_test file per invocation.
# After the first file completes, subsequent files fail with:
#
#   "Error waiting for a debug connection: The log reader stopped
#   unexpectedly, or never started."
#
# `flutter_tools` does not cleanly tear down the observatory connection
# between integration_test files inside a single `flutter test`
# invocation. This script works around that by invoking `flutter test`
# once per file, accumulating pass/fail counts, and printing a final
# summary.
#
# Two distinct end-of-test / build-reuse problems also affect this suite;
# the script defaults to `flutter clean` between files (`--clean`, the
# default) so the WHOLE suite — including FFI-heavy decoder tests — runs
# green out of the box. The two problems:
#
#   (a) SemanticsHandle leak. The framework's
#       `_verifySemanticsHandlesWereDisposed` verifier trips because the
#       macOS embedder enables accessibility/semantics during the first
#       test that gains focus and never sends a disable. This one is
#       handled at the TEST level by `suppressPlatformSemanticsLeak()` in
#       `integration_test/helpers/app_driver.dart` (called right after
#       `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` in every
#       integration test) — so it no longer requires a clean.
#
#   (b) FFI-heavy decoder-test hang on build reuse. The decoder tests
#       (`integration_test/decoders/*`) deterministically fail with
#       "did not complete" / "No tests were found" when run against a
#       REUSED `build/macos/.../WaveCrux.app` bundle — the app launches
#       but flutter_tools never establishes the VM-service connection
#       within its startup deadline. A full `flutter clean` rebuild
#       produces a fresh bundle that connects cleanly. This is an upstream
#       flutter_tools/macOS flake (reproduces with the suppression helper
#       removed, i.e. it is unrelated to (a)); the only reliable fix at
#       this layer is a clean rebuild before the test.
#
# Suites that don't load the FFI decode path (e.g. `workspace`,
# `diagnostics`) pass fine on build reuse, so `--no-clean` is a safe,
# much faster option when iterating on just those.
#
# Usage:
#
#   tool/run_integration_tests.sh                       # all tests, clean between (safe default)
#   tool/run_integration_tests.sh workspace             # one subdirectory
#   tool/run_integration_tests.sh workspace diagnostics # multiple subdirs
#   tool/run_integration_tests.sh -d linux              # device override
#   tool/run_integration_tests.sh --no-clean workspace  # fast; only for reuse-safe suites
#   tool/run_integration_tests.sh --clean workspace     # default; here for clarity
#   tool/run_integration_tests.sh --shard 2/4           # the 2nd of 4 slices
#
# Exits non-zero if any test fails.

set -u
set -o pipefail

# ── Argument parsing ─────────────────────────────────────────────────────────

DEVICE="macos"
# Default: clean between tests. Necessary for the FFI-heavy decoder suite,
# which hangs on a reused build bundle (see problem (b) in the header).
# `--no-clean` is a safe, faster opt-in for suites that don't exercise the
# FFI decode path (workspace, diagnostics).
CLEAN_BETWEEN=1
# `--shard I/N` runs only the Ith of N slices of the discovered file list.
# 0/0 means "no sharding" — run everything.
SHARD_INDEX=0
SHARD_COUNT=0
SUBDIRS=()

while (("$#")); do
  case "$1" in
    -d|--device)
      DEVICE="$2"
      shift 2
      ;;
    --no-clean)
      CLEAN_BETWEEN=0
      shift
      ;;
    --clean)
      CLEAN_BETWEEN=1
      shift
      ;;
    --shard)
      if [[ ! "${2:-}" =~ ^[0-9]+/[0-9]+$ ]]; then
        echo "error: --shard wants I/N (e.g. --shard 2/4), got '${2:-}'" >&2
        exit 64
      fi
      SHARD_INDEX="${2%/*}"
      SHARD_COUNT="${2#*/}"
      if (( SHARD_COUNT < 1 || SHARD_INDEX < 1 || SHARD_INDEX > SHARD_COUNT )); then
        echo "error: --shard $2 is out of range (want 1 <= I <= N, N >= 1)" >&2
        exit 64
      fi
      shift 2
      ;;
    -h|--help)
      sed -n '1,/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      SUBDIRS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#SUBDIRS[@]} -eq 0 ]]; then
  # No subdirs specified → discover them.
  while IFS= read -r dir; do
    SUBDIRS+=("$(basename "$dir")")
    # `web` holds web-only integration tests (run separately on -d chrome via
    # tool/run_web_integration_tests.sh). They cannot build for a desktop/mobile
    # device, so exclude them from the default discovery here.
  done < <(find integration_test -mindepth 1 -maxdepth 1 -type d ! -name helpers ! -name web | sort)
fi

# ── Collect test files ───────────────────────────────────────────────────────

TEST_FILES=()
for sub in "${SUBDIRS[@]}"; do
  while IFS= read -r f; do
    TEST_FILES+=("$f")
  done < <(find "integration_test/$sub" -name '*_test.dart' -type f | sort)
done

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "No integration test files found under: ${SUBDIRS[*]}" >&2
  exit 1
fi

# ── Shard ────────────────────────────────────────────────────────────────────
# Round-robin, not contiguous blocks. The per-file cost is very uneven — the
# FFI decoder files rebuild and run several times slower than the workspace
# ones — so contiguous slices would hand one shard every slow file and leave
# another idle. Dealing every Nth file spreads them, and because the list is
# already sorted the slices stay stable and disjoint across a matrix.
if (( SHARD_COUNT > 1 )); then
  ALL_FILES=("${TEST_FILES[@]}")
  TEST_FILES=()
  for ((i = SHARD_INDEX - 1; i < ${#ALL_FILES[@]}; i += SHARD_COUNT)); do
    TEST_FILES+=("${ALL_FILES[i]}")
  done
  if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
    echo "Shard $SHARD_INDEX/$SHARD_COUNT is empty (only ${#ALL_FILES[@]} files); nothing to do."
    exit 0
  fi
  echo "Shard $SHARD_INDEX/$SHARD_COUNT: ${#TEST_FILES[@]} of ${#ALL_FILES[@]} file(s) on device '$DEVICE'..."
else
  echo "Running ${#TEST_FILES[@]} integration test file(s) on device '$DEVICE'..."
fi
echo

# ── Run each file individually ───────────────────────────────────────────────

PASSED=()
FAILED=()
TIMED_OUT=()
TOTAL=${#TEST_FILES[@]}
INDEX=0

# Per-file wall-clock cap. `flutter test -d` can hang indefinitely
# establishing the Dart VM-service / debug connection — the sibling
# tool/run_integration_tests_device.sh has capped this since it was first
# written, but this script did not, and on 2026-09-01 the iOS-simulator
# sweep sat on file 2 of 11 for 75 minutes until the job's own
# timeout-minutes killed it. A cancelled job reports nothing: not which
# file hung, and not the results of the 9 files it never reached.
#
# `perl -e 'alarm'` is a portable timeout (macOS ships no GNU
# `timeout`/`gtimeout`); the alarm timer survives exec, so SIGALRM
# (exit 142) lands on the flutter process. Override with TEST_TIMEOUT.
#
# 900s, not the device script's 600s: a `--clean` run rebuilds the whole
# app before each file, and the macOS decoder files legitimately take
# ~3.5 minutes each.
TEST_TIMEOUT="${TEST_TIMEOUT:-900}"

# Per-file log directory so failed tests' full stack traces survive even
# when the script's stdout is piped through `tail` or otherwise truncated.
LOG_DIR="build/integration_test_logs"
mkdir -p "$LOG_DIR"
echo "Per-file logs: $LOG_DIR/"
echo

for f in "${TEST_FILES[@]}"; do
  INDEX=$((INDEX + 1))
  printf '── [%d/%d] %s ' "$INDEX" "$TOTAL" "$f"
  printf '%*s\n' $((72 - ${#f})) '' | tr ' ' '─'

  if [[ $CLEAN_BETWEEN -eq 1 ]]; then
    # `flutter clean` between tests forces a fresh build bundle for each
    # invocation. Without this, the macOS embedder inherits accessibility
    # / semantics state from the previous run and the next test trips
    # `_verifySemanticsHandlesWereDisposed` at teardown.
    flutter clean >/dev/null 2>&1
    flutter pub get >/dev/null 2>&1
  fi

  # `flutter clean` above removes the entire `build/` tree — including this
  # log directory created before the loop. Recreate it here so the `tee`
  # below does not fail; under `set -o pipefail` a failed `tee` would flip
  # the pipeline's exit status and make every passing test be counted as a
  # failure.
  mkdir -p "$LOG_DIR"

  # Compute a flat log filename from the test path (slashes → underscores).
  log_name=$(echo "$f" | tr '/' '_').log

  perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' \
    "$TEST_TIMEOUT" flutter test "$f" -d "$DEVICE" 2>&1 | tee "$LOG_DIR/$log_name"
  status="${PIPESTATUS[0]}"
  if [[ $status -eq 0 ]]; then
    PASSED+=("$f")
  elif [[ $status -eq 142 ]]; then
    # 142 = SIGALRM: the file hung rather than failed. Report it as its own
    # class — a hang and an assertion failure want different follow-ups —
    # and carry on to the remaining files instead of stalling the sweep.
    echo ">>> $f HUNG: no result after ${TEST_TIMEOUT}s; moving on"
    TIMED_OUT+=("$f")
  else
    FAILED+=("$f")
  fi
  echo
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo "════════════════════════════════════════════════════════════════════════════════"
echo "Integration test summary"
echo "────────────────────────────────────────────────────────────────────────────────"
echo "Passed:  ${#PASSED[@]} / ${#TEST_FILES[@]}"
echo "Failed:  ${#FAILED[@]}"
echo "Hung:    ${#TIMED_OUT[@]}"
if [[ ${#TIMED_OUT[@]} -gt 0 ]]; then
  echo
  echo "Hung tests (no result within ${TEST_TIMEOUT}s):"
  for f in "${TIMED_OUT[@]}"; do
    echo "  ⏱ $f"
  done
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo
  echo "Failed tests:"
  for f in "${FAILED[@]}"; do
    echo "  ✗ $f"
  done
fi
# A hang is a failure of the sweep, same as an assertion — it just gets its
# own bucket above so the two are not conflated in the summary.
if [[ ${#FAILED[@]} -gt 0 || ${#TIMED_OUT[@]} -gt 0 ]]; then
  exit 1
fi
echo
echo "All integration tests passed."
exit 0
