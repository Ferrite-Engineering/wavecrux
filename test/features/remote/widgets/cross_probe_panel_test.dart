// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/remote/providers/cross_probe_originate_gate_provider.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/cxp_event_log_entry.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../support/fake_waveform_source.dart';

/// Preloads [waveformSourceProvider] with the reference in-memory source so the
/// panel can translate a selected backend-local `signalRef` (`s_data`) into its
/// canonical `fullPath` (`top.data`) — the string a peer can actually resolve.
/// Sending a cross-probe is Pro (the gate group at the end proves both sides
/// of that), so the tests about what a send does run at a Pro seat.
final Override _proSeat = licenseTierProvider.overrideWithValue(
  LicenseTier.pro,
);

Override _sourceOverride() => waveformSourceProvider.overrideWith(
  () => _PreloadedSourceNotifier(FakeWaveformSource.reference()),
);

/// WaveCrux docks the SHARED `crux_cxp_ui.CrossProbePanel`
/// (via [WaveCruxCrossProbePanel] + its controller) instead of a bespoke modal.
/// These tests assert WaveCrux's controller correctly bridges its live CXP
/// providers into the shared widget — peers, the event log (mapped onto the
/// shared semantic event kinds), unreachable peers, the offline banner, and the
/// clear-events command — so the reference adoption renders the shared chrome.
void main() {
  Widget wrap({
    List<Override> overrides = const [],
    Locale locale = const Locale('en'),
    Widget panel = const WaveCruxCrossProbePanel(),
  }) {
    return ProviderScope(
      overrides: [productTelemetryConfig, ...overrides],
      child: MaterialApp(
        // Wire the root messenger key so the controller's send-guard snackbars
        // (no selection / unreachable peer) surface where the tests can find
        // them — production wires the same key in MaterialApp.
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: const [
          Locale('en'),
          Locale('zh', 'CN'),
          Locale('ja'),
          Locale('ko'),
        ],
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 800,
            child: panel,
          ),
        ),
      ),
    );
  }

  group('WaveCruxCrossProbePanel', () {
    testWidgets('shows empty-state when no peers and no events', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(find.text('Connected Peers'), findsOneWidget);
      expect(find.text('No peers connected'), findsOneWidget);
      expect(find.text('Recent Events'), findsOneWidget);
      expect(find.text('No events yet'), findsOneWidget);
    });

    testWidgets(
      'shows a server-offline banner when the CXP server is stopped',
      (tester) async {
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('cross_probe_offline_banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('CXP server is offline'),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders peer rows from cxpPeersProvider', (tester) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            cxpPeersProvider.overrideWith(
              () => _StaticPeers(const [
                PeerIdentity(
                  peerId: 'othercrux-1-2',
                  productName: 'othercrux',
                  productVersion: '0.1.0',
                ),
                PeerIdentity(
                  peerId: 'peercrux-1-2',
                  productName: 'peercrux',
                  productVersion: '0.1.0',
                ),
              ]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('othercrux 0.1.0'), findsOneWidget);
      expect(find.text('peercrux 0.1.0'), findsOneWidget);
      expect(find.text('No peers connected'), findsNothing);
      // A per-peer direct-send control is keyed on the peer id.
      expect(
        find.byKey(const Key('cross_probe_send_othercrux-1-2')),
        findsOneWidget,
      );
    });

    testWidgets('maps event-log entries onto the shared event kinds', (
      tester,
    ) async {
      final ts = DateTime(2026, 5, 24, 10, 30, 45);
      await tester.pumpWidget(
        wrap(
          overrides: [
            cxpEventLogProvider.overrideWith(
              () => _StaticEventLog([
                CxpEventLogEntry(
                  timestamp: ts,
                  direction: CxpEventDirection.outbound,
                  messageKind: CxpMessageKind.notifySelection,
                  peerLabel: '(broadcast)',
                  summary: 'top.cpu.clk',
                ),
                CxpEventLogEntry(
                  timestamp: ts,
                  direction: CxpEventDirection.inbound,
                  messageKind: CxpMessageKind.requestHighlight,
                  peerLabel: 'othercrux',
                  summary: 'top.cpu.alu.sum',
                ),
              ]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // The shared widget renders SEMANTIC labels, not raw wire kinds.
      expect(find.text('Selection sent'), findsOneWidget);
      expect(find.text('Highlight received'), findsOneWidget);
      // Subtitles surface peer · summary.
      expect(find.textContaining('(broadcast) · top.cpu.clk'), findsOneWidget);
      expect(
        find.textContaining('othercrux · top.cpu.alu.sum'),
        findsOneWidget,
      );
      expect(find.text('Clear events'), findsOneWidget);
    });

    testWidgets('clear events button empties the event log', (tester) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            cxpEventLogProvider.overrideWith(
              () => _StaticEventLog([
                CxpEventLogEntry(
                  timestamp: DateTime(2026),
                  direction: CxpEventDirection.inbound,
                  messageKind: CxpMessageKind.notifySelection,
                  peerLabel: 'othercrux',
                ),
              ]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cross_probe_clear_events')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('cross_probe_clear_events')));
      await tester.pumpAndSettle();
      expect(find.text('No events yet'), findsOneWidget);
    });

    testWidgets(
      'renders a persistent unreachable-peer indicator from '
      'cxpDialFailuresProvider',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            overrides: [
              cxpDialFailuresProvider.overrideWith(
                () => _StaticDialFailures(const [
                  CxpDialFailure(
                    peerId: 'othercrux-1-2',
                    host: '127.0.0.1',
                    port: 54399,
                    error: 'Connection refused',
                    consecutiveFailures: 3,
                    nextRetryAfterTicks: 3,
                  ),
                ]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('cross_probe_unreachable')),
          findsOneWidget,
        );
        expect(find.text('Unreachable peers'), findsOneWidget);
        expect(find.text('othercrux-1-2'), findsOneWidget);
        expect(find.text('127.0.0.1:54399'), findsOneWidget);
      },
    );

    testWidgets(
      'unreachable-peer indicator is absent when there are no dial failures',
      (tester) async {
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('cross_probe_unreachable')),
          findsNothing,
        );
        expect(find.text('Unreachable peers'), findsNothing);
      },
    );

    // ── per-peer direct send delivery + guards ────────────────────────────────

    testWidgets(
      'send to a reachable peer with a selection delivers a request_highlight',
      (tester) async {
        const peer = PeerIdentity(
          peerId: 'netcrux-1-2',
          productName: 'netcrux',
          productVersion: '0.1.0',
        );
        final server = _FakeCxpServer(reachable: const [peer]);
        await tester.pumpWidget(
          wrap(
            overrides: [
              _proSeat,
              _sourceOverride(),
              cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
              cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
              // The focus stores the backend-local ref `s_data`, not a path.
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

        expect(server.sent, hasLength(1));
        final (sentPeerId, message) = server.sent.single;
        expect(sentPeerId, 'netcrux-1-2');
        // The explicit panel send is the ack-bearing request_highlight, not
        // fire-and-forget notify_selection.
        expect(message, isA<RequestHighlight>());
        final rh = message as RequestHighlight;
        // Crucially the wire carries the canonical fullPath (`top.data`), NOT
        // the opaque per-process signalRef `s_data` that no peer can resolve.
        expect(rh.element.path, 'top.data');
        expect(rh.element.kind, ElementKind.signal);
      },
    );

    testWidgets(
      'a rejected send (honored:false ack) raises a panel toast',
      (tester) async {
        const peer = PeerIdentity(
          peerId: 'netcrux-1-2',
          productName: 'netcrux',
          productVersion: '0.1.0',
        );
        final server = _FakeCxpServer(
          reachable: const [peer],
          ackHonored: false,
          ackReason: 'element not found: top.data',
        );
        await tester.pumpWidget(
          wrap(
            overrides: [
              _proSeat,
              _sourceOverride(),
              cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
              cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
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

        expect(
          find.byKey(const Key('cross_probe_send_failure')),
          findsOneWidget,
        );
        expect(
          find.textContaining('element not found: top.data'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'send with no selection surfaces a snackbar and delivers nothing',
      (
        tester,
      ) async {
        const peer = PeerIdentity(
          peerId: 'netcrux-1-2',
          productName: 'netcrux',
          productVersion: '0.1.0',
        );
        final server = _FakeCxpServer(reachable: const [peer]);
        await tester.pumpWidget(
          wrap(
            overrides: [
              _proSeat,
              cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
              cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
              // selectedSignalProvider left at its default (null) — no selection.
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
        await tester.pumpAndSettle();

        expect(find.text('Select a signal to send'), findsOneWidget);
        expect(server.sent, isEmpty);
      },
    );

    testWidgets(
      'send to a listed-but-unreachable peer surfaces a snackbar, no delivery',
      (tester) async {
        const peer = PeerIdentity(
          peerId: 'netcrux-1-2',
          productName: 'netcrux',
          productVersion: '0.1.0',
        );
        // Peer is discovered/listed but NOT in the reachable (connected) set.
        final server = _FakeCxpServer(reachable: const <PeerIdentity>[]);
        await tester.pumpWidget(
          wrap(
            overrides: [
              _proSeat,
              cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
              cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
              selectedSignalProvider.overrideWith(
                () => _StaticSelection('top.cpu.alu.sum'),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('cross_probe_send_netcrux-1-2')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining("Can't reach netcrux"), findsOneWidget);
        expect(server.sent, isEmpty);
      },
    );

    testWidgets(
      'a send the peer never receives says so, like an unreachable peer',
      (tester) async {
        const peer = PeerIdentity(
          peerId: 'netcrux-1-2',
          productName: 'netcrux',
          productVersion: '0.1.0',
        );
        // Connected when the button is pressed, gone before the request
        // reaches it: the server reports the send as never delivered.
        final server = _FakeCxpServer(
          reachable: const [peer],
          delivered: false,
        );
        await tester.pumpWidget(
          wrap(
            overrides: [
              _proSeat,
              _sourceOverride(),
              cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
              cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
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

        expect(server.sent, hasLength(1));
        expect(
          find.textContaining("Can't reach netcrux"),
          findsOneWidget,
          reason:
              'a send is never a silent no-op; a press that reached nobody '
              'must say so',
        );
      },
    );

    testWidgets(
      'closing the panel while a send waits for its ack neither throws nor '
      'loses the probe count',
      (tester) async {
        const peer = PeerIdentity(
          peerId: 'netcrux-1-2',
          productName: 'netcrux',
          productVersion: '0.1.0',
        );
        final ackWait = Completer<void>();
        final server = _FakeCxpServer(
          reachable: const [peer],
          // A refusal, so the send would also raise the failure toast on the
          // panel that is no longer there.
          ackHonored: false,
          ackWait: ackWait.future,
        );
        final telemetry = _RecordingTelemetry();
        final showPanel = ValueNotifier<bool>(true);
        addTearDown(showPanel.dispose);
        await tester.pumpWidget(
          wrap(
            overrides: [
              _proSeat,
              telemetryServiceProvider.overrideWithValue(telemetry),
              _sourceOverride(),
              cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
              cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
              selectedSignalProvider.overrideWith(
                () => _StaticSelection('s_data'),
              ),
            ],
            panel: ValueListenableBuilder<bool>(
              valueListenable: showPanel,
              builder: (_, show, _) => show
                  ? const WaveCruxCrossProbePanel()
                  : const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('cross_probe_send_netcrux-1-2')),
        );
        await tester.pump();
        expect(server.sent, hasLength(1));

        // The user closes the panel inside the ack wait, which disposes the
        // controller and its notifiers.
        showPanel.value = false;
        await tester.pump();
        expect(find.byType(WaveCruxCrossProbePanel), findsNothing);

        ackWait.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final probes = telemetry.events
            .where((e) => e.name == 'cxp.crossprobe')
            .toList();
        expect(
          probes,
          hasLength(1),
          reason:
              'the probe reached the peer; closing the panel does not undo '
              'that, so it still counts',
        );
        expect(probes.single.properties, containsPair('honored', false));
      },
    );

    testWidgets('a second refused send to the same peer raises its own toast', (
      tester,
    ) async {
      // Two refusals from one peer with one reason compare equal. Published
      // as-is, the second would not notify the panel and would be silent.
      const peer = PeerIdentity(
        peerId: 'netcrux-1-2',
        productName: 'netcrux',
        productVersion: '0.1.0',
      );
      final server = _FakeCxpServer(
        reachable: const [peer],
        ackHonored: false,
        ackReason: 'element not found: top.data',
      );
      await tester.pumpWidget(
        wrap(
          overrides: [
            _proSeat,
            _sourceOverride(),
            cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
            cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
            selectedSignalProvider.overrideWith(
              () => _StaticSelection('s_data'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final send = find.byKey(const Key('cross_probe_send_netcrux-1-2'));
      final toast = find.byKey(const Key('cross_probe_send_failure'));

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(toast, findsOneWidget);

      // The first toast is gone by the time the user tries again.
      rootScaffoldMessengerKey.currentState!.removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(toast, findsNothing);

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(server.sent, hasLength(2));
      expect(toast, findsOneWidget, reason: 'the second press is not silent');
    });

    testWidgets('locale sweep — en/zh_CN/ja/ko render without exception', (
      tester,
    ) async {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        await tester.pumpWidget(
          wrap(
            locale: locale,
            overrides: [
              cxpDialFailuresProvider.overrideWith(
                () => _StaticDialFailures(const [
                  CxpDialFailure(
                    peerId: 'othercrux-1-2',
                    host: '127.0.0.1',
                    port: 54399,
                    error: 'Connection refused',
                    consecutiveFailures: 1,
                    nextRetryAfterTicks: 0,
                  ),
                ]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale');
      }
    });
  });

  group('the send-failure toast is in the user language', () {
    // The shared panel falls back to English for this toast. Without the
    // app's strings it stayed English in every locale.
    const peer = PeerIdentity(
      peerId: 'netcrux-1-2',
      productName: 'netcrux',
      productVersion: '0.1.0',
    );

    Future<void> sendAndSettle(
      WidgetTester tester, {
      required Locale locale,
      required _FakeCxpServer server,
    }) async {
      await tester.pumpWidget(
        wrap(
          locale: locale,
          overrides: [
            _proSeat,
            _sourceOverride(),
            cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
            cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
            selectedSignalProvider.overrideWith(
              () => _StaticSelection('s_data'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();
    }

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('a refusal with no reason, in $locale', (tester) async {
        await sendAndSettle(
          tester,
          locale: locale,
          server: _FakeCxpServer(reachable: const [peer], ackHonored: false),
        );
        expect(
          find.text(lookupL10N(locale).crossProbeSendFailed('netcrux')),
          findsOneWidget,
        );
      });

      testWidgets('a refusal with the peer reason, in $locale', (
        tester,
      ) async {
        const reason = 'element not found: top.data';
        await sendAndSettle(
          tester,
          locale: locale,
          server: _FakeCxpServer(
            reachable: const [peer],
            ackHonored: false,
            ackReason: reason,
          ),
        );
        expect(
          find.text(
            lookupL10N(locale).crossProbeSendRefused('netcrux', reason),
          ),
          findsOneWidget,
          reason: 'the frame is translated; the reason is the peer words',
        );
      });
    }
  });

  group('the per-peer send button is a route to a Pro capability', () {
    // Origination is sold as Pro. WaveCrux has no other open-core route to
    // gate — this panel IS the door — so its send button has to check the
    // tier itself. Every test here pins a real selection and a reachable
    // peer so that, absent the gate, the send WOULD go through, which is
    // what made the button a bypass before `crossProbeOriginateGateProvider`
    // existed.
    const peer = PeerIdentity(
      peerId: 'netcrux-1-2',
      productName: 'netcrux',
      productVersion: '0.1.0',
    );

    List<Override> gated({
      required bool beta,
      required LicenseTier tier,
      required _FakeCxpServer server,
    }) => [
      betaPeriodProvider.overrideWithValue(beta),
      licenseTierProvider.overrideWithValue(tier),
      _sourceOverride(),
      cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
      cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
      selectedSignalProvider.overrideWith(() => _StaticSelection('s_data')),
    ];

    testWidgets('post-beta at Open Core: nothing is sent, and the user is '
        'told why', (tester) async {
      final server = _FakeCxpServer(reachable: const [peer]);
      await tester.pumpWidget(
        wrap(
          overrides: gated(
            beta: false,
            tier: LicenseTier.openCore,
            server: server,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();

      expect(
        server.sent,
        isEmpty,
        reason:
            'origination is a Pro capability and this button is the only '
            'route to it that ships in open core; without a gate here '
            'there is no paywall on it at all',
      );
      expect(
        find.textContaining('requires WaveCrux Pro'),
        findsOneWidget,
        reason: 'a denied press is never silent',
      );
    });

    testWidgets('post-beta at Pro: the send goes through', (tester) async {
      final server = _FakeCxpServer(reachable: const [peer]);
      await tester.pumpWidget(
        wrap(
          overrides: gated(beta: false, tier: LicenseTier.pro, server: server),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();

      expect(server.sent, hasLength(1));
      expect(find.textContaining('requires WaveCrux Pro'), findsNothing);
    });

    testWidgets('EDU is feature-equivalent to Pro', (tester) async {
      final server = _FakeCxpServer(reachable: const [peer]);
      await tester.pumpWidget(
        wrap(
          overrides: gated(beta: false, tier: LicenseTier.edu, server: server),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();
      expect(server.sent, hasLength(1));
    });

    testWidgets('during the beta every tier sends', (tester) async {
      final server = _FakeCxpServer(reachable: const [peer]);
      await tester.pumpWidget(
        wrap(
          overrides: gated(
            beta: true,
            tier: LicenseTier.openCore,
            server: server,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();
      expect(server.sent, hasLength(1));
      expect(find.textContaining('requires WaveCrux Pro'), findsNothing);
    });

    testWidgets('the panel asks the gate seam rather than the tier directly', (
      tester,
    ) async {
      // Proves the panel is wired to `crossProbeOriginateGateProvider` and
      // not to a hand-rolled tier check that happens to agree with it today
      // — the seam is what a future rebinding (a different deny surface, an
      // overlay) would need to intercept.
      final server = _FakeCxpServer(reachable: const [peer]);
      var asked = 0;
      await tester.pumpWidget(
        wrap(
          overrides: [
            // A tier the default gate would ADMIT, so a send that still
            // gets through can only mean the seam was bypassed.
            ...gated(beta: true, tier: LicenseTier.pro, server: server),
            crossProbeOriginateGateProvider.overrideWith(
              (ref) => (_) {
                asked++;
                return false;
              },
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(server.sent, isEmpty);
    });
  });
}

/// Keeps every telemetry event it is handed.
class _RecordingTelemetry implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}

class _StaticDialFailures extends CxpDialFailures {
  _StaticDialFailures(this._failures);
  final List<CxpDialFailure> _failures;
  @override
  List<CxpDialFailure> build() => _failures;
}

class _StaticPeers extends CxpPeers {
  _StaticPeers(this._peers);
  final List<PeerIdentity> _peers;
  @override
  List<PeerIdentity> build() => _peers;
}

class _StaticEventLog extends CxpEventLog {
  _StaticEventLog(this._entries);
  final List<CxpEventLogEntry> _entries;
  @override
  List<CxpEventLogEntry> build() => _entries;

  @override
  void clear() {
    state = const <CxpEventLogEntry>[];
  }
}

class _StaticSelection extends SelectedSignalNotifier {
  _StaticSelection(this._selection);
  final String? _selection;
  @override
  String? build() => _selection;
}

/// Preloads [waveformSourceProvider] so the panel can translate a selected
/// `signalRef` to its `fullPath`.
class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource> build() => AsyncData(_source);
}

/// A [WaveCruxCxpServer] test double: never opens a socket, reports a fixed
/// reachable-peer set, and records every [sendTo] instead of delivering it.
class _FakeCxpServer extends WaveCruxCxpServer {
  _FakeCxpServer({
    required List<PeerIdentity> reachable,
    this.ackHonored = true,
    this.ackReason,
    this.delivered = true,
    this.ackWait,
  }) : _reachable = reachable,
       super(
         productVersion: '0.0.0-test',
         manifestDirectory: '/tmp/does-not-matter',
         onHighlight: _noHighlight,
         onOpenSource: _noOpenSource,
       );

  final List<PeerIdentity> _reachable;
  final bool ackHonored;
  final String? ackReason;

  /// False models a peer that passed the reachability check and went away
  /// before the request reached it: `delivered: false`, no ack.
  final bool delivered;

  /// When set, the ack is held until this completes — the real server waits
  /// up to five seconds for it.
  final Future<void>? ackWait;
  final List<(String, CxpMessage)> sent = [];

  static Future<CxpHandlerResult> _noHighlight(
    ElementId element,
    Map<String, Object?> metadata,
    CxpStreamCoordinate? coordinate,
  ) async => CxpHandlerResult.honoredOk;

  static Future<CxpHandlerResult> _noOpenSource(
    String filePath,
    int line,
    int? column,
  ) async => CxpHandlerResult.honoredOk;

  @override
  List<PeerIdentity> get connectedPeers => _reachable;

  @override
  bool sendTo(String peerId, CxpMessage message, {String? summary}) {
    sent.add((peerId, message));
    return true;
  }

  @override
  Future<({bool delivered, RequestHighlightAck? ack})> requestHighlight(
    String peerId,
    RequestHighlight request, {
    Duration timeout = const Duration(seconds: 5),
    String? summary,
  }) async {
    sent.add((peerId, request));
    if (ackWait != null) await ackWait;
    if (!delivered) return (delivered: false, ack: null);
    return (
      delivered: true,
      ack: RequestHighlightAck(
        inReplyTo: 'req',
        honored: ackHonored,
        reason: ackReason,
      ),
    );
  }
}

/// A [CxpServerNotifier] whose [server] is the injected fake and which reports
/// the server as running so the panel enables its send controls.
class _FakeServerNotifier extends CxpServerNotifier {
  _FakeServerNotifier(this._server);
  final WaveCruxCxpServer _server;

  @override
  CxpServerState build() => const CxpServerState(isRunning: true);

  @override
  WaveCruxCxpServer? get server => _server;
}
