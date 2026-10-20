// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_binding.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../support/fake_waveform_source.dart';

/// Every send the fake dispatcher saw in the current test.
final List<(PeerIdentity, CrossProbeSelection?)> _sent = [];

class _FakeDispatcher extends CrossProbeDispatcher {
  _FakeDispatcher() : super(_unread);

  static T _unread<T>(ProviderListenable<T> provider) =>
      throw UnimplementedError('the fake reads nothing');

  @override
  Future<CrossProbeOutcome> send(
    PeerIdentity peer,
    CrossProbeSelection? selection, {
    String? label,
  }) async {
    _sent.add((peer, selection));
    return const CrossProbeOutcome(CrossProbeOutcomeKind.sent);
  }
}

/// Preloads [waveformSourceProvider] with the reference in-memory source so
/// the panel can translate a selected backend-local `signalRef` (`s_data`)
/// into its canonical `fullPath` (`top.data`), the string a peer can resolve.
Override _sourceOverride() => waveformSourceProvider.overrideWith(
  () => _PreloadedSourceNotifier(FakeWaveformSource.reference()),
);

const _peer = PeerIdentity(
  peerId: 'netcrux-1-2',
  productName: 'netcrux',
  productVersion: '0.1.0',
);

/// Outside an editor host WaveCrux docks the suite-shared bound panel. These
/// tests pin what WaveCrux adds to it: the selection a send carries (the
/// canonical signal path with the cursor time and design id) and that a send is
/// free in every tier. The panel's own chrome is covered where it lives, in the
/// shared package.
void main() {
  setUp(_sent.clear);

  Widget wrap({
    List<Override> overrides = const [],
    Locale locale = const Locale('en'),
    List<PeerIdentity> peers = const [],
    bool running = true,
    List<CxpDialFailure> unreachable = const [],
  }) {
    return ProviderScope(
      overrides: [
        productTelemetryConfig,
        cruxCxpProductBindingProvider.overrideWithValue(kWaveCruxCxpBinding),
        cruxCxpRuntimeProvider.overrideWith((_) async => null),
        cruxCxpPeersProvider.overrideWithValue(peers),
        cruxCxpServerStatusProvider.overrideWithValue((
          running: running,
          port: running ? 54322 : null,
          problem: null,
        )),
        cruxCxpUnreachablePeersProvider.overrideWith(
          (_) => Stream<List<CxpDialFailure>>.value(unreachable),
        ),
        crossProbeDispatcherProvider.overrideWith((_) => _FakeDispatcher()),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: const [
          Locale('en'),
          Locale('zh', 'CN'),
          Locale('ja'),
          Locale('ko'),
        ],
        home: const Scaffold(
          body: SizedBox(
            width: 800,
            height: 800,
            child: WaveCruxCrossProbePanel(),
          ),
        ),
      ),
    );
  }

  group('WaveCruxCrossProbePanel', () {
    testWidgets('shows the empty state when no peers and no events', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(find.text('Connected peers'), findsOneWidget);
      expect(find.text('No peers connected'), findsOneWidget);
      expect(find.text('Recent events'), findsOneWidget);
      expect(find.text('No events yet'), findsOneWidget);
    });

    testWidgets('shows a server-off banner when the CXP server is stopped', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(running: false));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cross_probe_offline_banner')),
        findsOneWidget,
      );
      expect(find.textContaining('CXP server is off'), findsOneWidget);
    });

    testWidgets('renders a row for every connected peer', (tester) async {
      await tester.pumpWidget(
        wrap(
          peers: const [
            PeerIdentity(
              peerId: 'othercrux-1-2',
              productName: 'othercrux',
              productVersion: '0.1.0',
            ),
            _peer,
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No peers connected'), findsNothing);
      expect(
        find.byKey(const Key('cross_probe_send_othercrux-1-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cross_probe_send_netcrux-1-2')),
        findsOneWidget,
      );
    });

    testWidgets('renders a persistent unreachable-peer indicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          unreachable: const [
            CxpDialFailure(
              peerId: 'othercrux-1-2',
              host: '127.0.0.1',
              port: 54399,
              error: 'Connection refused',
              consecutiveFailures: 3,
              nextRetryAfterTicks: 3,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cross_probe_unreachable')),
        findsOneWidget,
      );
      expect(find.text('othercrux-1-2'), findsOneWidget);
      expect(find.text('127.0.0.1:54399'), findsOneWidget);
    });

    testWidgets('clear events empties the shared event log', (tester) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            cruxCxpEventLogProvider.overrideWith(_SeededLog.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Peer connected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cross_probe_clear_events')));
      await tester.pumpAndSettle();
      expect(find.text('No events yet'), findsOneWidget);
    });

    testWidgets('a send carries the canonical signal path, not the local ref', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          peers: const [_peer],
          overrides: [
            _sourceOverride(),
            // The focus stores the backend-local ref `s_data`, not a path.
            selectedSignalProvider.overrideWith(
              () => _StaticSelection('s_data'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();

      expect(_sent, hasLength(1));
      final (peer, selection) = _sent.single;
      expect(peer.peerId, 'netcrux-1-2');
      // Crucially the wire carries the canonical fullPath (`top.data`), NOT the
      // opaque per-process signalRef `s_data` that no peer can resolve.
      expect(selection!.candidates.single.path, 'top.data');
      expect(selection.candidates.single.kind, ElementKind.signal);
      expect(selection.displayName, 'top.data');
    });

    testWidgets('with nothing selected the dispatcher is handed no selection', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(peers: const [_peer]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();

      // The shared send reports "select something first"; WaveCrux's part is
      // to resolve nothing rather than a guess.
      expect(_sent.single.$2, isNull);
    });

    testWidgets('locale sweep: en/zh_CN/ja/ko render without exception', (
      tester,
    ) async {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        await tester.pumpWidget(wrap(locale: locale, peers: const [_peer]));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale');
      }
    });
  });

  group('the selection a send carries', () {
    ProviderContainer container({String? selected}) {
      final c = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          _sourceOverride(),
          if (selected != null)
            selectedSignalProvider.overrideWith(
              () => _StaticSelection(selected),
            ),
        ],
      );
      addTearDown(c.dispose);
      // Keep the auto-disposed per-tab providers alive across reads.
      c.listen(waveformSourceProvider, (_, _) {});
      return c;
    }

    test('is the selected signal as a canonical path', () {
      final c = container(selected: 's_data');
      final selection = resolveWaveCruxCrossProbeSelection(c.read);
      expect(selection, isNotNull);
      expect(selection!.candidates.single.path, 'top.data');
      expect(selection.candidates.single.kind, ElementKind.signal);
    });

    test('is null when nothing is selected', () {
      final c = container();
      expect(resolveWaveCruxCrossProbeSelection(c.read), isNull);
    });

    test('is null when the waveform cannot name the selection', () {
      final c = container(selected: 'not_a_ref');
      expect(resolveWaveCruxCrossProbeSelection(c.read), isNull);
    });

    test('for a signal row is that row path, with no cursor time unset', () {
      final c = container();
      final selection = waveCruxSignalSelection(c.read, 'top.cpu.alu.sum');
      expect(selection.candidates.single.path, 'top.cpu.alu.sum');
      expect(selection.candidates.single.kind, ElementKind.signal);
      expect(selection.metadata.containsKey('wavecrux.cursor_time_fs'), false);
    });
  });

  group('sending a cross-probe is free in every tier', () {
    // Cross-probing is free across the board, sending as well as receiving.
    // Every test here runs after the beta, when a tier check would bite, and
    // pins a real selection and a connected peer, so a send that does not go
    // through can only mean something is gating it.
    for (final tier in LicenseTier.values) {
      testWidgets('post-beta at ${tier.name}: the send goes through', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            peers: const [_peer],
            overrides: [
              betaPeriodProvider.overrideWithValue(false),
              licenseTierProvider.overrideWithValue(tier),
              _sourceOverride(),
              selectedSignalProvider.overrideWith(
                () => _StaticSelection('s_data'),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('cross_probe_send_netcrux-1-2')),
        );
        await tester.pumpAndSettle();
        expect(_sent, hasLength(1));
        expect(find.byType(Dialog), findsNothing);
        expect(find.textContaining('requires WaveCrux'), findsNothing);
      });
    }
  });
}

class _SeededLog extends CruxCxpEventLog {
  @override
  List<CrossProbeEvent> build() => <CrossProbeEvent>[
    CrossProbeEvent.peerConnected(peerLabel: 'netcrux'),
  ];
}

class _StaticSelection extends SelectedSignalNotifier {
  _StaticSelection(this._selection);
  final String? _selection;
  @override
  String? build() => _selection;
}

/// Preloads [waveformSourceProvider] so a selected `signalRef` resolves to its
/// `fullPath`.
class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource> build() => AsyncData(_source);
}
