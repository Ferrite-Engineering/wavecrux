// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/remote/wcp_server.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../../helpers/product_telemetry_config.dart';

// ── _WcpSocket ────────────────────────────────────────────────────────────────

class _WcpSocket {
  _WcpSocket(this._socket) {
    _socket.listen(_onData, onDone: () {}, onError: (_) {});
  }

  final Socket _socket;
  final List<int> _buf = [];
  final List<Map<String, dynamic>> _frames = [];
  Completer<void>? _waiting;

  void _onData(List<int> chunk) {
    _buf.addAll(chunk);
    while (true) {
      final idx = _buf.indexOf(0);
      if (idx < 0) break;
      final bytes = List<int>.from(_buf.sublist(0, idx));
      _buf.removeRange(0, idx + 1);
      if (bytes.isNotEmpty) {
        _frames.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
        _waiting?.complete();
        _waiting = null;
      }
    }
  }

  Future<Map<String, dynamic>> next({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    while (_frames.isEmpty) {
      _waiting = Completer<void>();
      await _waiting!.future.timeout(timeout);
    }
    return _frames.removeAt(0);
  }

  void send(Map<String, dynamic> msg) =>
      _socket.add([...utf8.encode(jsonEncode(msg)), 0]);

  void destroy() => _socket.destroy();
}

// ── per-tab fakes ───────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// Fake notifier whose [openFile] keeps the injected source loaded instead of
/// crossing into the FFI. Used by the reload-success test so `_handleReload`
/// observes a still-loaded source after re-opening the current file.
class _ReloadableFakeNotifier extends WaveformSourceNotifier {
  _ReloadableFakeNotifier(this._source);
  final WaveformDataSource? _source;
  int openCalls = 0;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    openCalls++;
    currentFilePath = path;
    state = AsyncData(_source);
  }
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('RemoteControlState', () {
    test('default values', () {
      const s = RemoteControlState();
      expect(s.isRunning, isFalse);
      expect(s.port, WcpServer.defaultPort);
      expect(s.connectedClients, 0);
    });

    test('copyWith', () {
      const s = RemoteControlState();
      final s2 = s.copyWith(isRunning: true, port: 12345, connectedClients: 3);
      expect(s2.isRunning, isTrue);
      expect(s2.port, 12345);
      expect(s2.connectedClients, 3);
    });

    test('equality', () {
      const a = RemoteControlState(isRunning: true, port: 1234);
      const b = RemoteControlState(isRunning: true, port: 1234);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when fields differ', () {
      const a = RemoteControlState(isRunning: true, port: 1234);
      const b = RemoteControlState(port: 1234);
      expect(a, isNot(b));
    });
  });

  group('RemoteControlNotifier — lifecycle', () {
    late ProviderContainer container;

    setUp(
      () => container = ProviderContainer(overrides: [productTelemetryConfig]),
    );
    tearDown(() async {
      await container.read(remoteControlProvider.notifier).stopServer();
      container.dispose();
    });

    test('initial state is not running', () {
      expect(container.read(remoteControlProvider).isRunning, isFalse);
    });

    test('startServer transitions to running', () async {
      final err = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(err, isNull);
      expect(container.read(remoteControlProvider).isRunning, isTrue);
      expect(
        container.read(remoteControlProvider).port,
        isNot(WcpServer.defaultPort),
      );
    });

    test('stopServer transitions to not running', () async {
      await container.read(remoteControlProvider.notifier).startServer(0);
      await container.read(remoteControlProvider.notifier).stopServer();
      expect(container.read(remoteControlProvider).isRunning, isFalse);
    });

    test('startServer on already-running server restarts cleanly', () async {
      final notifier = container.read(remoteControlProvider.notifier);
      await notifier.startServer(0);
      final err = await notifier.startServer(0);
      expect(err, isNull);
      expect(container.read(remoteControlProvider).isRunning, isTrue);
    });

    test('WCP greeting is sent to each new client', () async {
      await container.read(remoteControlProvider.notifier).startServer(0);
      final port = container.read(remoteControlProvider).port;

      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);

      final msg = await ws.next();
      expect(msg['type'], 'greeting');
      expect(msg['version'], WcpServer.wcpVersion);
    });
  });

  group('RemoteControlNotifier — connectedClients', () {
    late ProviderContainer container;

    setUp(
      () => container = ProviderContainer(overrides: [productTelemetryConfig]),
    );
    tearDown(() async {
      await container.read(remoteControlProvider.notifier).stopServer();
      container.dispose();
    });

    test('connectedClients increments and decrements', () async {
      await container.read(remoteControlProvider.notifier).startServer(0);
      final port = container.read(remoteControlProvider).port;

      expect(container.read(remoteControlProvider).connectedClients, 0);

      final s1 = await Socket.connect('127.0.0.1', port);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(remoteControlProvider).connectedClients, 1);

      final s2 = await Socket.connect('127.0.0.1', port);
      addTearDown(s2.destroy);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(remoteControlProvider).connectedClients, 2);

      s1.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(remoteControlProvider).connectedClients, 1);
    });
  });

  group('RemoteControlNotifier — WCP commands (no waveform loaded)', () {
    late ProviderContainer container;
    late TabContainerManager tcm;
    late int port;

    setUp(() async {
      // WCP commands mutate/query per-tab providers via the active tab's
      // container, so the server must run in a tab-wired root container.
      tcm = TabContainerManager();
      container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          tabContainerManagerProvider.overrideWithValue(tcm),
        ],
      );
      tcm.init(container);
      await container.read(remoteControlProvider.notifier).startServer(0);
      port = container.read(remoteControlProvider).port;
    });

    tearDown(() async {
      await container.read(remoteControlProvider.notifier).stopServer();
      tcm.dispose();
      container.dispose();
    });

    Future<_WcpSocket> connect() async {
      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // consume greeting
      return ws;
    }

    Future<Map<String, dynamic>> sendCommand(
      _WcpSocket ws,
      String command, [
      Map<String, dynamic>? data,
    ]) async {
      ws.send({
        'type': 'command',
        'id': 1,
        'command': command,
        'data': data ?? <String, dynamic>{},
      });
      return await ws.next();
    }

    test('reload with no file loaded returns error code 5', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'reload');
      expect(msg['type'], 'error');
      expect(msg['code'], 5);
    });

    test('zoom_to_fit returns response', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'zoom_to_fit');
      expect(msg['type'], 'response');
      expect(msg['data'], isA<Map<String, dynamic>>());
    });

    test('get_item_list returns empty list when nothing added', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'get_item_list');
      expect(msg['type'], 'response');
      expect((msg['data'] as Map<String, dynamic>)['items'], isEmpty);
    });

    test('load with missing source returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'load', <String, dynamic>{});
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test('add_items with no file loaded returns error code 5', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'add_items', {'item_path': 'top.sig'});
      expect(msg['type'], 'error');
      expect(msg['code'], 5);
    });

    test('remove_items with no ids field returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'remove_items', <String, dynamic>{});
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test('set_cursor with missing timestamp returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'set_cursor', <String, dynamic>{});
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test('set_viewport_range with bad params returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'set_viewport_range', {
        'start': 'bad',
        'end': 100,
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test('wavecrux.getState returns expected keys', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'wavecrux.getState');
      expect(msg['type'], 'response');
      final data = msg['data'] as Map<String, dynamic>;
      expect(data.containsKey('is_loaded'), isTrue);
      expect(data.containsKey('signal_count'), isTrue);
    });

    test('add_markers with an empty name returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'add_markers', {
        'markers': [
          {'name': '', 'time': 100},
        ],
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test('add_markers with valid letter registers and returns id', () async {
      final ws = await connect();
      final msg = await sendCommand(ws, 'add_markers', {
        'markers': [
          {'name': 'a', 'time': 500},
        ],
      });
      expect(msg['type'], 'response');
      final items =
          (msg['data'] as Map<String, dynamic>)['items'] as List<dynamic>;
      expect(items, hasLength(1));
      expect((items.first as Map<String, dynamic>)['id'], isA<int>());
    });
  });

  group('RemoteControlNotifier — wavecrux.setActiveTab', () {
    late Directory tempDir;
    late ProviderContainer container;
    late int port;
    late WorkspaceTab tabA;
    late WorkspaceTab tabB;
    late PaneId paneL;
    late PaneId paneR;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wcp_set_active_tab_');
      container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const WaveCruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
              logger: (_) {},
            ),
          ),
        ],
      );

      // Hydrate the workspace, then create a split-pane workspace with two
      // tabs (tabA in pane L, tabB in pane R).
      final wsNotifier = container.wavecruxWorkspace;
      final initial = await container.read(workspaceProvider.future);
      paneL = initial.activePaneId;
      tabA = buildWorkspaceTab(
        id: TabId.generate(),
        displayName: 'a.vcd',
        paneId: paneL,
        filePath: '/tmp/a.vcd',
      );
      await wsNotifier.addTab(tabA);
      paneR = await wsNotifier.splitPane();
      tabB = buildWorkspaceTab(
        id: TabId.generate(),
        displayName: 'b.vcd',
        paneId: paneR,
        filePath: '/tmp/b.vcd',
      );
      await wsNotifier.addTab(tabB);

      await container.read(remoteControlProvider.notifier).startServer(0);
      port = container.read(remoteControlProvider).port;
    });

    tearDown(() async {
      await container.read(remoteControlProvider.notifier).stopServer();
      container.dispose();
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException catch (_) {}
    });

    Future<_WcpSocket> connect() async {
      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // consume greeting
      return ws;
    }

    Future<Map<String, dynamic>> sendCommand(
      _WcpSocket ws,
      String command, [
      Map<String, dynamic>? data,
    ]) async {
      ws.send({
        'type': 'command',
        'id': 1,
        'command': command,
        'data': data ?? <String, dynamic>{},
      });
      return await ws.next();
    }

    test('greeting announces wavecrux.setActiveTab', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      final greeting = await ws.next();
      expect(greeting['type'], 'greeting');
      final commands = (greeting['commands'] as List).cast<String>();
      expect(commands, contains('wavecrux.setActiveTab'));
    });

    test('activates a tab in the active pane (no pane_id)', () async {
      final ws = await connect();
      // Pre-condition: pane R is active after splitPane.
      expect(
        container.read(workspaceProvider).requireValue.activePaneId,
        paneR,
      );

      final msg = await sendCommand(
        ws,
        'wavecrux.setActiveTab',
        {'tab_id': tabA.id.value},
      );
      expect(msg['type'], 'response');
      final data = msg['data'] as Map<String, dynamic>;
      expect(data['tab_id'], tabA.id.value);
      expect(data['pane_id'], paneL.value);

      final updated = container.read(workspaceProvider).requireValue;
      expect(updated.activePaneId, paneL);
      final activePane = updated.panes.firstWhere((p) => p.id == paneL);
      expect(activePane.activeTabId, tabA.id);
    });

    test('activates a tab in a specified pane (matching pane_id)', () async {
      final ws = await connect();
      final msg = await sendCommand(
        ws,
        'wavecrux.setActiveTab',
        {'tab_id': tabB.id.value, 'pane_id': paneR.value},
      );
      expect(msg['type'], 'response');
      final updated = container.read(workspaceProvider).requireValue;
      expect(updated.activePaneId, paneR);
      final activePane = updated.panes.firstWhere((p) => p.id == paneR);
      expect(activePane.activeTabId, tabB.id);
    });

    test('returns error code 6 when tab_id is unknown', () async {
      final ws = await connect();
      final msg = await sendCommand(
        ws,
        'wavecrux.setActiveTab',
        {'tab_id': TabId.generate().value},
      );
      expect(msg['type'], 'error');
      expect(msg['code'], 6);
    });

    test('returns error code 6 when tab is not hosted by named pane', () async {
      final ws = await connect();
      // tabA is in paneL — pin it to paneR and assert refusal.
      final msg = await sendCommand(
        ws,
        'wavecrux.setActiveTab',
        {'tab_id': tabA.id.value, 'pane_id': paneR.value},
      );
      expect(msg['type'], 'error');
      expect(msg['code'], 6);
    });

    test('returns error code 3 when tab_id is missing', () async {
      final ws = await connect();
      final msg = await sendCommand(
        ws,
        'wavecrux.setActiveTab',
        <String, dynamic>{},
      );
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test(
      'returns error code 3 when pane_id is provided but non-string',
      () async {
        final ws = await connect();
        final msg = await sendCommand(
          ws,
          'wavecrux.setActiveTab',
          {'tab_id': tabA.id.value, 'pane_id': 42},
        );
        expect(msg['type'], 'error');
        expect(msg['code'], 3);
      },
    );
  });

  // ── additional handler coverage ───────────────────────────────────────────
  // Tests that exercise handler paths not reachable from the existing
  // "no waveform loaded" group. All of these work without a waveform file.

  group('RemoteControlNotifier — command handler coverage', () {
    late ProviderContainer container;
    late TabContainerManager tcm;
    late int port;

    setUp(() async {
      tcm = TabContainerManager();
      container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          tabContainerManagerProvider.overrideWithValue(tcm),
        ],
      );
      tcm.init(container);
      await container.read(remoteControlProvider.notifier).startServer(0);
      port = container.read(remoteControlProvider).port;
    });

    tearDown(() async {
      await container.read(remoteControlProvider.notifier).stopServer();
      tcm.dispose();
      container.dispose();
    });

    Future<_WcpSocket> connect() async {
      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // consume greeting
      return ws;
    }

    Future<Map<String, dynamic>> sendCmd(
      _WcpSocket ws,
      String command, [
      Map<String, dynamic>? data,
    ]) async {
      ws.send({
        'type': 'command',
        'id': 42,
        'command': command,
        'data': data ?? <String, dynamic>{},
      });
      return await ws.next();
    }

    // ── set_cursor success ────────────────────────────────────────────────

    test('set_cursor with valid integer timestamp succeeds', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'set_cursor', {'timestamp': 1000});
      expect(msg['type'], 'response');
    });

    // ── set_viewport_range ────────────────────────────────────────────────

    test('set_viewport_range with valid integers succeeds', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'set_viewport_range', {
        'start': 0,
        'end': 1000,
      });
      expect(msg['type'], 'response');
    });

    // ── set_viewport_to ───────────────────────────────────────────────────

    test(
      'set_viewport_to with missing timestamp returns error code 3',
      () async {
        final ws = await connect();
        final msg = await sendCmd(ws, 'set_viewport_to', <String, dynamic>{});
        expect(msg['type'], 'error');
        expect(msg['code'], 3);
      },
    );

    test('set_viewport_to with valid timestamp succeeds', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'set_viewport_to', {'timestamp': 500});
      expect(msg['type'], 'response');
    });

    // ── get_item_info ─────────────────────────────────────────────────────

    test('get_item_info with non-list ids returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'get_item_info', {'ids': 'bad'});
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test('get_item_info with unknown id returns error code 6', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'get_item_info', {
        'ids': [99999],
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 6);
    });

    test('get_item_info with known marker id returns item info', () async {
      final ws = await connect();
      // Register a marker to populate the registry.
      final addMsg = await sendCmd(ws, 'add_markers', {
        'markers': [
          {'name': 'b', 'time': 100},
        ],
      });
      expect(addMsg['type'], 'response');
      final id =
          (((addMsg['data'] as Map)['items'] as List).first as Map)['id']
              as int;

      final infoMsg = await sendCmd(ws, 'get_item_info', {
        'ids': [id],
      });
      expect(infoMsg['type'], 'response');
      final items = (infoMsg['data'] as Map)['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['id'], id);
    });

    // ── remove_items ──────────────────────────────────────────────────────

    test('remove_items with unknown ids is a silent no-op', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'remove_items', {
        'ids': [99999, 88888],
      });
      expect(msg['type'], 'response');
    });

    test(
      'remove_items with known marker id removes it from the registry',
      () async {
        final ws = await connect();
        // Register a marker.
        final addMsg = await sendCmd(ws, 'add_markers', {
          'markers': [
            {'name': 'c', 'time': 200},
          ],
        });
        final id =
            (((addMsg['data'] as Map)['items'] as List).first as Map)['id']
                as int;

        // Remove it.
        final removeMsg = await sendCmd(ws, 'remove_items', {
          'ids': [id],
        });
        expect(removeMsg['type'], 'response');

        // Confirm it's gone: get_item_info returns error 6.
        final infoMsg = await sendCmd(ws, 'get_item_info', {
          'ids': [id],
        });
        expect(infoMsg['type'], 'error');
        expect(infoMsg['code'], 6);
      },
    );

    // ── set_item_color ────────────────────────────────────────────────────

    test('set_item_color with non-integer id returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'set_item_color', {
        'id': 'bad',
        'color': '#ff0000',
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test('set_item_color with non-string color returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'set_item_color', {
        'id': 1,
        'color': 12345,
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test(
      'set_item_color with invalid hex string returns error code 3',
      () async {
        final ws = await connect();
        final msg = await sendCmd(ws, 'set_item_color', {
          'id': 1,
          'color': 'not-a-color',
        });
        expect(msg['type'], 'error');
        expect(msg['code'], 3);
      },
    );

    test('set_item_color with unknown id returns error code 6', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'set_item_color', {
        'id': 99999,
        'color': '#ff0000',
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 6);
    });

    // ── focus_item ────────────────────────────────────────────────────────

    test('focus_item with non-integer id returns error code 3', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'focus_item', {'id': 'bad'});
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
    });

    test('focus_item with unknown id returns error code 6', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'focus_item', {'id': 99999});
      expect(msg['type'], 'error');
      expect(msg['code'], 6);
    });

    test('add_markers auto-assigns the first free letter when name is '
        'absent', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'add_markers', {
        'markers': [
          {'time': 100},
          {'time': 200},
        ],
      });
      expect(msg['type'], 'response');
      final items = (msg['data'] as Map)['items'] as List;
      expect(items, hasLength(2));
      expect((items.first as Map)['name'], 'a');
      expect((items.last as Map)['name'], 'b');
    });

    test('add_markers tolerates the spec move_focus field', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'add_markers', {
        'markers': [
          {'name': 'e', 'time': 5, 'move_focus': true},
        ],
      });
      expect(msg['type'], 'response');
      expect((msg['data'] as Map)['items'] as List, hasLength(1));
    });

    test('add_markers validation failure places no markers', () async {
      final ws = await connect();
      final tab = tcm.containerFor(container.read(activeTabIdProvider));
      final sub = tab.listen(markerStateProvider, (_, _) {});
      addTearDown(sub.close);

      final msg = await sendCmd(ws, 'add_markers', {
        'markers': [
          {'name': 'f', 'time': 10},
          {'name': 42, 'time': 20},
        ],
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 3);
      expect(tab.read(markerStateProvider).markers, isEmpty);
    });

    test(
      'remove_items on a marker id removes the marker from '
      'markerStateProvider',
      () async {
        final ws = await connect();
        final tab = tcm.containerFor(container.read(activeTabIdProvider));
        final sub = tab.listen(markerStateProvider, (_, _) {});
        addTearDown(sub.close);

        final addMsg = await sendCmd(ws, 'add_markers', {
          'markers': [
            {'name': 'g', 'time': 300},
          ],
        });
        final id =
            (((addMsg['data'] as Map)['items'] as List).first as Map)['id']
                as int;
        expect(tab.read(markerStateProvider).getMarker('g'), 300);

        final removeMsg = await sendCmd(ws, 'remove_items', {
          'ids': [id],
        });
        expect(removeMsg['type'], 'response');
        expect(tab.read(markerStateProvider).getMarker('g'), isNull);
      },
    );

    test('add_markers carries a free-string name on a free letter', () async {
      final ws = await connect();
      final tab = tcm.containerFor(container.read(activeTabIdProvider));
      final sub = tab.listen(markerStateProvider, (_, _) {});
      addTearDown(sub.close);

      final msg = await sendCmd(ws, 'add_markers', {
        'markers': [
          {'name': 'a', 'time': 5},
          {'name': 'enable_rises', 'time': 100},
        ],
      });
      expect(msg['type'], 'response');
      final items = (msg['data'] as Map)['items'] as List;
      final named = items.last as Map;
      expect(named['name'], 'enable_rises');
      expect(tab.read(markerStateProvider).getMarker('b'), 100);

      final info = await sendCmd(ws, 'get_item_info', {
        'ids': [named['id']],
      });
      expect(((info['data'] as Map)['items'] as List).single, {
        'id': named['id'],
        'name': 'enable_rises',
        'path': 'marker:b',
        'type': 'Marker',
      });

      // The name survives a get_item_list reconciliation.
      final list = await sendCmd(ws, 'get_item_list');
      final names = [
        for (final i in (list['data'] as Map)['items'] as List)
          (i as Map)['name'],
      ];
      expect(names, containsAll(['a', 'enable_rises']));
    });

    test('add_markers with a free name again moves that marker', () async {
      final ws = await connect();
      final tab = tcm.containerFor(container.read(activeTabIdProvider));
      final sub = tab.listen(markerStateProvider, (_, _) {});
      addTearDown(sub.close);

      final first = await sendCmd(ws, 'add_markers', {
        'markers': [
          {'name': 'handshake stalls', 'time': 100},
        ],
      });
      final second = await sendCmd(ws, 'add_markers', {
        'markers': [
          {'name': 'handshake stalls', 'time': 250},
        ],
      });
      final id1 =
          (((first['data'] as Map)['items'] as List).single as Map)['id'];
      final id2 =
          (((second['data'] as Map)['items'] as List).single as Map)['id'];
      expect(id2, id1);
      expect(tab.read(markerStateProvider).markers, {'a': 250});

      final removed = await sendCmd(ws, 'remove_items', {
        'ids': [id1],
      });
      expect(removed['type'], 'response');
      expect(tab.read(markerStateProvider).markers, isEmpty);
    });

    test('focus_item with registered marker id succeeds', () async {
      final ws = await connect();
      // Register a marker so there is an id in the registry.
      final addMsg = await sendCmd(ws, 'add_markers', {
        'markers': [
          {'name': 'd', 'time': 50},
        ],
      });
      final id =
          (((addMsg['data'] as Map)['items'] as List).first as Map)['id']
              as int;

      final focusMsg = await sendCmd(ws, 'focus_item', {'id': id});
      expect(focusMsg['type'], 'response');
    });

    // ── wavecrux.getValueAt error paths ──────────────────────────────────

    test(
      'wavecrux.getValueAt with missing signal_path returns error code 3',
      () async {
        final ws = await connect();
        final msg = await sendCmd(ws, 'wavecrux.getValueAt', {'time': 100});
        expect(msg['type'], 'error');
        expect(msg['code'], 3);
      },
    );

    test(
      'wavecrux.getValueAt with missing time returns error code 3',
      () async {
        final ws = await connect();
        final msg = await sendCmd(ws, 'wavecrux.getValueAt', {
          'signal_path': 'top.clk',
        });
        expect(msg['type'], 'error');
        expect(msg['code'], 3);
      },
    );

    test('wavecrux.getValueAt with no waveform returns error code 5', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'wavecrux.getValueAt', {
        'signal_path': 'top.clk',
        'time': 100,
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 5);
    });

    // ── wavecrux.getHierarchy ─────────────────────────────────────────────

    test(
      'wavecrux.getHierarchy with no waveform returns error code 5',
      () async {
        final ws = await connect();
        final msg = await sendCmd(ws, 'wavecrux.getHierarchy');
        expect(msg['type'], 'error');
        expect(msg['code'], 5);
      },
    );

    // ── add_items paths list variant ─────────────────────────────────────

    test(
      'add_items via "paths" list with no waveform returns error code 5',
      () async {
        final ws = await connect();
        final msg = await sendCmd(ws, 'add_items', {
          'paths': ['top.clk', 'top.data'],
        });
        expect(msg['type'], 'error');
        expect(msg['code'], 5);
      },
    );

    test(
      'add_items with no item_path and no paths returns error code 3',
      () async {
        final ws = await connect();
        final msg = await sendCmd(ws, 'add_items', <String, dynamic>{});
        // No file loaded → error 5 is raised first (before path validation)
        // because the source-null check runs before path validation.
        expect(msg['type'], 'error');
      },
    );

    // ── unknown command ───────────────────────────────────────────────────

    test('unknown command returns error response', () async {
      final ws = await connect();
      final msg = await sendCmd(ws, 'totally_unknown_command');
      expect(msg['type'], 'error');
    });
  });

  group('SelectedSignalNotifier', () {
    late ProviderContainer container;

    setUp(
      () => container = ProviderContainer(overrides: [productTelemetryConfig]),
    );
    tearDown(() => container.dispose());

    test('initial state is null', () {
      expect(container.read(selectedSignalProvider), isNull);
    });

    test('select sets state', () {
      container.read(selectedSignalProvider.notifier).select('top.data');
      expect(container.read(selectedSignalProvider), 'top.data');
    });

    test('select null clears state', () {
      container.read(selectedSignalProvider.notifier).select('top.data');
      container.read(selectedSignalProvider.notifier).select(null);
      expect(container.read(selectedSignalProvider), isNull);
    });
  });

  // ── per-tab routing (issue #44 scope-leak class) ──────────────────────────
  // The WCP server is a root-scoped keepAlive notifier, but its commands must
  // operate on the FOCUSED tab's providers — not the empty root scope. These
  // tests inject a loaded source into the active tab's container (via
  // `extraTabOverrides`) and prove commands read/write that tab, while the
  // root container stays empty.
  group('RemoteControlNotifier — per-tab command routing', () {
    late ProviderContainer container;
    late TabContainerManager tcm;
    late _MockSource source;
    late int port;

    setUp(() async {
      source = _MockSource();
      const sig = Variable(
        name: 'sig',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: '0',
        scopePath: 'top',
        bitWidth: 1,
      );
      when(() => source.findVariables(const SignalFilter())).thenReturn([sig]);
      when(() => source.rootScopes).thenReturn(const []);
      when(() => source.startTime).thenReturn(0);
      when(() => source.isSignalLoaded('0')).thenReturn(true);
      when(() => source.loadSignal('0')).thenAnswer((_) async {});
      when(() => source.valueAt('0', any())).thenReturn('1');

      // The TAB gets the loaded source; ROOT stays empty.
      tcm = TabContainerManager(
        extraTabOverrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
        ],
      );
      container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          tabContainerManagerProvider.overrideWithValue(tcm),
          waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(null)),
        ],
      );
      tcm.init(container);
      await container.read(remoteControlProvider.notifier).startServer(0);
      port = container.read(remoteControlProvider).port;
    });

    tearDown(() async {
      await container.read(remoteControlProvider.notifier).stopServer();
      tcm.dispose();
      container.dispose();
    });

    Future<_WcpSocket> connect() async {
      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting
      return ws;
    }

    Future<Map<String, dynamic>> send(
      _WcpSocket ws,
      String command, [
      Map<String, dynamic>? data,
    ]) async {
      ws.send({
        'type': 'command',
        'id': 1,
        'command': command,
        'data': data ?? <String, dynamic>{},
      });
      return await ws.next();
    }

    test(
      'getState reads the active tab source (is_loaded true), not root',
      () async {
        // Root source is null; only the tab has a file. Pre-fix this read the
        // root source and reported is_loaded:false.
        final ws = await connect();
        final msg = await send(ws, 'wavecrux.getState');
        expect(msg['type'], 'response');
        expect((msg['data'] as Map)['is_loaded'], isTrue);
      },
    );

    test('add_items resolves and adds against the active tab source', () async {
      final ws = await connect();
      final add = await send(ws, 'add_items', {'item_path': 'top.sig'});
      expect(add['type'], 'response');
      expect((add['data'] as Map)['items'] as List, hasLength(1));

      // The signal landed in the active tab's signal group, not root.
      final state = await send(ws, 'wavecrux.getState');
      expect((state['data'] as Map)['signal_count'], 1);
    });

    test('getValueAt queries the active tab source', () async {
      final ws = await connect();
      final msg = await send(ws, 'wavecrux.getValueAt', {
        'signal_path': 'top.sig',
        'time': 10,
      });
      expect(msg['type'], 'response');
      expect((msg['data'] as Map)['value'], '1');
    });
  });

  // ── loaded-source success handlers ────────────────────────────────────────
  // A richer mock source (two variables under scope `top`, a populated
  // hierarchy) drives the success branches the other groups never reach:
  // add_items exact + recursive, set_item_color, get_item_info for signals,
  // getHierarchy, reload, clear and shutdown.
  group('RemoteControlNotifier — loaded-source success handlers', () {
    late ProviderContainer container;
    late TabContainerManager tcm;
    late _MockSource source;
    late int port;

    const sigA = Variable(
      name: 'a',
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: 'A',
      scopePath: 'top',
      bitWidth: 1,
    );
    const sigB = Variable(
      name: 'b',
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: 'B',
      scopePath: 'top',
      bitWidth: 8,
    );

    setUp(() async {
      source = _MockSource();
      when(
        () => source.findVariables(const SignalFilter()),
      ).thenReturn([sigA, sigB]);
      when(() => source.rootScopes).thenReturn(const [
        Scope(
          name: 'top',
          type: ScopeType.module,
          path: 'top',
          variables: [sigA, sigB],
        ),
      ]);
      when(() => source.startTime).thenReturn(0);
      when(() => source.isSignalLoaded(any())).thenReturn(false);
      when(() => source.loadSignal(any())).thenAnswer((_) async {});
      when(() => source.valueAt(any(), any())).thenReturn('42');
      when(source.close).thenReturn(null);

      tcm = TabContainerManager(
        extraTabOverrides: [
          waveformSourceProvider.overrideWith(
            () => _ReloadableFakeNotifier(source),
          ),
        ],
      );
      container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          tabContainerManagerProvider.overrideWithValue(tcm),
        ],
      );
      tcm.init(container);
      await container.read(remoteControlProvider.notifier).startServer(0);
      port = container.read(remoteControlProvider).port;
    });

    tearDown(() async {
      await container.read(remoteControlProvider.notifier).stopServer();
      tcm.dispose();
      container.dispose();
    });

    Future<_WcpSocket> connect() async {
      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting
      return ws;
    }

    Future<Map<String, dynamic>> send(
      _WcpSocket ws,
      String command, [
      Map<String, dynamic>? data,
    ]) async {
      ws.send({
        'type': 'command',
        'id': 7,
        'command': command,
        'data': data ?? <String, dynamic>{},
      });
      return await ws.next();
    }

    _ReloadableFakeNotifier tabNotifier() =>
        tcm
                .containerFor(container.read(activeTabIdProvider))
                .read(waveformSourceProvider.notifier)
            as _ReloadableFakeNotifier;

    test('add_items via "paths" list resolves and adds both signals', () async {
      final ws = await connect();
      final msg = await send(ws, 'add_items', {
        'paths': ['top.a', 'top.b'],
      });
      expect(msg['type'], 'response');
      final items = (msg['data'] as Map)['items'] as List;
      expect(items, hasLength(2));
    });

    test(
      'add_items recursive expands a scope path into its variables',
      () async {
        final ws = await connect();
        final msg = await send(ws, 'add_items', {
          'item_path': 'top',
          'recursive': true,
        });
        expect(msg['type'], 'response');
        final items = (msg['data'] as Map)['items'] as List;
        expect(items, hasLength(2), reason: 'both signals under top');
      },
    );

    test(
      'add_items recursive on an empty scope returns error code 6',
      () async {
        final ws = await connect();
        final msg = await send(ws, 'add_items', {
          'item_path': 'nonexistent',
          'recursive': true,
        });
        expect(msg['type'], 'error');
        expect(msg['code'], 6);
      },
    );

    test(
      'add_items with a non-string entry in "paths" returns error code 3',
      () async {
        final ws = await connect();
        final msg = await send(ws, 'add_items', {
          'paths': ['top.a', 123],
        });
        expect(msg['type'], 'error');
        expect(msg['code'], 3);
      },
    );

    test(
      'add_items with an unknown non-recursive path returns error code 6',
      () async {
        final ws = await connect();
        final msg = await send(ws, 'add_items', {'item_path': 'top.missing'});
        expect(msg['type'], 'error');
        expect(msg['code'], 6);
      },
    );

    test('add_items via spec "items" param resolves and adds', () async {
      final ws = await connect();
      final msg = await send(ws, 'add_items', {
        'items': ['top.a', 'top.b'],
      });
      expect(msg['type'], 'response');
      expect((msg['data'] as Map)['items'] as List, hasLength(2));
    });

    test('add_items partial failure adds and registers nothing', () async {
      final ws = await connect();
      final msg = await send(ws, 'add_items', {
        'paths': ['top.a', 'top.missing'],
      });
      expect(msg['type'], 'error');
      expect(msg['code'], 6);

      // Atomicity: the resolvable first path must not have been displayed
      // or registered.
      final state = await send(ws, 'wavecrux.getState');
      expect((state['data'] as Map)['signal_count'], 0);
      final list = await send(ws, 'get_item_list');
      expect((list['data'] as Map)['items'] as List, isEmpty);
    });

    test('add_items non-recursive scope path adds direct children', () async {
      final ws = await connect();
      final msg = await send(ws, 'add_items', {'item_path': 'top'});
      expect(msg['type'], 'response');
      expect((msg['data'] as Map)['items'] as List, hasLength(2));
    });

    test('add_variables alias adds the named variables', () async {
      final ws = await connect();
      final msg = await send(ws, 'add_variables', {
        'variables': ['top.a'],
      });
      expect(msg['type'], 'response');
      final items = (msg['data'] as Map)['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['path'], 'top.a');
    });

    test('add_scope alias adds the scope variables', () async {
      final ws = await connect();
      final msg = await send(ws, 'add_scope', {'scope': 'top'});
      expect(msg['type'], 'response');
      expect((msg['data'] as Map)['items'] as List, hasLength(2));
    });

    test(
      'get_item_list enumerates UI-added signals and prunes UI-removed '
      'ones',
      () async {
        final ws = await connect();
        final tab = tcm.containerFor(container.read(activeTabIdProvider));

        // Simulate a UI-side add (no WCP involvement).
        tab.read(signalGroupsProvider.notifier).addSignals(const [sigA]);
        final list = await send(ws, 'get_item_list');
        final items = (list['data'] as Map)['items'] as List;
        expect(items, hasLength(1));
        expect((items.first as Map)['path'], 'top.a');
        expect((items.first as Map)['type'], 'Variable');

        // Simulate a UI-side removal; the registry entry must be pruned.
        tab.read(signalGroupsProvider.notifier).removeSignal(0);
        final after = await send(ws, 'get_item_list');
        expect((after['data'] as Map)['items'] as List, isEmpty);
      },
    );

    test('set_item_color on an added signal succeeds', () async {
      final ws = await connect();
      final add = await send(ws, 'add_items', {'item_path': 'top.a'});
      final id =
          (((add['data'] as Map)['items'] as List).first as Map)['id'] as int;

      final color = await send(ws, 'set_item_color', {
        'id': id,
        'color': '#ff8800',
      });
      expect(color['type'], 'response');
    });

    test('a signal displayed twice has one item id per row', () async {
      final ws = await connect();
      List<int> idsOf(Map<String, dynamic> msg) => [
        for (final i in (msg['data'] as Map)['items'] as List)
          (i as Map)['id'] as int,
      ];
      final first = idsOf(
        await send(ws, 'add_variables', {
          'variables': ['top.a', 'top.b'],
        }),
      );
      final second = idsOf(await send(ws, 'add_scope', {'scope': 'top'}));
      expect(first, hasLength(2));
      expect(second, hasLength(2));
      expect({...first, ...second}, hasLength(4));

      final tab = tcm.containerFor(container.read(activeTabIdProvider));
      expect(tab.read(signalGroupsProvider).signalCount, 4);
      final list = idsOf(await send(ws, 'get_item_list'));
      expect(list, unorderedEquals([...first, ...second]));

      // Removing one id removes exactly its row; the other row of the same
      // signal keeps its id.
      await send(ws, 'remove_items', {
        'ids': [second.first],
      });
      expect(tab.read(signalGroupsProvider).signalCount, 3);
      expect(
        idsOf(await send(ws, 'get_item_list')),
        unorderedEquals([...first, second.last]),
      );

      final color = await send(ws, 'set_item_color', {
        'id': first.first,
        'color': 'red',
      });
      expect(color['type'], 'response');
      final rows = tab.read(signalGroupsProvider).entries;
      expect(rows.first.argbColor, 0xFFFF0000);
    });

    test('set_item_color accepts colour names and short hex', () async {
      final ws = await connect();
      final add = await send(ws, 'add_items', {'item_path': 'top.a'});
      final id =
          (((add['data'] as Map)['items'] as List).first as Map)['id'] as int;
      final tab = tcm.containerFor(container.read(activeTabIdProvider));
      int? argb() => tab.read(signalGroupsProvider).entries.first.argbColor;

      for (final (name, expected) in [
        ('Green', 0xFF00FF00),
        ('  ORANGE ', 0xFFFFA500),
        ('grey', 0xFF808080),
        ('#0f0', 0xFF00FF00),
        ('#00ff0080', 0x00FF0080),
      ]) {
        final msg = await send(ws, 'set_item_color', {
          'id': id,
          'color': name,
        });
        expect(msg['type'], 'response', reason: name);
        expect(argb(), expected, reason: name);
      }

      final bad = await send(ws, 'set_item_color', {
        'id': id,
        'color': 'chartreuse-ish',
      });
      expect(bad['type'], 'error');
      expect(bad['code'], 3);
    });

    test('get_item_info returns info for an added signal id', () async {
      final ws = await connect();
      final add = await send(ws, 'add_items', {'item_path': 'top.a'});
      final id =
          (((add['data'] as Map)['items'] as List).first as Map)['id'] as int;

      final info = await send(ws, 'get_item_info', {
        'ids': [id],
      });
      expect(info['type'], 'response');
      final items = (info['data'] as Map)['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['path'], 'top.a');
    });

    test('get_item_list reflects added signals', () async {
      final ws = await connect();
      await send(ws, 'add_items', {'item_path': 'top.a'});
      final list = await send(ws, 'get_item_list');
      final items = (list['data'] as Map)['items'] as List;
      expect(items, hasLength(1));
    });

    test('wavecrux.getHierarchy returns the scope tree', () async {
      final ws = await connect();
      final msg = await send(ws, 'wavecrux.getHierarchy');
      expect(msg['type'], 'response');
      final scopes = (msg['data'] as Map)['scopes'] as List;
      expect(scopes, hasLength(1));
      final top = scopes.first as Map;
      expect(top['name'], 'top');
      expect(top['variables'] as List, hasLength(2));
    });

    test(
      'getValueAt loads the signal before querying when not yet loaded',
      () async {
        final ws = await connect();
        final msg = await send(ws, 'wavecrux.getValueAt', {
          'signal_path': 'top.b',
          'time': 100,
        });
        expect(msg['type'], 'response');
        expect((msg['data'] as Map)['value'], '42');
        // isSignalLoaded was false, so loadSignal must have been invoked.
        verify(() => source.loadSignal('B')).called(1);
      },
    );

    test('reload re-opens the current file (broadcasts loaded)', () async {
      final ws = await connect();
      // Seed a current file path so reload does not short-circuit on the
      // "no file loaded" guard, then assert it re-opened that path.
      tabNotifier().currentFilePath = '/tmp/loaded.vcd';

      // reload broadcasts a `waveforms_loaded` event to all clients, which can
      // arrive before the command response; skip event frames.
      var msg = await send(ws, 'reload');
      while (msg['type'] == 'event') {
        msg = await ws.next();
      }
      expect(msg['type'], 'response');
      expect(tabNotifier().openCalls, 1);
    });

    test('load opens the requested source and returns a response', () async {
      final ws = await connect();
      var msg = await send(ws, 'load', {'source': '/tmp/new.vcd'});
      while (msg['type'] == 'event') {
        msg = await ws.next();
      }
      expect(msg['type'], 'response');
      expect(tabNotifier().openCalls, 1);
      expect(tabNotifier().currentFilePath, '/tmp/new.vcd');
    });

    test('clear empties the signal group and registry', () async {
      final ws = await connect();
      await send(ws, 'add_items', {'item_path': 'top.a'});
      final clear = await send(ws, 'clear');
      expect(clear['type'], 'response');

      final list = await send(ws, 'get_item_list');
      expect((list['data'] as Map)['items'] as List, isEmpty);
    });

    test('shutdown returns a response then stops the server', () async {
      final ws = await connect();
      final msg = await send(ws, 'shutdown');
      expect(msg['type'], 'response');
      // The server stops ~50 ms later; give it time and assert it is down.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(container.read(remoteControlProvider).isRunning, isFalse);
    });
  });
}
