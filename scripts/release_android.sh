#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build a signed Android App Bundle (.aab) for Google Play — open-core WaveCrux.
#
# Mobile ships the OPEN-CORE wavecrux app (no beta expiry — the store auto-
# updates users). Signing uses the upload key in android/key.properties
# (gitignored). The wellen native .so libraries are built automatically by the
# Gradle preBuild task (scripts/build_android.sh) — no separate step here.
#
# Run from the repo root:
#   ./scripts/release_android.sh
#
# Output:
#   build/app/outputs/bundle/release/app-release.aab
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Preflight: without the upload key the AAB is debug-signed and Play rejects it.
# Fail early with the exact fix instead of producing an unusable bundle.
if [[ ! -f android/key.properties ]]; then
  cat >&2 <<'EOF'
error: android/key.properties not found — a release AAB would be debug-signed,
and Google Play rejects debug-signed bundles.

1. Create the upload keystore once (keep the .jks OUTSIDE the repo):
     keytool -genkeypair -v -keystore "$HOME/keys/ferrite-wavecrux-upload.jks" \
       -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
       -dname "CN=Ferrite Engineering LLC, O=Ferrite Engineering LLC, C=US"
2. cp android/key.properties.example android/key.properties  and fill it in
   (storeFile = absolute path to the .jks).

Then re-run this script.
EOF
  exit 1
fi

echo "=== Code generation ==="
dart run build_runner build --delete-conflicting-outputs

# NOTE: no --dart-define=BETA_EXPIRY. Mobile ships open-core with no expiry —
# app stores reject self-expiring builds and the store auto-updates users.
#
# AI_EXPERIMENTAL=false removes the Settings → AI Assistant section from the
# store build, matching release_ios.sh. Kept in lockstep deliberately: the two
# mobile stores should ship the same feature surface, and the section's own
# copy ("may change or be removed") reads as unfinished on either.
echo "=== flutter build appbundle (release) ==="
flutter build appbundle --release \
  --dart-define=AI_EXPERIMENTAL=false

echo ""
echo "AAB: build/app/outputs/bundle/release/app-release.aab"
echo ""
echo "Upload in Play Console -> WaveCrux -> Testing/Production -> Create release."
echo "On the FIRST release, accept Play App Signing (the default): Google holds the"
echo "app signing key; your upload key only signs uploads and can be reset if lost."
echo ""
echo "Local install testing (not for Play): flutter build apk --release"
