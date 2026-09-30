// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:logging/logging.dart';
import 'package:wavecrux/core/theme/theme_pack_directory.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';

/// A theme pack the user chose and did not get. `developer.log` emits nothing
/// from a release build, so this goes to the product log.
final _log = Logger('wavecrux.theme');

/// Riverpod override that wires WaveCrux persistence into `crux_theme`'s
/// `cruxColorThemeProvider`.
///
/// The shipped `CruxColorThemeNotifier` builds from a static `initial:`
/// theme and exposes in-memory `activate` / `applyOverrides` / `reset`
/// mutators. WaveCrux's UX persists the active preset name and any
/// quick-override tokens in [appSettingsProvider], so we replace the
/// default notifier with one that:
///
/// 1. Derives `build()` from settings — preset lookup by
///    `activeThemeName`, with `themeOverrides` layered on via
///    `CruxColorTheme.mergeTokens`.
/// 2. Overrides [activate] so that the crux_theme widgets'
///    preset-switch flow (`PresetCard` taps, `ThemePackBrowser`
///    activate / token-reset) writes the resulting state back to
///    [appSettingsProvider] — preserving the WaveCrux convention that
///    the on-disk settings store is the source of truth for theme
///    selection.
/// 3. Overrides [applyOverrides] so that the crux_theme widgets'
///    token-edit flow (`TokenEditor` color picks) appends to
///    `settings.themeOverrides` in `#RRGGBBAA` form.
///
/// Persistence write-through reuses the existing
/// `setActiveThemeName` / `setThemeOverrides` notifier methods.
/// `_persistDerivedFromTheme` reconciles the active in-memory theme
/// against the matching built-in preset baseline so a token reset (via
/// `TokenEditor`, which calls `activate(current.copyWith(...))`)
/// drops the override entry rather than re-applying it on the next
/// `build()`.
///
/// Use [wavecruxCruxColorThemeOverride] from `bootstrap()` so the
/// override is applied before any consumer reads `cruxColorThemeProvider`.
class WaveCruxCruxColorThemeNotifier extends CruxColorThemeNotifier {
  /// Creates a notifier seeded with the WaveCrux Dark preset so reads
  /// that race the first settings hydration still observe a sensible
  /// theme.
  WaveCruxCruxColorThemeNotifier() : super(initial: defaultBuiltinPreset());

  /// The theme pack in force when the active theme is not a built-in preset —
  /// one activated from Settings ▸ Appearance ▸ Theme packs, or the
  /// organization's.
  ///
  /// Settings persist only the active theme's id, and [build] re-runs on every
  /// settings change, the activation's own write included. A pack's tokens are
  /// nowhere in settings, so without this the rebuild after activating a pack
  /// found no preset with its id and fell back to the seed preset.
  CruxColorTheme? _packTheme;

  @override
  CruxColorTheme build() {
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return _packTheme ?? initial;
    // `builtinPresetById` applies the legacy id alias map, so a beta user
    // whose settings still carry `wavecrux-dark` / `wavecrux-light` keeps the
    // theme they chose instead of silently reverting to the seed preset.
    final id = settings.activeThemeName;
    final pack = _packTheme;
    final base =
        builtinPresetById(id) ?? (pack?.id == id ? pack : null) ?? initial;
    if (settings.themeOverrides.isEmpty) return base;
    final parsed = _parseOverrides(settings.themeOverrides);
    if (parsed.isEmpty) return base;
    return base.mergeTokens(parsed);
  }

  @override
  void activate(CruxColorTheme theme) {
    if (builtinPresetById(theme.id) == null) _packTheme = theme;
    super.activate(theme);
    _persistDerivedFromTheme(theme);
  }

  /// Puts back the theme pack [theme] that settings name as active, at
  /// startup, before the first frame.
  ///
  /// Settings already hold its id, so nothing is written.
  void restorePack(CruxColorTheme theme) {
    _packTheme = theme;
    super.activate(theme);
  }

  @override
  void applyOverrides(Map<String, Color> overrides) {
    if (overrides.isEmpty) return;
    super.applyOverrides(overrides);
    // A pack's edited tokens are its new baseline for this session: no
    // override is derived against a pack (see _persistDerivedFromTheme).
    if (_packTheme?.id == state.id) _packTheme = state;
    _persistDerivedFromTheme(state);
  }

  /// Applies [theme] for this session only — never persisted to
  /// [AppSettings], and never touches [_persistDerivedFromTheme].
  ///
  /// The editor-host theme bridge calls this, not [activate]:
  /// when a VSCode extension host is driving this build, the active theme
  /// is a live synthesis of the host's own color theme
  /// (`synthesizeEditorHostTheme`), not a user preset choice. Persisting it
  /// would (a) overwrite the user's actual preset/override selection on
  /// disk with a value that only makes sense while this session is
  /// embedded in that one VSCode window, and (b) fail
  /// `_persistDerivedFromTheme`'s preset-diff bookkeeping outright, since
  /// `builtinPresetById(kEditorHostThemeId)` is `null` by design. Calling
  /// straight through to the base [CruxColorThemeNotifier.activate] (which
  /// only sets `state`) is what keeps the rendering path identical to
  /// every other theme source — nothing downstream of `state` can tell an
  /// ephemeral theme from a persisted one.
  void applyEphemeral(CruxColorTheme theme) {
    super.activate(theme);
  }

  /// Recomputes WaveCrux's persisted theme state ([AppSettings.activeThemeName]
  /// and [AppSettings.themeOverrides]) from [theme]. Overrides are the
  /// diff between [theme.tokens] and the matching built-in preset's
  /// defaults. When the active preset id is not a built-in (e.g. an
  /// imported `.crux-theme.json` pack), no overrides are derived — the
  /// pack's tokens are the baseline. The product-local
  /// `canvas.signal.palette` list-valued override is preserved
  /// untouched.
  void _persistDerivedFromTheme(CruxColorTheme theme) {
    final baseline = builtinPresetById(theme.id);

    final overrides = <String, String>{};
    if (baseline != null) {
      for (final categoryEntry in theme.tokens.entries) {
        final baselineCategory =
            baseline.tokens[categoryEntry.key] ?? const <String, Color>{};
        for (final tokenEntry in categoryEntry.value.entries) {
          final baselineValue = baselineCategory[tokenEntry.key];
          if (baselineValue == null ||
              baselineValue.toARGB32() != tokenEntry.value.toARGB32()) {
            final dotted = CruxColorTheme.dottedId(
              categoryEntry.key,
              tokenEntry.key,
            );
            overrides[dotted] = ThemePackCodec.encodeColor(tokenEntry.value);
          }
        }
      }
    }

    final settingsNow = ref.read(appSettingsProvider).value;
    final paletteOverride =
        settingsNow?.themeOverrides['canvas.signal.palette'];
    if (paletteOverride != null) {
      overrides['canvas.signal.palette'] = paletteOverride;
    }

    final notifier = ref.read(appSettingsProvider.notifier);
    // Fire-and-forget: the in-memory state already reflects the new
    // theme; the on-disk write is best-effort and any error surfaces
    // via the SettingsService.
    unawaited(notifier.setActiveThemeName(theme.id));
    unawaited(notifier.setThemeOverrides(overrides));
  }

  static Map<String, Color> _parseOverrides(Map<String, String> raw) {
    final out = <String, Color>{};
    for (final entry in raw.entries) {
      // The signal palette is a list-valued token; `crux_theme` stores
      // scalar colors only, so palette state stays product-local and is
      // skipped here. See the crux_theme README.
      if (entry.key == 'canvas.signal.palette') continue;
      final color = ThemePackCodec.tryParseColor(entry.value);
      if (color != null) out[entry.key] = color;
    }
    return out;
  }
}

/// Re-activates the installed theme pack the saved settings name as active.
///
/// A built-in preset needs nothing: the theme notifier resolves it from
/// settings. A pack's tokens live in its file, so it is loaded here, at
/// bootstrap and before the first frame, instead of the app opening on the
/// default theme. A pack that has since been uninstalled or will not parse is
/// logged and leaves the default theme in place.
///
/// Does nothing on the web, which has no pack directory.
Future<void> restoreActiveThemePack(
  ProviderContainer container, {
  Future<ThemePackStore> Function()? storeResolver,
}) async {
  if (kIsWeb) return;
  final String id;
  try {
    id = (await container.read(appSettingsProvider.future)).activeThemeName;
  } on Object {
    return;
  }
  if (builtinPresetById(id) != null) return;

  final notifier = container.read(cruxColorThemeProvider.notifier);
  if (notifier is! WaveCruxCruxColorThemeNotifier) return;
  try {
    final store = await (storeResolver ?? _directoryThemePackStore)();
    final pack = await store.loadPack(id);
    notifier.restorePack(pack.toTheme());
  } on Object catch (error) {
    _log.warning('active theme pack "$id" not restored: $error');
  }
}

Future<ThemePackStore> _directoryThemePackStore() async =>
    DirectoryThemePackStore(directory: await wavecruxThemePackDirectory());

/// Convenience: the single override every WaveCrux bootstrap should
/// spread into its [ProviderScope] before `runApp`.
final Override wavecruxCruxColorThemeOverride = cruxColorThemeProvider
    .overrideWith(WaveCruxCruxColorThemeNotifier.new);
