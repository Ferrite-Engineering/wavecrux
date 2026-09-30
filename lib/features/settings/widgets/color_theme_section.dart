// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crux_settings_ui/crux_settings_ui.dart' show CruxPolicyLockNote;
import 'package:crux_theme/crux_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/theme/theme_pack_directory.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_appearance_strings.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/policy/org_theme_application.dart';

/// Resolves the directory used by [ThemePackBrowser] for installed
/// `.crux-theme.json` packs.
typedef PackDirectoryResolver = Future<Directory> Function();

/// Settings → Appearance: drops `crux_theme`'s [ThemeAppearanceSection]
/// composer in place, wired with the WaveCrux-localized
/// [WaveCruxThemeAppearanceStrings] adapter and `file_picker`-backed
/// pack import / export callbacks.
///
/// All of the actual UI — preset grid, per-token color editor,
/// `.crux-theme.json` pack import / export / activate / uninstall — is
/// authored in [`crux_theme`](https://github.com/Ferrite-Engineering/crux-shared).
/// Activation flows through `cruxColorThemeProvider`, whose
/// WaveCrux-flavored notifier (see
/// `wavecrux_color_theme_bootstrap.dart`) writes preset and override
/// changes back to [AppSettings] so the choice survives a restart.
///
/// The constructor still takes [settings] so existing call sites in
/// [SettingsScreen] continue to compose without changes; the value is
/// only used to surface the settings shape, not consumed directly.
///
/// Tests may pass [packDirectoryResolver], [pickPackDocument], and
/// [savePackDocument] to inject deterministic file-system seams
/// without touching `path_provider` or the desktop file-picker dialogs.
class ColorThemeSection extends ConsumerStatefulWidget {
  /// Creates the Settings → Appearance section.
  const ColorThemeSection({
    required this.settings,
    this.packDirectoryResolver,
    this.pickPackDocument,
    this.savePackDocument,
    super.key,
  });

  /// Active settings snapshot; preserved so existing call sites continue
  /// to construct the widget without API breakage. Theme reads now flow
  /// through `cruxColorThemeProvider` which derives from
  /// `appSettingsProvider` internally.
  final AppSettings settings;

  /// Optional override for the `.crux-theme.json` install directory.
  /// Defaults to `{appSupportDir}/themes` (created on demand).
  final PackDirectoryResolver? packDirectoryResolver;

  /// Optional override for the import file picker. Defaults to a
  /// desktop `file_picker` invocation accepting `.json` files, whose
  /// contents are read and handed to the browser as document text.
  final PickPackDocument? pickPackDocument;

  /// Optional override for the export destination picker. Defaults to a
  /// `file_picker` save dialog suggesting a `.crux-theme.json` name;
  /// receives the encoded document and returns the path it wrote to.
  final SavePackDocument? savePackDocument;

  @override
  ConsumerState<ColorThemeSection> createState() => _ColorThemeSectionState();
}

class _ColorThemeSectionState extends ConsumerState<ColorThemeSection> {
  Directory? _packDirectory;

  @override
  void initState() {
    super.initState();
    unawaited(_resolvePackDirectory());
  }

  Future<void> _resolvePackDirectory() async {
    // The same directory bootstrap restores the active pack from.
    final resolver = widget.packDirectoryResolver ?? wavecruxThemePackDirectory;
    try {
      final dir = await resolver();
      if (!mounted) return;
      setState(() => _packDirectory = dir);
    } on Object {
      // Production environments always resolve. In tests where
      // `path_provider` is unregistered the fallback in
      // [wavecruxThemePackDirectory] returns systemTemp; if even that throws
      // we still want a renderable section, so use systemTemp directly.
      if (!mounted) return;
      setState(() => _packDirectory = Directory.systemTemp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final dir = _packDirectory;
    if (dir == null) {
      // Static placeholder while the directory resolves — a
      // CircularProgressIndicator would prevent pumpAndSettle in widget
      // tests from ever finishing because indicators animate forever.
      return const SizedBox(height: 24);
    }
    final theme = Theme.of(context);
    final strings = WaveCruxThemeAppearanceStrings(l10n);
    final categories = ThemeRegistry.instance.registeredCategories;

    // This composes the `crux_theme` color-theme widgets directly rather
    // than dropping in `ThemeAppearanceSection`. The composer renders its
    // own `headlineSmall` "Appearance" heading, which collided with the
    // Settings screen's own "Appearance" section header (two "Appearance"
    // titles stacked). Composing the three surfaces ourselves lets the
    // Settings section header be the single title, with these as labelled
    // subsections beneath it.
    //
    // Visual language: the Settings screen distinguishes *section grouping*
    // cards (quiet `surfaceContainerLow`) from *data / value* surfaces
    // (`surfaceContainerHighest` — the same fill the app uses for text
    // inputs). Preset cards, token-override swatches, and theme-pack rows
    // are data the user picks or edits, so we pin every `Card` in this
    // subtree to the value tone. That keeps "what is a section vs. what is
    // content" legible: section = low tone, no nested boxes; data =
    // highest tone, discrete bordered boxes.
    final dataSurface = theme.copyWith(
      cardTheme: theme.cardTheme.copyWith(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
    );

    // A theme the organization locked stays visible — an engineer has to be
    // able to see what was chosen — but nothing below the note can change it.
    final locked = ref.watch(orgThemeLockedProvider);

    final pickers = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubsectionLabel(strings.presetSectionHeading),
        const SizedBox(height: 8),
        PresetPicker(
          presets: builtinPresets().values.toList(),
          strings: strings,
          previewTokens: const [
            ('canvas', 'background'),
            ('canvas', 'cursor.primary'),
            ('canvas', 'signal.x.fill'),
            ('canvas', 'signal.z.line'),
          ],
        ),
        const SizedBox(height: 20),
        _SubsectionLabel(strings.tokenOverridesSectionHeading),
        const SizedBox(height: 8),
        for (final category in categories)
          TokenCategorySection(category: category, strings: strings),
        const SizedBox(height: 20),
        _SubsectionLabel(strings.themePackBrowserSectionHeading),
        const SizedBox(height: 8),
        ThemePackBrowser(
          store: DirectoryThemePackStore(directory: dir),
          pickPackDocument: widget.pickPackDocument ?? _defaultPickPackDocument,
          savePackDocument: widget.savePackDocument ?? _defaultSavePackDocument,
          strings: strings,
        ),
      ],
    );

    return Theme(
      data: dataSurface,
      child: Padding(
        // Aligns with the 16 dp ListTile inset of the surrounding Appearance
        // card so the subsection labels line up with the rows above them.
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: locked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CruxPolicyLockNote(
                    message: l10n.appearanceThemeLockedByPolicy,
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: 0.6,
                    child: IgnorePointer(child: ExcludeFocus(child: pickers)),
                  ),
                ],
              )
            : pickers,
      ),
    );
  }

  static Future<String?> _defaultPickPackDocument() async {
    // pickFile, not pickFiles: importing a theme pack is single-target, and
    // `pickFiles` is the multiple-selection API — `allowMultiple` defaults to
    // true there and is deprecated in favour of this one. Asking it for one
    // file and then reading `.single` threw on a two-file selection, in an
    // async callback where nothing surfaced it, so Import silently did nothing.
    final file = await FilePicker.pickFile(
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    final path = file?.path;
    if (path == null) return null;
    return await File(path).readAsString();
  }

  static Future<String?> _defaultSavePackDocument(String document) async {
    // `ThemePackBrowser` hands us the already-encoded document, so
    // file_picker 12's write-on-save behaviour does the whole job in one
    // call — no second write through ThemePackService.
    final path = await FilePicker.saveFile(
      bytes: Uint8List.fromList(utf8.encode(document)),
      fileName: 'wavecrux-theme.crux-theme.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    return path;
  }
}

/// Label for a subsection *inside* the Settings → Appearance section
/// (Presets / Color overrides / Theme packs). Deliberately lighter than the
/// Settings screen's icon-led section headers so the hierarchy reads
/// section → subsection → data, not two competing section titles.
class _SubsectionLabel extends StatelessWidget {
  const _SubsectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
