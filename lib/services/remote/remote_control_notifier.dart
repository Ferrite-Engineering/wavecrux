// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show stderr, stdout;
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/policy/org_server_policy.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/remote/wcp_server.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

part 'remote_control_notifier.g.dart';
part 'wcp_displayed_items.dart';

/// The same logger the WCP server reports its own faults on.
final _log = Logger('wavecrux.wcp');

// ── SelectedSignal ─────────────────────────────────────────────────────────────

/// Tracks the signal currently focused by the WCP `focus_item` command.
@Riverpod(keepAlive: true)
class SelectedSignalNotifier extends _$SelectedSignalNotifier {
  @override
  String? build() => null;

  // A setter cannot be named 'selection' because _$SelectedSignalNotifier
  // already exposes 'state'; a named method is clearer at call sites.
  // ignore: use_setters_to_change_properties
  void select(String? signalRef) => state = signalRef;
}

// ── State ─────────────────────────────────────────────────────────────────────

/// Runtime state of the WCP remote control server.
@immutable
class RemoteControlState {
  const RemoteControlState({
    this.isRunning = false,
    this.port = WcpServer.defaultPort,
    this.connectedClients = 0,
  });

  final bool isRunning;
  final int port;
  final int connectedClients;

  RemoteControlState copyWith({
    bool? isRunning,
    int? port,
    int? connectedClients,
  }) => RemoteControlState(
    isRunning: isRunning ?? this.isRunning,
    port: port ?? this.port,
    connectedClients: connectedClients ?? this.connectedClients,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteControlState &&
          other.isRunning == isRunning &&
          other.port == port &&
          other.connectedClients == connectedClients;

  @override
  int get hashCode => Object.hash(isRunning, port, connectedClients);

  @override
  String toString() =>
      'RemoteControlState('
      'isRunning: $isRunning, port: $port, clients: $connectedClients)';
}

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Manages the lifecycle of the WCP (Waveform Control Protocol) server.
///
/// Call [startServer] to bind to a TCP port and begin accepting connections.
/// Each connected client can send WCP commands via null-byte-delimited JSON
/// messages to control the waveform viewer (load files, add items, set
/// cursors, query values, etc.).
///
/// Kept alive across navigations. Call [stopServer] to release all sockets.
@Riverpod(keepAlive: true)
class RemoteControlNotifier extends _$RemoteControlNotifier {
  WcpServer? _server;
  final _registry = _DisplayedItemRegistry();

  @override
  RemoteControlState build() => const RemoteControlState();

  // ── per-tab routing ──────────────────────────────────────────────────────────

  /// The [ProviderContainer] of the focused tab.
  ///
  /// This notifier is a process-wide `keepAlive` server living at the root
  /// container, but the providers WCP commands mutate and query —
  /// `waveformSourceProvider`, `signalGroupsProvider`, `cursorStateProvider`,
  /// `markerStateProvider`, `navigationProvider`, `timeMapperProvider` — are all
  /// per-tab (overridden in `wavecruxTabOverrides`). Reading them from this root
  /// scope would target the empty root container instead of the tab the user is
  /// looking at, so every WCP mutation/query must go through the active tab's
  /// container. (Same per-tab scope-leak class as issue #44; mirrors the
  /// active-tab resolution in `mobileMemoryGuardProvider`.)
  ///
  /// `selectedSignalProvider` and `workspaceProvider` are intentionally NOT
  /// routed here — the former is the WCP server's own global focus state and the
  /// latter is the app-level workspace model.
  ProviderContainer get _activeTab => ref
      .read(tabContainerManagerProvider)
      .containerFor(
        ref.read(activeTabIdProvider),
      );

  // ── lifecycle ──────────────────────────────────────────────────────────────

  /// Starts the WCP server on [port].
  ///
  /// Stops any previously running server first. Returns an error string on
  /// failure (e.g. port already in use), or `null` on success.
  Future<String?> startServer(int port) async {
    if (state.isRunning) await stopServer();

    final server = WcpServer(
      onCommand: _handleCommand,
      onClientCountChanged: (count) {
        state = state.copyWith(connectedClients: count);
      },
    );

    try {
      await server.start(port);
      _server = server;
      state = RemoteControlState(isRunning: true, port: server.port ?? port);
      return null;
    } on Object catch (e) {
      return e.toString();
    }
  }

  /// Stops the server and disconnects all clients.
  Future<void> stopServer() async {
    await _server?.stop();
    _server = null;
    state = const RemoteControlState();
  }

  // ── command dispatch ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _handleCommand(
    String command,
    Map<String, dynamic> data,
  ) async {
    switch (command) {
      case 'load':
        return await _handleLoad(data);
      case 'reload':
        return await _handleReload();
      case 'clear':
        return await _handleClear();
      case 'shutdown':
        return await _handleShutdown();
      case 'add_items':
        return await _handleAddItems(data);
      case 'remove_items':
        return await _handleRemoveItems(data);
      case 'get_item_list':
        return await _handleGetItemList();
      case 'get_item_info':
        return await _handleGetItemInfo(data);
      case 'set_cursor':
        return await _handleSetCursor(data);
      case 'set_viewport_range':
        return await _handleSetViewportRange(data);
      case 'set_viewport_to':
        return await _handleSetViewportTo(data);
      case 'zoom_to_fit':
        return await _handleZoomToFit();
      case 'set_item_color':
        return await _handleSetItemColor(data);
      case 'focus_item':
        return await _handleFocusItem(data);
      case 'add_markers':
        return await _handleAddMarkers(data);
      case 'wavecrux.getValueAt':
        return await _handleGetValueAt(data);
      case 'wavecrux.getHierarchy':
        return await _handleGetHierarchy();
      case 'wavecrux.getState':
        return await _handleGetState();
      case 'wavecrux.setActiveTab':
        return await _handleSetActiveTab(data);
      default:
        throw WcpException('Unknown command: $command', code: 2);
    }
  }

  // ── handlers ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _handleLoad(Map<String, dynamic> data) async {
    final source = data['source'];
    if (source is! String || source.isEmpty) {
      throw const WcpException('"source" must be a non-empty string', code: 3);
    }
    final tab = await _tabForLoad(source);
    await tab.read(waveformSourceProvider.notifier).openFile(source);
    final sourceAsync = tab.read(waveformSourceProvider);
    if (sourceAsync is AsyncError) {
      throw WcpException('File load failed: ${sourceAsync.error}', code: 4);
    }
    _server?.broadcastEvent('waveforms_loaded', {'source': source});
    return null;
  }

  /// The tab a `load` lands in: the active tab, or a new one opened for
  /// [source] when the workspace has no tab at all. With no tab open the
  /// active id is a synthetic fallback that no pane displays, so a file
  /// loaded there is never laid out and the viewport commands that follow
  /// have nothing to act on.
  Future<ProviderContainer> _tabForLoad(String source) async {
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null || workspace.tabs.isNotEmpty) return _activeTab;
    final tabId = await ref.wavecruxWorkspace.openFile(source);
    return ref.read(tabContainerManagerProvider).containerFor(tabId);
  }

  /// Throws unless a viewport command on [tab] can take effect: a waveform
  /// must be loaded and laid out in a pane. Without this the command would be
  /// acknowledged and change nothing.
  ///
  /// The canvas initialises the time mapper a frame or more after the source
  /// arrives, so a command sent straight after `load` waits a bounded moment
  /// for it before giving up.
  Future<void> _requireViewport(ProviderContainer tab) async {
    if (tab.read(waveformSourceProvider).value == null) {
      throw const WcpException('No waveform file loaded', code: 5);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    bool laidOut() => tab.read(timeMapperProvider.notifier).isLaidOut;
    while (!laidOut() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (!laidOut()) {
      throw const WcpException(
        'The waveform is not displayed in a pane yet, so the viewport '
        'cannot change',
        code: 5,
      );
    }
  }

  /// Re-reads the current file and keeps the view: displayed items, cursors,
  /// markers and zoom survive, each item resolved against the reloaded
  /// hierarchy by path and dropped only if it no longer exists. This is the
  /// file watcher's auto-reload path, so a script's reload and an on-disk
  /// change behave the same, and item ids stay valid across it.
  Future<Map<String, dynamic>?> _handleReload() async {
    final tab = _activeTab;
    final path = tab.read(waveformSourceProvider.notifier).currentFilePath;
    if (path == null || path.isEmpty) {
      throw const WcpException('No waveform file loaded', code: 5);
    }
    await tab.read(sessionProvider.notifier).reloadCurrentFile();
    final sourceAsync = tab.read(waveformSourceProvider);
    if (sourceAsync is AsyncError) {
      throw WcpException('Reload failed: ${sourceAsync.error}', code: 4);
    }
    _server?.broadcastEvent('waveforms_loaded', {'source': path});
    return null;
  }

  Future<Map<String, dynamic>?> _handleClear() async {
    _activeTab.read(signalGroupsProvider.notifier).clear();
    _registry.clear();
    return null;
  }

  Future<Map<String, dynamic>?> _handleShutdown() async {
    // Send the response first, then stop the server after a brief delay.
    Future.delayed(const Duration(milliseconds: 50), stopServer);
    return null;
  }

  /// Adds variables (or all variables in a scope) to the viewer.
  ///
  /// Accepts the spec parameter name `items` plus the legacy aliases `paths`
  /// and `item_path`. Each entry resolves to either an exact variable (by
  /// signal ref or full path) or a scope: a scope contributes its direct
  /// variables, or its full subtree when `recursive` is true.
  ///
  /// Resolution is atomic: every entry is resolved before any state is
  /// mutated, so a failure part-way through leaves nothing registered or
  /// displayed.
  Future<Map<String, dynamic>?> _handleAddItems(
    Map<String, dynamic> data,
  ) async {
    final tab = _activeTab;
    final source = tab.read(waveformSourceProvider).value;
    if (source == null) {
      throw const WcpException('No waveform file loaded', code: 5);
    }

    final List<String> paths;
    final rawItems = data['items'] ?? data['paths'];
    final rawPath = data['item_path'];
    if (rawItems is List) {
      final typed = rawItems.whereType<String>().toList();
      if (typed.length != rawItems.length) {
        throw const WcpException(
          'All entries in "items" must be strings',
          code: 3,
        );
      }
      paths = typed;
    } else if (rawPath is String && rawPath.isNotEmpty) {
      paths = [rawPath];
    } else {
      throw const WcpException(
        '"items", "paths", or "item_path" is required',
        code: 3,
      );
    }

    final recursive = data['recursive'] == true;
    final allVars = source.findVariables(const SignalFilter());

    final toAdd = <Variable>[];
    for (final path in paths) {
      toAdd.addAll(_resolveItemPath(path, allVars, recursive: recursive));
    }

    final before = {
      for (final e in _signalEntries(tab.read(signalGroupsProvider).entries))
        e.id,
    };
    if (toAdd.isNotEmpty) {
      tab.read(signalGroupsProvider.notifier).addSignals(toAdd);
    }
    // Each variable added is a new row with its own entry id, so a signal
    // that is already displayed gets a second item rather than sharing the
    // first row's. The organisation's signal groups may have placed the new
    // rows inside groups, so they are matched by ref, not by position.
    final newRows = [
      for (final e in _signalEntries(tab.read(signalGroupsProvider).entries))
        if (!before.contains(e.id)) e,
    ];
    final addedItems = <Map<String, dynamic>>[];
    for (final v in toAdd) {
      final rowIndex = newRows.indexWhere((e) => e.signalRef == v.signalRef);
      if (rowIndex < 0) continue;
      final row = newRows.removeAt(rowIndex);
      final item = _registry.register(
        row.id,
        v.name,
        v.fullPath,
        type: _kTypeVariable,
      );
      addedItems.add(_itemToJson(item));
    }
    return {'items': addedItems};
  }

  /// Resolves one `add_items` entry to the variables it denotes, throwing
  /// [WcpException] code 6 when nothing matches. Never mutates state.
  List<Variable> _resolveItemPath(
    String path,
    List<Variable> allVars, {
    required bool recursive,
  }) {
    for (final v in allVars) {
      if (v.signalRef == path || v.fullPath == path) return [v];
    }
    final prefix = '$path.';
    final scopeVars = allVars.where((v) {
      if (!v.fullPath.startsWith(prefix)) return false;
      if (recursive) return true;
      return !v.fullPath.substring(prefix.length).contains('.');
    }).toList();
    if (scopeVars.isEmpty) {
      throw WcpException('Item not found: $path', code: 6);
    }
    return scopeVars;
  }

  Future<Map<String, dynamic>?> _handleRemoveItems(
    Map<String, dynamic> data,
  ) async {
    final rawIds = data['ids'];
    if (rawIds is! List) {
      throw const WcpException('"ids" must be a list', code: 3);
    }
    final ids = rawIds.whereType<int>().toList();
    final tab = _activeTab;

    final rowIds = <String>{};
    for (final id in ids) {
      final item = _registry.byId(id);
      if (item == null) continue; // silently ignore unknown IDs
      if (item.type == _kTypeMarker) {
        tab
            .read(markerStateProvider.notifier)
            .removeMarker(_markerLetter(item));
      } else {
        rowIds.add(item.key);
      }
      _registry.remove(id);
    }

    // One pass over the whole tree, so rows inside groups go too.
    if (rowIds.isNotEmpty) {
      tab
          .read(signalGroupsProvider.notifier)
          .removeSignalsWhere((e) => rowIds.contains(e.id));
    }
    return null;
  }

  Future<Map<String, dynamic>?> _handleGetItemList() async {
    _syncRegistryWithDisplayedState(_activeTab);
    return {'items': _registry.allItems.map(_itemToJson).toList()};
  }

  /// Reconciles the item registry with the tab's real displayed state so
  /// `get_item_list` enumerates what the user actually sees: signals added
  /// through the UI receive ids on first enumeration, and registry entries
  /// whose signal or marker is no longer displayed are dropped. Ids stay
  /// monotonic and are never reused, so a removed-then-re-added item gets a
  /// fresh id.
  void _syncRegistryWithDisplayedState(ProviderContainer tab) {
    final rows = _signalEntries(tab.read(signalGroupsProvider).entries);
    final markers = tab.read(markerStateProvider).markers;
    final live = <String>{
      for (final row in rows) row.id,
      for (final name in markers.keys) '$_kMarkerRefPrefix$name',
    };
    for (final item in _registry.allItems) {
      if (!live.contains(item.key)) _registry.remove(item.id);
    }

    final source = tab.read(waveformSourceProvider).value;
    List<Variable>? allVars;
    for (final row in rows) {
      if (_registry.idFor(row.id) != null) continue;
      final ref = row.signalRef;
      allVars ??=
          source?.findVariables(const SignalFilter()) ?? const <Variable>[];
      Variable? match;
      for (final v in allVars) {
        if (v.signalRef == ref) {
          match = v;
          break;
        }
      }
      _registry.register(
        row.id,
        match?.name ?? row.displayName ?? ref ?? row.id,
        match?.fullPath ?? row.signalPath ?? ref ?? row.id,
        type: _kTypeVariable,
      );
    }
    for (final name in markers.keys) {
      final ref = '$_kMarkerRefPrefix$name';
      if (_registry.idFor(ref) == null) {
        _registry.register(ref, name, ref, type: _kTypeMarker);
      }
    }
  }

  Future<Map<String, dynamic>?> _handleGetItemInfo(
    Map<String, dynamic> data,
  ) async {
    final rawIds = data['ids'];
    if (rawIds is! List) {
      throw const WcpException('"ids" must be a list', code: 3);
    }
    final ids = rawIds.whereType<int>().toList();
    final items = <Map<String, dynamic>>[];
    for (final id in ids) {
      final item = _registry.byId(id);
      if (item == null) throw WcpException('Item not found: $id', code: 6);
      items.add(_itemToJson(item));
    }
    return {'items': items};
  }

  Map<String, dynamic> _itemToJson(_WcpItem item) => {
    'id': item.id,
    'name': item.name,
    'path': item.path,
    'type': item.type,
  };

  Future<Map<String, dynamic>?> _handleSetCursor(
    Map<String, dynamic> data,
  ) async {
    final timestamp = data['timestamp'];
    if (timestamp is! int) {
      throw const WcpException('"timestamp" must be an integer', code: 3);
    }
    _activeTab.read(cursorStateProvider.notifier).placePrimary(timestamp);
    return null;
  }

  Future<Map<String, dynamic>?> _handleSetViewportRange(
    Map<String, dynamic> data,
  ) async {
    final start = data['start'];
    final end = data['end'];
    if (start is! int || end is! int) {
      throw const WcpException('"start" and "end" must be integers', code: 3);
    }
    final tab = _activeTab;
    await _requireViewport(tab);
    tab.read(navigationProvider.notifier).fitRange(start, end);
    return null;
  }

  Future<Map<String, dynamic>?> _handleSetViewportTo(
    Map<String, dynamic> data,
  ) async {
    final timestamp = data['timestamp'];
    if (timestamp is! int) {
      throw const WcpException('"timestamp" must be an integer', code: 3);
    }
    final tab = _activeTab;
    await _requireViewport(tab);
    tab.read(navigationProvider.notifier).jumpToTime(timestamp);
    return null;
  }

  Future<Map<String, dynamic>?> _handleZoomToFit() async {
    final tab = _activeTab;
    await _requireViewport(tab);
    tab.read(navigationProvider.notifier).fitAll();
    return null;
  }

  Future<Map<String, dynamic>?> _handleSetItemColor(
    Map<String, dynamic> data,
  ) async {
    final id = data['id'];
    final rawColor = data['color'];
    if (id is! int) {
      throw const WcpException('"id" must be an integer', code: 3);
    }
    if (rawColor is! String) {
      throw const WcpException(
        '"color" must be a hex color or a color name',
        code: 3,
      );
    }
    final color = _parseColor(rawColor);
    if (color == null) {
      throw WcpException('Invalid color: $rawColor', code: 3);
    }
    final item = _registry.byId(id);
    if (item == null) throw WcpException('Item not found: $id', code: 6);

    final tab = _activeTab;
    final entries = tab.read(signalGroupsProvider).entries;
    final idx = item.type == _kTypeVariable
        ? entries.indexWhere(
            (e) => e.kind == SignalEntryKind.signal && e.id == item.key,
          )
        : -1;
    if (idx < 0) throw WcpException('Item not in viewer: $id', code: 6);

    tab.read(signalGroupsProvider.notifier).setSignalColor(idx, color);
    return null;
  }

  Future<Map<String, dynamic>?> _handleFocusItem(
    Map<String, dynamic> data,
  ) async {
    final id = data['id'];
    if (id is! int) {
      throw const WcpException('"id" must be an integer', code: 3);
    }
    final item = _registry.byId(id);
    if (item == null) throw WcpException('Item not found: $id', code: 6);

    ref.read(selectedSignalProvider.notifier).select(_focusRef(item));
    return null;
  }

  /// Places named markers.
  ///
  /// WaveCrux markers occupy the letters a–z (GTKWave convention). Each
  /// marker object carries a `time` and an optional `name`: a single
  /// lowercase letter places that letter; any other non-empty string is a
  /// free name, carried as the item's name over WCP, on the first free
  /// letter (or on the letter it already holds, so placing a named marker
  /// again moves it); a missing name takes the first free letter. The
  /// spec's `move_focus` field is accepted and ignored. Validation is
  /// atomic: every marker is checked before any is placed.
  Future<Map<String, dynamic>?> _handleAddMarkers(
    Map<String, dynamic> data,
  ) async {
    final rawMarkers = data['markers'];
    if (rawMarkers is! List) {
      throw const WcpException('"markers" must be a list', code: 3);
    }

    final tab = _activeTab;
    final placed = tab.read(markerStateProvider).markers;
    final usedNames = <String>{...placed.keys};
    // Free names already on a placed letter, so naming one again moves it.
    final letterForName = <String, String>{
      for (final item in _registry.allItems)
        if (item.type == _kTypeMarker &&
            placed.containsKey(_markerLetter(item)) &&
            item.name != _markerLetter(item))
          item.name: _markerLetter(item),
    };
    final toPlace = <(String, String, int)>[];
    for (final m in rawMarkers) {
      if (m is! Map<String, dynamic>) {
        throw const WcpException('Each marker must be an object', code: 3);
      }
      final rawName = m['name'];
      final time = m['time'];
      final String letter;
      final String name;
      if (rawName == null) {
        letter = _firstFreeMarkerName(usedNames);
        name = letter;
      } else if (rawName is String && RegExp(r'^[a-z]$').hasMatch(rawName)) {
        letter = rawName;
        name = rawName;
      } else if (rawName is String && rawName.trim().isNotEmpty) {
        letter = letterForName[rawName] ?? _firstFreeMarkerName(usedNames);
        name = rawName;
        letterForName[rawName] = letter;
      } else {
        throw const WcpException(
          '"name" must be a non-empty string when provided',
          code: 3,
        );
      }
      final int tick;
      if (time is int) {
        tick = time;
      } else if (time is num && time == time.roundToDouble()) {
        tick = time.toInt();
      } else {
        throw const WcpException('"time" must be an integer', code: 3);
      }
      usedNames.add(letter);
      toPlace.add((letter, name, tick));
    }

    final addedItems = <Map<String, dynamic>>[];
    for (final (letter, name, tick) in toPlace) {
      tab.read(markerStateProvider.notifier).setMarker(letter, tick);
      final markerRef = '$_kMarkerRefPrefix$letter';
      // A letter taken over under a new name is a new item.
      final existingId = _registry.idFor(markerRef);
      if (existingId != null && _registry.byId(existingId)!.name != name) {
        _registry.remove(existingId);
      }
      final item = _registry.register(
        markerRef,
        name,
        markerRef,
        type: _kTypeMarker,
      );
      addedItems.add({
        'id': item.id,
        'name': item.name,
        'time': tick,
        'type': _kTypeMarker,
      });
    }
    return {'items': addedItems};
  }

  /// The marker letter an item occupies, from its `marker:<letter>` key.
  String _markerLetter(_WcpItem item) =>
      item.key.substring(_kMarkerRefPrefix.length);

  /// What `focus_item` selects: a variable's current signal ref (looked up
  /// from its row, since a reload may have re-resolved it), or a marker's
  /// `marker:<letter>` key.
  String? _focusRef(_WcpItem item) {
    if (item.type == _kTypeMarker) return item.key;
    final rows = _signalEntries(_activeTab.read(signalGroupsProvider).entries);
    for (final row in rows) {
      if (row.id == item.key) return row.signalRef;
    }
    return null;
  }

  String _firstFreeMarkerName(Set<String> used) {
    for (var c = 'a'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++) {
      final name = String.fromCharCode(c);
      if (!used.contains(name)) return name;
    }
    throw const WcpException('All marker names (a–z) are in use', code: 4);
  }

  Future<Map<String, dynamic>?> _handleGetValueAt(
    Map<String, dynamic> data,
  ) async {
    final signalPath = data['signal_path'];
    final time = data['time'];
    if (signalPath is! String || signalPath.isEmpty) {
      throw const WcpException(
        '"signal_path" must be a non-empty string',
        code: 3,
      );
    }
    if (time is! int) {
      throw const WcpException('"time" must be an integer', code: 3);
    }
    final source = _activeTab.read(waveformSourceProvider).value;
    if (source == null) {
      throw const WcpException('No waveform file loaded', code: 5);
    }
    // Resolve the hierarchical path (e.g. "top.clk") to a wellen signal-ref
    // handle before querying. loadSignal/isSignalLoaded/valueAt key off
    // Variable.signalRef, not the path string; accept either the ref or the
    // full path so callers can pass whichever they hold (mirrors the
    // add_items resolution above).
    Variable? variable;
    for (final v in source.findVariables(const SignalFilter())) {
      if (v.signalRef == signalPath || v.fullPath == signalPath) {
        variable = v;
        break;
      }
    }
    if (variable == null) {
      throw WcpException('Item not found: $signalPath', code: 6);
    }
    final signalRef = variable.signalRef;
    if (!source.isSignalLoaded(signalRef)) {
      await source.loadSignal(signalRef);
    }
    final value = source.valueAt(signalRef, time);
    return {'signal_path': signalPath, 'time': time, 'value': value};
  }

  Future<Map<String, dynamic>?> _handleGetHierarchy() async {
    final source = _activeTab.read(waveformSourceProvider).value;
    if (source == null) {
      throw const WcpException('No waveform file loaded', code: 5);
    }
    return {'scopes': source.rootScopes.map(_scopeToJson).toList()};
  }

  /// Activates the tab identified by `tab_id` in the workspace. When `pane_id`
  /// is supplied, also asserts that the tab is hosted by that pane before
  /// activating it (returns error code 6 if it is not). Activation focuses the
  /// hosting pane as a side effect — subsequent WCP commands that target the
  /// active tab will route there.
  Future<Map<String, dynamic>?> _handleSetActiveTab(
    Map<String, dynamic> data,
  ) async {
    final rawTabId = data['tab_id'];
    if (rawTabId is! String || rawTabId.isEmpty) {
      throw const WcpException('"tab_id" must be a non-empty string', code: 3);
    }
    final tabId = TabId.fromString(rawTabId);

    final rawPaneId = data['pane_id'];
    PaneId? paneId;
    if (rawPaneId != null) {
      if (rawPaneId is! String || rawPaneId.isEmpty) {
        throw const WcpException(
          '"pane_id" must be a non-empty string when provided',
          code: 3,
        );
      }
      paneId = PaneId.fromString(rawPaneId);
    }

    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null) {
      throw const WcpException('Workspace not yet hydrated', code: 5);
    }

    final tabIndex = workspace.tabs.indexWhere((t) => t.id == tabId);
    if (tabIndex < 0) {
      throw WcpException('Tab not found: $rawTabId', code: 6);
    }
    final tab = workspace.tabs[tabIndex];

    if (paneId != null && tab.paneId != paneId) {
      throw WcpException(
        'Tab $rawTabId is not hosted by pane $rawPaneId',
        code: 6,
      );
    }

    await ref.read(workspaceProvider.notifier).setActiveTab(tabId);

    return {
      'tab_id': tabId.value,
      'pane_id': tab.paneId.value,
    };
  }

  Future<Map<String, dynamic>?> _handleGetState() async {
    final tab = _activeTab;
    final sourceAsync = tab.read(waveformSourceProvider);
    final cursor = tab.read(cursorStateProvider);
    final mapper = tab.read(timeMapperProvider);
    final group = tab.read(signalGroupsProvider);
    final refs = <String>[];
    _collectSignalRefs(group.entries, refs);
    return {
      'file': tab.read(waveformSourceProvider.notifier).currentFilePath,
      'is_loaded': sourceAsync.value != null,
      'cursor': cursor.primaryCursorTime,
      'secondary_cursor': cursor.secondaryCursorTime,
      'ticks_per_pixel': mapper.ticksPerPixel,
      'pan_offset_ticks': mapper.panOffsetTicks,
      'signal_count': group.signalCount,
      'signals': refs,
    };
  }

  // ── lookup helpers ─────────────────────────────────────────────────────────

  /// Every signal row in [entries], groups flattened, in display order.
  List<SignalEntry> _signalEntries(List<SignalEntry> entries) => [
    for (final entry in entries)
      if (entry.kind == SignalEntryKind.signal)
        entry
      else if (entry.kind == SignalEntryKind.group)
        ..._signalEntries(entry.children),
  ];

  void _collectSignalRefs(List<SignalEntry> entries, List<String> out) {
    for (final entry in entries) {
      if (entry.kind == SignalEntryKind.signal) {
        final r = entry.signalRef;
        if (r != null) out.add(r);
      } else if (entry.kind == SignalEntryKind.group) {
        _collectSignalRefs(entry.children, out);
      }
    }
  }

  Map<String, dynamic> _scopeToJson(Scope scope) => {
    'name': scope.name,
    'path': scope.path,
    'type': scope.type.name,
    'variables': scope.variables.map(_variableToJson).toList(),
    'children': scope.childScopes.map(_scopeToJson).toList(),
  };

  Map<String, dynamic> _variableToJson(Variable v) => {
    'name': v.name,
    'full_path': v.fullPath,
    'signal_ref': v.signalRef,
    'var_type': v.varType.name,
    'direction': v.direction.name,
    'bit_width': v.bitWidth,
  };

  /// Parses a `set_item_color` colour: `#RGB`, `#RRGGBB` or `#RRGGBBAA`
  /// (the `#` optional), or a common colour name in any case, the form
  /// clients written against Surfer send.
  Color? _parseColor(String raw) {
    final named = _kNamedColors[raw.trim().toLowerCase()];
    if (named != null) return Color(named);
    final hex = raw.trim();
    var clean = hex.startsWith('#') ? hex.substring(1) : hex;
    if (clean.length == 3) {
      clean = [for (final c in clean.split('')) '$c$c'].join();
    }
    if (clean.length != 6 && clean.length != 8) return null;
    final value = int.tryParse(
      clean.length == 6 ? 'FF$clean' : clean,
      radix: 16,
    );
    if (value == null) return null;
    return Color(value);
  }
}

// ── App-lifecycle bridge ──────────────────────────────────────────────────────

/// The WCP port given for this process by `--wcp-port` or
/// `WAVECRUX_WCP_PORT`, or null when neither was.
///
/// When set, [WcpLifecycleBridge] runs the server on this port from launch
/// whatever `AppSettings.remoteControlEnabled` and `remoteControlPort` say,
/// and writes neither, so a script, a CI job or a second instance can listen
/// without touching the preference every instance shares. An organization
/// policy that turns the server off still wins. `bootstrap()` overrides it.
@Riverpod(keepAlive: true)
int? wcpPortOverride(Ref ref) => null;

/// Mirrors `AppSettings.remoteControlEnabled` into the WCP server lifecycle.
///
/// Starts the server on launch when the setting is true and reacts to
/// settings changes (toggle off → stop; toggle on → start; port change →
/// restart). Hosted as a `keepAlive: true` provider so the bridge stays
/// active for the lifetime of the app; consumers `ref.read` it once at
/// bootstrap to instantiate the listener.
///
/// Without this bridge the persisted `remoteControlEnabled` flag was inert on
/// relaunch: settings showed the switch on and the configured port, but the
/// only caller of [RemoteControlNotifier.startServer] was the settings-screen
/// toggle, so status read "stopped" and scripted clients could not connect
/// until the user toggled the switch by hand (beta issue #9).
/// Deliberately identical in shape to `CxpLifecycleBridge` — the two servers
/// are orthogonal protocols with the same enable/port settings contract.
@Riverpod(keepAlive: true)
WcpLifecycleBridge wcpLifecycleBridge(Ref ref) {
  return WcpLifecycleBridge(ref)..start();
}

/// Tracks [AppSettings.remoteControlEnabled] + [AppSettings.remoteControlPort]
/// and drives [RemoteControlNotifier.startServer] / [RemoteControlNotifier
/// .stopServer] accordingly.
class WcpLifecycleBridge {
  /// Creates a bridge bound to [ref]. Call [start] to begin listening.
  WcpLifecycleBridge(this._ref);

  final Ref _ref;
  ProviderSubscription<AsyncValue<AppSettings>>? _settingsSub;
  bool _started = false;

  /// Begin listening for settings changes. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _settingsSub = _ref.listen<AsyncValue<AppSettings>>(
      appSettingsProvider,
      _onSettings,
      fireImmediately: true,
    );
    _ref.onDispose(() {
      _settingsSub?.close();
      _settingsSub = null;
    });
  }

  bool _previouslyEnabled = false;
  int _previousPort = -1;

  void _onSettings(
    AsyncValue<AppSettings>? previous,
    AsyncValue<AppSettings> next,
  ) {
    final settings = next.value;
    if (settings == null) return;
    final portOverride = _ref.read(wcpPortOverrideProvider);
    // The ORG's answer, not just the engineer's: a locked
    // `products.wavecrux.wcpServer: false` outranks the Settings switch, and
    // an administrator who turned this off is entitled to have it stay off.
    // Until this read existed the key was documented, registered and inert.
    final enabled = resolveWcpServerPolicy(
      _ref.read(cruxPolicyProvider).document,
      userSetting: portOverride != null || settings.remoteControlEnabled,
    ).value;
    final port = portOverride ?? settings.remoteControlPort;
    if (enabled == _previouslyEnabled && port == _previousPort) return;
    _previouslyEnabled = enabled;
    _previousPort = port;
    final notifier = _ref.read(remoteControlProvider.notifier);
    if (enabled) {
      // `startServer` returns a failed bind — most often the port held by
      // another process — instead of throwing. Nothing else reads the result
      // on this path, so it is logged here or not at all.
      unawaited(
        notifier.startServer(port).then((error) {
          if (error == null) {
            // A port given on the command line is the caller's to connect
            // to, and with port 0 only this line says which one it got.
            if (portOverride != null) {
              final bound = _ref.read(remoteControlProvider).port;
              stdout.writeln(
                'WaveCrux: WCP remote control listening on '
                '127.0.0.1:$bound',
              );
            }
            return;
          }
          _log.warning('WCP server did not start on port $port: $error');
          if (portOverride != null) {
            stderr.writeln(
              'WaveCrux: WCP remote control could not start on port '
              '$port: $error',
            );
          }
        }),
      );
    } else {
      if (portOverride != null) {
        stderr.writeln(
          'WaveCrux: WCP remote control is turned off by organization '
          'policy; --wcp-port is ignored.',
        );
      }
      unawaited(notifier.stopServer());
    }
  }
}
