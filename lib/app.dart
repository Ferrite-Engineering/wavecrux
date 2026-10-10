// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io' show File, Platform, exit, stderr, stdout;

import 'package:crux_eula/crux_eula.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart'
    show kCruxErrorSnackDuration;
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:crux_policy/crux_policy.dart'
    show PolicyDocument, PolicyLoadResult;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/core/initial_additional_file_paths_provider.dart';
import 'package:wavecrux/core/initial_file_path_provider.dart';
import 'package:wavecrux/core/initial_session_path_provider.dart';
import 'package:wavecrux/core/initial_streaming_provider.dart';
import 'package:wavecrux/core/initial_workspace_path_provider.dart';
import 'package:wavecrux/core/issue_reporter/wavecrux_issue_reporter_strings.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/platform/linux_desktop_identity.dart';
import 'package:wavecrux/core/platform_utils.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/core/router.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:wavecrux/core/startup_reconcile_provider.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_strings.dart';
import 'package:wavecrux/core/theme/theme_brightness_toggle.dart';
import 'package:wavecrux/core/theme/wavecrux_color_theme_bootstrap.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';
import 'package:wavecrux/core/updates/wavecrux_update_strings.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/beta_expiry/widgets/beta_expiry_gate.dart';
import 'package:wavecrux/features/collaboration/providers/collab_viewer_bridge_provider.dart';
import 'package:wavecrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:wavecrux/features/cursors/marker_chord_controller.dart'
    show MarkerChordMode;
import 'package:wavecrux/features/cursors/providers/marker_chord_providers.dart';
import 'package:wavecrux/features/diagnostics/providers/log_console_sink_provider.dart';
import 'package:wavecrux/features/eula/wavecrux_eula_overrides.dart';
import 'package:wavecrux/features/issue_reporter/wavecrux_issue_reporter_overrides.dart';
import 'package:wavecrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/settings/providers/orientation_lock_provider.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_startup_render_gate_provider.dart';
import 'package:wavecrux/features/stage/widgets/primitives/builtin_stage_widgets.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/telemetry/wavecrux_telemetry_overrides.dart';
import 'package:wavecrux/features/update/providers/observed_server_time_provider.dart';
import 'package:wavecrux/features/update/wavecrux_update_overrides.dart';
import 'package:wavecrux/features/viewer/providers/org_session_template_seed.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/commands/open_workspace_command.dart';
import 'package:wavecrux/features/workspace/providers/other_tabs_from_last_session_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_workspaces_provider.dart';
import 'package:wavecrux/features/workspace/providers/startup_recovery_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/features/workspace/widgets/desktop_file_drop_target.dart';
import 'package:wavecrux/features/workspace/widgets/recovery_banner_host.dart';
import 'package:wavecrux/features/workspace/workspace_restore_strategy.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/plugins/eager_startup_providers.dart';
import 'package:wavecrux/plugins/extra_decoders_provider.dart';
import 'package:wavecrux/plugins/extra_localizations_delegates_provider.dart';
import 'package:wavecrux/plugins/extra_stage_widgets_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/cli/cli_args.dart';
import 'package:wavecrux/services/cli/first_run_reset_flags.dart';
import 'package:wavecrux/services/decoders/ahb_lite_decoder.dart';
import 'package:wavecrux/services/decoders/apb_decoder.dart';
import 'package:wavecrux/services/decoders/axi4lite_decoder.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader_provider.dart';
import 'package:wavecrux/services/decoders/i2c_decoder.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/decoders/isa/isa_trace_decoder.dart';
import 'package:wavecrux/services/decoders/isa/riscv_decoder.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/spi_flash/spi_flash_decoder.dart';
import 'package:wavecrux/services/decoders/uart_decoder.dart';
import 'package:wavecrux/services/decoders/wishbone_decoder.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_provider.dart';
import 'package:wavecrux/services/logging/severe_log_stderr_sink.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/platform/incoming_file_service.dart';
import 'package:wavecrux/services/policy/org_theme_application.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/session/last_session_service.dart';
import 'package:wavecrux/services/session/restore_guard_service.dart';
import 'package:wavecrux/services/session/session_reset.dart';
import 'package:wavecrux/services/settings/settings_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/last_session_migration.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';
import 'package:wavecrux/services/workspace/window_bounds_store.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/display_size_feed.dart';

/// An organization theme pack that did not apply at launch. `developer.log`
/// emits nothing from a release build, so this goes to the product log.
final _policyLog = Logger('wavecrux.policy');

/// Scroll `dragDevices` applied app-wide by the root [ScrollConfiguration] in
/// [buildApp]: Flutter's default set (touch, stylus, invertedStylus, trackpad,
/// unknown) MINUS `mouse`.
///
/// Removing `mouse` is deliberate — it stops a 1-px mouse drift during a click
/// from letting a `SingleChildScrollView`'s `VerticalDragGestureRecognizer`
/// steal the gesture from a tap target (the non-deterministic `DropdownButton`
/// item-click misses in the decoder config dialog). Mouse-wheel scrolling uses
/// `PointerScrollEvent` (a separate path) and is unaffected.
///
/// IMPORTANT: `trackpad` MUST stay in this set. A two-finger trackpad scroll is
/// delivered as `PointerPanZoom` events, which a `Scrollable` only treats as a
/// scroll when `trackpad` is in `dragDevices`. An earlier revision narrowed
/// this to `{ touch }`, which silently killed two-finger scrolling in EVERY
/// list/panel/dialog in the app (signal tree, value column, diagnostics, …) on
/// macOS/iPad — only the scrollbar and mouse wheel worked. The three widgets
/// that own trackpad gestures themselves (waveform canvas, signal-list names
/// column, command palette) opt back OUT of `trackpad` locally via
/// [kTrackpadOwnedDragDevices] so the native scrollable doesn't double-drive
/// them.
const Set<PointerDeviceKind> kAppScrollDragDevices = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

/// Runs [bootstrap] and ends the process when it handled a headless
/// invocation — the entry point both `lib/main.dart` files call.
///
/// A Flutter desktop runner creates its window at launch and keeps its event
/// loop alive after Dart's `main` returns, so `wavecrux --help` used to print
/// the usage and then sit there with an empty window instead of exiting. The
/// headless branch of [bootstrap] only returns, so the exit happens here,
/// after stdout and stderr are flushed. [exitProcess] is injectable for tests.
Future<void> runWaveCrux({
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  List<Override> extraTabOverrides = const [],
  LinuxDesktopApp? linuxDesktopApp,
  Future<void> Function(int code)? exitProcess,
}) async {
  final headless = await bootstrap(
    args: args,
    extraOverrides: extraOverrides,
    extraTabOverrides: extraTabOverrides,
    linuxDesktopApp: linuxDesktopApp,
  );
  if (!headless || kIsWeb) return;
  await (exitProcess ?? _flushAndExit)(0);
}

Future<void> _flushAndExit(int code) async {
  await stdout.flush();
  await stderr.flush();
  exit(code);
}

/// Starts capturing diagnostics. Idempotent under hot restart.
///
/// The Beta Issue Reporter's ring buffer takes every log record, and uncaught
/// framework and async errors are routed into the log (the console red box
/// and dumps are preserved), so a failure during the session lands in a bug
/// report's Diagnostics section. The buffer is memory only, though; off the
/// web, [SevereLogStderrSink] also writes SEVERE records to stderr, the one
/// trace a release build leaves once the session is gone. [stderrSink]
/// replaces the process-wide sink in tests.
@visibleForTesting
void attachDiagnosticSinks({SevereLogStderrSink? stderrSink}) {
  CruxIssueReporterLogBuffer.instance
    ..attachToLogging()
    ..captureFlutterErrors();
  if (!kIsWeb) (stderrSink ?? SevereLogStderrSink.instance).attach();
}

/// The root [ProviderContainer] built by the most recent [bootstrap] call in
/// this process, or null before the first one.
///
/// For integration tests, which boot the app once per `testWidgets` body in a
/// single process. Between two bodies the test binding unmounts the previous
/// app's widget tree, but nothing disposes its root container, so that
/// container's timers keep running: its workspace auto-save, debounced by a
/// couple of seconds, can land *after* the next test cleared `workspace.json`
/// and hand the next boot the previous test's tabs. With the tree gone, this
/// is the only remaining handle on that container, so test setup can flush
/// its pending save before clearing.
@visibleForTesting
ProviderContainer? get lastBootstrapRootContainer =>
    _lastBootstrapRootContainer;
ProviderContainer? _lastBootstrapRootContainer;

/// Entry-point body shared by the open-core `lib/main.dart` and the
/// Pro overlay's `lib/main.dart` (through [runWaveCrux]).
/// Open-core runs `bootstrap(args: args)`; the Pro overlay adds
/// `extraOverrides: proOverrides` to layer Pro/Enterprise provider
/// implementations on top without forking the bootstrap logic. See
/// ARCHITECTURE.md §10.
///
/// Returns true when [args] selected a headless flow (`--help`) that has
/// finished; false once the GUI is running.
///
/// [extraOverrides] are root-scope overrides; [extraTabOverrides] are appended
/// to every per-tab container's override list (via [TabContainerManager]) so the
/// Pro overlay can scope its own providers per-tab — e.g. the AI Waveform
/// Assistant controller, whose tools must read the active tab's loaded waveform,
/// not the empty root source.
///
/// [linuxDesktopApp] is the freedesktop identity installed when the app runs
/// from an AppImage: open core passes nothing and gets
/// [kWaveCruxLinuxDesktopApp]; the Pro overlay passes its own.
///
/// Parses CLI args so `wavecrux dump.fst` and
/// `wavecrux dump.fst --session debug.wavecrux` open directly into the viewer.
///
/// On iOS/Android, also checks [IncomingFileService.getInitialFile] so that a
/// file opened via the share sheet or "Open With" (cold start) routes straight
/// to the viewer.
Future<bool> bootstrap({
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  List<Override> extraTabOverrides = const [],
  LinuxDesktopApp? linuxDesktopApp,
}) async {
  // `--help` / `-h` short-circuits before the platform binding so the
  // ergonomic `wavecrux --help` prints usage on stdout and exits cleanly
  // (the exit is [runWaveCrux]'s), matching every other CLI tool an HDL
  // engineer reaches for.
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(cliHelpText());
    return true;
  }

  // Required before any platform-channel calls or await in main.
  WidgetsFlutterBinding.ensureInitialized();

  // `--reset-eula` and `--reset-telemetry-consent` put this installation back
  // to "never answered" for the licence agreement and the telemetry
  // disclosure, so each mounts again this launch rather than next one. Testing
  // affordances: both dialogs are deliberately once-per-installation, which
  // makes them the surfaces hardest to see twice.
  //
  // Before the container is built, because the EULA acceptance store and
  // `TelemetryConsentStore` start reading their persisted values the moment
  // anything touches their graphs. The telemetry installation id is left
  // alone — see `resetTelemetryConsent`.
  await applyFirstRunResetFlags(args);

  // Windows / Linux: switch to a frameless window and draw our own title bar
  // (logo + inline menus + caption buttons). macOS keeps its native title bar
  // + system menu; web/mobile have no window frame. The matching window frame
  // (drop shadow + drag-to-resize edges) is restored in this app's
  // MaterialApp.builder. window_manager access is behind the conditional-import
  // facade so it never reaches the web build. See features/window_chrome/.
  if (useCustomWindowChrome) {
    // Restore the previous session's window geometry before the first show so
    // the window opens at its saved size/position with no visible jump. Read
    // straight from workspace.json (a side-effect-free peek — the provider
    // hasn't hydrated yet); skipped under `--reset`, which intentionally
    // launches fresh at the default geometry. Null (first launch / restore
    // unavailable) falls through to the centered 1280×720 default.
    final restoreBounds = args.contains('--reset')
        ? null
        : await peekPersistedWindowBounds();
    await initWindowChrome(restore: restoreBounds);
  }

  // BEFORE any provider is constructed, so early-startup warnings (decoder
  // plugin scan, workspace hydration, theme registration) are captured.
  attachDiagnosticSinks();

  // Prevent the browser from intercepting right-click events so Flutter's
  // secondary-button gesture handlers (PlatformContextMenu) can receive them.
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  }

  DecoderRegistry.instance.register(
    SpiDecoder.decoderDefinition,
    SpiDecoder.new,
  );
  DecoderRegistry.instance.register(
    I2cDecoder.decoderDefinition,
    I2cDecoder.new,
  );
  DecoderRegistry.instance.register(
    UartDecoder.decoderDefinition,
    UartDecoder.new,
  );
  DecoderRegistry.instance.register(
    Axi4LiteDecoder.decoderDefinition,
    Axi4LiteDecoder.new,
  );
  DecoderRegistry.instance.register(
    ApbDecoder.decoderDefinition,
    ApbDecoder.new,
  );
  DecoderRegistry.instance.register(
    AhbLiteDecoder.decoderDefinition,
    AhbLiteDecoder.new,
  );
  DecoderRegistry.instance.register(
    WishboneDecoder.decoderDefinition,
    WishboneDecoder.new,
  );
  DecoderRegistry.instance.register(
    SpiFlashDecoder.decoderDefinition,
    SpiFlashDecoder.new,
  );

  // RISC-V instruction-trace decoder (Open Core).
  // Async load of bundled TOMLs; registers a closure so the assets are
  // available to every decoder instance constructed by the registry.
  // A failure to load any single TOML degrades extension coverage but
  // never breaks startup (the assets loader isolates per-file errors).
  final riscvAssets = await IsaDecoderAssets.loadFromBundle(
    userTableDirectories: await peekIsaTableDirectories(),
  );
  DecoderRegistry.instance.register(
    RiscvDecoder.decoderDefinition,
    (config) => RiscvDecoder(
      config,
      riscvAssets,
      renderer: isaDisassemblyRenderer,
    ),
  );

  registerBuiltinStageWidgets();

  // Register WaveCrux's canvas + chrome token categories with the
  // cross-suite ThemeRegistry. Idempotent; safe under repeated bootstraps
  // (tests, hot restart). Per ARCHITECTURE.md §10.
  registerWaveCruxThemeTokens();

  // Discover and register user-contributed decoder plugins.
  // Gated on AppSettings.pluginSafetyAcknowledged
  // so first-launch users do not load native code without consent. The
  // scan is intentionally awaited so plugins are visible in the
  // DecoderRegistry by the time the first frame builds; per-plugin
  // failures are isolated inside the loader and never thrown past
  // scanPluginsOnStartup. Conditionally compiled to a no-op on Web.
  await scanPluginsOnStartup();

  // `wavecrux a.fst b.vcd` opens each file as a separate tab: the first
  // goes to [initialFilePathProvider]; the rest go to
  // [initialAdditionalFilePathsProvider] and are opened via
  // [TabListNotifier.openFile] in [WaveCruxApp.initState]. `--workspace
  // <path>` and bare positional `.wavecrux-workspace` arguments route
  // through [initialWorkspacePathProvider] and trigger the Open Workspace
  // flow at startup. The parser lives in
  // [services/cli/cli_args.dart] so it is exercisable from unit tests
  // without spinning up a Flutter binding.
  final cli = parseCliArgs(args);
  final initialFiles = List<String>.from(cli.initialFiles);
  final initialSession = cli.initialSession;
  final initialWorkspace = cli.initialWorkspace;
  final stdinMode = cli.stdinMode;
  final pipePath = cli.pipePath;
  // `--wcp-port` / WAVECRUX_WCP_PORT: WCP on for this process only, on that
  // port, without touching the stored Remote Control setting.
  final wcpPortOverride = kIsWeb
      ? null
      : resolveWcpPortOverride(cli, Platform.environment);

  // On mobile, check whether the app was cold-started by a share-sheet / "Open
  // With" action.  This is a no-op on desktop and web.
  if (initialFiles.isEmpty &&
      initialSession == null &&
      initialWorkspace == null) {
    final incoming = await IncomingFileService.getInitialFile();
    if (incoming != null) initialFiles.add(incoming);
  }

  // One-shot migration from the legacy last_session.json manifest to the
  // workspace.json document. Idempotent — subsequent launches see
  // no legacy file and immediately skip the migration. Failures are
  // non-fatal: a corrupt or missing manifest yields false and startup
  // continues with whatever workspace.json already exists (or empty).
  // Skipped on Flutter Web — path_provider is unavailable, and there is no
  // legacy manifest there to migrate.
  if (!kIsWeb) {
    try {
      await LastSessionMigration(
        lastSessionService: const LastSessionService(),
        workspaceService: WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
        ),
      ).run();
    } on Object {
      // Migration is best-effort; never block startup.
    }
  }

  // Startup session recovery (desktop/mobile only; web has no on-disk session).
  //
  // `--reset` is the documented escape hatch for a session so corrupt it wedges
  // startup: wipe workspace.json, every per-tab sidecar, and the legacy
  // manifest, then launch into an empty workspace. Runs BEFORE the workspace
  // hydration below so the fresh launch sees nothing to restore. Scoped to
  // session state — settings, keymap, and recent files are kept.
  //
  // The restore guard is the automatic crash-loop breaker. If the previous
  // launch armed the sentinel (it was about to reopen a waveform) and never
  // disarmed it — because that load crashed, or the user force-quit a hang —
  // we detect it here, clear it, and suppress this launch's auto-load so the
  // app reaches a usable state instead of re-wedging. This is the ONLY recovery
  // path on mobile, where there is no command line to pass a flag. See
  // [RestoreGuardService].
  var startupInterrupted = false;
  if (!kIsWeb) {
    const restoreGuard = RestoreGuardService();
    if (cli.reset) {
      await resetPersistedSessionData(
        WorkspaceService(codec: const WaveCruxWorkspaceCodec()),
      );
      await restoreGuard.disarm();
      // ignore: avoid_print, intentional CLI confirmation on stdout
      print('WaveCrux: cleared saved session and workspace state (--reset).');
    } else {
      startupInterrupted = await restoreGuard.wasInterrupted();
      if (startupInterrupted) {
        // We won't act on the poisoned session this launch (auto-load is
        // suppressed below), so clear the sentinel now — the next launch
        // retries restore from the intact, still-on-disk workspace.
        await restoreGuard.disarm();
      }
    }
  }
  // `--no-restore` skips this launch's auto-load without deleting anything; an
  // interrupted previous launch forces the same skip automatically.
  final suppressAutoLoad = cli.noRestore || startupInterrupted;

  // Two-phase init: create the managers first so they can be injected as
  // override values, then pass the root container back so each manager can
  // create child containers parented to it. Per ARCHITECTURE.md §6.4.
  // `extraTabOverrides` lets the Pro overlay scope its own providers per-tab
  // (e.g. the AI Waveform Assistant controller, so its tools read the active
  // tab's loaded waveform rather than the empty root source). Open-core passes
  // an empty list.
  final tcm = TabContainerManager(extraTabOverrides: extraTabOverrides);
  final pcm = PaneContainerManager();
  // Which editor, if any, is hosting this build — read here, before the
  // container exists, because it can be: the extension's `index.html` shim sets
  // the marker before `main.dart.js` runs. That synchronous answer is what lets
  // telemetry treat `form_factor` as non-deferring (see `EditorHostKind`) and
  // what lets the relay override below be a startup decision rather than a
  // watch. Off the web the conditional export resolves to the stub, which
  // answers `none` without touching anything.
  final editorHostKind = HostBridgeChannel.detectHostKind();
  final rootContainer = ProviderContainer(
    overrides: [
      if (initialFiles.isNotEmpty)
        initialFilePathProvider.overrideWithValue(initialFiles.first),
      if (initialFiles.length > 1)
        initialAdditionalFilePathsProvider.overrideWithValue(
          initialFiles.sublist(1),
        ),
      if (initialSession != null)
        initialSessionPathProvider.overrideWithValue(initialSession),
      if (initialWorkspace != null)
        initialWorkspacePathProvider.overrideWithValue(initialWorkspace),
      if (stdinMode) initialStdinModeProvider.overrideWithValue(true),
      if (pipePath != null) initialPipePathProvider.overrideWithValue(pipePath),
      if (wcpPortOverride != null)
        wcpPortOverrideProvider.overrideWithValue(wcpPortOverride),
      tabContainerManagerProvider.overrideWithValue(tcm),
      paneContainerManagerProvider.overrideWithValue(pcm),
      // A mobile store build is not distributed as a public beta, so nothing
      // in it should advertise one — most visibly the About screen's "Public
      // Beta" chip. Consumer app stores forbid shipping pre-release software
      // (App Store Review Guideline 2.2, which rejected WaveCrux 0.1.0 (2)),
      // and the mobile builds carry no beta expiry either (see
      // scripts/release_ios.sh), so on these hosts there is genuinely no beta
      // for the chip to describe. Desktop remains a real public beta and keeps
      // saying so.
      //
      // This flips only provider-reading UI. `FeatureGate.isAvailable` reads
      // the compile-time `kBetaPeriod` constant, not this provider, so tier
      // gating is unchanged; and the picker dialogs that do read it (decoder,
      // Stage widget, translator) gate nothing in an Open Core build, which
      // registers no PRO/ENT content. Spread BEFORE extraOverrides so the Pro
      // overlay can layer on top per the open-core conflict semantics.
      if (isMobileHostPlatform) betaPeriodProvider.overrideWithValue(false),
      // Wire WaveCrux persistence (AppSettings.activeThemeName +
      // themeOverrides) into crux_theme's cruxColorThemeProvider. Spread
      // BEFORE extraOverrides so the Pro overlay can layer its own
      // override on top per the open-core conflict semantics
      // (ARCHITECTURE §10).
      wavecruxCruxColorThemeOverride,
      // Wire the persisted "Enable experimental AI features" opt-in
      // (AppSettings.aiExperimentalEnabled) into the cross-suite
      // `aiExperimentalUserToggleProvider` from crux_license, so
      // `aiExperimentalEnabledProvider` (build flag AND user toggle) reflects
      // the user's setting. Spread BEFORE extraOverrides so the Pro overlay
      // can layer on top per the open-core conflict semantics.
      aiExperimentalUserToggleProvider.overrideWith(
        (ref) =>
            ref.watch(appSettingsProvider).value?.aiExperimentalEnabled ??
            false,
      ),
      // Feed the persisted, most-recently-observed update-manifest `server_time`
      // into crux_license's beta-expiry clock so setting the device clock BACK
      // can no longer defer beta expiry (clock-tampering hardening).
      // Spread BEFORE extraOverrides so the Pro overlay can layer on top.
      observedServerTimeProvider.overrideWith(
        (ref) => ref.watch(observedServerTimeStoreProvider),
      ),
      // Bind the cross-suite `crux_updates` package: the WaveCrux manifest
      // config (with the App Store / Play Store targets and checkOnMobile),
      // build info, the persisted auto-check setting, the URL launcher, and the
      // server-time sink half of the beta-expiry clock hardening (the
      // `observedServerTimeProvider` override above is the other half).
      ...wavecruxUpdateOverrides,
      // Bind the cross-suite `crux_issue_reporter` package: the GitHub target,
      // build info, the privacy-scrubbed session contributor, and the
      // diagnostics-report seam. The overlay's extra "Pro State" category
      // arrives via `cruxIssueReporterDataProviderProvider`, whose open-core
      // default contributes nothing. Spread BEFORE extraOverrides so the Pro
      // overlay can layer on top per the open-core conflict semantics.
      ...wavecruxIssueReporterOverrides,
      // Stamps every audit event this installation records with the product
      // id. One JSONL file holds four products' events and this is what makes
      // it filterable; the same string the policy namespace uses, so filtering
      // the log and writing `.crux-policy.json` share one vocabulary. Emission
      // is unconditional — the SINK is what an administrator gates, and it is
      // `NoopAuditSink` until one sets `suite.audit.path`.
      cruxAuditProductIdProvider.overrideWithValue(
        WaveCruxPolicyKeys.productId,
      ),
      // A browser has no organization policy file, so every policy consumer
      // sees the absent document without running discovery at all.
      // `PolicyLoader.load()` already answers absent on the web; binding the
      // answer here keeps the pre-frame theme-pack read below off the loader
      // entirely, so a regression there cannot stop the web app starting.
      // Spread BEFORE extraOverrides so the Pro overlay can layer on top.
      if (kIsWeb)
        cruxPolicyProvider.overrideWithValue(
          const PolicyLoadResult(document: PolicyDocument.absent),
        ),
      // Bind the telemetry pipeline's locale seam. Everything else the
      // envelope needs resolves from `core/` and `shared/`. Spread BEFORE
      // extraOverrides so the Pro overlay can layer the Enterprise policy-file
      // decision on top per the open-core conflict semantics.
      // Bind the EULA gate's persistence and quit path. Spread BEFORE
      // extraOverrides for the same reason as the telemetry bindings, though
      // the Pro overlay layers nothing on top today: acceptance is required at
      // every edition, Open Core included (EULA 2.1).
      ...wavecruxEulaOverrides,
      ...wavecruxTelemetryOverrides,
      // …and, under a VSCode extension host, replace the sender: the host owns
      // the `vscode.env.isTelemetryEnabled` gate and is the pack's only
      // transmitter, so this half relays its events and keeps no pipeline of
      // its own. Empty on every other host. Spread BEFORE extraOverrides so the
      // Pro overlay can still layer on top.
      ...wavecruxHostRelayTelemetryOverrides(editorHostKind),
      ...extraOverrides,
    ],
  );
  _lastBootstrapRootContainer = rootContainer;
  // The host-kind signal `telemetryFormFactorProvider` reads, set before
  // anything can flush. Idempotent, and a no-op for the `none` default.
  rootContainer.read(editorHostKindProvider.notifier).set(editorHostKind);
  // Instantiate the editor-host bridge so an extension host can drive this
  // build and so local selection changes mirror back out for cross-probing.
  // Same keepAlive read-once pattern as the CXP and collaboration bridges
  // below; a no-op when nothing is hosting us, which is why it needs no guard.
  // See lib/services/host_bridge/editor_host_bridge.dart.
  rootContainer.read(editorHostBridgeProvider);
  // The organization's theme pack, applied BEFORE the first frame. A
  // theme applied after the window is up is a flash of the wrong colours
  // followed by a correction, on every launch, forever. `rootContainer` exists
  // and nothing has painted yet, which is the one moment this fits.
  //
  // A no-op with no policy file, which is every default install: the user's own
  // theme is what loads, untouched. A failure is logged rather than surfaced —
  // an unreachable share is usually a laptop off the VPN, and a modal on every
  // launch in a coffee shop is worse than the default theme.
  //
  // The user's own active theme pack goes first, for the same reason: settings
  // hold only its id, so it is loaded from its file here rather than the app
  // opening on the default theme. The organization's pack, applied next,
  // takes precedence over it.
  await restoreActiveThemePack(rootContainer);
  final orgTheme = applyOrgThemePack(rootContainer);
  if (orgTheme.problem case final problem?) {
    _policyLog.warning('organization theme pack not applied: $problem');
  }

  // The startup plugin scan ran before this container existed, so any refusal
  // it made under the organization's allowlist was buffered rather than
  // recorded. Drain it now — a refusal at startup is precisely the one worth
  // an audit line, because it is the moment an unapproved plugin would
  // otherwise have been loaded. Draining is idempotent.
  flushStartupPluginAuditEvents(rootContainer.read(cruxAuditRecorderProvider));

  // Say which policy file won, or that one was refused
  // (<https://edacrux.app/policy-reference#failures>). Until this call
  // existed, `policy.loaded` and `policy.rejected` were
  // registered kinds with no producer anywhere in the suite, which meant a file
  // whose signature failed was refused **silently**: from inside a running app
  // a refused policy and an absent one were indistinguishable, and telling
  // those two apart is the whole point of the distinction.
  //
  // The two halves land in different places and `reportPolicyLoad` decides
  // which — a refusal CANNOT reach the audit sink, because the sink's path
  // comes from `suite.audit.path`, which comes from the file that was just
  // refused. See `crux_license`'s `PolicyReportDestination`.
  //
  // Here rather than in the Pro overlay: the policy file is honoured at every
  // tier for the day-one keys, so an open-core seat pointed at a bad file has
  // to be told too.
  reportPolicyLoad(
    result: rootContainer.read(cruxPolicyProvider),
    // Names any key the administrator set that this build does not act on.
    productId: WaveCruxPolicyKeys.productId,
    recorder: rootContainer.read(cruxAuditRecorderProvider),
  );

  tcm.init(rootContainer);
  pcm.init(rootContainer);

  // Structural scope eviction (crux_workspace's `WorkspaceScopeReconciler`
  // seam). Without these two registrations the container managers hold every
  // per-tab / per-pane `ProviderContainer` ever created for the process
  // lifetime — leaking that tab's providers, subscriptions and timers — and,
  // worse, a workspace reload that revives a persisted `TabId` hands the
  // "new" tab the DEAD tab's container, which presents as cross-tab state
  // bleed rather than as memory growth. Registered before the hydration read
  // below so the first snapshot the notifier emits already reaches them.
  rootContainer.read(workspaceProvider.notifier)
    ..addScopeReconciler(tcm)
    ..addScopeReconciler(pcm);

  // Hydrate workspaceProvider before the first frame so [_WaveCruxApp]'s
  // post-frame restoration sees a resolved AsyncValue and the empty-canvas
  // state does not flash an AsyncLoading placeholder on launch.
  // A hydration failure logs and falls through — the provider's own
  // error-recovery returns Workspace.empty.
  if (!kIsWeb) {
    try {
      await rootContainer.read(workspaceProvider.future);
    } on Object {
      // Non-fatal — Workspace.empty is the documented fallback.
    }
  }

  // Record the recovery posture for the UI before the first frame. The workspace
  // load above quarantines an unreadable workspace.json and records a recovery
  // for the host to surface; combine that with the crash-loop / --no-restore
  // signals computed pre-hydration. The banner (RecoveryBannerHost) reads the
  // reason; the cold-start reconcile reads suppressAutoLoad.
  if (!kIsWeb) {
    final recovery = rootContainer
        .read(workspaceServiceProvider)
        .takeRecovery();
    final reason = startupInterrupted
        ? StartupRecoveryReason.interrupted
        : (recovery != null
              ? StartupRecoveryReason.workspaceCorrupt
              : StartupRecoveryReason.none);
    rootContainer
        .read(startupRecoveryProvider.notifier)
        .configure(
          StartupRecoveryState(
            reason: reason,
            suppressAutoLoad: suppressAutoLoad,
          ),
        );
  }

  // AppImage first-run desktop self-integration (Linux/Wayland): write the
  // host-side .desktop + hicolor icons so GNOME/Ubuntu matches this window's
  // app_id to its dock icon. Inert off Linux and off AppImage. MUST be guarded
  // off web: maybeIntegrateDesktopEntry reaches dart:io `Platform`, which is
  // unavailable on web and throws before the function's own Linux guard — an
  // unguarded call throws out of bootstrap here, so runApp never fires and the
  // web app hangs on the loading spinner forever.
  if (!kIsWeb) {
    await maybeIntegrateDesktopEntry(
      linuxDesktopApp ?? kWaveCruxLinuxDesktopApp,
    );
  }

  runApp(
    UncontrolledProviderScope(
      container: rootContainer,
      child: const WaveCruxApp(),
    ),
  );
  return false;
}

/// Root application widget.
///
/// Subscribes to [IncomingFileService.incomingFiles] in [initState] so that
/// files opened while the app is already running (warm start) are routed to the
/// viewer immediately without user interaction.
class WaveCruxApp extends ConsumerStatefulWidget {
  /// Creates the root application widget.
  const WaveCruxApp({super.key});

  @override
  ConsumerState<WaveCruxApp> createState() => _WaveCruxAppState();
}

class _WaveCruxAppState extends ConsumerState<WaveCruxApp>
    with WidgetsBindingObserver {
  // Subscription kept alive for the lifetime of the app. Established in
  // [initState] — NOT via a `late final` initializer: a lazy initializer only
  // runs on first *access*, and this field's only other reference is in
  // `dispose`, so the EventChannel was never subscribed during the app's life.
  // The native side's eventSink therefore stayed nil and every warm-launch
  // share-sheet / "Open With" file was parked in `pendingFilePath` and dropped.
  // Cancelled in dispose so the channel is released on hot restart.
  late final StreamSubscription<String> _incomingFileSub;

  /// Tabs whose deferred waveform load is currently in flight, so the
  /// [activeTabIdProvider] listener doesn't kick off a second load for a tab
  /// that is already loading. See [_ensureTabLoaded].
  final Set<TabId> _deferredInFlight = <TabId>{};

  /// Crash-loop breaker for the cold-start restore. Armed by
  /// [_beginGuardedRestore] just before the active tab's waveform load (the one
  /// operation at launch that can crash or hang the app) and disarmed by
  /// [_disarmRestoreGuardOnce] the moment the first load completes. A launch
  /// that crashes or is force-quit mid-load leaves the sentinel set, which the
  /// next `bootstrap()` detects to suppress the auto-load. See
  /// [RestoreGuardService].
  final RestoreGuardService _restoreGuard = const RestoreGuardService();

  /// Whether [_restoreGuard] is currently armed, so [_disarmRestoreGuardOnce]
  /// fires its disarm exactly once (on the first completed load).
  bool _restoreGuardArmed = false;

  /// Listens for tab activation to lazily load a restored tab's waveform the
  /// first time it is viewed (see [_ensureTabLoaded]). Closed in [dispose].
  ProviderSubscription<TabId>? _deferredLoadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Subscribe to warm-launch incoming files (share sheet / "Open With" while
    // the app is already running). Doing this here forces the EventChannel's
    // onListen so the native IncomingFilePlugin has a live sink to deliver to;
    // as a `late final` initializer it never ran until dispose. See the field.
    _incomingFileSub = IncomingFileService.incomingFiles.listen(
      _onIncomingFile,
      onError: (_) {
        /* ignore — channel errors are non-fatal */
      },
    );

    // Register decoders contributed via the [extraDecodersProvider] extension
    // point. Open-core returns an empty list; the Pro overlay
    // overrides the provider to register Pro-tier decoders (USB, AXI4-full,
    // PCIe TLP, …) without forking the open-core bootstrap or registry.
    for (final extra in ref.read(extraDecodersProvider)) {
      DecoderRegistry.instance.register(extra.definition, extra.factory);
    }

    // Instantiate the CXP lifecycle bridge so it starts mirroring
    // AppSettings.cxpServerEnabled into the CXP server lifecycle. The
    // bridge provider is keepAlive: true, so this single read is enough
    // to keep the listener installed for the lifetime of the app — the
    // CXP server then auto-starts on launch when the setting is true
    // (default) and reacts to subsequent toggle/port changes.
    // See lib/features/remote/providers/cxp_server_provider.dart.
    // Skip on the test platform (only desktop hosts the CXP server) —
    // path_provider needs the platform channel in widget tests.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      ref
        ..read(cxpLifecycleBridgeProvider)
        // Instantiate the selection emitter so it begins watching the
        // selection / cursor / marker providers as soon as the CXP server
        // is up. The provider depends on cxpServerProvider; it returns
        // null while the server is stopped (the listen is harmless).
        ..read(cxpSelectionEmitterProvider);
    }

    // Instantiate the WCP lifecycle bridge so the remote-control server
    // auto-starts on launch when AppSettings.remoteControlEnabled is true,
    // instead of only when the user toggles the settings switch by hand
    // (beta issue #9: correct port shown, status "stopped", scripted
    // clients unable to connect after a relaunch). Same keepAlive read-once
    // pattern as the CXP bridge above, but not desktop-gated — the Remote
    // Control settings section is offered on mobile too, and the bridge
    // touches no platform channels. Web is excluded: dart:io ServerSocket
    // cannot bind there (startServer would return its error string, which the
    // bridge has no surface to show).
    // See lib/services/remote/remote_control_notifier.dart.
    if (!kIsWeb) {
      ref.read(wcpLifecycleBridgeProvider);
    }

    // Instantiate the collaboration viewer bridge so local cursor / viewport /
    // marker changes mirror into the active CollaborationService once an
    // Enterprise session is live. Read unconditionally (no platform guard): it
    // touches no platform channels, stays inert until a session is active, and
    // is a complete no-op in open-core where the default noop service never
    // starts one. keepAlive plain provider — this single read keeps its
    // listeners installed for the app lifetime.
    // See lib/features/collaboration/providers/collab_viewer_bridge_provider.dart.
    ref.read(collabViewerBridgeProvider);

    // Register Stage widgets contributed via the [extraStageWidgetsProvider]
    // extension point. Open-core returns an empty list; the Pro
    // overlay overrides the provider to register the curated Pro pack
    // (framebuffer, audio waveform, character LCD, …) without forking the
    // open-core bootstrap or either of the two registries. Each contribution
    // carries both the pure-Dart definition and the Flutter renderer because
    // they live in different layers — see [ExtraStageWidgetRegistration].
    for (final extra in ref.read(extraStageWidgetsProvider)) {
      StageRegistry.instance.register(extra.definition);
      StageWidgetRendererRegistry.instance.register(
        extra.definition.id,
        extra.renderer,
      );
    }

    // Eagerly initialise the community custom-widget bundle manager so
    // persisted `.wcrux-widget` bundles register their definitions at
    // startup — like the built-ins and the Pro pack above. Without this the
    // manager only initialises when Settings → Custom Widgets is opened (its
    // sole other reader), so a restored session referencing a community
    // widget renders "Unknown widget", and the picker omits it, until then.
    // The async load races session restore; the Stage tile additionally
    // watches the manager to re-resolve once it completes.
    ref.read(customWidgetBundleManagerProvider);

    // Startup workspace handling, deferred to post-frame so the tab bar widget
    // tree is fully built and settings are available before the async load.
    //
    // `--workspace <path>` (or a bare positional `.wavecrux-workspace` arg)
    // takes priority: it replaces the whole arrangement with the named
    // workspace, so the auto-managed-workspace reconcile is skipped. The
    // startup-reconcile barrier is still completed so anything awaiting it
    // (there is no CLI-file open in this branch) can never hang.
    final initialWorkspacePath = ref.read(initialWorkspacePathProvider);
    if (initialWorkspacePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _completeStartupReconcile();
        unawaited(_openWorkspaceFromCli(initialWorkspacePath));
      });
      return;
    }

    // Otherwise reconcile the auto-managed workspace on every cold start —
    // including when CLI files were provided. When [restoreTabsOnLaunch] is on
    // the saved tabs are restored (deferred-loaded); when off they are closed.
    // The CLI files (collected here so the reconcile can de-duplicate against
    // a restored copy) are opened + focused by [ViewerScreen] *after* this
    // reconcile completes the startup barrier — see [startupReconcileProvider].
    final cliFilePaths = <String>{
      if (ref.read(initialFilePathProvider) case final p? when p.isNotEmpty) p,
      ...ref.read(initialAdditionalFilePathsProvider),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_restoreFromWorkspace(cliFilePaths: cliFilePaths));
    });
  }

  /// Completes the [startupReconcileProvider] barrier exactly once, releasing
  /// any CLI-file open in [ViewerScreen] that is waiting for the cold-start
  /// workspace reconcile to settle.
  void _completeStartupReconcile() {
    final completer = ref.read(startupReconcileProvider);
    if (!completer.isCompleted) completer.complete();
  }

  /// Routes a CLI-provided `--workspace <path>` argument through the same
  /// open-workspace flow the GUI Open Workspace command uses. Failures
  /// surface a non-blocking snackbar via the root messenger; the existing
  /// auto-managed workspace remains intact.
  Future<void> _openWorkspaceFromCli(String path) async {
    final container = ProviderScope.containerOf(context);
    final error = await openWorkspaceFromPathForContainer(container, path);
    if (!mounted) return;
    if (error != null) {
      // Use the messenger's context (a descendant of MaterialApp) for the
      // Localizations lookup — `_WaveCruxAppState.context` is ABOVE the
      // MaterialApp.router this build() returns, so `L10N.of(this.context)`
      // would walk up past MaterialApp and never reach the Localizations
      // widget it creates. Same idiom as [_scheduleDroppedFilesSnackbar].
      final messengerState = rootScaffoldMessengerKey.currentState;
      if (messengerState != null && messengerState.mounted) {
        final l10n = Localizations.of<L10N>(messengerState.context, L10N);
        if (l10n != null) {
          final colorScheme = Theme.of(messengerState.context).colorScheme;
          messengerState.showSnackBar(
            SnackBar(
              content: Text(
                l10n.openWorkspaceError(error),
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
              backgroundColor: colorScheme.errorContainer,
              behavior: SnackBarBehavior.floating,
              duration: kCruxErrorSnackDuration,
            ),
          );
        }
      }
      return;
    }
    await container.read(recentWorkspacesProvider.notifier).addWorkspace(path);
  }

  /// Snapshots the live tab list into a fresh [Workspace] and writes it
  /// atomically. Called from [didChangeAppLifecycleState] on
  /// [AppLifecycleState.paused] (mobile) and [AppLifecycleState.detached]
  /// (desktop close).
  ///
  /// Uses [ref.read] rather than `ref.watch`: the lifecycle callback fires
  /// after the widget tree may be torn down, so the read-only snapshot is
  /// the only safe option. Errors are swallowed because the flush is the
  /// final operation before quit — there is no UI left to surface a
  /// failure dialog against.
  Future<void> _flushWorkspace() async {
    if (kIsWeb) return;
    final settings = ref.read(appSettingsProvider).value;
    if (settings == null || !settings.restoreTabsOnLaunch) return;
    try {
      // Capture the live window geometry into the workspace extras so the next
      // cold start reopens the window where the user left it. Desktop-only
      // (window_manager is initialized only under custom chrome — Windows /
      // Linux); a failed read returns null and simply skips this session's
      // geometry. Recorded BEFORE the flush below so it lands in the same
      // synchronous write.
      if (useCustomWindowChrome) {
        final bounds = await readCurrentWindowBounds();
        if (bounds != null) {
          await ref.wavecruxWorkspace.setWindowBounds(bounds);
        }
      }

      // The workspace document is now the single source of truth for tabs,
      // panes, order, and active pointers (pane-collapse and active-tab
      // invariants are maintained on every mutation), so the quit-time flush
      // no longer reconstructs a snapshot from a separate live tab list — it
      // just forces the debounced auto-save to land synchronously.
      await ref.read(workspaceProvider.notifier).flushPendingSave();

      // Issue #1: flush each tab's pending sidecar autosave so a restart
      // restores cursors, signal groups, zoom, markers, and Stage workspace
      // — not just "files loaded". The autosave debounce window means the
      // most recent user action (placing a cursor, zooming) may not have
      // landed on disk yet; flushPendingSave forces an immediate write to
      // `{appSupportDir}/sessions/{tabId}.wavecrux`. The autosave's per-tab
      // override resolves `tabIdProvider` correctly so each flush targets
      // the correct sidecar.
      final ws = ref.read(workspaceProvider).value;
      if (ws == null) return;
      final tcm = ref.read(tabContainerManagerProvider);
      for (final tab in ws.tabs) {
        try {
          await tcm
              .containerFor(tab.id)
              .read(sessionAutoSaveProvider.notifier)
              .flushPendingSave();
        } on Object {
          // Best-effort: one tab's failed flush should not abort the
          // workspace flush.
        }
      }
    } on Object {
      // Lifecycle callbacks must never throw — a failed flush at quit is
      // recoverable on next launch (workspace.json reverts to its previous
      // good state under atomic-write semantics).
    }
  }

  /// Reconciles the auto-managed workspace on cold start, then releases the
  /// [startupReconcileProvider] barrier so any CLI-file open waiting on it can
  /// proceed. Always completes the barrier, even on an early-exit path.
  ///
  /// [cliFilePaths] are the file arguments this launch will open (the first
  /// positional file plus any extras). They are forwarded to the reconcile so
  /// a saved tab the user is re-opening is de-duplicated (focused, not opened a
  /// second time) and so the reconcile does not steal focus from the file the
  /// CLI open will activate.
  Future<void> _restoreFromWorkspace({
    Set<String> cliFilePaths = const <String>{},
  }) async {
    try {
      await _reconcileWorkspace(cliFilePaths: cliFilePaths);
    } finally {
      _completeStartupReconcile();
    }
  }

  /// Brings the live tab set in line with the hydrated workspace: restores the
  /// saved tabs (deferred-loaded) when [AppSettings.restoreTabsOnLaunch] is on,
  /// or closes them all when it is off, dropping tabs whose
  /// [WorkspaceTab.filePath] no longer exists and surfacing a non-blocking
  /// snackbar listing them. No-op on web (workspace persistence is
  /// desktop/mobile only).
  ///
  /// Awaits [appSettingsProvider.future] so the post-frame callback
  /// does not race the settings load. The workspace itself has already been
  /// hydrated in `bootstrap()` so this is a synchronous read.
  Future<void> _reconcileWorkspace({
    required Set<String> cliFilePaths,
  }) async {
    if (kIsWeb) return;
    final AppSettings settings;
    try {
      settings = await ref.read(appSettingsProvider.future);
    } on Object {
      return; // settings unavailable — silently abort.
    }
    if (!mounted) return;
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null || workspace.tabs.isEmpty) return;

    // When tab restore is disabled the saved tabs were only hydrated to avoid
    // an empty-canvas flash; nothing survives, so the reconcile below closes
    // every chip. When enabled, the survivors are the persisted tabs whose
    // file still exists. A tab the user is re-opening on the CLI this launch is
    // KEPT here (with its persisted per-tab session) — the CLI open focuses it
    // rather than opening a duplicate.
    final surviving = <WorkspaceTab>[];
    final dropped = <String>[];
    if (settings.restoreTabsOnLaunch) {
      for (final t in workspace.tabs) {
        final path = t.filePath;
        if (path == null) continue;
        if (File(path).existsSync()) {
          surviving.add(t);
        } else {
          dropped.add(path);
        }
      }
    }

    // Phone single-tab fallback (ARCHITECTURE.md §3.1.4).
    //
    // Phone widths always render a single-tab layout — the workspace at
    // quit may have hosted multiple tabs (the user roamed between a tablet
    // / desktop and the phone), but on phone we restore only the most
    // recent active tab and expose the rest through
    // [otherTabsFromLastSessionProvider] so the empty-canvas state can
    // surface them under "Other tabs from your last session".
    final plan = planWorkspaceRestore(
      deviceClass: ref.read(deviceClassProvider),
      surviving: surviving,
      activeTabId: workspace.activePane.activeTabId,
      activePaneId: workspace.activePaneId,
    );

    ref.read(otherTabsFromLastSessionProvider.notifier).set(plan.otherTabs);

    // The workspace document is the source of truth and was hydrated from
    // disk in bootstrap(), so every persisted tab already exists as a chip.
    // Reconcile it down to exactly the tabs to show: drop tabs whose file is
    // missing, the tabs deferred to "Other tabs from your last session" on
    // phone, and — when restore is disabled — all of them. This ALWAYS runs
    // (even when nothing survives) so a hydrated chip is never left orphaned
    // without a loaded source. Survivors' waveforms load LAZILY on first
    // activation (the listener below) so a multi-tab / split-pane restore
    // doesn't fan GPU-surface init across every tab at once and crash the
    // Windows/Intel GPU driver (docs/flutter-windows-gpu-crash-issue.md in the
    // Pro overlay).
    final wsNotifier = ref.wavecruxWorkspace;
    final survivingIds = plan.tabsToOpen.map((t) => t.id).toSet();
    for (final t in workspace.tabs) {
      if (!survivingIds.contains(t.id)) {
        await wsNotifier.closeTab(t.id);
      }
    }

    if (plan.tabsToOpen.isNotEmpty) {
      // Restore focus EXPLICITLY (Issue #1: "nothing has focus" after
      // restart). Two pieces have to land for focus to read correctly:
      //   1. workspace.activePaneId must equal the persisted active pane —
      //      the pane border, the focused-pane tab chip styling, and
      //      _togglePanelOnActivePane all depend on this.
      //   2. activeTabIdProvider must match the persisted active tab — falls
      //      back to the first tab in the persisted pane, then the first tab
      //      anywhere, when the original active tab was dropped during the
      //      file-exists filter above.
      final persistedActivePaneId = workspace.activePaneId;
      final reconciled = ref.read(workspaceProvider).value;
      if (reconciled != null &&
          reconciled.panes.any((p) => p.id == persistedActivePaneId)) {
        await wsNotifier.setActivePane(persistedActivePaneId);
      }
      final persistedActiveTabId = workspace.activePane.activeTabId;
      final TabId? resolvedActive;
      if (persistedActiveTabId != null &&
          survivingIds.contains(persistedActiveTabId)) {
        resolvedActive = persistedActiveTabId;
      } else {
        final firstInPane = plan.tabsToOpen.firstWhere(
          (t) => t.paneId == persistedActivePaneId,
          orElse: () => plan.tabsToOpen.first,
        );
        resolvedActive = firstInPane.id;
      }
      // Don't claim the global active tab when the user is opening files on the
      // CLI this launch: ViewerScreen activates the opened (or de-duplicated)
      // file after this reconcile completes, and a competing activate() here
      // would race it for focus. The per-pane up-front loads below still run so
      // a split-pane restore shows each pane's content.
      if (cliFilePaths.isEmpty) {
        ref.read(activeTabIdProvider.notifier).activate(resolvedActive);
      }

      // Deferred-load wiring.
      //
      // Load the active tab of every pane up front: a split-pane restore shows
      // both panes' content simultaneously, so each pane's visible tab must
      // load. That is at most one tab per pane (#panes ≤ 2 here), well under the
      // concurrent-GPU-init threshold that causes the Windows/Intel crash
      // (docs/flutter-windows-gpu-crash-issue.md). Every OTHER restored tab
      // loads lazily the first time it is activated, via the listener below.
      //
      // Installed AFTER the synchronous create + focus block above so the
      // transient per-tab activations emitted while creating the tabs don't
      // trigger eager loads.
      final restoredPaths = <TabId, String>{
        for (final t in plan.tabsToOpen) t.id: t.filePath!,
      };
      final activeTabPerPane = <TabId>{resolvedActive};
      for (final pane in workspace.panes) {
        final a = pane.activeTabId;
        if (a != null && survivingIds.contains(a)) activeTabPerPane.add(a);
      }
      // Crash-loop breaker / `--no-restore`: when this launch is suppressing
      // auto-load, keep the restored tab chips (nothing is lost or deleted) but
      // DON'T reopen any waveform — the load is the operation that can crash or
      // hang. Register the held-back load so the recovery banner's "Open last
      // session" action can perform it on demand. Otherwise load eagerly under
      // the restore guard so an interrupted load is detected next launch.
      if (ref.read(startupRecoveryProvider).suppressAutoLoad) {
        ref
            .read(startupRestoreResumeProvider.notifier)
            .registerResume(
              () => _beginGuardedRestore(activeTabPerPane, restoredPaths),
            );
      } else {
        _beginGuardedRestore(activeTabPerPane, restoredPaths);
      }
      _deferredLoadSub?.close();
      _deferredLoadSub = ref.listenManual<TabId>(
        activeTabIdProvider,
        (_, next) {
          // This listener owns ONLY the deferred *restored* tabs (those in
          // [restoredPaths]). Tabs opened during the session — File→Open, CLI
          // open, recent files, drag-drop — are loaded by their own open path,
          // which calls `waveformSourceProvider.notifier.openFile` immediately
          // after `wavecruxWorkspace.openFile` creates AND activates the tab.
          //
          // Without this guard, that activation re-enters [_ensureTabLoaded]
          // *before* the open path's `openFile` has run its synchronous
          // `state = AsyncLoading()` — so the `source.isLoading` check below
          // still sees `AsyncData(null)` and kicks off a SECOND concurrent load
          // on the same per-tab notifier. The two loads share the notifier's
          // `_loadToken` / `_pendingSource` / `_activeSource` and tear down each
          // other's in-flight wellen isolate, which can strand the surviving
          // load in `AsyncLoading` forever (the canvas spinner never clears).
          // Restricting the listener to restored tabs removes the trigger; new
          // tabs are loaded exactly once, by their opener.
          if (!restoredPaths.containsKey(next)) return;
          _ensureTabLoaded(next, restoredPaths[next]);
        },
      );
    }

    if (dropped.isNotEmpty && mounted) {
      // `_restoreFromWorkspace` is scheduled as a post-frame callback after
      // the FIRST frame. On a freshly-launched app the `Localizations`
      // delegate's lookup future may not yet have completed by that frame —
      // `Localizations.of<L10N>(context, L10N)` then returns null and the
      // pre-existing `L10N.of(context)!` non-null assertion crashes the
      // restore (observed under macOS integration tests). Defer the snackbar
      // through `addPostFrameCallback` retries until L10N has loaded; cap
      // the retry count so a permanently-broken delegate state can't loop
      // forever. After the cap we drop the snackbar — the missing files
      // are still surfaced via the empty-canvas "Other tabs from your last
      // session" section, so this is a non-fatal degradation.
      _scheduleDroppedFilesSnackbar(dropped, attemptsRemaining: 10);
    }
  }

  void _scheduleDroppedFilesSnackbar(
    List<String> dropped, {
    required int attemptsRemaining,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // CRITICAL: `_WaveCruxAppState.context` is the context of the
      // [_WaveCruxApp] widget itself, which is the PARENT of the
      // [MaterialApp.router] this build method returns. The
      // [Localizations] inherited widget that holds L10N is a DESCENDANT
      // of MaterialApp, so a `Localizations.of(this.context, L10N)` walks
      // UP past MaterialApp and finds nothing. We need a descendant
      // context. [rootScaffoldMessengerKey] is wired into MaterialApp via
      // the `scaffoldMessengerKey:` parameter, so its current context is
      // inside MaterialApp's Localizations scope. Use that for the L10N
      // lookup; the snackbar messenger is the same object.
      final messengerState = rootScaffoldMessengerKey.currentState;
      final messengerContext = messengerState?.context;
      final l10n = messengerContext == null
          ? null
          : Localizations.of<L10N>(messengerContext, L10N);
      if (l10n == null) {
        if (attemptsRemaining > 0) {
          _scheduleDroppedFilesSnackbar(
            dropped,
            attemptsRemaining: attemptsRemaining - 1,
          );
        }
        return;
      }
      final summary = dropped.length == 1
          ? l10n.workspaceRestoreDroppedSingle(dropped.first)
          : l10n.workspaceRestoreDroppedMany(dropped.length);
      // `l10n != null` above implies the messenger context resolved.
      final colorScheme = Theme.of(messengerContext!).colorScheme;
      messengerState?.showSnackBar(
        SnackBar(
          content: Text(
            summary,
            style: TextStyle(color: colorScheme.onErrorContainer),
          ),
          backgroundColor: colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
          duration: kCruxErrorSnackDuration,
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Fire-and-forget: lifecycle callbacks cannot await. The atomic
      // write inside WorkspaceService makes a partial-write impossible
      // even if the process is killed mid-rename.
      unawaited(_flushWorkspace());
    }
  }

  /// Monotonic counter stamped into each incoming-file navigation as the
  /// `req` query parameter. go_router's `go()` is a no-op when the target
  /// location equals the current one — and the share-sheet import writes
  /// every incoming file to `Documents/SharedImports/<name>`, so sharing a
  /// same-named file twice produces the IDENTICAL `?file=` location while the
  /// on-disk contents were replaced. The changing token keeps every share
  /// reaching [ViewerScreen]'s didUpdateWidget open path, which then detects
  /// the replacement and reloads. See [ViewerScreen.openRequest].
  int _incomingFileRequestCounter = 0;

  void _onIncomingFile(String filePath) {
    // Navigate to (or replace) the viewer screen with the new file.
    _incomingFileRequestCounter++;
    ref
        .read(routerProvider)
        .go(
          Uri(
            path: '/viewer',
            queryParameters: {
              'file': filePath,
              'req': '$_incomingFileRequestCounter',
            },
          ).toString(),
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_incomingFileSub.cancel());
    _deferredLoadSub?.close();
    super.dispose();
  }

  /// Loads the waveform (and per-tab session sidecar) for [tabId] if it is not
  /// already loaded or loading. The deferred-load path: restored tabs are
  /// created without loading, then loaded the first time they become active —
  /// so only the active tab's GPU-backed content is live at restore, which
  /// avoids the concurrent-GPU-init crash documented in
  /// `docs/flutter-windows-gpu-crash-issue.md`.
  ///
  /// [knownPath] is the restored tab's file path (captured at restore time);
  /// `null` falls back to a lookup in the current workspace.
  void _ensureTabLoaded(TabId tabId, String? knownPath) {
    if (!mounted || _deferredInFlight.contains(tabId)) return;
    var path = knownPath;
    if (path == null) {
      final tabs = ref.read(workspaceProvider).value?.tabs;
      if (tabs != null) {
        for (final t in tabs) {
          if (t.id == tabId) {
            path = t.filePath;
            break;
          }
        }
      }
    }
    if (path == null) return;
    final container = ref.read(tabContainerManagerProvider).containerFor(tabId);
    final source = container.read(waveformSourceProvider);
    // Already loaded or loading — nothing to defer-load (covers tabs opened
    // through the normal open flow, which loads itself).
    if (source.isLoading || source.value != null) return;
    _deferredInFlight.add(tabId);
    final service = ref.read(workspaceServiceProvider);
    final filePath = path;
    unawaited(
      () async {
        try {
          final sidecarPath = await service.sidecarPathFor(tabId.value);
          if (sidecarPath != null && File(sidecarPath).existsSync()) {
            await container
                .read(sessionProvider.notifier)
                .loadFromPath(sidecarPath);
            return;
          }
        } on Object {
          // Fall through to plain openFile.
        }
        try {
          await container
              .read(waveformSourceProvider.notifier)
              .openFile(filePath);
          // No sidecar, so this restored tab has a NEW session — the one
          // moment an organization's template may seed one. The sidecar
          // branch above returned, which is what makes this unambiguous.
          await seedOrgSessionTemplateLogging(container);
        } on Object {
          // Non-fatal — the tab survives in the list as an unloaded entry so
          // the user can see the failure (empty canvas) rather than losing the
          // tab silently.
        }
      }().whenComplete(() {
        _deferredInFlight.remove(tabId);
        // The *data* load completed — but that is NOT yet past the operation
        // that wedges startup on the Windows/Intel GPU path. The crash
        // documented in `docs/flutter-windows-gpu-crash-issue.md` fires on the
        // raster thread during D3D device / render-surface creation, which
        // happens while the just-loaded content (the waveform canvas plus any
        // restored Stage widgets) paints its first frame — i.e. AFTER this
        // future resolves. Disarming here would clear the sentinel before that
        // crash could happen, defeating the crash-loop breaker for the exact
        // class of crash it exists to catch (a "good" session whose render
        // wedges reload). Stand the guard down only once a content frame has
        // actually been rendered without crashing.
        _disarmRestoreGuardAfterContentFrame();
      }),
    );
  }

  /// Arms the restore-guard sentinel, then eagerly loads the active tab of each
  /// pane. The sentinel is cleared by [_disarmRestoreGuardOnce] once the first
  /// of those loads completes. Shared by the normal cold-start path and the
  /// recovery banner's "Open last session" action (which reopens a session that
  /// was held back after an interrupted previous launch).
  void _beginGuardedRestore(
    Set<TabId> activeTabPerPane,
    Map<TabId, String> restoredPaths,
  ) {
    _restoreGuardArmed = true;
    unawaited(_restoreGuard.arm());
    // Hold the Stage board's GPU-heavy content out of this restore's burst —
    // see [_disarmRestoreGuardAfterContentFrame] and the gate provider doc. The
    // gate releases on the same content frame the guard stands down.
    _setStageStartupGate(engaged: true);
    for (final id in activeTabPerPane) {
      _ensureTabLoaded(id, restoredPaths[id]);
    }
    // If no active tab actually started loading (unloadable/empty tabs), no
    // canvas restoration burst will form and the `whenComplete` release below
    // never fires — release the gate now so the Stage is not left deferred
    // behind a load that will never complete.
    if (_deferredInFlight.isEmpty) {
      _disarmRestoreGuardOnce();
      _setStageStartupGate(engaged: false);
    }
  }

  /// Disarms the restore guard once the restored content has actually been
  /// rendered, not merely once its data finished loading.
  ///
  /// The Windows/Intel GPU-surface crash this guard protects against
  /// (`docs/flutter-windows-gpu-crash-issue.md`) fires on the raster thread
  /// while the canvas / Stage widgets create their render surfaces — during the
  /// frame that paints the just-loaded content, after the load future resolved.
  /// We therefore wait for two frame boundaries before standing down: by the
  /// time the second post-frame callback runs, the first content frame has been
  /// built, laid out, and handed to (and drawn by) the raster thread. If that
  /// raster crashes the process, [_disarmRestoreGuardOnce] never runs, the
  /// sentinel survives, and the next launch recovers instead of re-wedging.
  ///
  /// `scheduleFrame()` guards the case where the completed load dirtied nothing
  /// (e.g. an already-current source), so a frame — and thus the callback — is
  /// guaranteed to fire.
  void _disarmRestoreGuardAfterContentFrame() {
    if (!_restoreGuardArmed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _disarmRestoreGuardOnce();
        // The active tab's restoration burst has now rendered; let the Stage
        // board build its content on the following frame, on its own.
        _setStageStartupGate(engaged: false);
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Engages or releases the Stage cold-start render gate
  /// ([stageStartupRenderGateProvider]), which keeps the Stage board's
  /// GPU-heavy content out of the restore burst. Mounted-guarded — a post-frame
  /// release that lands after teardown is a no-op.
  void _setStageStartupGate({required bool engaged}) {
    if (!mounted) return;
    final notifier = ref.read(stageStartupRenderGateProvider.notifier);
    engaged ? notifier.engage() : notifier.release();
  }

  /// Disarms the restore guard the first time a guarded restore reaches a
  /// rendered content frame. Idempotent and a no-op when the guard was never
  /// armed (e.g. lazy loads from the activation listener, or a suppressed
  /// launch).
  void _disarmRestoreGuardOnce() {
    if (!_restoreGuardArmed) return;
    _restoreGuardArmed = false;
    unawaited(_restoreGuard.disarm());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Keep the OS-level orientation lock in sync with the user's preference.
    // No-op on desktop and web; on mobile this calls
    // SystemChrome.setPreferredOrientations whenever the setting changes.
    ref.watch(orientationLockSyncProvider);

    // Read themeMode from AppSettingsNotifier so the choice is persisted.
    // Fall back to dark while settings are loading.
    final settings = ref.watch(appSettingsProvider).value;

    // Keep the console log sink attached (and its threshold synced to the
    // "Log verbosity" setting) for the app's lifetime. The ring buffer always
    // captures every level regardless; this only governs console output.
    ref.watch(logConsoleSinkProvider);
    final locale = _toLocale(settings?.locale ?? 'en');

    // Watch the active color theme so chrome extensions update when the user
    // changes theme packs. The preset's `brightness` is the source of truth
    // for Material light/dark — picking a light preset switches the entire
    // chrome to the light theme; picking dark/Solarized/etc. switches to
    // dark. The legacy AppThemeMode setting is no longer consulted here
    // because it created two competing levers for brightness and the user
    // expects the preset selection to "just work".
    final cruxColorTheme = ref.watch(cruxColorThemeProvider);
    final chromeExt = CruxThemeExtension(theme: cruxColorTheme);
    final themeMode = themeModeFromBrightness(cruxColorTheme);

    // Apply chrome-token overrides on top of the base WaveCrux theme so
    // presets that ship chrome tokens (solarized-dark, oscilloscope, …)
    // recolor the scaffold, app bar, panel surfaces, and tab bar.
    final lightTheme = applyChromeTokens(
      WavecruxTheme.light.copyWith(
        extensions: [const WavecruxColorExtension.light(), chromeExt],
      ),
      chromeExt,
    );
    final darkTheme = applyChromeTokens(
      WavecruxTheme.dark.copyWith(
        extensions: [const WavecruxColorExtension.dark(), chromeExt],
      ),
      chromeExt,
    );
    final hcLightTheme = applyChromeTokens(
      WavecruxTheme.highContrastLight.copyWith(
        extensions: [const WavecruxColorExtension.light(), chromeExt],
      ),
      chromeExt,
    );
    final hcDarkTheme = applyChromeTokens(
      WavecruxTheme.highContrastDark.copyWith(
        extensions: [const WavecruxColorExtension.dark(), chromeExt],
      ),
      chromeExt,
    );

    return MaterialApp.router(
      routerConfig: router,
      // Hide the debug banner — it covers toolbar action icons in the
      // top-right of the viewer chrome and adds no signal in this app.
      debugShowCheckedModeBanner: false,
      // Global messenger so the workspace lifecycle (missing-file recovery,
      // dropped-tab snackbar) can surface non-blocking feedback without
      // owning a BuildContext.
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: lightTheme,
      darkTheme: darkTheme,
      highContrastTheme: hcLightTheme,
      highContrastDarkTheme: hcDarkTheme,
      themeMode: themeMode,
      locale: locale,
      // Concatenate any overlay-contributed delegates (e.g. the Pro overlay's
      // L10NPro.delegate) with the open-core delegates. Without this seam,
      // any Pro widget calling `L10NPro.of(context)` crashes with a null
      // check on the Localizations lookup. Per ARCHITECTURE.md §10.
      localizationsDelegates: <LocalizationsDelegate<Object?>>[
        ...L10N.localizationsDelegates,
        ...ref.watch(extraLocalizationsDelegatesProvider),
      ],
      supportedLocales: L10N.supportedLocales,
      builder: (context, child) {
        // Localized string bundles for the two `crux_shared` packages that
        // render user-visible copy (the update banner and the beta issue
        // reporter dialog). Both need `L10N.of(context)`, which the root
        // container built by `bootstrap` cannot reach — so they are overridden
        // here, from inside `MaterialApp.builder`, where a Localizations scope
        // is in context. Device-class metrics drive the update banner's
        // touch-target / typography sizing, preserving the pre-migration
        // per-device banner sizing (formerly baked into the in-tree banner).
        final l10n = L10N.of(context);
        final deviceClass = ref.watch(deviceClassProvider);
        // Standalone or embedded. The marker the extension's index.html shim
        // sets is readable from the first frame, so this never defers and the
        // agreement gate below can decide synchronously.
        final editorHost = ref.watch(editorHostKindProvider);
        final bannerMetrics = MobileMetrics.of(context, deviceClass);
        // Windows/Linux frameless windows lose the OS drop shadow and the
        // drag-to-resize edges; VirtualWindowFrame restores both around the
        // whole app. Applied only where we draw our own chrome (never macOS,
        // web, or mobile). Wraps the outermost widget so resize edges sit
        // outside every other layer. See features/window_chrome/.
        final app =
            // Push the current MediaQuery size into displaySizeProvider
            // so deviceClassProvider stays live across window resizes / iPad
            // split-screen entries. Without this, the provider sticks at its
            // DeviceClass.desktop default for the entire run and every
            // width-based layout decision (force-hide-side-panes-on-phone,
            // status-bar chevrons, adaptive toolbar) breaks. Per
            // ARCHITECTURE.md §3.1.7.
            DisplaySizeFeed(
              child:
                  // Clamp OS text scaling to [0.85, 1.5] per ARCHITECTURE.md §3.1.8.13:
                  // accessibility scaling is honored, but the cap prevents 14 sp body
                  // text from being pushed to 28 sp+ which would break every chrome
                  // Row in the app. The 0.85 floor preserves layout density for users
                  // who shrink scaling.
                  MediaQuery.withClampedTextScaling(
                    minScaleFactor: 0.85,
                    maxScaleFactor: 1.5,
                    // App-wide scroll drag devices — includes `trackpad` (so
                    // two-finger scrolling works in every list) and excludes
                    // `mouse` (so a click-drift never steals a tap). See
                    // [kAppScrollDragDevices] for the full rationale. Placed
                    // above the Navigator so dropdown overlays inherit it too.
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: kAppScrollDragDevices,
                      ),
                      child: RepaintBoundary(
                        // Capture target for the Beta Issue Reporter's Flutter-layer
                        // screenshot. Wraps the routed app
                        // content so the reporter can grab a clean shot before the dialog
                        // mounts. The key is provider-exposed so the service and tests can
                        // resolve the RenderRepaintBoundary.
                        key: ref.watch(cruxAppScreenshotBoundaryKeyProvider),
                        child: ShortcutManagerWidget(
                          handlers: {
                            // Marker chords (M+a–z = set, ⇧M+a–z = jump) are
                            // handled globally — above the focus chain — so the
                            // bare-key shortcut and the command-palette entry
                            // arm the chord regardless of where focus sits
                            // (toolbar/menu chrome included). Marker chords have
                            // no native-menu key-equivalent, so there is no
                            // responder-chain fallback to disturb. The viewer's
                            // _handleShortcut cases (menu + in-viewer keyboard)
                            // delegate to the same coordinator; exactly one path
                            // fires per keystroke. See [MarkerChordCoordinator].
                            ShortcutAction.setMarker: () => ref
                                .read(markerChordCoordinatorProvider)
                                .arm(MarkerChordMode.set),
                            ShortcutAction.jumpToMarker: () => ref
                                .read(markerChordCoordinatorProvider)
                                .arm(MarkerChordMode.jump),
                            ShortcutAction.toggleTheme: () {
                              // A theme the organization locked is not the
                              // user's to flip (see the viewer's _toggleTheme).
                              if (ref.read(orgThemeLockedProvider)) {
                                final messenger =
                                    rootScaffoldMessengerKey.currentState;
                                final l10n = messenger == null
                                    ? null
                                    : Localizations.of<L10N>(
                                        messenger.context,
                                        L10N,
                                      );
                                if (l10n != null) {
                                  messenger!.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l10n.appearanceThemeLockedByPolicy,
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                              // Brightness is driven by the active color-theme preset, not the
                              // legacy AppThemeMode flag — flip between the default light and
                              // dark presets. See theme_brightness_toggle.dart.
                              toggleThemeBrightness(
                                ref.read(cruxColorThemeProvider.notifier),
                                ref.read(cruxColorThemeProvider),
                              );
                            },
                            // Cmd/Ctrl+Shift+P opens the command palette globally — handled
                            // at the [ShortcutManagerWidget] level (above any screen-specific
                            // [Actions] widget) so the shortcut works regardless of which
                            // route is active and regardless of where focus currently sits.
                            // We open the dialog with [rootNavigatorKey]'s context so it
                            // mounts above the live route. Once the user picks an action in
                            // the palette, [Actions.maybeInvoke] fires a
                            // [ShortcutActionIntent] from that same context — which walks up
                            // and lands on the active screen's [Actions] handler
                            // (ViewerScreen's `_handleShortcut`), so per-screen behavior
                            // continues to drive every dispatched action.
                            //
                            // openSettings and openDiagnostics are intentionally NOT handled
                            // here. ViewerScreen handles them via openAdaptive(), which
                            // shows a dialog on desktop and pushes a route on mobile.
                            // router.go('/settings') would bypass that logic and always do a
                            // full-screen navigation, which is wrong on desktop.
                            ShortcutAction.openCommandPalette: () {
                              final navContext =
                                  rootNavigatorKey.currentContext;
                              if (navContext == null) return;
                              unawaited(
                                CommandPaletteDialog.show(
                                  navContext,
                                  onAction: (action) {
                                    // The dialog has already requested pop by the time onAction
                                    // fires (see CommandPaletteDialog._execute), but primary
                                    // focus has not yet returned to the previous focus —
                                    // schedule the dispatch on the next frame so the focus
                                    // walk-up actually reaches the active screen's [Actions]
                                    // widget (ViewerScreen).
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          final focusCtx = WidgetsBinding
                                              .instance
                                              .focusManager
                                              .primaryFocus
                                              ?.context;
                                          final ctx =
                                              focusCtx ??
                                              rootNavigatorKey.currentContext;
                                          if (ctx == null) return;
                                          Actions.maybeInvoke<
                                            ShortcutActionIntent
                                          >(
                                            ctx,
                                            ShortcutActionIntent(action),
                                          );
                                        });
                                  },
                                ),
                              );
                            },
                          },
                          // The desktop menu bar wraps every route, not just
                          // the viewer. On Windows/Linux it draws the frameless
                          // window's title bar and caption buttons, so mounting
                          // it inside a screen meant navigating to /settings
                          // took the whole title bar — and the only way to
                          // close the window — with it. Menu items dispatch by
                          // firing a [ShortcutActionIntent] from the focused
                          // context, exactly as the command palette does, so
                          // they land on the active screen's [Actions] handler
                          // (ViewerScreen's `_handleShortcut`).
                          child: DesktopMenuBar(
                            onAction: (action) {
                              // Quit must work on EVERY route. The intent
                              // round-trip below lands on the active screen's
                              // Actions handler — which only the viewer
                              // mounts, so on the welcome route a menu Quit
                              // silently no-oped (the app could only be quit
                              // from the Dock). Handle it here, with the same
                              // semantics as the viewer dispatcher's case.
                              if (action == ShortcutAction.quit) {
                                exit(0);
                              }
                              final ctx =
                                  WidgetsBinding
                                      .instance
                                      .focusManager
                                      .primaryFocus
                                      ?.context ??
                                  rootNavigatorKey.currentContext;
                              if (ctx == null) return;
                              Actions.maybeInvoke<ShortcutActionIntent>(
                                ctx,
                                ShortcutActionIntent(action),
                              );
                            },
                            // Enforce the per-release hard beta build-expiry. Sits inside
                            // MaterialApp (so L10N.of resolves) but above the viewer routes:
                            // shows a dismissible banner while the build is expiring soon and a
                            // blocking modal once it has expired. A no-op for every dev build
                            // and every post-beta build (no BETA_EXPIRY injected). The gate
                            // re-checks on app resume. See features/beta_expiry/.
                            child: RecoveryBannerHost(
                              child: BetaExpiryGate(
                                // Nested inside BetaExpiryGate so an expired-beta
                                // blocking modal covers the update banner. The
                                // update banner shows above the viewer when a
                                // newer version is available. See features/update/.
                                //
                                // The nested ProviderScope binds the two shared
                                // string bundles above both the banner (which
                                // reads `cruxUpdateStringsProvider`) and the
                                // routed content's Navigator, so the beta issue
                                // reporter dialog pushed onto it resolves
                                // `cruxIssueReporterStringsProvider` too.
                                child: ProviderScope(
                                  overrides: [
                                    cruxUpdateStringsProvider.overrideWithValue(
                                      WavecruxUpdateStrings(l10n),
                                    ),
                                    cruxIssueReporterStringsProvider
                                        .overrideWithValue(
                                          WavecruxIssueReporterStrings(l10n),
                                        ),
                                    // The consent surfaces read this. The gate
                                    // is now *inside* the scope rather than
                                    // outside it: `crux_telemetry` renders its
                                    // own copy, so the disclosure needs the
                                    // WaveCrux ARB bundle the same way the
                                    // update banner does.
                                    cruxTelemetryStringsProvider
                                        .overrideWithValue(
                                          WavecruxTelemetryStrings(l10n),
                                        ),
                                  ],
                                  child: CruxEulaGate(
                                    // Not presented when an editor is hosting
                                    // us: inside the VSCode webview the thing
                                    // the user installed and agreed to is the
                                    // extension, and a contract in an editor
                                    // tab is the wrong surface for it. Every
                                    // standalone build, a plain browser tab
                                    // included, still presents it — there is
                                    // no other acceptance moment there.
                                    //
                                    // This suppresses the surface and records
                                    // nothing; it is not an acceptance.
                                    presentAgreement:
                                        editorHost == EditorHostKind.none,
                                    // OUTSIDE the telemetry disclosure, and
                                    // that ordering is not a preference. The
                                    // disclosure asks for consent to a term
                                    // the EULA itself defines (EULA 8), so
                                    // collecting it first would have the user
                                    // answering a question about a contract
                                    // they had not been shown. It is also the
                                    // only ordering under which the
                                    // EEA/UK/CH/KR opt-in default is
                                    // defensible.
                                    //
                                    // Inside the expiry gate, on the same rule
                                    // that puts the disclosure there: an
                                    // expired build has nothing to license.
                                    //
                                    // Not localized — see CruxEulaStrings. The
                                    // agreement is executed in English, so its
                                    // chrome stays English rather than
                                    // implying a translated contract exists.
                                    isPhoneLayout: deviceClass.isPhoneClass,
                                    metrics: CruxEulaMetrics(
                                      touchTarget: bannerMetrics.touchTarget,
                                      iconSize: bannerMetrics.iconSize,
                                      bodyFontSize: bannerMetrics.bodyText,
                                    ),
                                    child: TelemetryConsentGate(
                                      // Above the update banner so the one-time
                                      // disclosure is not competing for the top of
                                      // the window with an update prompt, and below
                                      // the expiry gate so an expired build's
                                      // blocking modal still wins. Renders its
                                      // child untouched for the whole beta — it
                                      // never mounts without the dev flag.
                                      //
                                      // The sheet-vs-dialog choice and the control
                                      // sizing are WaveCrux's own layout idiom,
                                      // handed to the shared widget rather than
                                      // re-derived inside it.
                                      isPhoneLayout: deviceClass.isPhoneClass,
                                      metrics: CruxTelemetryConsentMetrics(
                                        touchTarget: bannerMetrics.touchTarget,
                                        iconSize: bannerMetrics.iconSize,
                                        bodyFontSize: bannerMetrics.bodyText,
                                      ),
                                      child: UpdateBanner(
                                        metrics: CruxUpdateBannerMetrics(
                                          touchTarget:
                                              bannerMetrics.touchTarget,
                                          iconSize: bannerMetrics.iconSize,
                                          bodyFontSize: bannerMetrics.bodyText,
                                        ),
                                        child: _EagerStartupGate(
                                          child:
                                              child ?? const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            );
        // The whole window is a drop target for files on a native desktop
        // host — title bar and menu bar included, which is why it wraps
        // everything the builder draws rather than living in the viewer.
        // Renders `app` untouched on the web and on mobile.
        final droppable = DesktopFileDropTarget(child: app);
        if (!useCustomWindowChrome) return droppable;
        // Persist window geometry live (debounced) on every resize/move/maximize
        // so it survives even when the quit-time flush is cut off by a hard
        // window-close or a killed `flutter run` session — the same reason tab
        // state persists on mutation rather than only at quit. The quit flush in
        // _flushWorkspace remains a best-effort final capture on top of this.
        return buildWindowGeometryPersister(
          onChanged: (bounds) async {
            try {
              await ref.wavecruxWorkspace.setWindowBounds(bounds);
            } on Object {
              // Best-effort: a resize must never surface an error.
            }
          },
          child: buildWindowFrame(droppable),
        );
      },
    );
  }

  Locale _toLocale(String tag) => switch (tag) {
    'zh_CN' => const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
    'ja' => const Locale('ja'),
    'ko' => const Locale('ko'),
    _ => const Locale('en'),
  };
}

/// Holds a live subscription to every provider named by
/// [eagerStartupProvidersProvider], realizing overlay-contributed
/// side-effecting providers (e.g. the Pro licence-tier audit
/// listener) and keeping them alive for the whole app session.
///
/// The subscriptions are taken against the ROOT [ProviderContainer], not
/// through this widget's `ref`. Two reasons:
///
///   * A one-shot `read` is not enough. Riverpod disposes a provider
///     with no listener, so a `read`-realized listener can be torn down
///     again — dropping the `ref.listen` it installed in its constructor
///     — and the side effect then depends on some other widget happening
///     to watch the same provider. An audit trail silently stopping is
///     exactly that failure, and it is the kind nobody notices until
///     they need the log.
///   * Container-owned subscriptions are unaffected by widget lifecycle:
///     route changes, `deactivate`, and rebuild churn cannot pause them.
///
/// The hook list itself is `watch`ed, so a test (or a future runtime
/// re-registration) that swaps the list re-syncs the subscription set;
/// in production the override is applied once at boot and the list is
/// constant.
class _EagerStartupGate extends ConsumerStatefulWidget {
  const _EagerStartupGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_EagerStartupGate> createState() => _EagerStartupGateState();
}

class _EagerStartupGateState extends ConsumerState<_EagerStartupGate> {
  /// Live keep-alive subscriptions, one per entry of the hook list.
  final List<ProviderSubscription<Object?>> _subscriptions =
      <ProviderSubscription<Object?>>[];

  /// The hook list the current [_subscriptions] were built from, so a
  /// rebuild with an unchanged list is a no-op.
  List<EagerStartupHook>? _boundHooks;

  bool _sameAsBound(List<EagerStartupHook> hooks) {
    final bound = _boundHooks;
    if (bound == null || bound.length != hooks.length) return false;
    for (var i = 0; i < bound.length; i++) {
      if (!identical(bound[i], hooks[i])) return false;
    }
    return true;
  }

  void _bind(List<EagerStartupHook> hooks) {
    if (_sameAsBound(hooks)) return;
    for (final sub in _subscriptions) {
      sub.close();
    }
    _subscriptions.clear();
    final container = ProviderScope.containerOf(context, listen: false);
    for (final hook in hooks) {
      // The callback body is intentionally empty: the subscription
      // exists for its keep-alive effect, not to observe values.
      _subscriptions.add(container.listen<Object?>(hook, (_, _) {}));
    }
    _boundHooks = List<EagerStartupHook>.unmodifiable(hooks);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.close();
    }
    _subscriptions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bind(ref.watch(eagerStartupProvidersProvider));
    return widget.child;
  }
}
