// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';

void main() {
  // The marker chords (setMarker, jumpToMarker) are bound to bare `M` / `⇧M`
  // in defaultBindings(): pressing the key arms the chord, and the next a–z
  // key (captured by the viewer's MarkerChordController) completes it. The
  // first key IS a SingleActivator, so these are NOT unbound — see the
  // explicit trigger assertions in the macOS group below.

  // Actions that are triggered only via the menu bar / overflow menu /
  // command palette — no global keyboard shortcut is registered for them.
  const paletteOnlyActions = {
    // Close File left this set: it is Ctrl+F4 on Windows and Linux, and
    // unbound only on Apple platforms — see the per-platform groups below.
    // Remove Marker opens a picker of currently-set markers (a–z). Removal is
    // infrequent and the `M` / `⇧M` slots belong to set/jump, so it has no
    // keyboard binding; it is reached via the command palette, menu, and a
    // right-click on a marker flag in the time ruler.
    ShortcutAction.removeMarker,
    // openAbout is no longer palette-only: F1 = About is the suite-wide
    // convention across the Crux apps, so it left this set.
    // Beta Issue Reporter — reached via the Help menu / overflow menu,
    // command palette, and the About box. No global keyboard shortcut.
    ShortcutAction.issueReporter,
    ShortcutAction.copyDiagnosticsReport,
    ShortcutAction.loadRtlStemsFile,
    ShortcutAction.generateRtlStems,
    ShortcutAction.importVerilatorAst,
    ShortcutAction.loadCocotbLog,
    ShortcutAction.clearCocotbLog,
    ShortcutAction.toggleCocotbLogPanel,
    // Load / Clear SVA Results (Pro tier) — reached via the Tools menu,
    // overflow menu, and command palette. No global keyboard shortcut
    // (toggleSvaPanel owns the one SVA chord, Cmd/Ctrl+Shift+V).
    ShortcutAction.loadSvaResults,
    ShortcutAction.clearSvaResults,
    // Convert PCAP to VCD — Enterprise-tier Tools menu action pulled-forward
    // from Future Phases. Reachable via Tools menu and command palette; no
    // global keyboard shortcut is registered by default.
    ShortcutAction.convertPcapToVcd,
    // Panel collapse via the chevron in each panel header (ARCHITECTURE.md
    // §3.1.8.6). Re-show via the command palette / overflow menu —
    // these actions intentionally have no global keyboard shortcut.
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
    // Review minutes share that reasoning: the export is reached
    // from the File menu and the command palette beside the raw recording, and
    // an infrequent document export does not deserve a global chord.
    ShortcutAction.exportReviewMinutes,
    // The Annotations *panel* toggle is a layout action done once per session
    // — palette and View menu are enough. Its sibling
    // `toggleAnnotationsVisible` IS bound (Cmd/Ctrl+Shift+N), because hiding
    // notes to read the raw trace happens mid-read.
    ShortcutAction.toggleAnnotationsPanel,
    // Annotate Selected Range is a menu/palette action. It follows a gesture
    // the user has just finished (a Shift-drag), so their hand is on the
    // pointer, not reaching for a chord.
    ShortcutAction.annotateSelectedRange,
    // Presenter Mode actions are invoked via the collaboration
    // status bar (presenter chip / handoff menu / request prompts) and the
    // pointer-drop gesture — no global keyboard shortcut is registered.
    ShortcutAction.handoffPresenter,
    ShortcutAction.requestPresenter,
    ShortcutAction.resumeFollowing,
    ShortcutAction.dropPing,
    ShortcutAction.dropPin,
    // Workspace management commands are reached through the File
    // menu and the command palette; no global keyboard shortcut is bound by
    // default because both are destructive operations that should require an
    // intentional menu/palette action.
    ShortcutAction.resetWorkspace,
    ShortcutAction.newWorkspace,
    ShortcutAction.saveWorkspaceAs,
    ShortcutAction.openWorkspace,
    ShortcutAction.exportTabAsSession,
    // Pane management actions (split-pane). splitPaneRight is
    // bound to Cmd/Ctrl+\ and closePane to Cmd/Ctrl+Shift+W in
    // defaultBindings(); focusOtherPane / moveTabToOtherPane still have
    // no default binding because their natural chord activators (Cmd+K
    // →, Cmd+K Shift+→) are not representable by SingleActivator. Both
    // remain discoverable through the menu bar and command palette.
    ShortcutAction.focusOtherPane,
    ShortcutAction.moveTabToOtherPane,
    // Pane Render Stats popover is anchored to a per-pane
    // `i`-icon in ViewerTabBar. The command-palette entry is the keyboard
    // fallback; no global keyboard shortcut is registered.
    ShortcutAction.openPaneRenderStats,
    // Cross-probe panel has the suite-wide Cmd/Ctrl+Shift+X default, so it
    // is not listed here.
    // Check for Updates — Help menu / overflow / palette and
    // the About box; no default keyboard binding.
    ShortcutAction.checkForUpdates,
    // Documentation — Help menu / overflow / palette; opens docs.wavecrux.app
    // in the browser. F1 is deliberately NOT taken: it is About's binding
    // across the suite, and a docs link is not worth a keyboard slot.
    ShortcutAction.openDocumentation,
    // Explain Selection (Experimental AI) — palette / Tools menu only; no
    // default keyboard binding.
    ShortcutAction.aiExplainSelection,
    // AI Waveform Assistant panel toggle (Experimental AI, Pro) — palette /
    // Tools menu only; no default keyboard binding.
    ShortcutAction.aiAdvisorTogglePanel,
    // Clear Signal Selection — Escape clears the selection via the viewer's
    // global key handler (clearCursors owns the Escape SingleActivator at the
    // binding-table level to keep the no-shadow conflict guard happy), so this
    // action registers no SingleActivator of its own. Reached via menu /
    // overflow / command palette and the Escape key.
    ShortcutAction.clearSignalSelection,
    // Stop Streaming — File menu / overflow / palette, and the toolbar button
    // that appears while a stream is live. No default chord: streaming is rare
    // enough not to be worth a keyboard slot.
    ShortcutAction.stopStreaming,
    // Share Annotated Waveform — File menu / overflow / palette only. No
    // default chord on purpose: it is the one action that sends design data
    // off the machine, and a chord that does that is one that can be hit by
    // accident.
    ShortcutAction.shareAnnotatedWaveform,
    // Play Walkthrough — menu / overflow / palette and the panel's own
    // transport. `]` and `[` carry the stepping; starting an automatic tour is
    // a deliberate act rather than something worth a keyboard slot.
    ShortcutAction.annotationWalkthroughPlay,
    // Clear Canvas — View menu / overflow / palette. No default chord: a
    // one-key wipe of a curated view is a chord that gets hit by accident,
    // even with the Undo snackbar behind it.
    ShortcutAction.clearCanvas,
    // Remove Selected Signals — Edit menu / overflow / palette. The Signals
    // list owns Delete and Backspace for it while the list has focus; a
    // global binding would fire from panels unrelated to the list.
    ShortcutAction.removeSelectedSignals,
  };

  const unboundActions = paletteOnlyActions;

  // WaveCrux has no by-design keyboard shadows: every default chord is owned by
  // exactly one action (issue #37 removed the last shadow — closeFile no longer
  // shares Cmd/Ctrl+W with closeTab). Any collision is therefore a wiring
  // defect (a dead shortcut), so the allow-list is empty.
  const intentionalShadows = <Set<ShortcutAction>>{};

  String sig(SingleActivator a) =>
      '${a.trigger.keyLabel}|c=${a.control}|m=${a.meta}|s=${a.shift}|a=${a.alt}';

  group('defaultBindings — no unintended collisions', () {
    test(
      'each activator is owned by exactly one action (or a documented pair)',
      () {
        final bindings = defaultBindings();
        final bySig = <String, List<ShortcutAction>>{};
        bindings.forEach((action, activator) {
          bySig
              .putIfAbsent(sig(activator as SingleActivator), () => [])
              .add(action);
        });

        final unexpected = <String>[];
        bySig.forEach((sig, actions) {
          if (actions.length < 2) return;
          final asSet = actions.toSet();
          final allowed = intentionalShadows.any(
            (pair) => pair.containsAll(asSet),
          );
          if (!allowed) {
            unexpected.add('$sig → ${actions.map((a) => a.name).join(', ')}');
          }
        });

        expect(
          unexpected,
          isEmpty,
          reason:
              'These activators are claimed by multiple actions; all but one '
              'are dead shortcuts:\n${unexpected.join('\n')}',
        );
      },
    );
  });

  group('defaultBindings — coverage', () {
    test('contains an entry for every bindable ShortcutAction', () {
      final bindings = defaultBindings();
      final bindable = ShortcutAction.values.where(
        (a) => !unboundActions.contains(a),
      );
      expect(bindings.keys, containsAll(bindable));
    });

    test('openAbout is bound to bare F1 (suite-wide About convention)', () {
      final about =
          defaultBindings()[ShortcutAction.openAbout]! as SingleActivator;
      expect(about.trigger, LogicalKeyboardKey.f1);
      expect(about.meta, isFalse);
      expect(about.control, isFalse);
      expect(about.shift, isFalse);
      expect(about.alt, isFalse);
    });

    test(
      'the marker chords are bound (their first key is a SingleActivator)',
      () {
        final bindings = defaultBindings();
        expect(bindings.containsKey(ShortcutAction.setMarker), isTrue);
        expect(bindings.containsKey(ShortcutAction.jumpToMarker), isTrue);
      },
    );

    test('togglePlayback is bound to bare Space (collision-free)', () {
      final bindings = defaultBindings();
      final play = bindings[ShortcutAction.togglePlayback]! as SingleActivator;
      expect(play.trigger, LogicalKeyboardKey.space);
      expect(play.meta, isFalse);
      expect(play.control, isFalse);
      expect(play.shift, isFalse);
      expect(play.alt, isFalse);
      // No other default binding claims Space.
      final spaceOwners = bindings.entries
          .where(
            (e) =>
                (e.value as SingleActivator).trigger ==
                LogicalKeyboardKey.space,
          )
          .map((e) => e.key)
          .toList();
      expect(spaceOwners, [ShortcutAction.togglePlayback]);
    });

    test('palette-only actions are absent from defaultBindings', () {
      final bindings = defaultBindings();
      for (final action in unboundActions) {
        expect(
          bindings.containsKey(action),
          isFalse,
          reason:
              '${action.name} is intentionally unbound and must not '
              'appear in defaultBindings',
        );
      }
    });
  });

  group('defaultBindings — macOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('closeFile is unbound (Cmd+W is close on this platform)', () {
      expect(defaultBindings().containsKey(ShortcutAction.closeFile), isFalse);
    });

    test('modifier-key actions use meta, not control', () {
      final b = defaultBindings();
      for (final action in const [
        ShortcutAction.openFile,
        ShortcutAction.quit,
        ShortcutAction.zoomIn,
        ShortcutAction.zoomOut,
        ShortcutAction.fitAll,
        ShortcutAction.toggleTheme,
      ]) {
        final a = b[action]! as SingleActivator;
        expect(
          a.meta,
          isTrue,
          reason: '${action.name} should use meta on macOS',
        );
        expect(
          a.control,
          isFalse,
          reason: '${action.name} should not use control on macOS',
        );
      }
    });

    test('WASD/QE navigation keys have no modifier', () {
      final b = defaultBindings();
      for (final action in const [
        ShortcutAction.panLeft,
        ShortcutAction.panRight,
        ShortcutAction.nextTransition,
        ShortcutAction.prevTransition,
      ]) {
        final a = b[action]! as SingleActivator;
        expect(a.meta, isFalse, reason: '${action.name} should have no meta');
        expect(
          a.control,
          isFalse,
          reason: '${action.name} should have no control',
        );
        expect(a.shift, isFalse, reason: '${action.name} should have no shift');
        expect(a.alt, isFalse, reason: '${action.name} should have no alt');
      }
    });

    test('panLeft trigger is keyA', () {
      final a = defaultBindings()[ShortcutAction.panLeft]! as SingleActivator;
      expect(a.trigger, LogicalKeyboardKey.keyA);
    });

    test('panRight trigger is keyD', () {
      final a = defaultBindings()[ShortcutAction.panRight]! as SingleActivator;
      expect(a.trigger, LogicalKeyboardKey.keyD);
    });

    test('nextTransition trigger is keyE', () {
      final a =
          defaultBindings()[ShortcutAction.nextTransition]! as SingleActivator;
      expect(a.trigger, LogicalKeyboardKey.keyE);
    });

    test('prevTransition trigger is keyQ (no modifier)', () {
      final a =
          defaultBindings()[ShortcutAction.prevTransition]! as SingleActivator;
      expect(a.trigger, LogicalKeyboardKey.keyQ);
      expect(a.meta, isFalse);
    });

    test('setMarker is bare M and jumpToMarker is ⇧M', () {
      final set =
          defaultBindings()[ShortcutAction.setMarker]! as SingleActivator;
      final jump =
          defaultBindings()[ShortcutAction.jumpToMarker]! as SingleActivator;
      expect(set.trigger, LogicalKeyboardKey.keyM);
      expect(set.shift, isFalse);
      expect(set.meta, isFalse);
      expect(set.control, isFalse);
      expect(set.alt, isFalse);
      expect(jump.trigger, LogicalKeyboardKey.keyM);
      expect(jump.shift, isTrue);
      expect(jump.meta, isFalse);
      expect(jump.control, isFalse);
      expect(jump.alt, isFalse);
    });

    test('marker chords do not collide with openAppDiagnostics (⌘⇧M)', () {
      final diag =
          defaultBindings()[ShortcutAction.openAppDiagnostics]!
              as SingleActivator;
      // openAppDiagnostics carries a primary modifier (meta on macOS); the
      // marker chords are bare M / Shift+M, so they never overlap.
      expect(diag.trigger, LogicalKeyboardKey.keyM);
      expect(diag.meta, isTrue);
      expect(diag.shift, isTrue);
    });

    test('quit uses meta+Q — distinct from bare-Q prevTransition', () {
      final quit = defaultBindings()[ShortcutAction.quit]! as SingleActivator;
      final prev =
          defaultBindings()[ShortcutAction.prevTransition]! as SingleActivator;
      expect(quit.trigger, LogicalKeyboardKey.keyQ);
      expect(quit.meta, isTrue);
      expect(prev.trigger, LogicalKeyboardKey.keyQ);
      expect(prev.meta, isFalse);
    });

    test('closePane uses meta+shift+W — distinct from closeTab (meta+W) and '
        'waveformZoomIn (bare W)', () {
      final close =
          defaultBindings()[ShortcutAction.closePane]! as SingleActivator;
      final tab =
          defaultBindings()[ShortcutAction.closeTab]! as SingleActivator;
      final zoom =
          defaultBindings()[ShortcutAction.waveformZoomIn]! as SingleActivator;
      expect(close.trigger, LogicalKeyboardKey.keyW);
      expect(close.meta, isTrue);
      expect(close.shift, isTrue);
      expect(close.control, isFalse);
      expect(close.alt, isFalse);
      // closeTab is meta+W, no shift — the sole owner of Cmd/Ctrl+W.
      expect(tab.trigger, LogicalKeyboardKey.keyW);
      expect(tab.meta, isTrue);
      expect(tab.shift, isFalse);
      // waveformZoomIn is bare W.
      expect(zoom.trigger, LogicalKeyboardKey.keyW);
      expect(zoom.meta, isFalse);
      expect(zoom.shift, isFalse);
    });

    test('generateTestVcd uses meta+alt+G — distinct from toggleStagePanel '
        '(meta+shift+G)', () {
      final gen =
          defaultBindings()[ShortcutAction.generateTestVcd]! as SingleActivator;
      final stage =
          defaultBindings()[ShortcutAction.toggleStagePanel]!
              as SingleActivator;
      expect(gen.trigger, LogicalKeyboardKey.keyG);
      expect(gen.meta, isTrue);
      expect(gen.alt, isTrue);
      expect(gen.shift, isFalse);
      expect(gen.control, isFalse);
      expect(stage.trigger, LogicalKeyboardKey.keyG);
      expect(stage.meta, isTrue);
      expect(stage.shift, isTrue);
      expect(stage.alt, isFalse);
    });
  });

  group('defaultBindings — Linux', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('closeFile is Ctrl+F4, the platform close-document key', () {
      final close =
          defaultBindings()[ShortcutAction.closeFile]! as SingleActivator;
      expect(close.trigger, LogicalKeyboardKey.f4);
      expect(close.control, isTrue);
      expect(close.meta, isFalse);
      expect(close.shift, isFalse);
      expect(close.alt, isFalse);
    });

    test('modifier-key actions use control, not meta', () {
      final b = defaultBindings();
      for (final action in const [
        ShortcutAction.openFile,
        ShortcutAction.quit,
        ShortcutAction.zoomIn,
        ShortcutAction.zoomOut,
        ShortcutAction.fitAll,
        ShortcutAction.toggleTheme,
      ]) {
        final a = b[action]! as SingleActivator;
        expect(
          a.control,
          isTrue,
          reason: '${action.name} should use control on Linux',
        );
        expect(
          a.meta,
          isFalse,
          reason: '${action.name} should not use meta on Linux',
        );
      }
    });

    test('toggleTheme uses shift modifier', () {
      final a =
          defaultBindings()[ShortcutAction.toggleTheme]! as SingleActivator;
      expect(a.shift, isTrue);
    });

    test('openFile trigger is keyO', () {
      final a = defaultBindings()[ShortcutAction.openFile]! as SingleActivator;
      expect(a.trigger, LogicalKeyboardKey.keyO);
    });

    test('fitAll trigger is digit0', () {
      final a = defaultBindings()[ShortcutAction.fitAll]! as SingleActivator;
      expect(a.trigger, LogicalKeyboardKey.digit0);
    });

    test('closePane uses control+shift+W on Linux', () {
      final a = defaultBindings()[ShortcutAction.closePane]! as SingleActivator;
      expect(a.trigger, LogicalKeyboardKey.keyW);
      expect(a.control, isTrue);
      expect(a.shift, isTrue);
      expect(a.meta, isFalse);
    });

    test('generateTestVcd uses control+alt+G on Linux', () {
      final a =
          defaultBindings()[ShortcutAction.generateTestVcd]! as SingleActivator;
      expect(a.trigger, LogicalKeyboardKey.keyG);
      expect(a.control, isTrue);
      expect(a.alt, isTrue);
      expect(a.meta, isFalse);
      expect(a.shift, isFalse);
    });
  });

  group('defaultBindings — Windows', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('closeFile is Ctrl+F4, the platform close-document key', () {
      final close =
          defaultBindings()[ShortcutAction.closeFile]! as SingleActivator;
      expect(close.trigger, LogicalKeyboardKey.f4);
      expect(close.control, isTrue);
      expect(close.meta, isFalse);
      expect(close.shift, isFalse);
      expect(close.alt, isFalse);
    });

    test('modifier-key actions use control, not meta', () {
      final b = defaultBindings();
      final a = b[ShortcutAction.openFile]! as SingleActivator;
      expect(a.control, isTrue);
      expect(a.meta, isFalse);
    });
  });
}
