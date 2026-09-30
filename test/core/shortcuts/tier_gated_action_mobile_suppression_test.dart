// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/tier_gated_actions_available_provider.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

/// Guards the fix for the App Store review rejection of WaveCrux 0.1.0 (2).
///
/// Apple rejected the build under Guideline 2.2 ("complete, remove, or fully
/// configure any partially implemented features"): the Open Core iOS build
/// listed PRO/ENT actions in the mobile overflow menu and command palette,
/// badged and enabled, whose handlers are empty closures. A reviewer tapped
/// "Share Session" and "Convert PCAP to VCD" and nothing happened at all.
///
/// The rule is enforced once, in `isActionVisibleIn`, so that a future PRO/ENT
/// action inherits it from `requiredTier` alone. These tests pin both halves:
/// tier-gated actions vanish when the build cannot run them, and Open Core
/// actions are untouched.
void main() {
  ActionContext context({required bool tierGatedActionsAvailable}) =>
      ActionContext(
        // Deliberately generous: a file is loaded, a session is active, and
        // the user both hosts and participates, so every `requires` predicate
        // on the PRO/ENT actions is satisfied. Any action that stays hidden
        // does so because of the tier rule and nothing else.
        fileLoaded: true,
        deviceClass: DeviceClass.phone,
        inSession: true,
        isHost: true,
        isRecording: true,
        aiAvailable: true,
        aiModelConfigured: true,
        hasSelection: true,
        cursorPresent: true,
        tierGatedActionsAvailable: tierGatedActionsAvailable,
      );

  final tierGatedActions = ShortcutAction.values
      .where((a) => descriptorFor(a).requiredTier != LicenseTier.openCore)
      .toList();

  final openCoreActions = ShortcutAction.values
      .where((a) => descriptorFor(a).requiredTier == LicenseTier.openCore)
      .toList();

  test('the table actually has tier-gated actions to suppress', () {
    // If this ever hits zero the rest of the suite would pass vacuously.
    expect(tierGatedActions, isNotEmpty);
  });

  group('when the build cannot execute tier-gated actions', () {
    final ctx = context(tierGatedActionsAvailable: false);

    test('every PRO/ENT action is hidden from every surface', () {
      for (final action in tierGatedActions) {
        for (final surface in ActionSurface.values) {
          expect(
            isActionVisibleIn(action, surface, ctx),
            isFalse,
            reason: '$action must not appear in $surface',
          );
        }
      }
    });

    test('no PRO/ENT action reaches the command palette', () {
      final palette = paletteActionsFor(ctx);
      for (final action in tierGatedActions) {
        expect(palette, isNot(contains(action)), reason: '$action');
      }
    });

    test('no PRO/ENT action reaches the overflow menu', () {
      // The overflow menu is the surface the reviewer actually used: it
      // *includes* disabled actions (greyed), so a merely-disabled action
      // would still render as a dead row here.
      final grouped = groupedActionsFor(ActionSurface.overflow, ctx);
      final listed = grouped.values.expand((actions) => actions).toList();
      for (final action in tierGatedActions) {
        expect(listed, isNot(contains(action)), reason: '$action');
      }
    });

    test('Open Core actions are unaffected', () {
      final available = context(tierGatedActionsAvailable: true);
      for (final action in openCoreActions) {
        for (final surface in ActionSurface.values) {
          expect(
            isActionVisibleIn(action, surface, ctx),
            isActionVisibleIn(action, surface, available),
            reason: '$action visibility in $surface must not change',
          );
        }
      }
    });
  });

  group('when the build can execute tier-gated actions', () {
    final ctx = context(tierGatedActionsAvailable: true);

    test('PRO/ENT actions still surface normally', () {
      // Desktop Open Core keeps the badged upsell — the tier badge there has
      // a working upgrade path behind it, so hiding would lose real signal.
      final listed = groupedActionsFor(
        ActionSurface.overflow,
        ctx,
      ).values.expand((actions) => actions).toList();
      expect(
        tierGatedActions.where(listed.contains),
        isNotEmpty,
        reason: 'suppression must be conditional, not permanent',
      );
    });
  });

  group('tierGatedActionsAvailableProvider default', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is false on iOS and Android — the app-store hosts', () {
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(
          container.read(tierGatedActionsAvailableProvider),
          isFalse,
          reason: '$platform',
        );
      }
    });

    test('is true on desktop hosts', () {
      for (final platform in const [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(
          container.read(tierGatedActionsAvailableProvider),
          isTrue,
          reason: '$platform',
        );
      }
    });

    test('is overridable, so a Pro mobile build can opt back in', () {
      // The Pro overlay replaces the no-op opener providers with real
      // implementations; when it ships mobile it overrides this to true. If
      // the platform check were hardcoded at the call site instead, Pro mobile
      // would silently lose every Pro feature.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final container = ProviderContainer(
        overrides: [tierGatedActionsAvailableProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      expect(container.read(tierGatedActionsAvailableProvider), isTrue);
    });
  });
}
