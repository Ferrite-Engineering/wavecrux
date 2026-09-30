# Build & release scripts — open-core WaveCrux

Native-library and release tooling for the open-core `wavecrux` app. All scripts
run from the **repo root**.

## Distribution model (read this first)

The open-core `wavecrux` artifact ships to **mobile (iOS, Android) and web** —
open-core features only. **Desktop** (macOS/Windows/Linux, with Pro/Enterprise
features) ships separately from the closed-source Pro overlay, not from here.

Mobile and web carry **no beta expiry**: the app stores reject self-expiring
builds and auto-update users, and the hosted web build always serves latest. So
the release scripts here never pass `--dart-define=BETA_EXPIRY` (that mechanism
is desktop-only, in the Pro overlay).

## Identities (Ferrite Engineering LLC)

| Use | Value |
|---|---|
| Apple Team ID | `7957R7M965` |
| iOS App Store signing | `Apple Distribution: Ferrite Engineering LLC (7957R7M965)` |
| iOS bundle id | `com.ferriteengineering.wavecrux` |
| Android applicationId | `com.ferriteengineering.wavecrux` |
| Android upload key alias | `upload` |
| Android min SDK | 24 (Android 7.0) |

## Native-library scripts (built automatically by the platform build)

These cross-compile the `wellen_ffi` Rust crate; you rarely run them by hand.

| Script | Builds |
|---|---|
| `build_android.sh` | Android `.so` for arm64-v8a / armeabi-v7a / x86_64 → `android/app/src/main/jniLibs/` (invoked by the Gradle `preBuild` hook). |
| `build_ios.sh` | iOS `WellenFFI.xcframework` (device + simulator). |
| `build_macos.sh` / `build_wellen_universal.sh` | macOS universal `.dylib` (desktop; the Pro overlay builds the distributable). |

---

## iOS — App Store

```bash
./scripts/release_ios.sh   # signed .ipa → build/ios/ipa/
```

Signing is automatic against the org's Apple Distribution cert; Xcode mints the
App Store provisioning profile on the first archive. Export options are in
[`ios/ExportOptions.plist`](../ios/ExportOptions.plist) (team `7957R7M965`,
method `app-store`, automatic signing).

Upload the `.ipa` with **Transporter.app**, `xcrun altool --upload-app`, or
Xcode Organizer. The app record (bundle id `com.ferriteengineering.wavecrux`)
must exist in App Store Connect first.

---

## Android — Google Play (AAB + Play App Signing)

```bash
./scripts/release_android.sh   # signed release AAB → build/app/outputs/bundle/release/
```

The Gradle build auto-compiles the wellen `.so` libs; signing reads the **upload
key** from `android/key.properties` (gitignored). Without that file, release
builds fall back to the debug key so `flutter run --release` still works locally
— but Play rejects debug-signed bundles, so the script refuses to proceed.

### One-time: create the upload key

```bash
keytool -genkeypair -v -keystore "$HOME/keys/ferrite-wavecrux-upload.jks" \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Ferrite Engineering LLC, O=Ferrite Engineering LLC, C=US"
cp android/key.properties.example android/key.properties   # then fill in real values
```

> **macOS: "Unable to locate a Java Runtime"?** The stub `/usr/bin/keytool`
> fails when no standalone JDK is installed. Use the JDK bundled with Android
> Studio (the one Flutter already uses) — replace `keytool` above with:
> `"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"`.
> To make `keytool`/`java` work bare in your shell, add to `~/.zshrc`:
> `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"` and
> `export PATH="$JAVA_HOME/bin:$PATH"`.

Keep the `.jks` **outside the repo** and back it up. `storeFile` in
`key.properties` is an absolute path to it.

### Play Console (first release)

1. Create the app under the Ferrite Engineering Google Play account.
2. Accept **Play App Signing** (the default) — Google holds the app *signing*
   key; your `.jks` is only the *upload* key (resettable if lost).
3. Create a release (start with **Internal testing**), upload `app-release.aab`.

Never commit `key.properties`, the `.jks`, or any password (all gitignored).

---

## Web — Cloudflare (app.wavecrux.app)

```bash
./scripts/deploy_web.sh   # flutter build web --release  →  wrangler deploy
```

The web app is hosted on **Cloudflare Workers Static Assets** (same model as the
marketing site), as the Worker `wavecrux-app` on **app.wavecrux.app**. Config is
[`wrangler.jsonc`](../wrangler.jsonc): assets from `build/web`, single-page-app
fallback for deep links, and the `app.wavecrux.app` custom domain (auto-
provisioned on first deploy — the `wavecrux.app` zone must be on the Cloudflare
account). No COOP/COEP headers are needed (single-threaded WASM), and **no beta
expiry** — redeploy to ship updates.

### One-time
- `wrangler login` (OAuth) to authenticate this machine to the Ferrite
  Cloudflare account.

The deploy uses the committed `web/wasm/` bundles (validated by the bundle-size
test). If you change the `wellen_wasm` / `lxt2fst` Rust crates, rebuild and
recommit the bundles first:
`dart run tool/build_web_wasm.dart` + `dart run tool/build_lxt2fst_wasm.dart`.

## CI

`.github/workflows/mobile.yml` currently builds iOS (simulator) and a debug
Android APK for verification only — it does **not** produce signed store
artifacts. Signed releases are built locally with the scripts above and uploaded
by hand; full CI store automation (signed AAB/IPA + TestFlight/Play upload) is a
later increment.
