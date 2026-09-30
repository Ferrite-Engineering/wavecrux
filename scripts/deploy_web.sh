#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build + deploy the OPEN-CORE WaveCrux web app to Cloudflare (app.wavecrux.app).
#
# Cloudflare Workers Static Assets, same model as the marketing site. Web ships
# open-core with NO beta expiry — you redeploy to ship updates to everyone.
#
# One-time setup:
#   - `wrangler login` (OAuth) to authenticate this machine to the Ferrite
#     Cloudflare account.
#   - The app.wavecrux.app custom domain is provisioned automatically from
#     wrangler.jsonc on first deploy (the wavecrux.app zone must be on that
#     Cloudflare account — it already hosts the marketing site).
#
# Run from the repo root:
#   ./scripts/deploy_web.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# `dart run build_runner` resolves the package graph itself, and without a
# prior `flutter pub get` it cannot see the Flutter SDK — it fails with
# "depends on integration_test from sdk which doesn't exist (the Flutter SDK is
# not available)". That bit during the 0.6.0 web deploy. NetCrux and LintCrux
# always had this step; WaveCrux's script was missing it and only ever worked
# because the tree happened to be resolved already.
echo "=== pub get ==="
flutter pub get

# Unlike SimCrux (which has no generated code at all), WaveCrux does use
# riverpod_generator, so this step is real — do not "simplify" it away.
echo "=== Code generation ==="
dart run build_runner build --delete-conflicting-outputs

# Matches the release workflow, which regenerates l10n before every build.
echo "=== l10n ==="
flutter gen-l10n

# No --dart-define=BETA_EXPIRY: web ships open-core with no expiry. This uses the
# committed web/wasm bundles (validated by the bundle-size test) — if you changed
# the wellen_wasm / lxt2fst Rust crates, rebuild + recommit the bundles first via
# `dart run tool/build_web_wasm.dart` and `dart run tool/build_lxt2fst_wasm.dart`.
echo "=== flutter build web (release) ==="
flutter build web --release

echo "=== Deploy to Cloudflare (wavecrux-app -> app.wavecrux.app) ==="
if command -v wrangler >/dev/null 2>&1; then
  wrangler deploy
else
  npx --yes wrangler deploy
fi

echo ""
echo "Deployed. Live at https://app.wavecrux.app/"
echo "(First deploy provisions the custom domain — DNS/SSL may take a minute.)"
