// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the split that WaveCrux's export-control position rests on:
/// **open core calls TLS and hashes; it does not encrypt.**
///
/// WaveCrux Pro implements AES-256-GCM for WAN collaboration E2EE (in the Pro
/// overlay, via `cryptography`). Open core implements no cipher, and two separate things
/// depend on that staying true:
///
/// 1. **The App Store declaration.** `ios/Runner/Info.plist` declares
///    `ITSAppUsesNonExemptEncryption` as `false`, and the iOS and Android store
///    builds are open core. Adding a cipher here makes that declaration untrue
///    at the next submission.
/// 2. **The open-core flip.** Publishing encryption *source code* triggers a
///    notification obligation (EAR §742.15(b)) that publishing TLS-calling code
///    does not. Open core is publishable without one only while it contains no
///    cipher.
///
/// Neither failure is loud: the plist key is read only by App Store Connect at
/// submission time, and the notification obligation has no build-time symptom
/// at all. A transitive pull-up through some unrelated new package would
/// produce no warning whatsoever. Hence a static guard.
///
/// **Hashing is deliberately allowed.** `crypto` (SHA/HMAC) is already a
/// transitive dependency and stays one — hashing is not encryption. So is
/// calling the platform's HTTPS stack, which is what every network path here
/// does.
///
/// If a cipher genuinely belongs in open core, the export-control position
/// described above is what needs revisiting first — do not simply delete an
/// entry from the list below.
void main() {
  test('open core bundles no encryption implementation', () {
    final lock = File('pubspec.lock');
    expect(
      lock.existsSync(),
      isTrue,
      reason:
          'pubspec.lock is missing, so this guard cannot see the resolved '
          'dependency set. The lock is tracked on purpose; restore it.',
    );

    final resolved = _resolvedPackages(lock.readAsStringSync());
    final found = _encryptionPackages.where(resolved.contains).toList();

    expect(
      found,
      isEmpty,
      reason:
          'Open core resolved an encryption package: ${found.join(', ')}.\n\n'
          'Encryption implementations belong in the Pro overlay. Two things break '
          'at once if one lands here: the ITSAppUsesNonExemptEncryption=false '
          'declaration in ios/Runner/Info.plist becomes untrue for the store '
          'builds (which are open core), and the open-core flip acquires an '
          'EAR §742.15(b) notification obligation it does not currently have.\n\n'
          'This fires for transitive pull-ups too, which is the case nothing '
          'else would catch. Check `flutter pub deps` for who wants it, and '
          'revisit the export-control position before accepting it.',
    );
  });

  test('ios/Runner/Info.plist declares no non-exempt encryption', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final match = RegExp(
      r'<key>ITSAppUsesNonExemptEncryption</key>\s*<(true|false)\s*/>',
    ).firstMatch(plist);

    expect(
      match?.group(1),
      'false',
      reason:
          'ios/Runner/Info.plist must declare ITSAppUsesNonExemptEncryption as '
          'false. Absent, App Store Connect prompts for the answer at every '
          'submission; true would demand export documentation this build does '
          'not need. The declaration is only true-by-fact while the guard above '
          'passes — the two tests are one fact.',
    );
  });
}

/// Packages that implement a cipher, as opposed to hashing or calling the
/// platform's TLS.
///
/// Not exhaustive — no fixed list can be — but it covers what a Flutter project
/// realistically reaches for, including the maintained forks that appeared after
/// `cryptography` went quiet.
const _encryptionPackages = <String>{
  'cryptography',
  'cryptography_flutter',
  'cryptography_flutter_plus',
  'cryptography_plus',
  'encrypt',
  'flutter_sodium',
  'libsodium',
  'pointycastle',
  'sodium',
  'sodium_libs',
  'steel_crypt',
  'webcrypto',
};

/// Every package name in a `pubspec.lock`, regardless of dependency kind.
///
/// Transitive entries matter as much as direct ones here: the failure this
/// guards against is a cipher arriving as somebody else's dependency, which is
/// invisible in `pubspec.yaml`. Package entries are the two-space-indented keys
/// under `packages:`; the file's other top-level sections (`sdks:`) have no
/// such nesting to confuse.
Set<String> _resolvedPackages(String lock) => RegExp(
  r'^  ([a-z_0-9]+):$',
  multiLine: true,
).allMatches(lock).map((m) => m.group(1)!).toSet();
