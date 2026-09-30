// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/session/session_extension_codec.dart';
import 'package:wavecrux/services/session/session_service.dart';

// ── fakes ─────────────────────────────────────────────────────────────────────

class _FakeSessionService extends Fake implements SessionService {
  SessionState? saved;
  String? savedPath;
  SessionState? toReturn;
  bool throwOnSave = false;
  bool throwOnLoad = false;

  @override
  Future<void> saveSession(SessionState state, String filePath) async {
    if (throwOnSave) throw SessionSaveException(filePath, 'test error');
    saved = state;
    savedPath = filePath;
  }

  @override
  Future<SessionState> loadSession(String filePath) async {
    if (throwOnLoad) throw SessionLoadException(filePath, 'test error');
    return toReturn ?? const SessionState();
  }
}

class _FakeRecentFilesNotifier extends RecentFilesNotifier {
  final List<String> added = [];

  @override
  Future<List<String>> build() async => [];

  @override
  Future<void> addFile(String path) async => added.add(path);
}

class _FakeWorkspaceService extends Fake implements WorkspaceService {
  _FakeWorkspaceService({this.sidecarPath = '/tmp/sessions/test.wavecrux'});
  final String? sidecarPath;
  @override
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.json',
  }) async => sidecarPath;
}

// A trivial provider + codec used to exercise the session-extension seam
// through the REAL SessionNotifier._snapshot / _restore path.
final _echoProvider = NotifierProvider<_EchoNotifier, String?>(
  _EchoNotifier.new,
);

class _EchoNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  // ignore: use_setters_to_change_properties — method form reads clearer here.
  void set(String? value) => state = value;
}

SessionExtensionCodec _echoCodec() => SessionExtensionCodec(
  capture: (ref) {
    final v = ref.read(_echoProvider);
    return v == null ? null : <String, Object?>{'v': v};
  },
  restore: (ref, payload) {
    if (payload is Map && payload['v'] is String) {
      ref.read(_echoProvider.notifier).set(payload['v'] as String);
    }
  },
);

// ── helpers ───────────────────────────────────────────────────────────────────

Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_sptest_');
  final path = p.join(dir.path, 'session.wavecrux');
  try {
    return await fn(path);
  } finally {
    await dir.delete(recursive: true);
  }
}

ProviderContainer _container({
  SessionService? service,
  WorkspaceService? workspaceService,
  List<Override> extras = const [],
}) {
  final fakeService = service ?? _FakeSessionService();
  final fakeWs = workspaceService ?? _FakeWorkspaceService();
  // Non-keepAlive providers are auto-disposed when there are no subscribers.
  // Subscribe here so state persists across async gaps in tests (no widget tree).
  final c =
      ProviderContainer(
          overrides: [
            sessionServiceProvider.overrideWithValue(fakeService),
            recentFilesProvider.overrideWith(_FakeRecentFilesNotifier.new),
            // Per-tab autosave reads `tabIdProvider` and `workspaceServiceProvider`.
            // Provide both so reads from outside a TabContainerManager-scoped
            // container don't trip the sentinel UnimplementedError.
            tabIdProvider.overrideWithValue(TabId.generate()),
            workspaceServiceProvider.overrideWithValue(fakeWs),
            ...extras,
          ],
        )
        ..listen(cursorStateProvider, (_, _) {})
        ..listen(markerStateProvider, (_, _) {})
        ..listen(panelLayoutProvider, (_, _) {})
        ..listen(timeMapperProvider, (_, _) {});
  addTearDown(c.dispose);
  return c;
}

// ── sessionServiceProvider ────────────────────────────────────────────────────

void main() {
  // Required so that platform channel calls (e.g. path_provider) throw
  // MissingPluginException rather than "Binding has not yet been initialized".
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sessionServiceProvider', () {
    test('returns a SessionService instance', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(sessionServiceProvider), isA<SessionService>());
    });
  });

  // ── SessionNotifier ─────────────────────────────────────────────────────────

  group('SessionNotifier — initial state', () {
    test('starts with null path', () {
      final c = _container();
      expect(c.read(sessionProvider), isNull);
    });
  });

  group('SessionNotifier — saveToPath', () {
    test('writes session to file and updates state', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).saveToPath(path);
        expect(c.read(sessionProvider), path);
        expect(fake.savedPath, path);
        expect(fake.saved, isNotNull);
      });
    });

    test('captures signalGroup from provider', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      // Add a signal to the signal group.
      c
          .read(signalGroupsProvider.notifier)
          .restoreFromSession(
            SignalGroup(
              entries: [
                SignalEntry.signal(
                  signalRef: 'top.clk',
                  displayName: 'clk',
                  format: DisplayFormat.binary,
                ),
              ],
            ),
          );

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).saveToPath(path);
        expect(fake.saved!.signalGroup.signalCount, 1);
        expect(fake.saved!.signalGroup.entries[0].signalRef, 'top.clk');
      });
    });

    test('captures cursor state', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      c.read(cursorStateProvider.notifier).placePrimary(500);
      c.read(cursorStateProvider.notifier).placeSecondary(750);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).saveToPath(path);
        expect(fake.saved!.cursorState.primaryCursorTime, 500);
        expect(fake.saved!.cursorState.secondaryCursorTime, 750);
      });
    });

    test('captures marker state', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      c.read(markerStateProvider.notifier).setMarker('a', 1000);
      c.read(markerStateProvider.notifier).setMarker('b', 2000);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).saveToPath(path);
        expect(fake.saved!.markerState.getMarker('a'), 1000);
        expect(fake.saved!.markerState.getMarker('b'), 2000);
      });
    });

    test('captures panel layout', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      c.read(panelLayoutProvider.notifier).setSignalTreeVisible(visible: false);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).saveToPath(path);
        expect(fake.saved!.signalTreeVisible, isFalse);
      });
    });

    test('adds path to recent files', () async {
      final fake = _FakeSessionService();
      final fakeRecent = _FakeRecentFilesNotifier();
      final c = ProviderContainer(
        overrides: [
          sessionServiceProvider.overrideWithValue(fake),
          recentFilesProvider.overrideWith(() => fakeRecent),
        ],
      );
      addTearDown(c.dispose);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).saveToPath(path);
        expect(fakeRecent.added, contains(path));
      });
    });

    test('propagates SessionSaveException', () async {
      final fake = _FakeSessionService()..throwOnSave = true;
      final c = _container(service: fake);

      await _withTempFile((path) async {
        expect(
          () => c.read(sessionProvider.notifier).saveToPath(path),
          throwsA(isA<SessionSaveException>()),
        );
      });
    });
  });

  group('SessionNotifier — save', () {
    test('no-op when path is null', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      await c.read(sessionProvider.notifier).save();
      expect(fake.saved, isNull);
    });

    test('saves to existing path when set', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).saveToPath(path);
        fake.saved = null;

        await c.read(sessionProvider.notifier).save();
        expect(fake.savedPath, path);
        expect(fake.saved, isNotNull);
      });
    });
  });

  group('SessionNotifier — loadFromPath', () {
    test('restores cursor state', () async {
      final fake = _FakeSessionService()
        ..toReturn = const SessionState(
          cursorState: CursorState(primaryCursorTime: 300),
        );
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
      });

      expect(c.read(cursorStateProvider).primaryCursorTime, 300);
    });

    test('restores markers', () async {
      final markers = const MarkerState().setMarker('a', 999);
      final fake = _FakeSessionService()
        ..toReturn = SessionState(markerState: markers);
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
      });

      expect(c.read(markerStateProvider).getMarker('a'), 999);
    });

    test('restores panel layout', () async {
      final fake = _FakeSessionService()
        ..toReturn = const SessionState(
          signalTreeVisible: false,
          transactionViewVisible: true,
        );
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
      });

      expect(c.read(panelLayoutProvider).signalTreeVisible, isFalse);
      expect(
        c.read(panelLayoutProvider).transactionViewVisible,
        isTrue,
      );
    });

    test('restores signal group', () async {
      final group = SignalGroup(
        entries: [SignalEntry.signal(signalRef: 'r', displayName: 'd')],
      );
      final fake = _FakeSessionService()
        ..toReturn = SessionState(signalGroup: group);
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
      });

      expect(c.read(signalGroupsProvider).signalCount, 1);
    });

    test('sets pending zoom/pan on TimeMapperNotifier', () async {
      final fake = _FakeSessionService()
        ..toReturn = const SessionState(
          ticksPerPixel: 7.5,
          panOffsetTicks: 123,
        );
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
      });

      // After restore the mapper still holds empty state because initialize()
      // hasn't been called by the canvas yet.  Verify that pending values were
      // registered by reading the notifier fields indirectly via initialize.
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 1000,
          );
      final mapper = c.read(timeMapperProvider);
      expect(mapper.ticksPerPixel, closeTo(7.5, 0.001));
      expect(mapper.panOffsetTicks, closeTo(123, 0.001));
    });

    test('updates state to session path', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
        expect(c.read(sessionProvider), path);
      });
    });

    test('propagates SessionLoadException', () async {
      final fake = _FakeSessionService()..throwOnLoad = true;
      final c = _container(service: fake);

      await _withTempFile((path) async {
        expect(
          () => c.read(sessionProvider.notifier).loadFromPath(path),
          throwsA(isA<SessionLoadException>()),
        );
      });
    });
  });

  // ── TimeMapperNotifier — setPendingZoomPan ───────────────────────────────────

  group('TimeMapperNotifier — setPendingZoomPan', () {
    test('pending values applied on next initialize', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c
          .read(timeMapperProvider.notifier)
          .setPendingZoomPan(
            ticksPerPixel: 3,
            panOffsetTicks: 500,
          );
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 800,
          );
      final m = c.read(timeMapperProvider);
      expect(m.ticksPerPixel, 3.0);
      expect(m.panOffsetTicks, 500.0);
    });

    test(
      'pending cleared after initialize — second initialize uses fitAll',
      () {
        final c = ProviderContainer();
        addTearDown(c.dispose);

        c
            .read(timeMapperProvider.notifier)
            .setPendingZoomPan(
              ticksPerPixel: 3,
              panOffsetTicks: 500,
            );
        c
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 10000,
              viewportWidth: 800,
            );
        // Second initialize should fitAll (pending was consumed).
        c
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 10000,
              viewportWidth: 800,
            );
        final m = c.read(timeMapperProvider);
        // fitAll: ticksPerPixel = range / width = 10000 / 800 = 12.5
        expect(m.ticksPerPixel, closeTo(12.5, 0.001));
      },
    );

    test('ticksPerPixel is clamped to valid range', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c
          .read(timeMapperProvider.notifier)
          .setPendingZoomPan(
            ticksPerPixel: 1e20, // unreasonably large
            panOffsetTicks: 0,
          );
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 1000,
            viewportWidth: 800,
          );
      final m = c.read(timeMapperProvider);
      expect(m.ticksPerPixel, lessThanOrEqualTo(m.maxTicksPerPixel));
    });
  });

  // ── WaveformSourceNotifier — currentFilePath ─────────────────────────────────

  group('WaveformSourceNotifier — currentFilePath', () {
    test('starts as null', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(waveformSourceProvider.notifier).currentFilePath,
        isNull,
      );
    });

    test('close resets currentFilePath to null', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(waveformSourceProvider.notifier)
        ..currentFilePath = '/tmp/test.vcd';
      unawaited(notifier.close());
      expect(notifier.currentFilePath, isNull);
    });
  });

  // ── Session save/load round-trip (real SessionService) ──────────────────────

  group('SessionNotifier — full round-trip with real SessionService', () {
    test('all fields survive save → load cycle', () async {
      await _withTempFile((path) async {
        // Build a rich session: signals with formats, cursors, markers, zoom,
        // panels. Leave sourceFilePath null to avoid triggering openFile.
        final markers = const MarkerState()
            .setMarker('a', 500)
            .setMarker('z', 9999);
        final group = SignalGroup(
          entries: [
            SignalEntry.signal(
              signalRef: 'top.clk',
              displayName: 'clk',
              format: DisplayFormat.binary,
              laneHeight: 40,
            ),
            SignalEntry.group(
              groupName: 'Bus',
              children: [
                SignalEntry.signal(
                  signalRef: 'top.data',
                  displayName: 'data',
                  argbColor: 0xFF00FF00,
                ),
              ],
            ),
            const SignalEntry.separator(),
            const SignalEntry.comment(text: 'annotation'),
          ],
        );
        final original = SessionState(
          signalGroup: group,
          cursorState: const CursorState(
            primaryCursorTime: 1000,
            secondaryCursorTime: 2000,
          ),
          markerState: markers,
          ticksPerPixel: 3.5,
          panOffsetTicks: 250,
          signalTreeVisible: false,
          transactionViewVisible: true,
          translateFilterPaths: const {'top.state': '/path/to/filter.txt'},
          fsmAnnotations: const {
            'top.fsm.state': FsmAnnotation(
              signalRef: 'top.fsm.state',
              stateLabels: {'0': 'IDLE', '1': 'RUN'},
            ),
          },
        );

        // Use a real SessionService against a real temp file.
        const service = SessionService();
        await service.saveSession(original, path);
        final loaded = await service.loadSession(path);

        expect(loaded, equals(original));
      });
    });

    test('round-trip via SessionNotifier restores providers', () async {
      final c = _container();
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(
            signalRef: 'top.q',
            displayName: 'q',
            format: DisplayFormat.signedDecimal,
          ),
        ],
      );

      c.read(signalGroupsProvider.notifier).restoreFromSession(group);
      c.read(cursorStateProvider.notifier).placePrimary(300);
      c.read(markerStateProvider.notifier).setMarker('b', 700);
      c
          .read(panelLayoutProvider.notifier)
          .setValueColumnVisible(visible: false);

      // Save with real service to temp file, then load back.
      await _withTempFile((path) async {
        const realService = SessionService();
        final container2 = _container(service: realService);

        // Inject saved signal group / cursor / marker into a real save.
        container2
            .read(signalGroupsProvider.notifier)
            .restoreFromSession(group);
        container2.read(cursorStateProvider.notifier).placePrimary(300);
        container2.read(markerStateProvider.notifier).setMarker('b', 700);
        container2
            .read(panelLayoutProvider.notifier)
            .setValueColumnVisible(visible: false);
        container2
            .read(fsmAnnotationProvider.notifier)
            .setAnnotation(
              'top.fsm.state',
              const FsmAnnotation(
                signalRef: 'top.fsm.state',
                stateLabels: {'0': 'IDLE', '1': 'RUN'},
              ),
            );

        await container2.read(sessionProvider.notifier).saveToPath(path);

        // Load into a fresh container.
        final container3 = _container(service: realService);
        await container3.read(sessionProvider.notifier).loadFromPath(path);

        expect(
          container3.read(signalGroupsProvider).entries.first.signalRef,
          'top.q',
        );
        expect(
          container3.read(signalGroupsProvider).entries.first.format,
          DisplayFormat.signedDecimal,
        );
        expect(
          container3.read(cursorStateProvider).primaryCursorTime,
          300,
        );
        expect(
          container3.read(markerStateProvider).getMarker('b'),
          700,
        );
        expect(
          container3.read(panelLayoutProvider).valueColumnVisible,
          isFalse,
        );
        final restoredFsm = container3.read(fsmAnnotationProvider);
        expect(restoredFsm.containsKey('top.fsm.state'), isTrue);
        expect(
          restoredFsm['top.fsm.state']!.stateLabels,
          equals(const {'0': 'IDLE', '1': 'RUN'}),
        );
      });
    });

    test('v3 pane sizes, panel flags, and signal-tree state round-trip '
        'through SessionNotifier', () async {
      await _withTempFile((path) async {
        const realService = SessionService();
        final container2 = _container(service: realService);

        container2.read(panelLayoutProvider.notifier)
          ..setLeftPaneSize(312)
          ..setRightPaneSize(188)
          ..setBottomPaneSize(244)
          ..setCocotbLogPanelVisible(visible: true)
          ..setRtlSourceVisible(visible: true);
        container2.read(expandedScopesProvider.notifier).applyExpanded({
          'top',
          'top.cpu',
        });
        container2.read(selectedVariablesProvider.notifier).applySelection({
          'top.clk',
        });
        container2.read(signalTreeScrollProvider.notifier).setOffset(140);
        // Set the search query last so it does not get clobbered.
        container2
            .read(signalSearchQueryProvider.notifier)
            .setQuery(query: 'clk');

        await container2.read(sessionProvider.notifier).saveToPath(path);

        final container3 = _container(service: realService);
        await container3.read(sessionProvider.notifier).loadFromPath(path);

        final panels = container3.read(panelLayoutProvider);
        expect(panels.leftPaneSize, 312);
        expect(panels.rightPaneSize, 188);
        expect(panels.bottomPaneSize, 244);
        expect(panels.cocotbLogPanelVisible, isTrue);
        expect(panels.rtlSourceVisible, isTrue);
        expect(
          container3.read(expandedScopesProvider),
          {'top', 'top.cpu'},
        );
        expect(container3.read(selectedVariablesProvider), {'top.clk'});
        expect(container3.read(signalTreeScrollProvider), 140);
        expect(container3.read(signalSearchQueryProvider), 'clk');
      });
    });
  });

  // ── Graceful degradation: signals not present in waveform ──────────────────

  group('SessionNotifier — loading session with unknown signals', () {
    test('restores signal group even when no waveform is loaded', () async {
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(
            signalRef: 'nonexistent.sig',
            displayName: 'ghost',
          ),
          SignalEntry.signal(
            signalRef: 'also.missing',
            displayName: 'phantom',
          ),
        ],
      );
      final fake = _FakeSessionService()
        ..toReturn = SessionState(signalGroup: group);
      final c = _container(service: fake);

      // Should complete without error.
      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
      });

      // Signal group is restored even though no waveform source is open.
      expect(c.read(signalGroupsProvider).signalCount, 2);
      expect(
        c.read(signalGroupsProvider).entries[0].signalRef,
        'nonexistent.sig',
      );
      // No waveform file opened (sourceFilePath was null in the session).
      expect(c.read(waveformIsLoadedProvider), isFalse);
    });
  });

  // ── Malformed / corrupt session files ──────────────────────────────────────

  group('SessionService — corrupt/malformed session files', () {
    test('invalid JSON throws SessionLoadException', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString('{not!valid!json');
        const service = SessionService();
        await expectLater(
          () => service.loadSession(path),
          throwsA(isA<SessionLoadException>()),
        );
      });
    });

    test('valid JSON but not an object throws SessionLoadException', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString('null');
        const service = SessionService();
        await expectLater(
          () => service.loadSession(path),
          throwsA(isA<SessionLoadException>()),
        );
      });
    });

    test('valid JSON array throws SessionLoadException', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString('[1, 2, 3]');
        const service = SessionService();
        await expectLater(
          () => service.loadSession(path),
          throwsA(isA<SessionLoadException>()),
        );
      });
    });

    test('missing file throws SessionLoadException', () async {
      const service = SessionService();
      await expectLater(
        () => service.loadSession('/nonexistent/path/session.wavecrux'),
        throwsA(isA<SessionLoadException>()),
      );
    });
  });

  // ── Forward compatibility: newer version / unknown keys ────────────────────

  group('SessionService — forward compatibility', () {
    test('unknown top-level keys are silently ignored', () async {
      await _withTempFile((path) async {
        // A session file from a hypothetical future WaveCrux that added extra
        // top-level fields. The current parser must ignore them.
        const json = '''
{
  "version": 99,
  "sourceFilePath": null,
  "signals": [],
  "cursor": { "primary": 42, "secondary": null },
  "markers": {},
  "view": { "ticksPerPixel": 2.0, "panOffsetTicks": 10.0 },
  "panels": { "signalTree": true, "valueColumn": false, "transactionView": true },
  "translateFilters": {},
  "futureFeature": { "someKey": "someValue" },
  "anotherNewField": 12345
}''';
        await File(path).writeAsString(json);
        const service = SessionService();
        final session = await service.loadSession(path);

        expect(session.cursorState.primaryCursorTime, 42);
        expect(session.ticksPerPixel, 2.0);
        expect(session.panOffsetTicks, 10.0);
        expect(session.valueColumnVisible, isFalse);
        expect(session.transactionViewVisible, isTrue);
      });
    });

    test('missing optional fields use defaults', () async {
      await _withTempFile((path) async {
        // Minimal valid session — all optional sections absent.
        await File(path).writeAsString('{"version": 1}');
        const service = SessionService();
        final session = await service.loadSession(path);

        expect(session, equals(const SessionState()));
      });
    });

    test('unknown signal kind degrades to separator', () async {
      await _withTempFile((path) async {
        const json = '''
{
  "version": 1,
  "signals": [
    { "kind": "future_signal_type", "ref": "top.x" }
  ]
}''';
        await File(path).writeAsString(json);
        const service = SessionService();
        final session = await service.loadSession(path);

        expect(session.signalGroup.entries.length, 1);
        expect(session.signalGroup.entries[0].kind, SignalEntryKind.separator);
      });
    });

    test('unknown display format falls back to hexadecimal', () async {
      await _withTempFile((path) async {
        const json = '''
{
  "version": 1,
  "signals": [
    { "kind": "signal", "ref": "top.x", "name": "x", "format": "future_format" }
  ]
}''';
        await File(path).writeAsString(json);
        const service = SessionService();
        final session = await service.loadSession(path);

        expect(
          session.signalGroup.entries[0].format,
          DisplayFormat.hexadecimal,
        );
      });
    });
  });

  // ── SessionNotifier — reloadCurrentFile ────────────────────────────────────

  group('SessionNotifier — reloadCurrentFile', () {
    test('is a no-op when no file is loaded', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      // currentFilePath is null — reloadCurrentFile should return immediately.
      await c.read(sessionProvider.notifier).reloadCurrentFile();

      // Nothing should have changed.
      expect(c.read(signalGroupsProvider).signalCount, 0);
      expect(c.read(cursorStateProvider).primaryCursorTime, isNull);
    });

    test('stages zoom/pan and restores all viewer state', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake);

      // Arrange: put the viewer in a known state.
      c
          .read(signalGroupsProvider.notifier)
          .restoreFromSession(
            SignalGroup(
              entries: [
                SignalEntry.signal(signalRef: 'top.clk', displayName: 'clk'),
              ],
            ),
          );
      c.read(cursorStateProvider.notifier)
        ..placePrimary(200)
        ..placeSecondary(400);
      c.read(markerStateProvider.notifier).setMarker('a', 1000);
      c.read(panelLayoutProvider.notifier).setSignalTreeVisible(visible: false);
      c
          .read(timeMapperProvider.notifier)
          .setPendingZoomPan(
            ticksPerPixel: 5,
            panOffsetTicks: 100,
          );
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 50000,
            viewportWidth: 800,
          );

      // Set the file path directly (the file need not exist — WaveformSourceNotifier
      // catches the open error internally and sets AsyncError state).
      c.read(waveformSourceProvider.notifier).currentFilePath =
          '/nonexistent/sim.vcd';

      await c.read(sessionProvider.notifier).reloadCurrentFile();

      // Signal group is restored from the pre-reload snapshot.
      expect(c.read(signalGroupsProvider).signalCount, 1);
      expect(
        c.read(signalGroupsProvider).entries[0].signalRef,
        'top.clk',
      );

      // Cursors are restored.
      expect(c.read(cursorStateProvider).primaryCursorTime, 200);
      expect(c.read(cursorStateProvider).secondaryCursorTime, 400);

      // Markers are restored.
      expect(c.read(markerStateProvider).getMarker('a'), 1000);

      // Panel layout is restored.
      expect(c.read(panelLayoutProvider).signalTreeVisible, isFalse);
    });

    test(
      'zoom/pan snapshot is staged for the next TimeMapper.initialize',
      () async {
        final fake = _FakeSessionService();
        final c = _container(service: fake);

        // Initialize the time mapper with a known zoom/pan.
        c
            .read(timeMapperProvider.notifier)
            .setPendingZoomPan(
              ticksPerPixel: 8,
              panOffsetTicks: 200,
            );
        c
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 100000,
              viewportWidth: 1000,
            );

        c.read(waveformSourceProvider.notifier).currentFilePath =
            '/nonexistent/sim.vcd';

        await c.read(sessionProvider.notifier).reloadCurrentFile();

        // After reload the pending values are staged. Simulate the canvas calling
        // initialize() on the new TimeMapper.
        c
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 100000,
              viewportWidth: 1000,
            );

        final mapper = c.read(timeMapperProvider);
        expect(mapper.ticksPerPixel, closeTo(8.0, 0.001));
        expect(mapper.panOffsetTicks, closeTo(200, 0.001));
      },
    );
  });

  // ── SessionNotifier — _restore with sourceFilePath set ─────────────────────

  group('SessionNotifier — loadFromPath with sourceFilePath set', () {
    test('does not crash when referenced waveform file is missing', () async {
      final fake = _FakeSessionService()
        ..toReturn = const SessionState(
          sourceFilePath: '/nonexistent/missing.vcd',
          cursorState: CursorState(primaryCursorTime: 42),
        );
      final c = _container(service: fake);

      // Should complete without throwing even though the file doesn't exist.
      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
      });

      // Cursor is still restored despite the failed file open.
      expect(c.read(cursorStateProvider).primaryCursorTime, 42);
    });

    test('restores markers and panels even when waveform open fails', () async {
      final markers = const MarkerState()
          .setMarker('c', 777)
          .setMarker('d', 888);
      final fake = _FakeSessionService()
        ..toReturn = SessionState(
          sourceFilePath: '/nonexistent/missing.vcd',
          markerState: markers,
          signalTreeVisible: false,
          transactionViewVisible: true,
        );
      final c = _container(service: fake);

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).loadFromPath(path);
      });

      expect(c.read(markerStateProvider).getMarker('c'), 777);
      expect(c.read(markerStateProvider).getMarker('d'), 888);
      expect(c.read(panelLayoutProvider).signalTreeVisible, isFalse);
      expect(c.read(panelLayoutProvider).transactionViewVisible, isTrue);
    });

    test(
      'secondary cursor is restored when sourceFilePath is non-null',
      () async {
        final fake = _FakeSessionService()
          ..toReturn = const SessionState(
            sourceFilePath: '/nonexistent/missing.vcd',
            cursorState: CursorState(
              primaryCursorTime: 100,
              secondaryCursorTime: 200,
            ),
          );
        final c = _container(service: fake);

        await _withTempFile((path) async {
          await c.read(sessionProvider.notifier).loadFromPath(path);
        });

        expect(c.read(cursorStateProvider).primaryCursorTime, 100);
        expect(c.read(cursorStateProvider).secondaryCursorTime, 200);
      },
    );
  });

  // ── SessionAutoSaveNotifier ─────────────────────────────────────────────────

  group('SessionAutoSaveNotifier', () {
    test('build() registers listeners without error', () {
      final c = _container();
      // Reading the provider triggers build(), which registers all listeners.
      expect(
        () => c.read(sessionAutoSaveProvider),
        returnsNormally,
      );
    });

    test('state changes schedule the debounce timer', () {
      FakeAsync().run((fake) {
        final fakeService = _FakeSessionService();
        final c = _container(service: fakeService);
        c.read(sessionAutoSaveProvider.notifier).autoSaveInterval =
            const Duration(milliseconds: 200);

        // Trigger multiple state changes; each cancels and reschedules the timer.
        c.read(cursorStateProvider.notifier).placePrimary(10);
        c.read(cursorStateProvider.notifier).placePrimary(20);
        c.read(cursorStateProvider.notifier).placePrimary(30);

        // Timer has not fired yet.
        expect(fakeService.saved, isNull);

        // Advance past the debounce interval; no file loaded → early return.
        fake.elapse(const Duration(milliseconds: 300));

        // Still no save because waveformIsLoaded is false.
        expect(fakeService.saved, isNull);

        c.dispose();
      });
    });

    test('does not save when no waveform is loaded', () {
      FakeAsync().run((fake) {
        final fakeService = _FakeSessionService();
        final c = _container(service: fakeService);
        c.read(sessionAutoSaveProvider.notifier).autoSaveInterval =
            const Duration(milliseconds: 100);

        // Trigger a state change to schedule the timer.
        c.read(cursorStateProvider.notifier).placePrimary(42);

        fake.elapse(const Duration(milliseconds: 200));

        // No waveform loaded — performAutoSave returns early without saving.
        expect(fakeService.saved, isNull);
        c.dispose();
      });
    });

    test('silently skips save when sidecar path is unavailable', () {
      // When WorkspaceService.sidecarPathFor returns null (e.g. path_provider
      // is unavailable in tests), _performAutoSave returns early without
      // throwing. This test verifies the null-path early-return path.
      FakeAsync().run((fake) {
        final fakeService = _FakeSessionService();
        final c = _container(
          service: fakeService,
          workspaceService: _FakeWorkspaceService(sidecarPath: null),
          extras: [waveformIsLoadedProvider.overrideWith((ref) => true)],
        );

        c.read(sessionAutoSaveProvider.notifier).autoSaveInterval =
            const Duration(milliseconds: 100);

        c.read(cursorStateProvider.notifier).placePrimary(99);

        // Should not throw — null sidecar path causes early-return without
        // touching SessionService.saveSession.
        expect(
          () => fake.elapse(const Duration(milliseconds: 200)),
          returnsNormally,
        );
        expect(fakeService.saved, isNull);
      });
    });

    test('writes to the per-tab sidecar path returned by WorkspaceService '
        'when a waveform is loaded', () {
      FakeAsync().run((fake) {
        final fakeSession = _FakeSessionService();
        final fakeWs = _FakeWorkspaceService(
          sidecarPath: '/tmp/wavecrux-test/sessions/abc-1234.wavecrux',
        );
        final c = _container(
          service: fakeSession,
          workspaceService: fakeWs,
          extras: [waveformIsLoadedProvider.overrideWith((ref) => true)],
        );
        c.read(sessionAutoSaveProvider.notifier).autoSaveInterval =
            const Duration(milliseconds: 100);

        c.read(cursorStateProvider.notifier).placePrimary(7);
        fake.elapse(const Duration(milliseconds: 200));

        expect(fakeSession.savedPath, equals(fakeWs.sidecarPath));
        expect(fakeSession.saved, isNotNull);
      });
    });

    test('flushPendingSave forces an immediate write and cancels the '
        'pending debounce timer', () async {
      final fakeSession = _FakeSessionService();
      final fakeWs = _FakeWorkspaceService(
        sidecarPath: '/tmp/wavecrux-test/sessions/flush.wavecrux',
      );
      final c = _container(
        service: fakeSession,
        workspaceService: fakeWs,
        extras: [waveformIsLoadedProvider.overrideWith((ref) => true)],
      );
      // Long interval — the test should NOT wait it out; flushPendingSave
      // is what triggers the write.
      c.read(sessionAutoSaveProvider.notifier).autoSaveInterval =
          const Duration(seconds: 60);
      c.read(cursorStateProvider.notifier).placePrimary(42);

      await c.read(sessionAutoSaveProvider.notifier).flushPendingSave();

      expect(fakeSession.savedPath, equals(fakeWs.sidecarPath));
      expect(fakeSession.saved, isNotNull);
    });

    test('dispose cancels the pending debounce timer', () {
      FakeAsync().run((fake) {
        final fakeService = _FakeSessionService();
        final c = _container(service: fakeService);
        c.read(sessionAutoSaveProvider.notifier).autoSaveInterval =
            const Duration(milliseconds: 100);

        c.read(cursorStateProvider.notifier).placePrimary(1);

        // Dispose before timer fires.
        c.dispose();

        // Elapsing time after dispose should not crash.
        expect(
          () => fake.elapse(const Duration(milliseconds: 200)),
          returnsNormally,
        );
      });
    });
  });

  // ── session-extension codec wiring ─────────────────────────────
  // Proves the seam is plumbed through the REAL SessionNotifier._snapshot /
  // _restore path — not just the SessionExtensions helper in isolation. This
  // is the live wiring the `pro.sva` codec depends on.
  group('SessionNotifier — session-extension codec wiring', () {
    Override echo() => extraSessionPayloadCodecsProvider.overrideWithValue({
      'pro.echo': _echoCodec(),
    });

    test(
      'snapshot captures a registered codec payload into extensions',
      () async {
        final fake = _FakeSessionService();
        final c = _container(service: fake, extras: [echo()]);
        c.read(_echoProvider.notifier).set('hello');

        await _withTempFile((path) async {
          await c.read(sessionProvider.notifier).saveToPath(path);
          expect(fake.saved!.extensions['pro.echo'], <String, Object?>{
            'v': 'hello',
          });
        });
      },
    );

    test('snapshot omits a codec that opts out (returns null)', () async {
      final fake = _FakeSessionService();
      final c = _container(service: fake, extras: [echo()]);
      // _echoProvider is null → codec.capture returns null → no key written.

      await _withTempFile((path) async {
        await c.read(sessionProvider.notifier).saveToPath(path);
        expect(fake.saved!.extensions.containsKey('pro.echo'), isFalse);
      });
    });

    test(
      'restore replays a registered codec payload into the live graph',
      () async {
        final c = _container(extras: [echo()]);
        expect(c.read(_echoProvider), isNull);

        await c
            .read(sessionProvider.notifier)
            .restoreFromState(
              const SessionState(
                extensions: <String, Object?>{
                  'pro.echo': <String, Object?>{'v': 'world'},
                },
              ),
            );

        expect(c.read(_echoProvider), 'world');
      },
    );

    test(
      'unknown-namespace payload survives a restore → snapshot cycle',
      () async {
        final fake = _FakeSessionService();
        // No codec registered → 'pro.future' is opaque to this build.
        final c = _container(service: fake);

        await c
            .read(sessionProvider.notifier)
            .restoreFromState(
              const SessionState(
                extensions: <String, Object?>{
                  'pro.future': <String, Object?>{'opaque': 1},
                },
              ),
            );

        await _withTempFile((path) async {
          await c.read(sessionProvider.notifier).saveToPath(path);
          expect(
            fake.saved!.extensions['pro.future'],
            <String, Object?>{'opaque': 1},
          );
        });
      },
    );

    test(
      'registered codec overlays a fresh value on top of preserved unknowns',
      () async {
        final fake = _FakeSessionService();
        final c = _container(service: fake, extras: [echo()]);

        await c
            .read(sessionProvider.notifier)
            .restoreFromState(
              const SessionState(
                extensions: <String, Object?>{
                  'pro.future': <String, Object?>{'opaque': 1},
                  'pro.echo': <String, Object?>{'v': 'stale'},
                },
              ),
            );
        // restore set echo='stale'; mutate live so the snapshot must re-capture.
        c.read(_echoProvider.notifier).set('fresh');

        await _withTempFile((path) async {
          await c.read(sessionProvider.notifier).saveToPath(path);
          expect(fake.saved!.extensions['pro.echo'], <String, Object?>{
            'v': 'fresh',
          });
          expect(
            fake.saved!.extensions['pro.future'],
            <String, Object?>{'opaque': 1},
          );
        });
      },
    );
  });
}
