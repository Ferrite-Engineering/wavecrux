// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/core/platform_utils.dart';
import 'package:wavecrux/core/policy/org_server_policy.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/settings/providers/extra_settings_categories_provider.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/widgets/ai_settings_section.dart';
import 'package:wavecrux/features/settings/widgets/color_theme_section.dart';
import 'package:wavecrux/features/settings/widgets/custom_translators_panel.dart';
import 'package:wavecrux/features/settings/widgets/decoder_plugins_panel.dart';
import 'package:wavecrux/features/settings/widgets/isa_tables_panel.dart';
import 'package:wavecrux/features/settings/widgets/settings_editors_section.dart';
import 'package:wavecrux/features/settings/widgets/shortcuts/shortcuts_settings_section.dart';
import 'package:wavecrux/features/stage/settings/custom_widgets_panel.dart';
import 'package:wavecrux/features/workspace/commands/reset_workspace_command.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/shared/widgets/help_link.dart';

/// Application settings screen (mobile/full-screen route).
///
/// On desktop platforms call [SettingsScreen.openAdaptive] instead — it
/// presents the same content inside a modal dialog.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Opens settings in a dialog on desktop or as a pushed route on mobile,
  /// via the suite-shared shell (`crux_settings_ui`).
  static Future<void> openAdaptive(BuildContext context) {
    final l10n = L10N.of(context);
    return openCruxSettings(
      context,
      title: l10n.settingsTitle,
      closeTooltip: isDesktopPlatform ? l10n.dialogClose : l10n.settingsClose,
      asDialog: isDesktopPlatform,
      bodyBuilder: (_) => const _SettingsContent(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return CruxSettingsRouteShell(
      title: l10n.settingsTitle,
      closeTooltip: l10n.settingsClose,
      body: const _SettingsContent(),
    );
  }
}

// ── Settings body (shared master-detail shell) ────────────────────────────────

/// Builds the WaveCrux category list and hands it to the shared
/// [CruxSettingsMasterDetail] shell (from `package:crux_settings_ui`). The
/// dialog / route chrome is the suite-shared shell (crux_settings_ui); the
/// per-category content widgets live below.
class _SettingsContent extends ConsumerWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    // Open-core categories, followed by any overlay-contributed categories
    // (e.g. the Pro Collaboration category) via the open-core seam. Builders
    // receive `context` so they can localize their own titles.
    final extras = ref
        .watch(extraSettingsCategoriesProvider)
        .map((extra) => extra.toCategory(context))
        .toList();
    // The AI Assistant section is offered only on a build with the
    // `kAiExperimental` flag on (it hosts the opt-in toggle). A normal beta
    // build shows no AI section at all. See `aiExperimentalEnabledProvider`.
    final showAiSection = ref.watch(aiExperimentalBuildFlagProvider);
    // Privacy holds the telemetry toggle and nothing else, so it is offered
    // only on a build whose pipeline can actually transmit. During the beta
    // with no dev flag the Settings screen is exactly what it was before
    // telemetry existed — a dark launch, extended to the UI.
    final showPrivacySection = ref.watch(telemetryConsentUiVisibleProvider);
    return CruxSettingsMasterDetail(
      categories: [
        ..._categories(
          l10n,
          settings,
          showAiSection: showAiSection,
          showPrivacySection: showPrivacySection,
        ),
        ...extras,
      ],
    );
  }

  List<CruxSettingsCategory> _categories(
    L10N l10n,
    AppSettings settings, {
    required bool showAiSection,
    required bool showPrivacySection,
  }) {
    return [
      // Suite-canonical order: General leads (the natural landing category;
      // three of four apps already did), then Appearance.
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.general,
        icon: Icons.tune,
        title: l10n.settingsGeneralSection,
        content: _GeneralSection(settings: settings),
      ),
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.appearance,
        icon: Icons.palette_outlined,
        title: l10n.settingsAppearanceSection,
        content: _AppearanceSection(settings: settings),
      ),
      // Privacy sits third — as high as the suite-canonical "General leads,
      // then Appearance" order allows. It holds the telemetry opt-out, and
      // the whole argument for default-on telemetry is that the off switch is
      // not buried; a section
      // the user has to scroll a rail to find is buried. Offered only when
      // this build can transmit at all.
      //
      // The section itself is `crux_telemetry`'s, so all four products' opt-out
      // is one implementation; only the category placement and the localized
      // heading are WaveCrux's.
      if (showPrivacySection)
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.privacy,
          icon: Icons.privacy_tip_outlined,
          title: l10n.settingsPrivacySection,
          content: const TelemetrySettingsSection(),
        ),
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.productDefaults,
        icon: Icons.show_chart,
        title: l10n.settingsWaveformDefaultsSection,
        content: _WaveformDefaultsSection(settings: settings),
      ),
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.fileHandling,
        icon: Icons.folder_outlined,
        title: l10n.settingsFileHandlingSection,
        content: _FileHandlingSection(settings: settings),
      ),
      // Orientation is mobile-only — desktop has no device orientation to lock.
      if (!isDesktopPlatform)
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.orientation,
          icon: Icons.screen_rotation_outlined,
          title: l10n.settingsOrientationSection,
          content: _OrientationSection(settings: settings),
        ),
      // Dedicated Editors section, present in every Crux app —
      // editor config is cross-feature, not CXP-specific, so it sits with the
      // general-purpose sections rather than inside CXP.
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.editors,
        icon: Icons.edit_outlined,
        title: l10n.settingsEditorsSection,
        content: SettingsEditorsSection(settings: settings),
      ),
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.remoteControl,
        icon: Icons.wifi_tethering,
        title: l10n.settingsRemoteControlSection,
        content: _RemoteControlSection(settings: settings),
      ),
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.cxp,
        icon: Icons.hub_outlined,
        title: l10n.settingsCxpSectionTitle,
        content: _CxpControlsBlock(settings: settings),
      ),
      // Extensions — decoder plugins (desktop only: runtime native code
      // loading is a no-op on iOS/Android/Web), custom value translators
      // (pure Dart, every platform), and Stage custom-widget bundles, merged
      // into one category (three single-panel rail entries were rail bloat).
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.extensions,
        icon: Icons.extension_outlined,
        title: l10n.settingsExtensionsSection,
        content: const _ExtensionsSection(),
      ),
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.shortcuts,
        icon: Icons.keyboard_outlined,
        title: l10n.settingsShortcutsSection,
        content: const ShortcutsSettingsSection(),
      ),
      // Experimental AI Waveform Assistant configuration. Only offered when the
      // `kAiExperimental` build flag is on; the section's own toggle then gates
      // the provider/key configuration and every other AI surface.
      if (showAiSection)
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.ai,
          icon: Icons.auto_awesome_outlined,
          title: l10n.settingsAiSection,
          content: const AiSettingsSection(),
        ),
    ];
  }
}

// ── Extensions ────────────────────────────────────────────────────────────────

/// Decoder plugins, custom value translators, and custom Stage widgets in
/// one category — each in its own card under a titleMedium group header
/// (the retired one-panel-per-rail-entry arrangement was rail bloat).
class _ExtensionsSection extends StatelessWidget {
  const _ExtensionsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    Widget header(String title) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: theme.textTheme.titleMedium),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Decoder plugins are desktop only — runtime native code loading is
        // a no-op on iOS, Android, and Web.
        if (isDesktopPlatform) ...[
          header(l10n.settingsDecoderPluginsSection),
          const CruxSettingsCard(children: [DecoderPluginsPanel()]),
          const SizedBox(height: 24),
          // Same desktop-only reasoning: a user table comes off the
          // filesystem, which a browser build does not have.
          const CruxSettingsCard(children: [IsaTablesPanel()]),
          const SizedBox(height: 24),
        ],
        // Custom value translators are pure Dart — available on every
        // platform (desktop, mobile, and web) unlike native decoder plugins.
        header(l10n.customTranslatorsPanelTitle),
        const CruxSettingsCard(children: [CustomTranslatorsPanel()]),
        const SizedBox(height: 24),
        // Stage custom-widget bundle management (.wcrux-widget install +
        // watched directories). The panel reads
        // customWidgetBundleManagerProvider and is tier-gated internally
        // (allowed during the beta period).
        header(l10n.customStageWidgetsPanelTitle),
        const CruxSettingsCard(children: [CustomWidgetsPanel()]),
      ],
    );
  }
}

// ── General ──────────────────────────────────────────────────────────────────

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final notifier = ref.read(appSettingsProvider.notifier);

    return CruxSettingsCard(
      children: [
        SwitchListTile(
          key: const Key('settingsAutoCheckUpdatesSwitch'),
          title: Text(l10n.settingsAutoCheckUpdatesLabel),
          subtitle: Text(l10n.settingsAutoCheckUpdatesDescription),
          value: settings.autoCheckForUpdates,
          onChanged: (v) => notifier.setAutoCheckForUpdates(enabled: v),
        ),
        SwitchListTile(
          key: const Key('settingsRestoreTabsSwitch'),
          title: Text(l10n.settingsRestoreTabsOnLaunchLabel),
          subtitle: Text(l10n.settingsRestoreTabsOnLaunchDescription),
          value: settings.restoreTabsOnLaunch,
          onChanged: (v) =>
              unawaited(notifier.setRestoreTabsOnLaunch(enabled: v)),
        ),
        // Log verbosity — absorbed from the retired single-entry Diagnostics
        // category, as in every Crux app.
        ListTile(
          title: Text(l10n.settingsLogVerbosityLabel),
          subtitle: Text(l10n.settingsLogVerbosityDescription),
          trailing: DropdownButton<LogVerbosity>(
            key: const Key('settingsLogVerbosityDropdown'),
            value: settings.logVerbosity,
            items: LogVerbosity.values
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(_verbosityLabel(v, l10n)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) unawaited(notifier.setLogVerbosity(v));
            },
          ),
        ),
      ],
    );
  }

  String _verbosityLabel(LogVerbosity v, L10N l10n) => switch (v) {
    LogVerbosity.quiet => l10n.logVerbosityQuiet,
    LogVerbosity.normal => l10n.logVerbosityNormal,
    LogVerbosity.detailed => l10n.logVerbosityDetailed,
    LogVerbosity.verbose => l10n.logVerbosityVerbose,
  };
}

// ── Appearance ─────────────────────────────────────────────────────────────────

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final notifier = ref.read(appSettingsProvider.notifier);

    return CruxSettingsCard(
      children: [
        CruxLocaleSettingTile(
          label: l10n.settingsLanguageLabel,
          description: l10n.settingsLanguageDescription,
          locale: settings.locale,
          onChanged: (v) => unawaited(notifier.setLocale(v)),
        ),
        // NOTE: the light/dark/system theme-mode selector that once sat here
        // was removed. Brightness is now chosen by the color-theme preset
        // (the picker below) — picking a light preset switches the whole app
        // to light, a dark preset to dark. The old SegmentedButton wrote a
        // separate AppThemeMode flag that `app.dart` no longer consults, so it
        // was both redundant with the preset picker and inert. See
        // theme_brightness_toggle.dart for the ⌘/Ctrl+Shift+K toggle.
        CruxSettingsSliderTile(
          title: l10n.settingsFontSizeLabel,
          description: l10n.settingsFontSizeDescription,
          min: 8,
          max: 24,
          divisions: 16,
          value: settings.waveformFontSize,
          label: settings.waveformFontSize.toStringAsFixed(0),
          valueText: settings.waveformFontSize.toStringAsFixed(0),
          onChanged: notifier.setWaveformFontSize,
        ),
        SwitchListTile(
          key: const Key('settingsCanvasLegibilityBoostSwitch'),
          title: Text(l10n.settingsCanvasLegibilityBoostLabel),
          subtitle: Text(l10n.settingsCanvasLegibilityBoostDescription),
          value: settings.canvasLegibilityBoost,
          onChanged: (v) =>
              unawaited(notifier.setCanvasLegibilityBoost(enabled: v)),
        ),
        // The color-theme composer lives *inside* the Appearance card so
        // its Presets / Color overrides / Theme packs subsections read as
        // part of this section rather than floating beneath it. The
        // divider the card inserts above it separates the simple display
        // prefs from the theme editor.
        ColorThemeSection(settings: settings),
      ],
    );
  }
}

// ── Waveform Defaults ─────────────────────────────────────────────────────────

class _WaveformDefaultsSection extends ConsumerWidget {
  const _WaveformDefaultsSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final notifier = ref.read(appSettingsProvider.notifier);

    return CruxSettingsCard(
      children: [
        ListTile(
          title: Text(l10n.settingsDefaultFormatLabel),
          subtitle: Text(l10n.settingsDefaultFormatDescription),
          trailing: DropdownButton<DisplayFormat>(
            value: settings.defaultDisplayFormat,
            items: DisplayFormat.values
                .map(
                  (f) => DropdownMenuItem(
                    value: f,
                    child: Text(_formatLabel(f, l10n)),
                  ),
                )
                .toList(),
            onChanged: (f) {
              if (f != null) unawaited(notifier.setDefaultDisplayFormat(f));
            },
          ),
        ),
        CruxSettingsSliderTile(
          title: l10n.settingsDefaultLaneHeightLabel,
          description: l10n.settingsDefaultLaneHeightDescription,
          min: 16,
          max: 80,
          divisions: 16,
          value: settings.defaultLaneHeight.toDouble(),
          label: '${settings.defaultLaneHeight}px',
          valueText: '${settings.defaultLaneHeight}px',
          onChanged: (v) => notifier.setDefaultLaneHeight(v.round()),
        ),
        SwitchListTile(
          title: Text(l10n.settingsWheelNavigatesTimeLabel),
          subtitle: Text(l10n.settingsWheelNavigatesTimeDescription),
          value: settings.wheelNavigatesTime,
          onChanged: (v) => notifier.setWheelNavigatesTime(enabled: v),
        ),
        SwitchListTile(
          key: const Key('settings_signal_tree_natural_sort'),
          title: Text(l10n.settingsSignalTreeSortLabel),
          subtitle: Text(l10n.settingsSignalTreeSortDescription),
          value: settings.signalTreeNaturalSort,
          onChanged: (v) => notifier.setSignalTreeNaturalSort(enabled: v),
        ),
      ],
    );
  }

  String _formatLabel(DisplayFormat f, L10N l10n) => switch (f) {
    DisplayFormat.binary => l10n.displayFormatBinary,
    DisplayFormat.hexadecimal => l10n.displayFormatHexadecimal,
    DisplayFormat.octal => l10n.displayFormatOctal,
    DisplayFormat.unsignedDecimal => l10n.displayFormatUnsignedDecimal,
    DisplayFormat.signedDecimal => l10n.displayFormatSignedDecimal,
    DisplayFormat.ascii => l10n.displayFormatAscii,
    DisplayFormat.ieee754Single => l10n.displayFormatIeee754Single,
    DisplayFormat.ieee754Double => l10n.displayFormatIeee754Double,
    DisplayFormat.fixedPointQ => l10n.displayFormatFixedPointQ,
    DisplayFormat.signedMagnitude => l10n.displayFormatSignedMagnitude,
    DisplayFormat.grayCode => l10n.displayFormatGrayCode,
    DisplayFormat.namedEnum => l10n.displayFormatNamedEnum,
  };
}

// ── Diagnostics ────────────────────────────────────────────────────────────────

// ── File Handling ─────────────────────────────────────────────────────────────

class _FileHandlingSection extends ConsumerWidget {
  const _FileHandlingSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final notifier = ref.read(appSettingsProvider.notifier);

    return CruxSettingsCard(
      children: [
        CruxAutoReloadSettingTile(
          label: l10n.settingsAutoReloadLabel,
          description: l10n.settingsAutoReloadDescription,
          value: settings.autoReloadMode,
          onChanged: notifier.setAutoReloadMode,
          promptLabel: l10n.settingsAutoReloadPrompt,
          autoLabel: l10n.settingsAutoReloadAuto,
          offLabel: l10n.settingsAutoReloadOff,
        ),
        CruxSettingsSliderTile(
          title: l10n.settingsAutoSaveLabel,
          description: l10n.settingsAutoSaveDescription,
          min: 10,
          max: 600,
          divisions: 59,
          value: settings.autoSaveIntervalSeconds.toDouble(),
          label: l10n.settingsAutoSaveSeconds(settings.autoSaveIntervalSeconds),
          valueText: l10n.settingsAutoSaveSeconds(
            settings.autoSaveIntervalSeconds,
          ),
          onChanged: (v) => notifier.setAutoSaveIntervalSeconds(v.round()),
        ),
        CruxSettingsControlTile(
          title: l10n.settingsResetSessionLabel,
          description: l10n.settingsResetSessionDescription,
          control: OutlinedButton(
            key: const Key('settingsResetSessionButton'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            // The shared in-app reset: confirmation dialog → clears the live
            // workspace plus every on-disk artifact (workspace.json, per-tab
            // sidecars, legacy manifest) — the same state the `--reset` CLI flag
            // clears. Reachable on every platform, including mobile where there
            // is no command line.
            onPressed: () => unawaited(
              runResetWorkspaceCommand(context: context, ref: ref),
            ),
            child: Text(l10n.settingsResetSessionButton),
          ),
        ),
      ],
    );
  }
}

// ── Orientation & Display (mobile only) ───────────────────────────────────────

class _OrientationSection extends ConsumerWidget {
  const _OrientationSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final notifier = ref.read(appSettingsProvider.notifier);

    return CruxSettingsCard(
      children: [
        CruxSettingsControlTile(
          title: l10n.settingsOrientationLockLabel,
          description: l10n.settingsOrientationLockDescription,
          control: SegmentedButton<OrientationLockMode>(
            segments: [
              ButtonSegment(
                value: OrientationLockMode.auto,
                label: Text(l10n.settingsOrientationLockAuto),
              ),
              ButtonSegment(
                value: OrientationLockMode.landscapeLock,
                label: Text(l10n.settingsOrientationLockLandscape),
              ),
              ButtonSegment(
                value: OrientationLockMode.portraitLock,
                label: Text(l10n.settingsOrientationLockPortrait),
              ),
              ButtonSegment(
                value: OrientationLockMode.sensor,
                label: Text(l10n.settingsOrientationLockSensor),
              ),
            ],
            selected: {settings.orientationLockMode},
            onSelectionChanged: (s) => notifier.setOrientationLockMode(s.first),
          ),
        ),
      ],
    );
  }
}

// ── Keyboard Shortcuts ────────────────────────────────────────────────────────
// The editable Settings → Keyboard Shortcuts surface lives in its own widget,
// [ShortcutsSettingsSection] (key capture, conflict detection, unbind, reset,
// and .crux-keymap import/export).

// ── Remote Control ────────────────────────────────────────────────────────────

class _RemoteControlSection extends ConsumerStatefulWidget {
  const _RemoteControlSection({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_RemoteControlSection> createState() =>
      _RemoteControlSectionState();
}

class _RemoteControlSectionState extends ConsumerState<_RemoteControlSection> {
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(
      text: widget.settings.remoteControlPort.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _RemoteControlSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The async appSettingsProvider load may resolve after this
    // section has already built once with the default `const AppSettings()`
    // settings. Sync the controller when the inbound settings change, but
    // only when the user is not editing — otherwise an in-flight load
    // mid-edit would overwrite their typing.
    final newPort = widget.settings.remoteControlPort.toString();
    if (_portController.text != newPort &&
        oldWidget.settings.remoteControlPort !=
            widget.settings.remoteControlPort) {
      _portController.text = newPort;
    }
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final remoteState = ref.watch(remoteControlProvider);
    final settings = widget.settings;
    // Whether this seat may run the server at all, and who decided. A locked
    // org value outranks the switch below; see `org_server_policy.dart`.
    final wcpAllowed = resolveWcpServerPolicy(
      ref.watch(cruxPolicyProvider).document,
      userSetting: settings.remoteControlEnabled,
    );
    final wcpLocked = wcpAllowed.source == PolicySource.policyLocked;

    return CruxSettingsCard(
      children: [
        SwitchListTile(
          title: Row(
            children: [
              // Flexible so the label shrinks (and ellipsises) before the
              // help-icon trailing the row gets pushed off-screen on
              // narrow viewports (e.g. SettingsScreen.openAdaptive at
              // 500×500 — Issue 9).
              Flexible(
                child: Text(
                  l10n.settingsRemoteControlEnabledLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              HelpLink(
                url: HelpUrls.remoteApi,
                tooltip: l10n.helpLinkRemoteApi,
              ),
            ],
          ),
          subtitle: Text(l10n.settingsRemoteControlEnabledDescription),
          value: wcpAllowed.value,
          // A locked org policy decides this, and the switch stops deciding
          // anything. Null disables it — and the note below says why, because
          // a dead switch with no reason given is a support ticket.
          onChanged: wcpLocked
              ? null
              : (enabled) async {
                  await settingsNotifier.setRemoteControlEnabled(
                    enabled: enabled,
                  );
                  // The WcpLifecycleBridge listens for the settings change and
                  // starts / stops the server automatically; no direct call
                  // needed here. Starting it from this callback as well would
                  // double-start (startServer stops-then-rebinds) and race the
                  // bridge for the port.
                },
        ),
        if (wcpLocked)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CruxPolicyLockNote(
              message: l10n.settingsServerLockedByPolicy,
            ),
          ),
        if (wcpAllowed.value) ...[
          ListTile(
            title: Text(l10n.settingsRemoteControlPortLabel),
            subtitle: Text(l10n.settingsRemoteControlPortDescription),
            trailing: SizedBox(
              width: 100,
              child: TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                onSubmitted: (value) {
                  final port = int.tryParse(value)?.clamp(1, 65535);
                  if (port != null) {
                    unawaited(settingsNotifier.setRemoteControlPort(port));
                  } else {
                    _portController.text = settings.remoteControlPort
                        .toString();
                  }
                },
              ),
            ),
          ),
          ListTile(
            title: Text(l10n.settingsRemoteControlStatus),
            trailing: Text(
              remoteState.isRunning
                  ? l10n.settingsRemoteControlStatusRunning(remoteState.port)
                  : l10n.settingsRemoteControlStatusStopped,
              style: TextStyle(
                color: remoteState.isRunning
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (remoteState.isRunning)
            ListTile(
              trailing: Text(
                l10n.settingsRemoteControlClientsConnected(
                  remoteState.connectedClients,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── CXP cross-probe controls ──────────────────────────────────────────────────
//
// A section in its own right, sibling to Remote Control rather than nested
// inside it: the two are orthogonal. WCP is the external driver protocol
// (third-party tools driving WaveCrux); CXP is the peer cross-probe protocol
// (Crux apps gossiping selection events).

/// WaveCrux's wiring around the suite-shared [CruxCxpSettingsControls]:
/// values from [AppSettings], callbacks into [appSettingsProvider], plus the
/// running-state / peers / last-error status column. The CxpLifecycleBridge
/// listens for the settings changes and starts / stops the server
/// automatically; no direct calls needed here.
class _CxpControlsBlock extends ConsumerWidget {
  const _CxpControlsBlock({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final cxpState = ref.watch(cxpServerProvider);
    // As with the WCP server: a locked org value decides whether this runs.
    final cxpAllowed = resolveCxpServerPolicy(
      ref.watch(cruxPolicyProvider).document,
      userSetting: settings.cxpServerEnabled,
    );
    final cxpLocked = cxpAllowed.source == PolicySource.policyLocked;

    return CruxSettingsSectionCard(
      children: [
        if (cxpLocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CruxPolicyLockNote(
              message: l10n.settingsServerLockedByPolicy,
            ),
          ),
        // Shown either way, dimmed and inert when the organization decided —
        // the port and cross-probe preferences are still worth reading.
        Opacity(
          opacity: cxpLocked ? 0.6 : 1,
          child: IgnorePointer(
            ignoring: cxpLocked,
            child: ExcludeFocus(
              excluding: cxpLocked,
              child: CruxCxpSettingsControls(
                strings: CruxCxpSettingsStrings(
                  enableLabel: l10n.settingsCxpEnabledLabel,
                  enableHelp: l10n.settingsCxpEnabledDescription,
                  portLabel: l10n.settingsCxpPortLabel,
                  portHelp: l10n.settingsCxpPortDescription,
                  portError: l10n.settingsCxpPortError,
                  attentionLabel:
                      l10n.settingsRequestAttentionOnCrossProbeLabel,
                  attentionHelp:
                      l10n.settingsRequestAttentionOnCrossProbeDescription,
                  broadcastLabel:
                      l10n.settingsBroadcastSelectionOnCrossProbeLabel,
                  broadcastHelp:
                      l10n.settingsBroadcastSelectionOnCrossProbeDescription,
                ),
                enabled: cxpAllowed.value,
                port: settings.cxpServerPort,
                requestAttention: settings.requestAttentionOnCrossProbe,
                broadcastSelection: settings.broadcastSelectionOnCrossProbe,
                onEnabledChanged: (enabled) => unawaited(
                  settingsNotifier.setCxpServerEnabled(enabled: enabled),
                ),
                onPortSubmitted: (port) =>
                    unawaited(settingsNotifier.setCxpServerPort(port)),
                onRequestAttentionChanged: (enabled) => unawaited(
                  settingsNotifier.setRequestAttentionOnCrossProbe(
                    enabled: enabled,
                  ),
                ),
                onBroadcastSelectionChanged: (enabled) => unawaited(
                  settingsNotifier.setBroadcastSelectionOnCrossProbe(
                    enabled: enabled,
                  ),
                ),
                statusTile: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.settingsCxpStatus),
                      trailing: Text(
                        cxpState.isRunning
                            ? l10n.settingsCxpStatusRunning(cxpState.port)
                            : l10n.settingsCxpStatusStopped,
                        style: TextStyle(
                          color: cxpState.isRunning
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (cxpState.isRunning)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        trailing: Text(
                          l10n.settingsCxpPeersConnected(
                            cxpState.connectedPeerCount,
                          ),
                        ),
                      ),
                    if (cxpState.lastError != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          cxpState.lastError!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
