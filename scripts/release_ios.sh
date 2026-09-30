#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build a signed iOS .ipa for App Store Connect upload — open-core WaveCrux.
#
# Mobile ships the OPEN-CORE wavecrux app (no beta expiry — the App Store auto-
# updates users). Signing is automatic: Apple Distribution cert + App Store
# provisioning profile for com.ferriteengineering.wavecrux under team
# 7957R7M965 (Ferrite Engineering LLC). Xcode mints the provisioning profile on
# the first archive; nothing to pre-create. Export options live in
# ios/ExportOptions.plist.
#
# Run from the repo root (on a Mac with Xcode signed in to the Apple account):
#   ./scripts/release_ios.sh
#
# Output:
#   build/ios/ipa/*.ipa
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Building wellen_ffi XCFramework for iOS ==="
./scripts/build_ios.sh

echo "=== Code generation ==="
dart run build_runner build --delete-conflicting-outputs

# NOTE: no --dart-define=BETA_EXPIRY. Mobile ships open-core with no expiry —
# app stores reject self-expiring builds and the App Store auto-updates users.
#
# AI_EXPERIMENTAL=false removes the Settings → AI Assistant section from the
# store build entirely. It defaults to true, so 0.1.0 (2) shipped a section
# labelled "Experimental" whose own description said the assistant "may change
# or be removed" — a self-declared unfinished feature under App Store Review
# Guideline 2.2, which asks us to "complete, remove, or fully configure any
# partially implemented features". We remove it. Desktop keeps the flag on;
# the BYO-key assistant stays available there.
echo "=== flutter build ipa (App Store) ==="
flutter build ipa --release \
  --dart-define=AI_EXPERIMENTAL=false \
  --export-options-plist ios/ExportOptions.plist

echo ""
echo "IPA ready under: build/ios/ipa/"
echo ""
echo "Upload it to App Store Connect with one of:"
echo "  - Transporter.app (Mac App Store) - drag the .ipa in. Easiest."
echo "  - xcrun altool --upload-app -t ios -f build/ios/ipa/*.ipa \\"
echo "      --apple-id <appleid@ferriteengineering.com> --password <app-specific-pw>"
echo "  - Xcode -> Organizer -> Distribute App (if you archive via Xcode instead)."
echo ""
echo "Prereq: the app record must exist in App Store Connect with bundle id"
echo "        com.ferriteengineering.wavecrux before the upload will accept."
