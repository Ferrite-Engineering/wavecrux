// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/shortcuts/keymap_presets.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';

// SingleActivator has no value equality, so compare its properties instead.
void expectSameActivator(
  ShortcutActivator? actual,
  ShortcutActivator? expected, {
  String? reason,
}) {
  expect(actual, isA<SingleActivator>(), reason: reason);
  expect(expected, isA<SingleActivator>(), reason: reason);
  final a = actual! as SingleActivator;
  final e = expected! as SingleActivator;
  expect(a.trigger, e.trigger, reason: reason);
  expect(a.control, e.control, reason: reason);
  expect(a.meta, e.meta, reason: reason);
  expect(a.shift, e.shift, reason: reason);
  expect(a.alt, e.alt, reason: reason);
}

// Actions triggered only via the menu bar / overflow / command palette —
// no keyboard binding.
const Set<ShortcutAction> paletteOnlyActions = {
  // Close File left this set: Ctrl+F4 on Windows and Linux, unbound only on
  // Apple platforms (see shortcut_bindings_test.dart).
  // Remove Marker opens a picker of currently-set markers; reached via the
  // command palette, menu, and a right-click on a marker flag in the ruler.
  // The `M` / `⇧M` keyboard slots belong to setMarker / jumpToMarker.
  ShortcutAction.removeMarker,
  // openAbout is no longer palette-only: F1 = About is the suite-wide
  // convention across the Crux apps, so it left this set.
  // Beta Issue Reporter — Help menu / palette / About box only.
  ShortcutAction.issueReporter,
  ShortcutAction.copyDiagnosticsReport,
  ShortcutAction.loadRtlStemsFile,
  ShortcutAction.generateRtlStems,
  ShortcutAction.importVerilatorAst,
  ShortcutAction.loadCocotbLog,
  ShortcutAction.clearCocotbLog,
  ShortcutAction.toggleCocotbLogPanel,
  // Load / Clear SVA Results (Pro tier) — Tools menu / overflow / palette;
  // no global keyboard shortcut (toggleSvaPanel owns the SVA chord).
  ShortcutAction.loadSvaResults,
  ShortcutAction.clearSvaResults,
  // Convert PCAP to VCD — Enterprise-tier Tools menu action pulled-forward
  // from Future Phases. Reachable via Tools menu and command palette; no
  // global keyboard shortcut is registered by default.
  ShortcutAction.convertPcapToVcd,
  ShortcutAction.toggleSignalTree,
  ShortcutAction.toggleValueColumn,
  // Format-switching actions are invoked via the value-column context menu
  // and command palette. No global keyboard shortcut is registered by
  // default to avoid conflicts with text-editing keys.
  ShortcutAction.setFormatBinary,
  ShortcutAction.setFormatHexadecimal,
  ShortcutAction.setFormatOctal,
  ShortcutAction.setFormatUnsignedDecimal,
  ShortcutAction.setFormatSignedDecimal,
  ShortcutAction.setFormatAscii,
  ShortcutAction.setFormatIeee754Single,
  ShortcutAction.setFormatIeee754Double,
  ShortcutAction.setFormatFixedPointQ,
  ShortcutAction.setFormatSignedMagnitude,
  ShortcutAction.setFormatGrayCode,
  ShortcutAction.setFormatNamedEnum,
  // Collaboration actions are invoked via the Share/Join dialogs and the
  // collaboration status panel — no global keyboard shortcut is registered.
  ShortcutAction.shareSession,
  ShortcutAction.joinSession,
  ShortcutAction.stopSharing,
  ShortcutAction.leaveSession,
  ShortcutAction.exportSessionRecording,
  ShortcutAction.exportReviewMinutes,
  ShortcutAction.toggleAnnotationsPanel,
  ShortcutAction.annotateSelectedRange,
  // Presenter Mode actions are invoked via the collaboration
  // status bar and the pointer-drop gesture — no global keyboard shortcut.
  ShortcutAction.handoffPresenter,
  ShortcutAction.requestPresenter,
  ShortcutAction.resumeFollowing,
  ShortcutAction.dropPing,
  ShortcutAction.dropPin,
  // Workspace management commands intentionally have no
  // global keyboard shortcut — destructive operations only fire through
  // the File menu and command palette.
  ShortcutAction.resetWorkspace,
  ShortcutAction.newWorkspace,
  ShortcutAction.saveWorkspaceAs,
  ShortcutAction.openWorkspace,
  ShortcutAction.exportTabAsSession,
  // Pane management commands (split-pane). [splitPaneRight] is
  // bound to Cmd/Ctrl+\ and [closePane] to Cmd/Ctrl+Shift+W;
  // focusOtherPane / moveTabToOtherPane have no default keyboard binding
  // because their natural chord activators aren't representable by
  // SingleActivator.
  ShortcutAction.focusOtherPane,
  ShortcutAction.moveTabToOtherPane,
  // Pane Render Stats popover — anchored to a per-pane `i`-icon
  // in ViewerTabBar; command-palette only, no default keyboard binding.
  ShortcutAction.openPaneRenderStats,
  // Cross-probe panel has the suite-wide Cmd/Ctrl+Shift+X default, so it is
  // not listed here.
  // Check for Updates — Help menu / overflow / palette and
  // the About box; no default keyboard binding.
  ShortcutAction.checkForUpdates,
  // Documentation — Help menu / overflow / palette; opens docs.wavecrux.app
  // in the browser. F1 is deliberately NOT taken: it is About's binding
  // across the suite, and a docs link is not worth a keyboard slot.
  ShortcutAction.openDocumentation,
  // Explain Selection (Experimental AI) — palette / Tools menu only; no
  // default keyboard binding (avoids chord conflicts with the feature gated
  // behind the experimental flag).
  ShortcutAction.aiExplainSelection,
  // AI Waveform Assistant panel toggle (Experimental AI, Pro) — palette /
  // Tools menu only; no default keyboard binding.
  ShortcutAction.aiAdvisorTogglePanel,
  // Clear Signal Selection — Escape clears the selection through the viewer's
  // global key handler (clearCursors owns the Escape SingleActivator), so this
  // action carries no SingleActivator of its own. Menu / overflow / palette
  // reachable.
  ShortcutAction.clearSignalSelection,
  // Stop Streaming — File menu / overflow / palette, and the toolbar button
  // that appears while a stream is live. No default chord: streaming is rare
  // enough not to be worth a keyboard slot, and every unbound slot is one
  // fewer collision for the user's own bindings.
  ShortcutAction.stopStreaming,
  // Share Annotated Waveform — File menu / overflow / palette only. No default
  // chord on purpose: it is the one action that sends design data off the
  // machine, and a chord that does that is one that can be hit by accident.
  ShortcutAction.shareAnnotatedWaveform,
  // Play Walkthrough — menu / overflow / palette and the annotations panel's
  // own transport. `]` and `[` carry the stepping; starting an automatic tour
  // is a deliberate act rather than something worth a keyboard slot.
  ShortcutAction.annotationWalkthroughPlay,
};

const Set<ShortcutAction> unboundActions = paletteOnlyActions;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() => ProviderContainer();

  // Container whose persistence is backed by [prefs], so customizations survive
  // and a fresh container restores them (the post-relaunch path).
  ProviderContainer makePersistentContainer(SharedPreferences prefs) =>
      ProviderContainer(
        overrides: [
          shortcutBindingsStoreProvider.overrideWithValue(
            KeyBindingsStore<ShortcutAction>(
              codec: waveCruxKeymapCodec,
              prefsOverride: prefs,
            ),
          ),
        ],
      );

  // Lets the unawaited _restore() microtask in build() complete.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('ShortcutBindingsNotifier — initial state', () {
    test('builds from defaultBindings', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final bindings = container.read(shortcutBindingsProvider);
      final bindable = ShortcutAction.values.where(
        (a) => !unboundActions.contains(a),
      );
      expect(bindings.keys, containsAll(bindable));
    });

    test('initial values match defaultBindings()', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final bindings = container.read(shortcutBindingsProvider);
      final defaults = defaultBindings();
      for (final action in ShortcutAction.values.where(
        (a) => !unboundActions.contains(a),
      )) {
        expectSameActivator(
          bindings[action],
          defaults[action],
          reason: '${action.name} initial binding should match default',
        );
      }
    });
  });

  group('ShortcutBindingsNotifier.setBinding', () {
    test('replaces the binding for the specified action', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      const newActivator = SingleActivator(LogicalKeyboardKey.keyZ);
      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(ShortcutAction.zoomIn, newActivator);

      final bindings = container.read(shortcutBindingsProvider);
      expect(bindings[ShortcutAction.zoomIn], newActivator);
    });

    test('does not change other bindings', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final beforeZoomOut = container.read(
        shortcutBindingsProvider,
      )[ShortcutAction.zoomOut];
      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.zoomIn,
            const SingleActivator(LogicalKeyboardKey.keyZ),
          );

      expect(
        container.read(shortcutBindingsProvider)[ShortcutAction.zoomOut],
        beforeZoomOut,
      );
    });

    test('state is a new map instance — original unaffected', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final before = container.read(shortcutBindingsProvider);
      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.zoomIn,
            const SingleActivator(LogicalKeyboardKey.keyZ),
          );
      final after = container.read(shortcutBindingsProvider);

      expect(identical(before, after), isFalse);
    });
  });

  group('ShortcutBindingsNotifier.reset', () {
    test('restores the default binding for the specified action', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final original = container.read(
        shortcutBindingsProvider,
      )[ShortcutAction.zoomIn];
      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.zoomIn,
            const SingleActivator(LogicalKeyboardKey.keyZ),
          );
      container
          .read(shortcutBindingsProvider.notifier)
          .reset(ShortcutAction.zoomIn);

      expectSameActivator(
        container.read(shortcutBindingsProvider)[ShortcutAction.zoomIn],
        original,
      );
    });

    test('does not affect other bindings', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final originalPan = container.read(
        shortcutBindingsProvider,
      )[ShortcutAction.panLeft];
      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.zoomIn,
            const SingleActivator(LogicalKeyboardKey.keyZ),
          );
      container
          .read(shortcutBindingsProvider.notifier)
          .reset(ShortcutAction.zoomIn);

      expect(
        container.read(shortcutBindingsProvider)[ShortcutAction.panLeft],
        originalPan,
      );
    });
  });

  group('ShortcutBindingsNotifier.resetAll', () {
    test('restores every action to its platform default', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.zoomIn,
            const SingleActivator(LogicalKeyboardKey.keyZ),
          );
      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.panLeft,
            const SingleActivator(LogicalKeyboardKey.keyZ),
          );
      container.read(shortcutBindingsProvider.notifier).resetAll();

      final bindings = container.read(shortcutBindingsProvider);
      final defaults = defaultBindings();
      for (final action in ShortcutAction.values.where(
        (a) => !unboundActions.contains(a),
      )) {
        expectSameActivator(
          bindings[action],
          defaults[action],
          reason: '${action.name} should be back to default after resetAll',
        );
      }
    });
  });

  group('ShortcutBindingsNotifier.unbind', () {
    test('removes the binding for the action', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container
          .read(shortcutBindingsProvider.notifier)
          .unbind(ShortcutAction.zoomIn);
      expect(
        container
            .read(shortcutBindingsProvider)
            .containsKey(ShortcutAction.zoomIn),
        isFalse,
      );
    });

    test('is a no-op for an already-unbound action', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final before = container.read(shortcutBindingsProvider);
      container
          .read(shortcutBindingsProvider.notifier)
          .unbind(ShortcutAction.checkForUpdates); // palette-only, unbound
      expect(
        identical(before, container.read(shortcutBindingsProvider)),
        isTrue,
      );
    });
  });

  group('ShortcutBindingsNotifier.currentDiffs', () {
    test('is empty when nothing has changed', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      expect(
        container.read(shortcutBindingsProvider.notifier).currentDiffs(),
        isEmpty,
      );
    });

    test('captures a rebind and an explicit unbind', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(shortcutBindingsProvider.notifier)
        ..setBinding(
          ShortcutAction.zoomIn,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        )
        ..unbind(ShortcutAction.quit);

      final diffs = notifier.currentDiffs();
      expect(
        diffs.keys,
        containsAll([ShortcutAction.zoomIn, ShortcutAction.quit]),
      );
      expect(diffs[ShortcutAction.quit], isNull);
      expect(diffs[ShortcutAction.zoomIn]!.key, LogicalKeyboardKey.keyZ);
    });
  });

  group('ShortcutBindingsNotifier — persistence', () {
    test('a rebind survives into a fresh container (relaunch path)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = makePersistentContainer(prefs);
      first
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.zoomIn,
            const SingleActivator(LogicalKeyboardKey.keyJ, meta: true),
          );
      await settle();
      first.dispose();

      final second = makePersistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider); // trigger build + _restore
      await settle();

      expectSameActivator(
        second.read(shortcutBindingsProvider)[ShortcutAction.zoomIn],
        const SingleActivator(LogicalKeyboardKey.keyJ, meta: true),
      );
    });

    test('an explicit unbind survives a relaunch', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = makePersistentContainer(prefs);
      first
          .read(shortcutBindingsProvider.notifier)
          .unbind(ShortcutAction.zoomIn);
      await settle();
      first.dispose();

      final second = makePersistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();

      expect(
        second
            .read(shortcutBindingsProvider)
            .containsKey(ShortcutAction.zoomIn),
        isFalse,
      );
    });

    test('resetAll clears persisted overrides', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = makePersistentContainer(prefs);
      first.read(shortcutBindingsProvider.notifier)
        ..setBinding(
          ShortcutAction.zoomIn,
          const SingleActivator(LogicalKeyboardKey.keyJ, meta: true),
        )
        ..resetAll();
      await settle();
      first.dispose();

      final second = makePersistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();

      expectSameActivator(
        second.read(shortcutBindingsProvider)[ShortcutAction.zoomIn],
        defaultBindings()[ShortcutAction.zoomIn],
      );
    });

    test('importDiffs applies and persists a keymap', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = makePersistentContainer(prefs);
      first.read(shortcutBindingsProvider.notifier).importDiffs({
        ShortcutAction.openFile: const KeyBinding(
          key: LogicalKeyboardKey.keyP,
          modifiers: {KeyModifier.mod},
        ),
        ShortcutAction.quit: null,
      });
      await settle();
      first.dispose();

      final second = makePersistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();

      final bindings = second.read(shortcutBindingsProvider);
      final openFile = bindings[ShortcutAction.openFile]! as SingleActivator;
      expect(openFile.trigger, LogicalKeyboardKey.keyP);
      expect(bindings.containsKey(ShortcutAction.quit), isFalse);
    });

    // After a downgrade the stored keymap is one this build cannot read. The
    // store refuses it by throwing rather than answering "no customizations",
    // precisely so the caller can decline to save over it. The launch restore
    // used to let that refusal escape as an uncaught error and then, on the
    // first rebind, save this build's diffs over the newer keymap.
    test('a keymap written by a newer build is refused and never '
        'overwritten', () async {
      const key = 'settings.shortcutBindings';
      const newer = '{"version": ${kKeymapVersion + 1}, "bindings": {}}';
      SharedPreferences.setMockInitialValues({key: newer});
      final prefs = await SharedPreferences.getInstance();
      final records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'wavecrux.shortcuts')
          .listen(records.add);
      addTearDown(sub.cancel);

      final container = makePersistentContainer(prefs);
      addTearDown(container.dispose);
      container.read(shortcutBindingsProvider);
      await settle();

      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.zoomIn,
            const SingleActivator(LogicalKeyboardKey.keyJ, meta: true),
          );
      await settle();

      expect(prefs.getString(key), newer);
      // The session still works, on this build's defaults plus the change.
      expectSameActivator(
        container.read(shortcutBindingsProvider)[ShortcutAction.zoomIn],
        const SingleActivator(LogicalKeyboardKey.keyJ, meta: true),
      );
      expect(records, isNotEmpty);
      expect(records.first.level, Level.WARNING);
    });
  });

  group('ShortcutBindingsNotifier.applyPreset', () {
    test('replaces the whole map with the supplied preset', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container
          .read(shortcutBindingsProvider.notifier)
          .applyPreset(
            bindingsForPreset(KeymapPreset.gtkwave),
          );

      final bindings = container.read(shortcutBindingsProvider);
      // GTKWave search lands on Alt+S.
      expectSameActivator(
        bindings[ShortcutAction.openSearch],
        const SingleActivator(LogicalKeyboardKey.keyS, alt: true),
      );
      expect(presetForBindings(bindings), KeymapPreset.gtkwave);
    });

    test('persists only the delta from defaults across a relaunch', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = makePersistentContainer(prefs);
      first
          .read(shortcutBindingsProvider.notifier)
          .applyPreset(bindingsForPreset(KeymapPreset.gtkwave));
      await settle();
      first.dispose();

      final second = makePersistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();

      expect(
        presetForBindings(second.read(shortcutBindingsProvider)),
        KeymapPreset.gtkwave,
      );
    });

    test('applying the WaveCrux preset returns to defaults', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(shortcutBindingsProvider.notifier)
        ..applyPreset(bindingsForPreset(KeymapPreset.gtkwave))
        ..applyPreset(bindingsForPreset(KeymapPreset.waveCrux));
      expect(
        presetForBindings(container.read(shortcutBindingsProvider)),
        KeymapPreset.waveCrux,
      );
      expect(notifier.currentDiffs(), isEmpty);
    });
  });
}
