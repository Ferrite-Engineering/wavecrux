// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_lists.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/links/wavecrux_link.dart';
import 'package:wavecrux/services/links/wavecrux_link_handler.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform/streaming_vcd_service.dart';

import '../../helpers/in_memory_workspace_service.dart';
import '../../helpers/product_telemetry_config.dart';

/// The whole link flow over the real workspace, tab container manager and VCD
/// reader: the confirmation is asked exactly when the file is new to the user
/// and its answer is not remembered, an open file's tab is focused rather than
/// duplicated, the signal is added and selected, the time lands on the right
/// tick and clamps to the file, and every refusal opens nothing.

/// `scalar_basics.vcd`: 1 ns timescale, `top.clk` / `top.rst` / `top.data`,
/// time 0 to 100.
final String _fixture = p.join(
  Directory.current.path,
  'test',
  'fixtures',
  'vcd',
  'scalar_basics.vcd',
);

class _Harness {
  _Harness(this.root, this.tcm, this.dir);

  final ProviderContainer root;
  final TabContainerManager tcm;
  final Directory dir;
  final List<String> asked = [];
  bool answer = true;

  Future<bool> confirm(String path) async {
    asked.add(path);
    return answer;
  }

  Future<WaveCruxLinkOutcome> open(String raw) =>
      openWaveCruxLink(root, raw, confirm: confirm);

  ProviderContainer activeTab() =>
      tcm.containerFor(root.read(activeTabIdProvider));

  int get tabCount => root.read(tabListProvider).length;
}

Future<_Harness> _harness() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final tcm = TabContainerManager(
    extraTabOverrides: [
      waveformSourceProvider.overrideWith(_RealVcdSourceNotifier.new),
    ],
  );
  final root = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      ...testWorkspaceOverrides(),
      tabContainerManagerProvider.overrideWithValue(tcm),
    ],
  );
  tcm.init(root);
  await root.read(workspaceProvider.future);
  final dir = Directory(
    Directory.systemTemp
        .createTempSync('wavecrux_link_handler_')
        .resolveSymbolicLinksSync(),
  );
  addTearDown(() {
    tcm.dispose();
    root.dispose();
    dir.deleteSync(recursive: true);
  });
  return _Harness(root, tcm, dir);
}

/// A copy of the fixture in the harness's own folder, so each test starts
/// with a file the user has never opened.
String _copy(_Harness h, [String name = 'dump.vcd']) {
  final path = p.join(h.dir.path, name);
  File(_fixture).copySync(path);
  return path;
}

/// The hierarchical names of the signals shown in [tab].
List<String?> _shown(ProviderContainer tab) => [
  for (final e in tab.read(signalGroupsProvider).entries) e.signalPath,
];

String _link(String file, {String? signal, String? t}) {
  final query = [
    'file=${Uri.encodeComponent(file)}',
    if (signal != null) 'signal=${Uri.encodeComponent(signal)}',
    if (t != null) 't=${Uri.encodeComponent(t)}',
  ].join('&');
  return 'wavecrux://open?$query';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the confirmation', () {
    test('a file the user has not opened is confirmed first, by its resolved '
        'path', () async {
      final h = await _harness();
      final path = _copy(h);
      final outcome = await h.open(_link(path));
      expect(h.asked, [path]);
      expect(outcome.opened, isTrue);
      expect(outcome.openedTab, isTrue);
      expect(h.tabCount, 1);
      expect(h.activeTab().read(waveformSourceProvider).value, isNotNull);
    });

    test('declining opens nothing', () async {
      final h = await _harness();
      final path = _copy(h);
      h.answer = false;
      final outcome = await h.open(_link(path, signal: 'top.clk', t: '20ns'));
      expect(outcome.declined, isTrue);
      expect(outcome.opened, isFalse);
      expect(h.tabCount, 0);
    });

    test('a confirmation that throws counts as Cancel', () async {
      final h = await _harness();
      final path = _copy(h);
      final outcome = await openWaveCruxLink(
        h.root,
        _link(path),
        confirm: (_) async => throw StateError('no navigator'),
      );
      expect(outcome.declined, isTrue);
      expect(h.tabCount, 0);
    });

    test('a file open in a tab is focused without asking, never '
        'duplicated', () async {
      final h = await _harness();
      final path = _copy(h);
      await h.open(_link(path));
      final other = _copy(h, 'other.vcd');
      await h.open(_link(other));
      expect(h.tabCount, 2);
      h.asked.clear();

      final outcome = await h.open(_link(path, signal: 'top.rst'));
      expect(h.asked, isEmpty);
      expect(outcome.openedTab, isFalse);
      expect(h.tabCount, 2);
      final active = h.root
          .read(tabListProvider)
          .singleWhere((t) => t.id == h.root.read(activeTabIdProvider));
      expect(active.filePath, path);
    });

    test('a file in Recent Files opens without asking', () async {
      final h = await _harness();
      final path = _copy(h);
      h.root.read(recentFiles.provider.notifier).markOpened(path);
      final outcome = await h.open(_link(path));
      expect(h.asked, isEmpty);
      expect(outcome.opened, isTrue);
    });

    test('consent is not remembered: closing the tab asks again', () async {
      final h = await _harness();
      final path = _copy(h);
      await h.open(_link(path));
      expect(h.asked, hasLength(1));
      expect(
        h.root.read(recentFiles.provider),
        isNot(contains(path)),
        reason: 'a link open must not quietly add the file to Recent Files',
      );
      final tabId = h.root.read(activeTabIdProvider);
      await h.root.wavecruxWorkspace.closeTab(tabId);
      expect(h.tabCount, 0);

      await h.open(_link(path));
      expect(h.asked, hasLength(2));
    });

    test('a file swapped while the question was up is not opened', () async {
      final h = await _harness();
      final path = _copy(h);
      final outcome = await openWaveCruxLink(
        h.root,
        _link(path),
        confirm: (asked) async {
          File(asked).deleteSync();
          return true;
        },
      );
      expect(outcome.failure, WaveCruxLinkFailure.fileNotFound);
      expect(h.tabCount, 0);
    });
  });

  group('refusals open nothing and ask nothing', () {
    test('a malformed link', () async {
      final h = await _harness();
      final outcome = await h.open('wavecrux://run?file=/x.vcd');
      expect(outcome.failure, WaveCruxLinkFailure.malformed);
      expect(outcome.parseRefusal, WaveCruxLinkRefusal.malformed);
      expect(h.asked, isEmpty);
      expect(h.tabCount, 0);
    });

    test('a relative path', () async {
      final h = await _harness();
      final outcome = await h.open('wavecrux://open?file=sim/dump.vcd');
      expect(outcome.failure, WaveCruxLinkFailure.pathRefused);
      expect(h.asked, isEmpty);
    });

    test('a missing file names the file', () async {
      final h = await _harness();
      final outcome = await h.open(_link(p.join(h.dir.path, 'gone.vcd')));
      expect(outcome.failure, WaveCruxLinkFailure.fileNotFound);
      expect(outcome.fileName, 'gone.vcd');
      expect(h.asked, isEmpty);
      expect(h.tabCount, 0);
    });

    test('a file that is not a waveform', () async {
      final h = await _harness();
      final script = p.join(h.dir.path, 'run.sh');
      File(script).writeAsStringSync('echo hi');
      final outcome = await h.open(_link(script));
      expect(outcome.failure, WaveCruxLinkFailure.notAWaveform);
      expect(outcome.fileName, 'run.sh');
      expect(h.asked, isEmpty);
      expect(h.tabCount, 0);
    });
  });

  group('signal', () {
    test('an exact name is added and selected', () async {
      final h = await _harness();
      final path = _copy(h);
      final outcome = await h.open(_link(path, signal: 'top.data'));
      expect(outcome.signalNotFound, isFalse);
      final tab = h.activeTab();
      expect(_shown(tab), contains('top.data'));
      expect(tab.read(selectedVariablesProvider), contains('top.data'));
      expect(h.root.read(selectedSignalProvider), isNotNull);
    });

    test('a unique tail resolves; an unknown name opens the file and says '
        'so', () async {
      final h = await _harness();
      final path = _copy(h);
      final tail = await h.open(_link(path, signal: 'clk'));
      expect(tail.signalNotFound, isFalse);
      expect(_shown(h.activeTab()), contains('top.clk'));

      final unknown = await h.open(_link(path, signal: 'top.nope'));
      expect(unknown.opened, isTrue);
      expect(unknown.signalNotFound, isTrue);
      expect(unknown.signal, 'top.nope');
    });

    test('a signal already in the view is selected, not added twice', () async {
      final h = await _harness();
      final path = _copy(h);
      await h.open(_link(path, signal: 'top.rst'));
      await h.open(_link(path, signal: 'top.rst'));
      expect(_shown(h.activeTab()).where((n) => n == 'top.rst'), hasLength(1));
    });
  });

  group('time', () {
    test('a time with a unit lands on its tick', () async {
      final h = await _harness();
      final path = _copy(h);
      final outcome = await h.open(_link(path, t: '0.04us'));
      expect(outcome.timeClamped, isFalse);
      expect(h.activeTab().read(cursorStateProvider).primaryCursorTime, 40);
    });

    test('a bare number is ticks', () async {
      final h = await _harness();
      final path = _copy(h);
      await h.open(_link(path, t: '70'));
      expect(h.activeTab().read(cursorStateProvider).primaryCursorTime, 70);
    });

    test('a time past the end clamps to the end and says so', () async {
      final h = await _harness();
      final path = _copy(h);
      final outcome = await h.open(_link(path, t: '5ms'));
      expect(outcome.timeClamped, isTrue);
      final source = h.activeTab().read(waveformSourceProvider).value!;
      expect(
        h.activeTab().read(cursorStateProvider).primaryCursorTime,
        source.endTime,
      );
    });

    test('a huge tick count clamps instead of overflowing', () async {
      final h = await _harness();
      final path = _copy(h);
      final outcome = await h.open(_link(path, t: '9' * 24));
      expect(outcome.timeClamped, isTrue);
    });

    test('a file with no timescale cannot place a time with a unit', () async {
      final h = await _harness();
      final path = p.join(h.dir.path, 'noscale.vcd');
      File(path).writeAsStringSync(
        File(_fixture).readAsStringSync().replaceFirst(
          r'$timescale 1 ns $end',
          '',
        ),
      );
      final outcome = await h.open(_link(path, t: '20ns'));
      expect(outcome.opened, isTrue);
      expect(outcome.timeNotPlaced, isTrue);
      final ticks = await h.open(_link(path, t: '20'));
      expect(ticks.timeNotPlaced, isFalse);
      expect(h.activeTab().read(cursorStateProvider).primaryCursorTime, 20);
    });
  });

  group('inbox', () {
    test('holds links until ready, then handles them in turn', () async {
      final handled = <String>[];
      final inbox = WaveCruxLinkInbox((raw) async => handled.add(raw))
        ..add('a');
      await Future<void>.delayed(Duration.zero);
      expect(handled, isEmpty);
      inbox.markReady();
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['a']);
    });

    test('keeps only the newest link while one is in progress', () async {
      final handled = <String>[];
      final gate = Completer<void>();
      WaveCruxLinkInbox((raw) async {
          handled.add(raw);
          if (raw == 'first') await gate.future;
        })
        ..markReady()
        ..add('first')
        ..add('second')
        ..add('third')
        ..add('fourth');
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['first']);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['first', 'fourth']);
    });

    test('a handler that throws does not stop the next link', () async {
      final handled = <String>[];
      final inbox =
          WaveCruxLinkInbox((raw) async {
              handled.add(raw);
              throw StateError('boom');
            })
            ..markReady()
            ..add('a');
      await Future<void>.delayed(Duration.zero);
      inbox.add('b');
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['a', 'b']);
    });
  });
}

/// A per-tab source that opens the real VCD with the production streaming
/// reader, so the file the link names is the bytes that are parsed.
class _RealVcdSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      const AsyncData<WaveformDataSource?>(null);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    currentFilePath = path;
    final source = StreamingVcdService();
    await source.openFile(path);
    await source.streamEndedFuture;
    addTearDown(source.close);
    state = AsyncData(source);
  }
}
