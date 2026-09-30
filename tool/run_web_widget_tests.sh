#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Run the web-only *widget* tests under headless Chrome via
# `flutter test --platform chrome`.
#
# This is distinct from tool/run_web_integration_tests.sh:
#
#   * run_web_integration_tests.sh drives a full app build in a real browser
#     via `flutter drive` + chromedriver (the integration_test/web/* suite).
#   * THIS script runs in-process widget tests compiled for web via
#     `flutter test --platform chrome`. It exists so that `kIsWeb == true` at
#     compile time, exercising the web branches of provider/widget code that
#     the default VM `flutter test` (kIsWeb == false) can never reach — e.g.
#     the WASM-load-failure path, where the bare Chrome harness deliberately
#     does NOT inject web/index.html's wellen_wasm_loader.js, so the module
#     genuinely fails to load.
#
# Test selection: every test file under test/ that opts into the browser
# platform with `@TestOn('browser')`. Such files are skipped by the default
# VM runner, so they MUST run here or they never run at all. New web widget
# tests are picked up automatically by adding that annotation.
#
# Usage:
#   tool/run_web_widget_tests.sh                  # all @TestOn('browser') tests
#   tool/run_web_widget_tests.sh test/a_web_test.dart [more...]   # explicit
#
# Exits non-zero if any test fails. Requires a Chrome that `flutter test
# --platform chrome` can launch (the CI image's setup-chrome provides one).

set -u
set -o pipefail

TEST_FILES=()
if [[ $# -gt 0 ]]; then
  TEST_FILES=("$@")
else
  while IFS= read -r f; do
    TEST_FILES+=("$f")
  done < <(grep -rln "@TestOn('browser')" test 2>/dev/null | sort)
fi

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "No @TestOn('browser') web widget tests found under test/ — nothing to run."
  exit 0
fi

echo "Running ${#TEST_FILES[@]} web widget test file(s) on headless Chrome:"
printf '  %s\n' "${TEST_FILES[@]}"
echo

# A single invocation compiles + runs them all on one Chrome instance.
exec flutter test --platform chrome "${TEST_FILES[@]}"
