// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
// The package exports its own resolveShortcutConflicts; hide it so WaveCrux's
// wrapper (shortcut_conflicts.dart, which injects defaultBindings + action
// order) is the one in scope.
import 'package:crux_keybindings/crux_keybindings.dart'
    hide resolveShortcutConflicts;
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/keymap_presets.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:wavecrux/core/shortcuts/shortcut_conflicts.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Settings → Keyboard Shortcuts detail content: the editable, per-category
/// shortcut list with key capture, conflict detection, unbind, reset (one /
/// all), and `.crux-keymap` Import / Export.
///
/// Thin WaveCrux wrapper over the cross-suite `KeyBindingsEditor`: it supplies
/// WaveCrux's actions, defaults, resolved conflicts,
/// `MobileMetrics`-derived sizing, localized strings, and the file-I/O for
/// Import / Export; the package widget owns the rendering and capture UX.
class ShortcutsSettingsSection extends ConsumerStatefulWidget {
  /// Creates the section. The two pick callbacks are injectable so widget tests
  /// can drive Export / Import without the platform file-picker plugin.
  const ShortcutsSettingsSection({
    this.pickExportLocation,
    this.pickImportFile,
    super.key,
  });

  /// Chooses a destination file for Export. Defaults to a `saveFile` picker.
  final Future<File?> Function()? pickExportLocation;

  /// Chooses a `.crux-keymap` file for Import. Defaults to an open picker.
  final Future<File?> Function()? pickImportFile;

  @override
  ConsumerState<ShortcutsSettingsSection> createState() =>
      _ShortcutsSettingsSectionState();
}

class _ShortcutsSettingsSectionState
    extends ConsumerState<ShortcutsSettingsSection> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    final isPhone =
        deviceClass == DeviceClass.phone ||
        deviceClass == DeviceClass.phoneLandscape;
    final notifier = ref.read(shortcutBindingsProvider.notifier);

    // Feed WaveCrux's MobileMetrics into the package widgets' sizing seam.
    final mm = MobileMetrics.of(context, deviceClass);

    // Resolve precedence once: the editor's asymmetric per-row warnings and
    // summary banner are driven by the same pass that decides which action
    // actually fires (ShortcutManagerWidget), so the UI can never disagree with
    // runtime behavior.
    final resolution = resolveShortcutConflicts(bindings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetSelector(
          active: presetForBindings(bindings),
          onSelect: (preset) => notifier.applyPreset(bindingsForPreset(preset)),
        ),
        KeyBindingsEditor<ShortcutAction>(
          actions: ShortcutAction.values,
          categoryOf: (a) => a.category,
          categoryLabelOf: (c) => c.label(l10n),
          labelOf: (a) => a.label(l10n),
          bindings: bindings,
          defaults: defaultBindings(),
          conflicts: const {},
          conflictDetails: resolution.conflicts,
          conflictMessages: _WaveCruxConflictMessages(l10n),
          metrics: KeyBindingEditorMetrics(
            touchTarget: mm.touchTarget,
            iconSize: mm.iconSize,
            bodyFontSize: mm.bodyText,
            labelFontSize: mm.labelText,
            monoFontSize: mm.monoText,
          ),
          strings: _WaveCruxKeyBindingsStrings(l10n),
          accessibilityStrings: _WaveCruxKeyBindingsAccessibilityStrings(l10n),
          onCapture: (action, binding) =>
              notifier.setBinding(action, binding.materialize()),
          onUnbind: notifier.unbind,
          onReset: notifier.reset,
          onResetAll: notifier.resetAll,
          onImport: _import,
          onExport: _export,
          // `crux_keybindings` no longer depends on `crux_settings_ui` (that
          // inverted layering edge was removed), so the grouped-card surface
          // is supplied by the host. WaveCrux uses the same `CruxSettingsCard`
          // every other Settings section uses, so the shortcut list keeps its
          // existing look.
          categoryCardBuilder: (context, rows) =>
              CruxSettingsCard(children: rows),
          showPhoneNote: isPhone,
        ),
      ],
    );
  }

  Future<void> _export() async {
    final l10n = L10N.of(context);
    final diffs = ref.read(shortcutBindingsProvider.notifier).currentDiffs();
    final content = waveCruxKeymapCodec.encodeToString(diffs);
    // In the browser the keymap downloads; there is no save dialog that
    // returns a path to write to.
    final download = ref.read(browserDownloadProvider);
    try {
      if (download != null) {
        await download(
          fileName: 'wavecrux.crux-keymap.json',
          bytes: utf8.encode(content),
        );
      } else {
        final file =
            await (widget.pickExportLocation ?? _defaultPickExportLocation)();
        if (file == null) return;
        await file.writeAsString(content);
      }
      if (!mounted) return;
      showCruxInfoSnack(context, l10n.settingsShortcutExportSuccess);
    } on Object catch (error) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.settingsShortcutExportFailure('$error'));
    }
  }

  Future<void> _import() async {
    final l10n = L10N.of(context);
    final notifier = ref.read(shortcutBindingsProvider.notifier);
    try {
      final file = await (widget.pickImportFile ?? _defaultPickImportFile)();
      if (file == null) return;
      final content = await file.readAsString();
      final diffs = waveCruxKeymapCodec.decodeString(content);
      if (diffs.isEmpty) {
        if (mounted) {
          showCruxInfoSnack(context, l10n.settingsShortcutImportEmpty);
        }
        return;
      }
      notifier.importDiffs(diffs);
      if (!mounted) return;
      showCruxInfoSnack(
        context,
        l10n.settingsShortcutImportSuccess(diffs.length),
      );
      // A keymap written by a newer WaveCrux is a different problem from a
      // corrupt one — the file is fine, this build is behind — so it gets its
      // own message instead of dumping the raw exception text at the user.
      // `KeymapSchemaVersionException` extends `FormatException`, so it must
      // be caught before the general handler below.
    } on KeymapSchemaVersionException {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.settingsShortcutImportVersionFailure);
    } on Object catch (error) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.settingsShortcutImportFailure('$error'));
    }
  }

  static Future<File?> _defaultPickExportLocation() async {
    final path = await FilePicker.saveFile(
      // file_picker 12 requires bytes & writes the file; pass empty so it
      // only returns the chosen path and we write via our own service below.
      bytes: Uint8List(0),
      fileName: 'wavecrux.crux-keymap.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    return path == null ? null : File(path);
  }

  static Future<File?> _defaultPickImportFile() async {
    // pickFile, not pickFiles: importing a keymap is single-target, and
    // `pickFiles` is the multiple-selection API — `allowMultiple` defaults to
    // true there and is deprecated in favour of this one. Asking it for one
    // file and then reading `.single` threw on a two-file selection, in an
    // async callback where nothing surfaced it, so Import silently did nothing.
    final file = await FilePicker.pickFile(
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    final path = file?.path;
    return path == null ? null : File(path);
  }
}

/// The keymap-preset chooser shown above the editable shortcut list. Selecting
/// a preset replaces all bindings; once the user hand-edits a row the active
/// preset reads as "Custom" (the `null` case, surfaced via the dropdown `hint`
/// so the user can land on it by editing but can never select it directly).
class _PresetSelector extends StatelessWidget {
  const _PresetSelector({required this.active, required this.onSelect});

  /// The preset the current bindings exactly match, or `null` for "Custom".
  final KeymapPreset? active;

  /// Invoked with the chosen preset (never called for the "Custom" item).
  final void Function(KeymapPreset preset) onSelect;

  String _label(KeymapPreset preset, L10N l10n) => switch (preset) {
    KeymapPreset.waveCrux => l10n.settingsShortcutsPresetWaveCrux,
    KeymapPreset.gtkwave => l10n.settingsShortcutsPresetGtkwave,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return ListTile(
      title: Text(l10n.settingsShortcutsPresetLabel),
      subtitle: Text(l10n.settingsShortcutsPresetDescription),
      // `active == null` ("Custom") has no item — it is surfaced via [hint], so
      // the user can never *select* Custom, only land on it by hand-editing.
      trailing: DropdownButton<KeymapPreset>(
        value: active,
        hint: Text(l10n.settingsShortcutsPresetCustom),
        onChanged: (preset) {
          if (preset != null) onSelect(preset);
        },
        items: [
          for (final preset in KeymapPreset.values)
            DropdownMenuItem<KeymapPreset>(
              value: preset,
              child: Text(_label(preset, l10n)),
            ),
        ],
      ),
    );
  }
}

/// Adapts WaveCrux's [L10N] to the package's [KeyBindingsEditorStrings].
class _WaveCruxKeyBindingsStrings implements KeyBindingsEditorStrings {
  const _WaveCruxKeyBindingsStrings(this._l10n);

  final L10N _l10n;

  @override
  String get description => _l10n.settingsShortcutsDescription;
  @override
  String get phoneNote => _l10n.settingsShortcutsPhoneNote;
  @override
  String get importLabel => _l10n.settingsShortcutsImport;
  @override
  String get exportLabel => _l10n.settingsShortcutsExport;
  @override
  String get resetAllLabel => _l10n.settingsShortcutsResetAll;
  @override
  String get notBound => _l10n.settingsShortcutNotBound;
  @override
  String get editTooltip => _l10n.settingsShortcutEditTooltip;
  @override
  String get unbindTooltip => _l10n.settingsShortcutUnbindTooltip;
  @override
  String get resetTooltip => _l10n.settingsShortcutResetTooltip;
  @override
  String get capturePrompt => _l10n.settingsShortcutCapturePrompt;
  @override
  String conflict(String actions) => _l10n.settingsShortcutConflict(actions);
  @override
  String get resetAllTitle => _l10n.settingsShortcutResetAllTitle;
  @override
  String get resetAllBody => _l10n.settingsShortcutResetAllBody;
  @override
  String get resetAllCancel => _l10n.settingsShortcutResetAllCancel;
}

/// Adapts WaveCrux's [L10N] to the package's keyboard hint and the spoken
/// form of an unbound row.
class _WaveCruxKeyBindingsAccessibilityStrings
    implements KeyBindingsAccessibilityStrings {
  const _WaveCruxKeyBindingsAccessibilityStrings(this._l10n);

  final L10N _l10n;

  @override
  String get keyboardHint => _l10n.settingsShortcutsKeyboardHint;
  @override
  String get notBoundSpoken => _l10n.settingsShortcutNotBoundSpoken;
}

/// Adapts WaveCrux's [L10N] onto the package's asymmetric-conflict message
/// builders (the winning row, a shadowed row, and the summary banner).
class _WaveCruxConflictMessages implements KeyBindingsConflictMessages {
  const _WaveCruxConflictMessages(this._l10n);

  final L10N _l10n;

  @override
  String wins(String others) => _l10n.settingsShortcutConflictWins(others);

  @override
  String shadowedBy(String winner) =>
      _l10n.settingsShortcutConflictShadowed(winner);

  @override
  String summary(int count) => _l10n.settingsShortcutConflictSummary(count);
}
