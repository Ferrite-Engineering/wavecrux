// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_project/crux_project.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/core/documentation_launcher.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/core/initial_additional_file_paths_provider.dart';
import 'package:wavecrux/core/initial_streaming_provider.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/platform_utils.dart';
import 'package:wavecrux/core/providers/ai_advisor_panel_toggler_provider.dart';
import 'package:wavecrux/core/providers/collaboration_command_handler_provider.dart';
import 'package:wavecrux/core/providers/debug_advisor_panel_opener_provider.dart';
import 'package:wavecrux/core/providers/paid_tier_actions_installed_provider.dart';
import 'package:wavecrux/core/providers/pcap_to_vcd_dialog_opener_provider.dart';
import 'package:wavecrux/core/providers/sva_panel_toggler_provider.dart';
import 'package:wavecrux/core/providers/sva_results_loader_provider.dart';
import 'package:wavecrux/core/providers/system_dialog_provider.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/action_requirement.dart';
import 'package:wavecrux/core/shortcuts/action_requirement_label.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:wavecrux/core/shortcuts/shortcut_conflicts.dart';
import 'package:wavecrux/core/startup_reconcile_provider.dart';
import 'package:wavecrux/core/theme/theme_brightness_toggle.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/about/widgets/wavecrux_about_dialog.dart';
import 'package:wavecrux/features/ai/providers/explain_selection_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/annotation_walkthrough_provider.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_adoption_prompt.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/cursors/marker_chord_controller.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/marker_chord_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_picker_dialog.dart';
import 'package:wavecrux/features/diagnostics/copy_app_diagnostics_report.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/diagnostics/providers/render_pipeline_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/widgets/app_diagnostics_dialog.dart';
import 'package:wavecrux/features/diagnostics/widgets/pane_render_stats_popover.dart';
import 'package:wavecrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:wavecrux/features/pack/providers/pack_providers.dart';
import 'package:wavecrux/features/panes/providers/active_pane_id_provider.dart';
import 'package:wavecrux/features/panes/providers/split_pane_allowed_provider.dart';
import 'package:wavecrux/features/panes/widgets/wavecrux_pane_host.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/rtl_source/widgets/generate_stems_dialog.dart';
import 'package:wavecrux/features/rtl_source/widgets/import_verilator_ast_dialog.dart';
import 'package:wavecrux/features/search/widgets/signal_search_dialog.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/screens/settings_screen.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/statistics/widgets/live_statistics_strip.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/tools/widgets/generate_test_vcd_dialog.dart';
import 'package:wavecrux/features/viewer/providers/active_tab_panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/file_watcher_provider.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/gtkw_import_apply.dart';
import 'package:wavecrux/features/viewer/providers/landscape_hint_provider.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/mobile_memory_guard_provider.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/org_session_template_seed.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/streaming_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/widgets/activity_heatmap_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/bottom_dock.dart';
import 'package:wavecrux/features/viewer/widgets/dock_restore_bars.dart';
import 'package:wavecrux/features/viewer/widgets/fsdb_conversion_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/gtkw_import_result_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/large_file_warning_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/pattern_search_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/side_docks.dart';
import 'package:wavecrux/features/viewer/widgets/signal_removal_feedback.dart';
import 'package:wavecrux/features/viewer/widgets/status_bar.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_view_center.dart';
import 'package:wavecrux/features/workspace/commands/export_tab_command.dart';
import 'package:wavecrux/features/workspace/commands/new_workspace_command.dart';
import 'package:wavecrux/features/workspace/commands/open_workspace_command.dart';
import 'package:wavecrux/features/workspace/commands/reset_workspace_command.dart';
import 'package:wavecrux/features/workspace/commands/save_workspace_as_command.dart';
import 'package:wavecrux/features/workspace/providers/desktop_file_drop_provider.dart';
import 'package:wavecrux/features/workspace/providers/other_tabs_from_last_session_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_workspaces_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/features/workspace/widgets/wavecrux_empty_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/extra_bottom_dock_tabs_provider.dart';
import 'package:wavecrux/services/host_bridge/capability_nudge_provider.dart';
import 'package:wavecrux/services/mobile/mobile_memory_guard_service.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_failure.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_reader.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/platform/desktop_file_drop_router.dart';
import 'package:wavecrux/services/platform/security_scoped_bookmark_service.dart';
import 'package:wavecrux/services/policy/org_theme_application.dart';
import 'package:wavecrux/services/samples/sample_waveform_service.dart';
import 'package:wavecrux/services/session/crux_project_resolution.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';
import 'package:wavecrux/services/session/session_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/services/waveform/fsdb_conversion_service.dart';
import 'package:wavecrux/services/waveform/url_file_loader.dart';
import 'package:wavecrux/services/waveform/web_file_loader.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/layouts/pane_defaults.dart';
import 'package:wavecrux/shared/widgets/editor_host_boundary.dart';
import 'package:wavecrux/widgets/legacy_conversion_progress_dialog.dart';
import 'package:wavecrux/widgets/legacy_format_banner.dart';

part 'viewer_screen_file_io.dart';
part 'viewer_screen_tools.dart';
part 'viewer_screen_annotations.dart';
part 'viewer_screen_widgets.dart';
part 'viewer_screen_reactions.dart';
part 'viewer_screen_shortcuts.dart';

/// The main waveform viewer screen.
///
/// Hosts a per-tab `CruxIdeLayout` (shared `crux_ide_layout`) with four panes:
/// - left: signal hierarchy browser
/// - center: waveform canvas (with time ruler and signal list)
/// - right: value column
/// - bottom: transaction / decoder view (hidden by default)
///
/// A [ViewerToolbar] sits above the layout and a [StatusBar] below it.
///
/// Panel visibility is kept in sync with [PanelLayoutNotifier] so that
/// external callers (toolbar, menu, keyboard shortcuts) can toggle panes; the
/// shared widget owns the underlying `IdeController`, and a per-tab adapter
/// folds in the phone-width force-hide and the 120dp center floor.
///
/// Navigation keyboard shortcuts (WASD, arrows, Home/End, Z) are handled by a
/// scoped [Actions] widget. Session shortcuts (Ctrl+S, Ctrl+Shift+S) trigger
/// save/save-as flows.
///
/// [filePath] opens a waveform file directly; [sessionPath] loads a full
/// `.wavecrux` session (which references its own waveform file).

/// Type signature for the OS open-file picker used by [ViewerScreen]'s
/// open / compare / cocotb / RTL-source / GTKW-import flows.
///
/// `file_picker` 12 made `FilePicker.pickFiles` a static method, so it can no
/// longer be swapped via `FilePicker.platform = mock`. Every picking flow on
/// the screen routes through [openFilePickerProvider] so tests can inject a
/// stub — the same injectable-function pattern the workspace commands use.
typedef OpenFilePicker =
    Future<FilePickerResult?> Function({
      String? dialogTitle,
      FileType type,
      List<String>? allowedExtensions,
    });

/// Default [OpenFilePicker] backed by the static `FilePicker.pickFiles`.
Future<FilePickerResult?> defaultOpenFilePicker({
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) => FilePicker.pickFiles(
  dialogTitle: dialogTitle,
  type: type,
  allowedExtensions: allowedExtensions,
);

/// Provides the [OpenFilePicker] used by [ViewerScreen]. Override in tests to
/// avoid the native OS open dialog.
final openFilePickerProvider = Provider<OpenFilePicker>(
  (ref) => defaultOpenFilePicker,
);

/// Provides the [WebFileLoader] used by [ViewerScreen]'s web open flow.
/// Override in tests to inject synthetic browser bytes — `file_picker` 12's
/// static `pickFiles` is otherwise unmockable.
final webFileLoaderProvider = Provider<WebFileLoader>(
  (ref) => const WebFileLoader(),
);

class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({
    this.filePath,
    this.sessionPath,
    this.openRequest,
    super.key,
  });

  /// Absolute path to a waveform file to open, or null if none was provided.
  final String? filePath;

  /// Absolute path to a `.wavecrux` session file to load, or null if none.
  final String? sessionPath;

  /// Monotonic token distinguishing repeat open requests for the SAME
  /// [filePath] (the router's `req` query parameter, stamped by the
  /// incoming-file handler). go_router's `go()` is a no-op when the target
  /// location equals the current one, so without this token sharing the same
  /// file twice in a row would never reach [State.didUpdateWidget] — and the
  /// mobile share sheet imports every incoming file to
  /// `Documents/SharedImports/<name>`, so same-named shares produce the SAME
  /// path with fresh contents. A changed token re-runs the open even when the
  /// path is unchanged, letting the dedupe path detect the on-disk
  /// replacement and reload.
  final String? openRequest;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  // One IdeController per open tab, and one RepaintBoundary GlobalKey per
  // (host pane, tab) pair.
  //
  // The controller is keyed by tab alone: it carries no GlobalKey, so reusing
  // the same instance across panes is harmless, and `_syncTabControllerToState`
  // re-syncs it to whichever pane currently owns the tab.
  //
  // The RepaintBoundary key is keyed by (HOST pane, tab) — where the host pane
  // is the pane actually rendering the tab (PaneHost's `hostPaneId`), NOT the
  // tab's model `paneId`. Three things this buys us:
  //   1. Within one pane, distinct tab ids give distinct keys, so the same
  //      GlobalKey never appears in two slots of that pane's IndexedStack (the
  //      original "ancestor == this" assertion).
  //   2. Cross-pane drag: when a tab is dragged from pane A to pane B its host
  //      pane flips in a single frame and the content leaves A's IndexedStack
  //      and enters B's. A pane-agnostic key would make Flutter *migrate* that
  //      live element (the only GlobalKey in the content subtree) across the
  //      two IndexedStacks in one frame; the semantics layer then walks a stale
  //      parent→child geometry relationship during flushSemantics and trips the
  //      framework assertion `identical(childRenderObject, parentRenderObject)`
  //      (rendering/object.dart) plus a follow-on null-check crash. A per-host
  //      key gives B a *different* key, so the canvas tears down in A and
  //      builds fresh in B with no element migration.
  //   3. Sentinel double-render: a tab still carrying the `PaneId.primary`
  //      hydration sentinel renders in BOTH its own pane and the active pane
  //      (see `_PaneScope`'s filter). Keying by `tab.paneId` would hand both
  //      hosts the SAME key → "Multiple widgets used the same GlobalKey".
  //      Keying by host pane keeps the two renders distinct.
  // No user state is lost when the canvas rebuilds in the new host: scroll /
  // zoom / cursor live in the per-tab ProviderContainer (e.g.
  // `waveformScrollProvider`, which `WaveformViewCenter` re-seeds on init), not
  // in widget State.
  final Map<(PaneId, TabId), GlobalKey> _repaintKeys = {};

  GlobalKey _repaintKeyForTab(PaneId paneId, TabId id) =>
      _repaintKeys.putIfAbsent((paneId, id), GlobalKey.new);

  /// The RepaintBoundary key currently mounted for the active tab, resolved by
  /// the pane that actually *hosts* it so it matches the key [PaneHost] mounted
  /// in that pane's IndexedStack (the key is scoped per (host pane, tab) — see
  /// [_repaintKeyForTab]). Used by the image/PDF export path, which captures
  /// the active tab's canvas boundary.
  ///
  /// Host resolution mirrors [PaneHost]'s `_PaneScope` filter: a tab renders in
  /// its own `paneId` when that pane exists, and a tab still carrying the
  /// [PaneId.primary] hydration sentinel renders in the active pane. The active
  /// (focused) tab's visible boundary is therefore in its own pane, falling
  /// back to the active pane.
  GlobalKey _activeTabRepaintKey() {
    final activeId = ref.read(activeTabIdProvider);
    final workspace = ref.read(workspaceProvider).value;
    final activePaneId = workspace?.activePaneId ?? PaneId.primary;
    final panes = workspace?.panes ?? const <WorkspacePane>[];
    PaneId? tabPaneId;
    for (final t in ref.read(tabListProvider)) {
      if (t.id == activeId) {
        tabPaneId = t.paneId;
        break;
      }
    }
    final hostPaneId =
        (tabPaneId != null && panes.any((p) => p.id == tabPaneId))
        ? tabPaneId
        : activePaneId;
    return _repaintKeyForTab(hostPaneId, activeId);
  }

  TabId get _activeTabId => ref.read(activeTabIdProvider);

  /// The per-tab [ProviderContainer] for [id]. Panel state (and every other
  /// per-tab provider) is read/written through this so it targets the tab's
  /// own [panelLayoutProvider] override rather than the empty root scope.
  ProviderContainer _tabContainer(TabId id) =>
      ref.read(tabContainerManagerProvider).containerFor(id);

  ProviderContainer get _activeTabContainer => _tabContainer(_activeTabId);

  // Debounce state for the disabled-shortcut hint (see
  // [_showDisabledActionHint]). A held key auto-repeats at the platform rate,
  // so without this a user leaning on Home would queue dozens of identical
  // snackbars, each waiting out the previous one's display.
  ActionRequirement? _visibleDisabledHint;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
  _disabledHintController;

  static const Duration _kDisabledHintDuration = Duration(seconds: 3);

  /// Explains why a keyboard shortcut just did nothing.
  ///
  /// The dispatch guard in `_handleShortcut` refuses actions the descriptor
  /// table reports disabled, exactly as the menu greys them out. The menu item
  /// is self-explanatory; a key press is not, so the unmet [ActionRequirement]
  /// is surfaced here through the viewer's ordinary snackbar idiom — the same
  /// surface the individual handlers used before the guard existed.
  ///
  /// Storm control is stated as an invariant rather than a timer: *the same
  /// hint is never shown twice while it is already on screen*. Key auto-repeat
  /// therefore leaves the one snackbar up for its full duration instead of
  /// re-animating (or worse, queueing) a copy per repeat, and the state clears
  /// itself when the snackbar closes — however it closes. A *different*
  /// requirement replaces the visible hint immediately rather than queueing
  /// behind it, because it is the more recent answer to what the user just
  /// pressed.
  void _showDisabledActionHint(ActionRequirement requirement) {
    if (!mounted) return;
    if (_visibleDisabledHint == requirement &&
        _disabledHintController != null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(requirement.hint(L10N.of(context))),
        behavior: SnackBarBehavior.floating,
        duration: _kDisabledHintDuration,
      ),
    );
    _visibleDisabledHint = requirement;
    _disabledHintController = controller;
    unawaited(
      controller.closed.whenComplete(() {
        if (!identical(_disabledHintController, controller)) return;
        _disabledHintController = null;
        _visibleDisabledHint = null;
      }),
    );
  }

  // Two-key marker chords (`M` then a–z = set, `⇧M` then a–z = jump) are owned
  // by the root-scope [markerChordCoordinatorProvider] so the focus-independent
  // arming path (the app-level global handlers in WaveCruxApp) shares the same
  // chord state as the menu / in-viewer keyboard path here. Arming dispatches
  // through the coordinator (setMarker / jumpToMarker cases below); the
  // completing a–z key is captured in [_onKeyEvent] so it works regardless of
  // focus and is consumed before WASD/QE navigation can claim it.

  // Handles Escape and armed marker chords globally regardless of which widget
  // has focus. Registered on HardwareKeyboard so it fires even when the
  // waveform canvas (which uses Listener, not Focus) is the active target.
  bool _onKeyEvent(KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return false;
    // A dialog, menu or Settings on top owns the keyboard: Escape there must
    // not clear the cursors, nor a bare key pan or mark the waveform behind.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;

    // 1. An armed marker chord consumes the next key-down: a letter a–z
    //    completes it, anything else cancels it. Either way the key is swallowed
    //    so it cannot ALSO trigger its bare-key navigation binding. This must be
    //    checked before step 3 so e.g. `M` then `q` sets marker `q` rather than
    //    running prevTransition. The chord state is the root-scope coordinator,
    //    shared with the focus-independent arming below + the palette handler.
    if (isDown &&
        ref
            .read(markerChordCoordinatorProvider)
            .handleCompletionKey(event.logicalKey)) {
      return true;
    }

    // 2. Escape is the universal "clear my transient state" key. Bare Escape
    //    clears the cursors and the signal selection (the selection notifier's
    //    `clear()` no-ops when nothing is selected). SHIFT IS PART OF THE MATCH:
    //    ⇧Escape is [ShortcutAction.clearSecondaryCursor], "primary remains",
    //    and matching any modifier here swallowed it.
    //    Both Escape bindings are in [kGlobalKeyHandledActions] so the focus
    //    Shortcuts layer cannot dispatch them again against the state this
    //    branch just cleared; that doc carries the argument.
    if (isDown && event.logicalKey == LogicalKeyboardKey.escape) {
      final cursors = _activeTabContainer.read(cursorStateProvider.notifier);
      if (HardwareKeyboard.instance.isShiftPressed) {
        cursors.clearSecondary();
      } else {
        _activeTabContainer.read(selectedVariablesProvider.notifier).clear();
        cursors.clearAll();
      }
      return true; // consumed
    }

    // 3. Alt+arrow nudges the SELECTED annotation's anchor; add Shift to step
    //    to the adjacent transition instead of by one tick.
    //
    //    Handled here rather than registered as ShortcutActions on purpose.
    //    These are contextual on a canvas selection that exists for seconds at
    //    a time: four permanently-greyed rows in the menu, the overflow and the
    //    keymap editor would be dead weight in every session that never
    //    annotates, and the palette has no way to say "select a note first".
    //    The precedent is the inline annotation editor's own Enter/Escape
    //    bindings, which are likewise local to the thing being edited. Bare
    //    arrow keys keep their `panLeftSmall`/`panRightSmall` bindings — those
    //    activators require Alt to be *up*, so nothing here shadows them.
    if (isDown || isRepeat) {
      final nudged = _nudgeSelectedAnnotation(event.logicalKey);
      if (nudged) return true;
    }

    // 4. Bare-key navigation + marker arming ([kGlobalKeyHandledActions]).
    //    Dispatched here — NOT via the focus Shortcuts layer (which excludes
    //    this set) — so WASD/QE pan-zoom and the M/⇧M marker chords work
    //    regardless of where focus sits (toolbar/menu chrome included), and so
    //    step 1 always wins over a colliding bare key. Suppressed while a text
    //    field is focused so typing is never hijacked.
    if (_isTextInputFocused()) return false;
    final hw = HardwareKeyboard.instance;
    final action = globalKeyHandledActionFor(
      resolveShortcutConflicts(
        ref.read(shortcutBindingsProvider),
      ).effectiveBindings,
      logicalKey: event.logicalKey,
      isControlPressed: hw.isControlPressed,
      isShiftPressed: hw.isShiftPressed,
      isAltPressed: hw.isAltPressed,
      isMetaPressed: hw.isMetaPressed,
    );
    if (action == null) return false;
    // Marker chords arm on key-down only (a held `M` must not re-arm every
    // repeat); pan/zoom navigation may auto-repeat while the key is held.
    if (isRepeat &&
        (action == ShortcutAction.setMarker ||
            action == ShortcutAction.jumpToMarker)) {
      return true;
    }
    _handleShortcut(action);
    return true;
  }

  /// Whether a text-input widget ([EditableText]) currently holds focus, in
  /// which case bare-key shortcuts must not fire (the user is typing). Mirrors
  /// the guard in `_TextAwareShortcutManager` for the focus Shortcuts layer.
  static bool _isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    var found = false;
    focusContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  /// Undoes [_attachFileDrop]; held so [dispose] needn't touch `ref`.
  late final void Function() _detachFileDrop;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _detachFileDrop = _attachFileDrop();
    // Each tab's CruxIdeLayout owns its own IdeController (built in the shared
    // widget's State.initState, seeded with phone-width force-hide via the
    // adapter), so there is no controller to eagerly create here.

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final stdinMode = ref.read(initialStdinModeProvider);
      final pipePath = ref.read(initialPipePathProvider);
      final placeholderName = L10N
          .of(context)
          .viewerTabBarNewTabDefaultDisplayName;
      if (stdinMode) {
        // Streaming targets a dedicated tab so the synthetic empty-canvas
        // active id from [ActiveTabIdNotifier] never becomes the streaming
        // source's host container. Capture the new tab's id so the streaming
        // source binds to its container regardless of activation timing.
        final tabId = await ref.wavecruxWorkspace.newTab(
          displayName: placeholderName,
        );
        unawaited(
          _startStreaming(
            () => _tabContainer(
              tabId,
            ).read(streamingSourceProvider.notifier).startFromStdin(),
          ),
        );
      } else if (pipePath != null) {
        final tabId = await ref.wavecruxWorkspace.newTab(
          displayName: placeholderName,
        );
        unawaited(
          _startStreaming(
            () => _tabContainer(
              tabId,
            ).read(streamingSourceProvider.notifier).startFromPipe(pipePath),
          ),
        );
      } else if (widget.sessionPath != null) {
        unawaited(_loadSessionOrPack(widget.sessionPath!));
      } else if (widget.filePath != null) {
        unawaited(_openInitialCliFiles(widget.filePath!));
      }
    });
  }

  @override
  void didUpdateWidget(ViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A warm incoming file (share sheet / "Open With" while the app is already
    // running) re-navigates to `/viewer?file=<path>`. go_router reuses this
    // State, so `initState` does NOT run again — the open must happen here or
    // the shared file is silently dropped. Guard on a *changed*, non-null value
    // so an unrelated rebuild with the same param doesn't reopen. `initState`
    // still covers the cold-start (launch-with-file) case.
    if (widget.sessionPath != null &&
        widget.sessionPath != oldWidget.sessionPath) {
      unawaited(_loadSessionOrPack(widget.sessionPath!));
    } else if (widget.filePath != null &&
        (widget.filePath != oldWidget.filePath ||
            widget.openRequest != oldWidget.openRequest)) {
      // The openRequest clause re-runs the open when the SAME path is shared
      // again (see [ViewerScreen.openRequest]) — the on-disk contents may
      // have been replaced by the share-sheet import.
      unawaited(_openRuntimeFile(widget.filePath!));
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _detachFileDrop();
    // The marker chord controller + coordinator are root-scope providers; their
    // lifecycle (and the chord timeout) is owned by Riverpod, not this State.
    // Per-tab IdeControllers are owned and disposed by each tab's
    // CruxIdeLayout State when its tab content unmounts.
    super.dispose();
  }

  // ── streaming ─────────────────────────────────────────────────────────────────

  Future<void> _startStreaming(Future<void> Function() starter) async {
    try {
      await starter();
    } on Object catch (e) {
      if (mounted) {
        showCruxErrorSnack(context, e.toString());
      }
    }
  }

  void _stopStreaming() {
    _activeTabContainer.read(streamingSourceProvider.notifier).stop();
  }

  // ── session helpers ──────────────────────────────────────────────────────────

  // ── file watcher ─────────────────────────────────────────────────────────────

  // ── pane sync ────────────────────────────────────────────────────────────────

  // ── shortcut dispatch ────────────────────────────────────────────────────────

  // `_handleShortcut` — the exhaustive ShortcutAction switch — lives in the
  // part file `viewer_screen_shortcuts.dart` (extension
  // `_ViewerScreenShortcuts`), extracted so the highest-churn dispatch table
  // is reviewable on its own. Call sites use `_handleShortcut` — the
  // explicit receiver is REQUIRED for extension-member resolution, not
  // stylistic.

  // ── pane management (split-pane) ─────────────────────────────────

  // ── cocotb log correlation ──────────────────────────────────────────────────

  // ── RTL source annotation ─────────────────────────────────────────────────────

  // ── switching activity ────────────────────────────────────────────────────────

  // ── close file ────────────────────────────────────────────────────────────────

  // ── toggle theme ──────────────────────────────────────────────────────────────

  // ── next / previous transition ───────────────────────────────────────────────

  // ── named markers (M / ⇧M chords + removal) ─────────────────────────────────
  //
  // The chord arm/complete/apply logic lives in the root-scope
  // [markerChordCoordinatorProvider] so it is shared by the focus-independent
  // app-level global handlers (WaveCruxApp), the menu / in-viewer keyboard path
  // (the setMarker / jumpToMarker cases in [_handleShortcut]), and the global
  // completion handler ([_onKeyEvent]). Only marker *removal* — a dialog — stays
  // here.

  // ── command palette ───────────────────────────────────────────────────────────

  // ── waveform comparison / diff ────────────────────────────────────────────────

  // ── landscape hint ────────────────────────────────────────────────────────────

  // ── decoder picker ────────────────────────────────────────────────────────────

  // ── search ───────────────────────────────────────────────────────────────────

  // ── export ────────────────────────────────────────────────────────────────────

  // ── share bundle ──────────────────────────────────────────────────────────────

  // ── annotation walkthrough ────────────────────────────────────────────────────

  // ── GTKWave import ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref
      // Issue 2: per-pane panel layout. The panelLayoutProvider is
      // overridden per-pane in PaneContainerManager, so the listener that
      // syncs panel visibility → IdeController must run inside each pane's
      // scope. That wiring lives in [_PerTabPanelLayoutBridge], built by
      // [_buildTabContent]. The screen-level listener that previously
      // applied a single global state to all controllers has been removed.
      //
      // The file-watch listener is likewise NOT registered here: `fileWatcherProvider`
      // is overridden per-tab (it watches the per-tab `waveformSourceProvider`'s
      // path), so a root-scope `ref.listen` observes the empty root instance and
      // never fires. It now lives in the per-tab Consumer in [_buildTabContent],
      // mirroring the X-Trace / FSM listeners.
      ..listen<MemoryGuardState>(
        mobileMemoryGuardProvider,
        _onMemoryGuardStateChanged,
      )
      // Show the landscape-orientation hint snackbar once per session when
      // a file finishes loading in phone-portrait.
      ..listen<bool>(waveformIsLoadedProvider, (prev, next) {
        if (next && !(prev ?? false)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _maybeShowLandscapeHint(),
          );
        }
      })
      // (X-Trace and FSM auto-show-bottom-panel listeners moved into
      // [_buildTabContent]'s per-tab Consumer — Issue 16. Both providers
      // are per-tab, so listening at the screen-level root scope never
      // fires when the user activates the feature from the focused tab's
      // signal-list context menu.)
      // (Bidirectional RTL source nav moved into [_buildTabContent]'s per-tab
      // Consumer — `selectedVariablesProvider` is per-tab, so a root-scope
      // listener never fired. Same class of bug as the X-Trace / FSM / file-
      // watch listeners that were relocated there.)
      // Remove per-tab GlobalKeys when a tab is closed so we don't accumulate
      // stale entries. (Each tab's IdeController is owned and disposed by its
      // CruxIdeLayout State when the tab content unmounts.)
      ..listen<List<WavecruxTab>>(tabListProvider, (previous, next) {
        final removedIds = (previous ?? [])
            .map((t) => t.id)
            .toSet()
            .difference(next.map((t) => t.id).toSet());
        for (final id in removedIds) {
          // Keys are scoped per (pane, tab); a closed tab may have left
          // entries under more than one pane id, so drop every key for it.
          _repaintKeys.removeWhere((key, _) => key.$2 == id);
        }
      });

    final tcm = ref.watch(tabContainerManagerProvider);
    final tabs = ref.watch(tabListProvider);
    final activeTabId = ref.watch(activeTabIdProvider);
    // The per-pane IndexedStack lives inside [PaneHost]; the active-tab
    // index per pane is resolved there. The outer screen only needs to
    // detect the empty-workspace case to render the empty-canvas state.

    // Splitter hit zones widen on touch device classes per
    // ARCHITECTURE.md §3.1.8.6 — visible thickness stays at 1 dp; the hit area
    // grows to 24 dp so a finger can reliably grab and resize panes.
    final paneMetrics = MobileMetrics.of(
      context,
      ref.watch(deviceClassProvider),
    );
    // Per ARCHITECTURE.md §3.1.8.6: the splitter's visible bar uses the theme's
    // outline color at rest and primary color on hover/focus, so users get
    // clear "this is grabbable" feedback as the cursor enters the 32-dp hit
    // zone. Without the hover color the splitter looks dead and grabbing it
    // is a guess — especially on the iPad simulator with a mouse.
    final colorScheme = Theme.of(context).colorScheme;

    // On phone widths the IdeLayout side panes are force-hidden (per
    // ARCHITECTURE.md §3.1.8.6). The signal-tree content is still reachable via
    // a left Drawer (opened by the StatusBar's left chevron). The value column
    // has NO phone drawer: the non-modal overlay replaced the modal values endDrawer — a
    // scrim that froze the canvas behind it — with the non-modal
    // [InlineCursorValueOverlay] drawn directly on the canvas lanes. The bottom
    // panel toggle remains tied to [panelState] (a follow-up can route
    // it through showModalBottomSheet on phone).
    final isPhoneWidth =
        ref.watch(deviceClassProvider) == DeviceClass.phone ||
        ref.watch(deviceClassProvider) == DeviceClass.phoneLandscape;

    // The desktop menu bar is NOT mounted here: it wraps every route from
    // `MaterialApp.builder` so it survives navigation to /settings, and on
    // Windows/Linux it carries the frameless window's title bar with it. Its
    // items dispatch back into this screen through `ShortcutActionIntent`, the
    // same path the command palette uses.
    return Scaffold(
      // The phone signal-tree drawer is hosted by the screen-level Scaffold,
      // OUTSIDE the per-tab UncontrolledProviderScope that PaneHost wraps the
      // body in. SignalTreePanel (inside ActivityHeatmapOverlay) reads per-tab
      // providers (waveformSourceProvider, signalTreeProvider, …) which are
      // overridden per tab; without re-binding the drawer to the active tab's
      // container it reads the empty root scope and shows no signals on phone
      // (tablet/desktop dock the tree inside the tab scope, so they were fine).
      // Keyed by activeTabId so it rebinds when the active tab changes.
      drawer: isPhoneWidth
          ? Drawer(
              child: SafeArea(
                child: UncontrolledProviderScope(
                  // Namespaced so it never collides with the tab chip's
                  // `ValueKey(tab.id)` (see tab_drag_reorder regression).
                  key: ValueKey('tabScope.drawer:${activeTabId.value}'),
                  container: tcm.containerFor(activeTabId),
                  child: const ActivityHeatmapOverlay(),
                ),
              ),
            )
          : null,
      // Wrap chrome + body in SafeArea per ARCHITECTURE.md §3.1.8.2 so the
      // toolbar is not covered by the iPad system status bar (clock,
      // wifi, battery) in landscape, and so the status bar isn't lost
      // under the iPhone home indicator. Desktop platforms report zero
      // padding so this is a no-op there. SafeArea is placed outside the
      // IndexedStack so it also protects the ViewerTabBar above the stack.
      body: SafeArea(
        child: Actions(
          actions: {
            ShortcutActionIntent: CallbackAction<ShortcutActionIntent>(
              onInvoke: (intent) {
                _handleShortcut(intent.action);
                return null;
              },
            ),
            // No DismissIntent handler: Escape is owned by `_onKeyEvent` step
            // 2. The one that used to sit here caught an Escape that Flutter's
            // defaults were said to consume first — untrue once the binding
            // table claimed the key, leaving a third handler for it. Dialogs
            // are in their own FocusScope and dismiss without it.
          },
          // Keyboard regions (F6 / Shift+F6) and lost-focus recovery. Inside
          // the Actions above, so focus it restores is always within reach of
          // the screen's shortcut handler: focus stranded on a bare scope
          // after a native file dialog or a toolbar rebuild left Ctrl+,
          // and every other screen shortcut dead, and a screen reader silent.
          child: CruxFocusRegionScope(
            child: AbsorbPointer(
              absorbing: ref.watch(systemDialogInFlightProvider),
              child: Column(
                children: [
                  Expanded(
                    // Empty-canvas state OR multi-tab workspace.
                    //
                    // The toolbar lives at the screen level — exactly
                    // ONE ViewerToolbar regardless of pane count. It reads
                    // panel-state-driven toggle flags from the ACTIVE pane's
                    // container so the toolbar's "is transaction table on?"
                    // indicator follows the focused pane. Toggle handlers
                    // mutate the active pane's panelLayoutProvider via
                    // [_toggleOnActivePane], so clicking the toolbar's
                    // "Toggle Transaction Table" button affects only the
                    // focused pane (matching the chevron behavior).
                    child: _ScreenContent(
                      tabs: tabs,
                      activeTabId: activeTabId,
                      tcm: tcm,
                      paneMetrics: paneMetrics,
                      colorScheme: colorScheme,
                      isPhoneWidth: isPhoneWidth,
                      onOpenFile: _openFile,
                      onCloseFile: _closeFile,
                      onSaveSession: _saveSession,
                      onSaveSessionAs: _saveSessionAs,
                      onExport: _exportWaveform,
                      onSearch: _openSearch,
                      onAddDecoder: _openDecoderPicker,
                      onOpenWorkspace: _openWorkspace,
                      onOpenSample: _openSampleWaveform,
                      onOpenRecentFile: _openRecentFile,
                      onOpenRecentWorkspace: _openRecentWorkspace,
                      onOpenOtherTab: _openOtherTabFromLastSession,
                      onOpenFromBytes: kIsWeb ? _openBytesAndNavigate : null,
                      onShortcutAction: _handleShortcut,
                      onShowBottomPanelSheet: isPhoneWidth
                          ? _showBottomPanelSheet
                          : null,
                      buildTabContent: (context, tab) => _buildTabContent(
                        tab,
                        // Post-consolidation each tab belongs to exactly one
                        // pane, so the hosting pane is the tab's own pane.
                        hostPaneId: tab.paneId,
                        paneMetrics: paneMetrics,
                        isPhoneWidth: isPhoneWidth,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Per-tab content subtree (IdeLayout + status bar). Hosted by PaneHost.
  /// inside each pane's IndexedStack; the surrounding per-tab
  /// [UncontrolledProviderScope] is supplied by PaneHost itself.
  ///
  /// Wrapped in a [Consumer] so ref reads inside resolve against the per-pane
  /// [ProviderContainer] (where [panelLayoutProvider] is overridden
  /// — Issue 2) rather than the screen-level root container. The Consumer
  /// watches `panelLayoutProvider` + `deviceClassProvider` and feeds a fresh
  /// layout snapshot to this tab's `CruxIdeLayout`, which reconciles its
  /// `IdeController` on the change.
  ///
  /// **Issue 3:** the toolbar used to live inside this Consumer, which meant
  /// one toolbar rendered per pane. With split-pane that produced two
  /// stacked toolbars. The toolbar now lives at the screen level (built once
  /// in [build]) and reads from the active pane's container via
  /// [_ActivePaneScope].
  Widget _buildTabContent(
    WorkspaceTab tab, {
    required PaneId hostPaneId,
    required MobileMetrics paneMetrics,
    required bool isPhoneWidth,
  }) {
    return Consumer(
      builder: (context, paneRef, _) {
        // Per-tab panel state drives this tab's CruxIdeLayout: [paneRef] is
        // this tab's Consumer ref, so watching [panelLayoutProvider] resolves
        // to THIS tab's per-tab instance, and rebuilding feeds the shared
        // widget a fresh layout snapshot — a chevron/toolbar toggle or a
        // session restore re-syncs only this tab's IdeController. Phone-width
        // force-hide (ARCHITECTURE §3.1.7) is folded into the adapter below via
        // [deviceClassProvider]: at phone widths the IdeLayout's pane min sizes
        // exceed the available width, so every side / bottom pane is hidden
        // while the user's PanelLayoutState is preserved untouched and restores
        // when the window grows back to tablet/desktop.
        final panelState = paneRef.watch(panelLayoutProvider);
        final deviceClass = paneRef.watch(deviceClassProvider);
        final ideIsPhone =
            deviceClass == DeviceClass.phone ||
            deviceClass == DeviceClass.phoneLandscape;

        paneRef
          // Issue 16: auto-show the bottom panel when this tab's X-Trace
          // becomes active. Both `xTraceProvider` and `panelLayoutProvider`
          // are per-tab and resolve through [paneRef], so this docks THIS
          // tab's bottom pane.
          ..listen<bool>(
            xTraceProvider.select((s) => s.isActive),
            (_, isActive) {
              if (isActive) {
                paneRef
                    .read(panelLayoutProvider.notifier)
                    .revealDockTabPlaced(
                      kBottomDockTabXTrace,
                      kDockRegionBottom,
                    );
                // The transition into `isActive` is the trace succeeding, so
                // this counts panels that opened with something in them — the
                // context-menu action that started it can still end in "no
                // driver found", which never reaches here.
                _recordToolOpened('x_trace');
              }
            },
          )
          // Same for the FSM panel (also a per-tab provider).
          ..listen<bool>(
            fsmProvider.select((s) => s.isActive),
            (_, isActive) {
              if (isActive) {
                paneRef
                    .read(panelLayoutProvider.notifier)
                    .revealDockTabPlaced(kBottomDockTabFsm, kDockRegionBottom);
                _recordToolOpened('fsm');
              }
            },
          )
          // Auto-reload / file-deletion notifications. `fileWatcherProvider` is
          // per-tab (it watches this tab's loaded file), so the listener must
          // run inside the per-tab subtree — a screen-level root-scope listener
          // observes the empty root instance and never fires (same class of bug
          // the X-Trace / FSM listeners above were moved here to fix). Gated to
          // the active tab so a background tab's on-disk change does not drive a
          // reload/notification against the focused tab's container.
          ..listen<FileWatchState>(
            fileWatcherProvider,
            (prev, next) {
              if (tab.id != paneRef.read(activeTabIdProvider)) return;
              _onFileWatchStateChanged(prev, next);
            },
          )
          // Bidirectional RTL source nav: when the user picks a signal in the
          // active tab, jump the source panel to its source location.
          // `selectedVariablesProvider` is per-tab, so (like the X-Trace / FSM
          // / file-watch listeners above) it must be listened through [paneRef];
          // a screen-level root-scope listener never fires. Gated to the active
          // tab so a background tab's selection doesn't drive the focused tab.
          ..listen<Set<String>>(
            selectedVariablesProvider,
            (prev, next) {
              if (tab.id != paneRef.read(activeTabIdProvider)) return;
              _onSelectedVariablesChanged(prev, next);
            },
          )
          // Offer the slow-parse capability notice on
          // the duration the parse actually took.
          //
          // Listened through [paneRef] for the same reason as every listener
          // above it: `waveformSourceProvider` is per-tab, and a root-scope
          // listener observes the empty root instance and never fires.
          // Deliberately NOT gated to the active tab — a background tab that
          // just spent twelve seconds parsing is exactly the open worth
          // explaining, and `offerSlowParse` applies the once-per-session and
          // not-on-the-first-file rules itself.
          ..listen<AsyncValue<WaveformDataSource?>>(
            waveformSourceProvider,
            (prev, next) {
              final source = next.value;
              if (next.isLoading || source == null) return;
              // A rebuild that re-emits the same source is not a new parse.
              if (identical(prev?.value, source)) return;
              final measured = paneRef
                  .read(waveformSourceProvider.notifier)
                  .lastParseTime;
              if (measured == null) return;
              paneRef
                  .read(capabilityNudgeProvider.notifier)
                  .offerSlowParse(measured);
            },
          );

        // Size-aware side-pane defaults at both ends of the range: widened on
        // an ultrawide display (XR-glasses 32:9, ultrawide monitors) so deep
        // signal names / wide values stop truncating, narrowed below 800 dp
        // (foldable inner display in portrait, small tablet in portrait) so the
        // fixed 500 dp of panes stops starving the canvas. No effect on normal
        // screens, and a user-dragged size always wins.
        final paneDefaults = paneDefaultsForViewport(
          MediaQuery.sizeOf(context),
        );

        return Column(
          children: [
            // In-flow banner above the waveform area announcing
            // a fresh LXT/LXT2 → FST conversion. The widget itself short-
            // circuits to SizedBox.shrink when the suppress flag is on or
            // no fresh-conversion event is pending, so it costs nothing on
            // native-format opens.
            const LegacyFormatBanner(),
            // The one unsolicited capability notice a
            // session is allowed, raised on a MEASURED slow parse. Same
            // in-flow, self-shrinking contract as the banner above it — it
            // renders nothing outside an editor host, nothing on the first
            // file of an installation, and nothing at all after the session's
            // single nudge has been spent. It also carries the parse-completed
            // listener; see `editor_host_boundary.dart`.
            const CapabilityNudgeBanner(),
            // What to do with the notes a collaborative session just
            // left behind. Same in-flow, self-shrinking contract as the two
            // above — nothing is drawn outside the seconds after a session
            // ends, and nothing ever in a build with no collaboration service.
            const AnnotationAdoptionPrompt(),
            Expanded(
              // A window narrower/shorter than the panes need no longer
              // needs a floor + clip here: `CruxIdeLayout` clamps its own
              // pixel-sized regions to the space it is given (shrinking them
              // rather than starving the canvas and overflowing `panes`'
              // RenderFlex), and restores them as the window grows back.
              // Collapsed regions leave a slim restore bar along their
              // edge (JetBrains tool-window model) — the wrapper watches
              // this tab's panel state and reuses the docks' own entry
              // assemblers.
              child: WaveCruxDockRestoreBars(
                onLoadStems: _loadRtlStemsFile,
                child: CruxIdeLayout(
                  layout: _WaveCruxIdePanelLayout(
                    panelState,
                    isPhone: ideIsPhone,
                    defaultLeft: paneDefaults.left,
                    defaultRight: paneDefaults.right,
                  ),
                  sink: _WaveCruxIdePanelLayoutSink(
                    _tabContainer(
                      tab.id,
                    ).read(panelLayoutProvider.notifier),
                  ),
                  // Geometry only. The resizer colours come from the theme
                  // (its splitter tokens, else outlineVariant / primary);
                  // passing them here would override a user's choice.
                  theme: CruxIdeLayoutTheme(
                    resizerThickness: paneMetrics.splitterVisualWidth,
                    resizerHitTestThickness: paneMetrics.splitterHitWidth,
                  ),
                  leftMinSize: PaneSize.pixel(150),
                  rightMinSize: PaneSize.pixel(150),
                  bottomMinSize: PaneSize.pixel(80),
                  centerMinSize: PaneSize.pixel(120),
                  // Left dock: Signals (pinned) · Diff (on-demand). The
                  // signal-tree ⇄ diff-summary swap became tabs.
                  leftBuilder: (context, _) => const WaveCruxLeftDock(),
                  centerBuilder: (context, _) => _FocusableWaveformPane(
                    child: _PaneScopedCanvas(
                      paneId: tab.paneId,
                      repaintKey: _repaintKeyForTab(hostPaneId, tab.id),
                      child: WaveformViewCenter(
                        onCompareWith: _compareWaveforms,
                      ),
                    ),
                  ),
                  // Right dock: Values (pinned) · RTL Source · Cross-Probe.
                  // The 3-deep priority chain became tabs.
                  rightBuilder: (context, _) => WaveCruxRightDock(
                    onLoadStems: _loadRtlStemsFile,
                  ),
                  // The VSCode-style bottom dock: every candidate surface is
                  // a tab (Transactions pinned; Stage ×N dynamic; analyses
                  // on-demand). The phone sheet hosts the same entries via
                  // [WaveCruxBottomDockSheet] — the priority chain is gone.
                  bottomBuilder: (context, _) => const WaveCruxBottomDock(),
                ),
              ),
            ),
            _TabBottomChrome(
              paneId: tab.paneId,
              showStatisticsStrip:
                  paneRef.watch(deviceClassProvider) == DeviceClass.desktop,
              onShowBottomPanelSheet: isPhoneWidth
                  ? _showBottomPanelSheet
                  : null,
            ),
          ],
        );
      },
    );
  }

  /// Routes a panel-visibility mutation to whichever **tab** currently has
  /// focus. Used by `_handleShortcut`'s toggle dispatchers so that keyboard
  /// shortcuts, menu items, and the toolbar hit ONLY the active tab's panel
  /// state, matching the chevron behavior in that tab's status bar.
  void _togglePanelOnActiveTab(
    void Function(PanelLayoutNotifier notifier) apply,
  ) {
    apply(_activeTabContainer.read(panelLayoutProvider.notifier));
  }
}
