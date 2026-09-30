// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';

import 'import_graph.dart';

/// Every action must be reachable, or be listed here with the reason it is not.
///
/// ## The defect class this closes
///
/// A suite audit's single most expensive finding was work that shipped and
/// then had no way in. An action's `surfaces` set is one line, it is silent
/// when empty, and nothing checked it:
///
///  * LintCrux Pro's entire multi-project feature set (project switcher,
///    reopen recent, cross-project search) was built, tier-badged,
///    telemetry-instrumented, and reachable by nobody. It shipped marked done;
///    a later "hide the stub actions" pass emptied the surface sets. Neither
///    side saw the other.
///  * SimCrux's `dispatchPrAnnotations` had a working dispatcher and no menu
///    entry, while the website described the menu entry's behaviour in detail.
///  * NetCrux's X-Trace engine computed a correct result into a provider
///    nothing rendered, and its documentation called it shipped at three
///    altitudes.
///
/// Each was found by a human reading code. This makes the machine read it.
///
/// ## Why an allowlist rather than a blanket ban
///
/// A surfaceless action is sometimes correct — a focus command bound only to a
/// chord, or an engine whose UI genuinely has not been built. What is never
/// correct is an *unexplained* one. The allowlist is a map so every entry
/// carries its reason: an allowance without one is indistinguishable from an
/// oversight six months later, which is precisely how the LintCrux feature set
/// stayed unreachable.
///
/// When a surface lands, delete the entry. When one is emptied, this fails.
const _allowedSurfaceless = <ShortcutAction, String>{
  // All 28 are the block `action_descriptors.dart` labels "Keyboard-only /
  // context-menu-only — hidden from every surface". They are deliberate, and
  // the allowlist records that in a form a test can check rather than a
  // comment a reader has to find.

  // Canvas navigation. WASD + arrow chords over the waveform; a menu entry for
  // "pan left a little" would be noise.
  ShortcutAction.clearSecondaryCursor:
      'canvas navigation chord; no useful menu placement',
  ShortcutAction.panLeft: 'canvas navigation chord; no useful menu placement',
  ShortcutAction.panLeftSmall:
      'canvas navigation chord; no useful menu placement',
  ShortcutAction.panRight: 'canvas navigation chord; no useful menu placement',
  ShortcutAction.panRightSmall:
      'canvas navigation chord; no useful menu placement',
  ShortcutAction.waveformZoomIn:
      'canvas navigation chord; no useful menu placement',
  ShortcutAction.waveformZoomOut:
      'canvas navigation chord; no useful menu placement',

  // The per-row display-format family. These act on the SELECTED SIGNAL, and a
  // global surface has no selection context — so they live on the signal row's
  // context menu instead. Several also gain an Alt-chord under the GTKWave
  // keymap preset; none has a default binding, which is why the reachability
  // assertion below exempts them explicitly rather than looking for a chord.
  ShortcutAction.setFormatAscii:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatBinary:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatFixedPointQ:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatGrayCode:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatHexadecimal:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatIeee754Double:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatIeee754Single:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatNamedEnum:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatOctal:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatSignedDecimal:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatSignedMagnitude:
      'per-row context menu; needs signal selection a global surface lacks',
  ShortcutAction.setFormatUnsignedDecimal:
      'per-row context menu; needs signal selection a global surface lacks',

  // Tab jumps. Cmd/Ctrl+1..9, the standard editor idiom; listing five near
  // identical entries in a menu earns nothing.
  ShortcutAction.jumpToTab1: 'numeric tab-jump chord; standard editor idiom',
  ShortcutAction.jumpToTab2: 'numeric tab-jump chord; standard editor idiom',
  ShortcutAction.jumpToTab3: 'numeric tab-jump chord; standard editor idiom',
  ShortcutAction.jumpToTab4: 'numeric tab-jump chord; standard editor idiom',
  ShortcutAction.jumpToTab5: 'numeric tab-jump chord; standard editor idiom',
  ShortcutAction.jumpToTab6: 'numeric tab-jump chord; standard editor idiom',
  ShortcutAction.jumpToTab7: 'numeric tab-jump chord; standard editor idiom',
  ShortcutAction.jumpToTab8: 'numeric tab-jump chord; standard editor idiom',
  ShortcutAction.jumpToTab9: 'numeric tab-jump chord; standard editor idiom',
};

/// The subset reachable through a per-row context menu rather than a chord.
///
/// Split out because the assertion below cannot see a context menu, and
/// "reachable by nothing" is exactly the bug this file exists to catch — so
/// the exemption has to be named rather than implied.
const _contextMenuOnly = <ShortcutAction>{
  ShortcutAction.setFormatAscii,
  ShortcutAction.setFormatBinary,
  ShortcutAction.setFormatFixedPointQ,
  ShortcutAction.setFormatGrayCode,
  ShortcutAction.setFormatHexadecimal,
  ShortcutAction.setFormatIeee754Double,
  ShortcutAction.setFormatIeee754Single,
  ShortcutAction.setFormatNamedEnum,
  ShortcutAction.setFormatOctal,
  ShortcutAction.setFormatSignedDecimal,
  ShortcutAction.setFormatSignedMagnitude,
  ShortcutAction.setFormatUnsignedDecimal,
};

/// The widget that renders each [ActionSurface], and how to tell it does.
///
/// ## Why declaring a surface is not enough
///
/// The checks further down ask whether an action *declares* a surface. That
/// question was once answered "yes" ninety-five times by a surface nobody
/// could see: `ActionOverflowMenu` read `ActionSurface.overflow`, was tested,
/// localized and named in the manual as one of four surfaces, and was mounted
/// nowhere — the toolbar had long since grown its own overflow. Every action
/// that declared `overflow` passed, on the strength of a widget the program
/// never loaded.
///
/// So each surface names the widget that renders it, the code that proves the
/// widget reads the surface, and the widget itself — and the tests below
/// require the file to be loaded from `lib/main.dart`, the read to be real
/// code rather than a comment, and the widget to be constructed by another
/// loaded file. Any other file that reads a surface fails the sweep: a second
/// consumer is either registered here or is the next phantom.
const _consumers = <ActionSurface, _SurfaceConsumer>{
  ActionSurface.toolbar: _SurfaceConsumer(
    file: 'lib/features/viewer/widgets/viewer_toolbar.dart',
    widget: 'ViewerToolbar',
    // The strip is hand-placed; action_surface_conformance_test.dart holds
    // its buttons to the descriptors that declare `toolbar`.
    reads: 'CruxToolbarButtonItem',
  ),
  ActionSurface.menu: _SurfaceConsumer(
    file: 'lib/features/menu_bar/widgets/desktop_menu_bar.dart',
    widget: 'DesktopMenuBar',
    reads: r'ActionSurface\.menu\b',
  ),
  ActionSurface.overflow: _SurfaceConsumer(
    file: 'lib/features/viewer/widgets/viewer_toolbar.dart',
    widget: 'ViewerToolbar',
    // The toolbar's trailing `CruxToolbarOverflowMenu`, painted once the strip
    // is too narrow for its buttons — always, on a phone.
    reads: r'ActionSurface\.overflow\b',
  ),
  ActionSurface.palette: _SurfaceConsumer(
    file: 'lib/features/command_palette/widgets/command_palette_dialog.dart',
    widget: 'CommandPaletteDialog',
    reads: r'\bpaletteActionsFor\(',
  ),
};

/// Files allowed to name surfaces without rendering one: the enum and the
/// descriptor table with its selectors.
const _surfaceDefinitions = <String>{
  'lib/core/shortcuts/action_descriptor.dart',
  'lib/core/shortcuts/action_descriptors.dart',
};

/// Code that reads an action surface: a named surface or a selector call.
final _readsASurface = RegExp(
  r'\bActionSurface\.\w+|\b(?:groupedActionsFor|paletteActionsFor|'
  r'isActionVisibleIn)\(',
);

void main() {
  test('every action is reachable, or explains why not', () {
    final offenders = <String>[];

    for (final action in ShortcutAction.values) {
      final hasSurface = descriptorFor(action).surfaces.isNotEmpty;
      if (hasSurface) {
        // A surfaced action that is ALSO on the allowlist means the allowance
        // outlived the problem. Fail, so the list cannot rot.
        if (_allowedSurfaceless.containsKey(action)) {
          offenders.add(
            '${action.name}: now has a surface but is still allowlisted — '
            'delete its entry from _allowedSurfaceless',
          );
        }
        continue;
      }
      if (_allowedSurfaceless.containsKey(action)) continue;
      offenders.add(
        '${action.name}: declares no ActionSurface, so it appears in no menu, '
        'no palette and no toolbar. If that is deliberate, add it to '
        '_allowedSurfaceless with the reason. If not, give it a surface — '
        'this is the built-but-unreachable defect class.',
      );
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('an allowlisted action is still reachable somehow', () {
    // The allowlist is for actions reachable some OTHER way. An entry with no
    // surface, no chord and no context menu is not an exception to the rule —
    // it is the bug the rule is about, wearing an exemption.
    final unreachable = <String>[];
    final bindings = defaultBindings();
    for (final action in _allowedSurfaceless.keys) {
      if (_contextMenuOnly.contains(action)) continue;
      if (bindings.containsKey(action)) continue;
      unreachable.add(
        '${action.name}: allowlisted as surfaceless, has no default chord, '
        'and is not marked context-menu-only. It is reachable by nothing.',
      );
    }
    expect(unreachable, isEmpty, reason: unreachable.join('\n'));
  });

  group('every declared surface is rendered by a mounted widget', () {
    late ImportGraph graph;
    late Map<String, String> code;

    setUpAll(() {
      graph = ImportGraph.walk(
        root: '.',
        packageName: 'wavecrux',
        entryPoints: const ['lib/main.dart'],
      );
      code = {
        for (final file in graph.sourceFiles())
          file: stripComments(File(file).readAsStringSync()),
      };
    });

    test('each surface names its consumer', () {
      expect(_consumers.keys.toSet(), ActionSurface.values.toSet());
    });

    test('each consumer is loaded, reads its surface, and is constructed', () {
      final problems = <String>[];
      for (final MapEntry(key: surface, value: c) in _consumers.entries) {
        final declaring = ShortcutAction.values
            .where((a) => descriptorFor(a).surfaces.contains(surface))
            .length;
        final what = '${surface.name} (declared by $declaring actions)';
        if (!graph.reached.contains(c.file)) {
          problems.add(
            '$what: ${c.file} is not loaded from lib/main.dart, so nothing '
            'renders this surface',
          );
          continue;
        }
        if (!RegExp(c.reads).hasMatch(code[c.file] ?? '')) {
          problems.add(
            '$what: ${c.file} no longer contains `${c.reads}` outside '
            'comments — it has stopped rendering this surface',
          );
        }
        final construction = RegExp('\\b${c.widget}(?:\\.\\w+)?\\(');
        final mountedBy = [
          for (final MapEntry(key: file, value: text) in code.entries)
            if (file != c.file &&
                graph.reached.contains(file) &&
                construction.hasMatch(text))
              file,
        ];
        if (mountedBy.isEmpty) {
          problems.add(
            '$what: no loaded file constructs ${c.widget} — the widget '
            'exists, and is mounted nowhere',
          );
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('no other file reads a surface', () {
      final consumers = {for (final c in _consumers.values) c.file};
      final strays = [
        for (final MapEntry(key: file, value: text) in code.entries)
          if (!consumers.contains(file) &&
              !_surfaceDefinitions.contains(file) &&
              _readsASurface.hasMatch(text))
            '$file${graph.reached.contains(file) ? '' : ' (not loaded from '
                      'lib/main.dart)'}',
      ];
      expect(
        strays,
        isEmpty,
        reason:
            'These files read an action surface but are not the registered '
            'consumer of one. A loaded one is a new surface — register it in '
            '_consumers. An unloaded one renders nothing, and every action '
            'that declares its surface is credited with a reachability it '
            'does not have — delete it:\n${strays.join('\n')}',
      );
    });
  });

  test('the guard is not vacuous', () {
    // If the enum or the descriptor table moved, every check above would pass
    // trivially.
    expect(ShortcutAction.values.length, greaterThan(10));
    expect(
      ShortcutAction.values.where(
        (a) => descriptorFor(a).surfaces.isNotEmpty,
      ),
      isNotEmpty,
      reason: 'no action has any surface — the descriptor table is not loading',
    );
  });
}

/// The widget rendering one [ActionSurface].
class _SurfaceConsumer {
  const _SurfaceConsumer({
    required this.file,
    required this.widget,
    required this.reads,
  });

  /// The file declaring [widget], relative to the package root.
  final String file;

  /// The widget class another loaded file must construct.
  final String widget;

  /// A pattern the file's code (comments stripped) must contain to be
  /// rendering the surface rather than merely mentioning it.
  final String reads;
}
