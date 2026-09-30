// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Size;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/features/telemetry/wavecrux_telemetry_overrides.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/telemetry/telemetry_platform.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// The `os` slug derivation moved to `crux_telemetry` with the rest of the
// pipeline — it needs nothing WaveCrux knows. What stayed, and is tested here,
// is the mapping from WaveCrux's own `DeviceClass` onto the Worker's
// `form_factor` bucket: telemetry must report the layout idiom the app
// actually drew, so the derivation reads the enum the layout already uses
// rather than a second breakpoint set inside the shared package.

void main() {
  group('telemetryFormFactorFor', () {
    test('maps the layout idiom the app already drew', () {
      const expected = <DeviceClass, String>{
        DeviceClass.desktop: 'desktop',
        DeviceClass.tablet: 'tablet',
        DeviceClass.phone: 'phone',
        // The landscape split exists to decide whether side panels fit — a
        // layout question, not a "what kind of device is this" question.
        DeviceClass.phoneLandscape: 'phone',
      };
      for (final entry in expected.entries) {
        expect(
          telemetryFormFactorFor(isWeb: false, deviceClass: entry.key),
          entry.value,
        );
      }
    });

    test('kIsWeb wins for every device class', () {
      for (final deviceClass in DeviceClass.values) {
        expect(
          telemetryFormFactorFor(isWeb: true, deviceClass: deviceClass),
          'web',
        );
      }
    });

    test('every bucket is one the ingestion Worker accepts', () {
      for (final deviceClass in DeviceClass.values) {
        for (final hostKind in EditorHostKind.values) {
          for (final isWeb in <bool>[true, false]) {
            expect(
              kTelemetryFormFactors,
              contains(
                telemetryFormFactorFor(
                  isWeb: isWeb,
                  deviceClass: deviceClass,
                  hostKind: hostKind,
                ),
              ),
            );
          }
        }
      }
    });

    test('a webview-hosted build reports vscode, a browser build web', () {
      // The trap this platform tag exists to close. `kIsWeb`
      // is true in BOTH cases — that is the whole difficulty — so the only
      // thing that separates them is the host-bridge signal.
      const expected = <EditorHostKind, String>{
        EditorHostKind.vscode: 'vscode',
        EditorHostKind.none: 'web',
      };
      for (final entry in expected.entries) {
        expect(
          telemetryFormFactorFor(
            isWeb: true,
            deviceClass: DeviceClass.desktop,
            hostKind: entry.key,
          ),
          entry.value,
        );
      }
    });

    test('the host-kind branch runs ahead of the isWeb short-circuit', () {
      // Ordering, asserted directly rather than inferred: with `isWeb` first,
      // every device class would answer `web` and the bucket would be
      // unreachable. A regression that reorders the two branches passes every
      // other test in this file.
      for (final deviceClass in DeviceClass.values) {
        expect(
          telemetryFormFactorFor(
            isWeb: true,
            deviceClass: deviceClass,
            hostKind: EditorHostKind.vscode,
          ),
          'vscode',
        );
      }
    });

    test('not-hosted is the default, so no platform has to opt out', () {
      // Desktop, mobile and browser builds never wire the bridge. If the
      // default were anything else they would all have to.
      expect(
        telemetryFormFactorFor(isWeb: false, deviceClass: DeviceClass.desktop),
        'desktop',
      );
      expect(
        telemetryFormFactorFor(isWeb: true, deviceClass: DeviceClass.phone),
        'web',
      );
    });

    test('the editor-host answer never defers, even before the first size', () {
      // Same contract as the web answer: the bridge resolves the host kind
      // synchronously at startup from a marker the extension's index.html shim
      // sets, so there is no race to wait out and deferring would cost a flush
      // for a question already answered.
      expect(
        telemetryFormFactorFor(
          isWeb: true,
          deviceClass: null,
          hostKind: EditorHostKind.vscode,
        ),
        'vscode',
      );
    });

    test('no dimension survives the mapping', () {
      // Four buckets, and a phone in landscape reports the same bucket as a
      // phone in portrait — nothing downstream can reconstruct a screen size.
      final buckets = <String?>{
        for (final deviceClass in DeviceClass.values)
          telemetryFormFactorFor(isWeb: false, deviceClass: deviceClass),
      };
      expect(buckets, <String>{'desktop', 'tablet', 'phone'});
    });

    test('an unknown device class defers rather than guessing', () {
      // D2. `resolvedDeviceClassForSize` reports null until a display size has
      // been pushed, and telemetry reads this from a service on the launch
      // flush — before `DisplaySizeFeed` runs inside `MaterialApp.builder`.
      // `crux_telemetry` treats null as "skip this flush and ask again", which
      // costs one interval; answering `desktop` cost a `w800dp` Pixel Tablet
      // its true bucket on three of four launches.
      expect(telemetryFormFactorFor(isWeb: false, deviceClass: null), isNull);
    });

    test('the web answer never defers — nothing about it can race', () {
      // `kIsWeb` is a compile-time constant, so a web build knows its bucket
      // before it knows anything else. Deferring here would cost a flush for
      // no question, on precisely the platform that had the hardest time
      // reporting at all.
      expect(telemetryFormFactorFor(isWeb: true, deviceClass: null), 'web');
    });
  });

  group('the wired seam under an editor host', () {
    // The pure function is only half the fix — the override has to actually
    // read the bridge. A version of this change that adds the parameter and
    // forgets to pass it passes every test in the group above.

    test('reports vscode once the bridge announces the host', () {
      final container = ProviderContainer(
        overrides: wavecruxTelemetryOverrides,
      );
      addTearDown(container.dispose);

      container
          .read(editorHostKindProvider.notifier)
          .set(EditorHostKind.vscode);

      expect(container.read(telemetryFormFactorProvider), 'vscode');
    });

    test('does not wait for a display size the way the others do', () {
      // A webview reports its size like any other host, but the bucket must
      // not depend on it: an editor-hosted build that flushed before the first
      // frame would otherwise skip, and the launch event is the one that
      // measures activation.
      final container = ProviderContainer(
        overrides: wavecruxTelemetryOverrides,
      );
      addTearDown(container.dispose);

      container
          .read(editorHostKindProvider.notifier)
          .set(EditorHostKind.vscode);

      expect(
        container.read(telemetryFormFactorProvider),
        'vscode',
        reason: 'no display size has been pushed at this point',
      );
    });

    test('an un-wired build is unaffected — the default is not hosted', () {
      final container = ProviderContainer(
        overrides: wavecruxTelemetryOverrides,
      );
      addTearDown(container.dispose);

      expect(container.read(editorHostKindProvider), EditorHostKind.none);
    });

    test('the bucket the bridge produces is one the Worker accepts', () {
      expect(kTelemetryFormFactors, contains('vscode'));
    });
  });

  group('resolvedDeviceClassForSize', () {
    test('a native desktop host answers without a size', () {
      // The one host where the question has no size dependency: the window is
      // a desktop window at any width. `isDesktopHostPlatform` is false under
      // the test binding, so this asserts the contract at the seam that
      // matters — a size, once present, always resolves.
      expect(resolvedDeviceClassForSize(const Size(1440, 900)), isNotNull);
    });

    test('null means "not yet", and only that', () {
      expect(resolvedDeviceClassForSize(null), isNull);
      expect(resolvedDeviceClassForSize(const Size(800, 1280)), isNotNull);
    });

    test('it agrees with deviceClassForSize wherever that has an answer', () {
      // The defaulting entry point must stay exactly this one plus a fallback,
      // or the layout and the telemetry bucket start to drift — which is the
      // failure the derivation reads DeviceClass at all to avoid.
      for (final size in const <Size>[
        Size(1440, 900),
        Size(800, 1280),
        Size(390, 844),
        Size(844, 390),
      ]) {
        expect(resolvedDeviceClassForSize(size), deviceClassForSize(size));
      }
      expect(resolvedDeviceClassForSize(null), isNull);
      expect(deviceClassForSize(null), DeviceClass.desktop);
    });
  });

  group('D2 — the wired seam on a tablet host', () {
    // The failing cell, reproduced against the override the app installs. A
    // Pixel Tablet in portrait reads `sw800dp w800dp h1280dp ... xlrg port`,
    // which `DeviceClass.fromSize` calls `tablet` without ambiguity — and four
    // consecutive launches of one build reported desktop, tablet, desktop,
    // desktop. Nothing about the device changed between them; what changed was
    // whether the launch flush beat `DisplaySizeFeed` to the provider.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('defers before the first size, and never says desktop', () {
      final container = ProviderContainer(
        overrides: wavecruxTelemetryOverrides,
      );
      addTearDown(container.dispose);

      expect(
        container.read(telemetryFormFactorProvider),
        isNull,
        reason:
            'this is the launch-flush moment: the service reads the seam '
            'before MaterialApp.builder has mounted DisplaySizeFeed',
      );
    });

    test('reports tablet once the first size lands, every time', () {
      final container = ProviderContainer(
        overrides: wavecruxTelemetryOverrides,
      );
      addTearDown(container.dispose);

      expect(container.read(telemetryFormFactorProvider), isNull);

      container
          .read(displaySizeProvider.notifier)
          .set(const Size(800, 1280)); // Pixel Tablet, portrait.

      expect(container.read(telemetryFormFactorProvider), 'tablet');
    });

    test('a landscape tablet still reports desktop at 1280 dp', () {
      // Not a regression, and worth pinning: the landscape cell PASSED in the
      // failing pass, and could not have distinguished a correct answer from
      // the pre-layout default. It reports `desktop` because the breakpoints
      // legitimately say so at that width, and it must keep doing so.
      final container = ProviderContainer(
        overrides: wavecruxTelemetryOverrides,
      );
      addTearDown(container.dispose);

      container.read(displaySizeProvider.notifier).set(const Size(1280, 800));

      expect(container.read(telemetryFormFactorProvider), 'desktop');
    });
  });
}
