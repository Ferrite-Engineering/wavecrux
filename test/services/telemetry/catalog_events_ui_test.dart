// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Guards the catalog events that fire from UI and provider code paths:
/// `search.used`, `format.set`, `tool.opened`, `ai.explain_used`, and
/// `cxp.crossprobe`.
///
/// Two things are asserted for each: that the event fires from the production
/// seam — the dialog, the menu, the shortcut, the notifier that ships — and
/// that every string property is inside [_propertyValueClass], the class the
/// ingestion Worker enforces. A value outside it is dropped at the edge, which
/// reads downstream as "nobody used the feature" rather than as an error.
library;

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/ai_model_client_provider.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/ai/providers/explain_selection_provider.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:wavecrux/features/search/providers/search_providers.dart';
import 'package:wavecrux/features/search/widgets/signal_search_dialog.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_row.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/settings/settings_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../helpers/fake_waveform_data_source.dart';
import '../../helpers/in_memory_workspace_service.dart';
import '../../helpers/product_telemetry_config.dart';
import '../../support/fake_waveform_source.dart';

/// Captures every recorded [TelemetryEvent] in memory for assertions.
class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = [];

  @override
  void record(TelemetryEvent event) {
    events.add(event);
  }

  List<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name).toList();
}

/// The ingestion Worker's property-value character class. Anything outside it
/// is dropped on arrival — silently, and per-property, so the event still lands
/// minus the dimension the dashboard is keyed on.
final _propertyValueClass = RegExp(r'^[a-z0-9_]{1,64}$');

/// Asserts a string property both carries [expected] and survives ingestion.
void _expectVocabularyValue(Object? actual, String expected) {
  expect(actual, expected);
  expect(actual, matches(_propertyValueClass));
}

void main() {
  // ── search.used — signal search dialog ──────────────────────────────────────

  group('search.used (signal search dialog)', () {
    Scope scopeWithTwoSignals() => const Scope(
      name: 'top',
      path: 'top',
      type: ScopeType.module,
      variables: [
        Variable(
          name: 'clk',
          varType: VarType.wire,
          direction: VarDirection.input,
          signalRef: 'top.clk',
          scopePath: 'top',
          bitWidth: 1,
        ),
        Variable(
          name: 'data',
          varType: VarType.wire,
          direction: VarDirection.input,
          signalRef: 'top.data',
          scopePath: 'top',
          bitWidth: 8,
        ),
      ],
    );

    ProviderContainer dialogContainer(_RecordingTelemetryService telemetry) {
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          hierarchyProvider.overrideWith(
            (_) => AsyncData([scopeWithTwoSignals()]),
          ),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Widget dialogApp(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: SignalSearchDialog()),
      ),
    );

    testWidgets('adding a result records mode signal_substring', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      await tester.pumpWidget(dialogApp(dialogContainer(telemetry)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('clk'));
      await tester.pumpAndSettle();

      final used = telemetry.named('search.used');
      expect(used, hasLength(1));
      _expectVocabularyValue(
        used.single.properties['mode'],
        'signal_substring',
      );
    });

    testWidgets('the glob mode reaches the event as signal_glob', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      final container = dialogContainer(telemetry);
      await tester.pumpWidget(dialogApp(container));
      // Settle first: the dialog resets the filter in a post-frame callback,
      // which would otherwise undo the mode set below.
      await tester.pumpAndSettle();
      container
          .read(searchDialogFilterProvider.notifier)
          .setMode(SearchMode.glob);
      await tester.pumpAndSettle();

      await tester.tap(find.text('clk'));
      await tester.pumpAndSettle();

      final used = telemetry.named('search.used');
      expect(used, hasLength(1));
      _expectVocabularyValue(used.single.properties['mode'], 'signal_glob');
    });

    testWidgets('two results added in one dialog session record one event', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      await tester.pumpWidget(dialogApp(dialogContainer(telemetry)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('clk'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('data'));
      await tester.pumpAndSettle();

      expect(telemetry.named('search.used'), hasLength(1));
    });

    testWidgets('merely opening the dialog records nothing', (tester) async {
      final telemetry = _RecordingTelemetryService();
      await tester.pumpWidget(dialogApp(dialogContainer(telemetry)));
      await tester.pumpAndSettle();

      expect(telemetry.named('search.used'), isEmpty);
    });
  });

  // ── search.used — pattern search ────────────────────────────────────────────

  group('search.used (pattern search)', () {
    const expression = SignalCondition(
      signalPath: 'top.a',
      operator: ConditionOperator.eq,
      value: '1',
    );

    ProviderContainer patternContainer(
      _RecordingTelemetryService telemetry, {
      bool withSource = true,
    }) {
      final source = FakeWaveformDataSource(
        signals: {
          'top.a': const [
            SignalChange(time: 0, value: '0'),
            SignalChange(time: 10, value: '1'),
            SignalChange(time: 30, value: '0'),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          if (withSource)
            waveformSourceProvider.overrideWith(
              () => _StubSourceNotifier(source),
            ),
          // The notifier resolves signal names through this map; a passthrough
          // entry keeps the fixture's path identical to its signalRef.
          signalVariablesMapProvider.overrideWithValue(const {
            'top.a': Variable(
              name: 'top.a',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: 'top.a',
              scopePath: '',
            ),
          }),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a search that runs against a trace records mode pattern', () async {
      final telemetry = _RecordingTelemetryService();
      final c = patternContainer(telemetry);

      await c.read(patternSearchProvider.notifier).search(expression, 0, 100);

      final used = telemetry.named('search.used');
      expect(used, hasLength(1));
      _expectVocabularyValue(used.single.properties['mode'], 'pattern');
    });

    test('a search with no waveform loaded records nothing', () async {
      final telemetry = _RecordingTelemetryService();
      final c = patternContainer(telemetry, withSource: false);

      await c.read(patternSearchProvider.notifier).search(expression, 0, 100);

      expect(c.read(patternSearchProvider).noWaveform, isTrue);
      expect(telemetry.named('search.used'), isEmpty);
    });

    test('nextMatch is navigation within a run and records nothing', () async {
      final telemetry = _RecordingTelemetryService();
      final c = patternContainer(telemetry);
      await c.read(patternSearchProvider.notifier).search(expression, 0, 100);
      telemetry.events.clear();

      c.read(patternSearchProvider.notifier).nextMatch();

      expect(telemetry.events, isEmpty);
    });
  });

  // ── format.set — per-row format menu ────────────────────────────────────────

  group('format.set (value column row menu)', () {
    Variable clk() => const Variable(
      name: 'clk',
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: 'ref_clk',
      scopePath: 'top',
      bitWidth: 1,
    );

    Future<void> pickFormat(WidgetTester tester, String label) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GestureDetector).first),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Display Format'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a camelCase enum constant round-trips to its snake_case token',
      (tester) async {
        final telemetry = _RecordingTelemetryService();
        final container = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            telemetryServiceProvider.overrideWithValue(telemetry),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(clk());
        final entry = container.read(signalGroupsProvider).entries.first;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: ValueColumnRow(
                  entry: entry,
                  signalValue: null,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await pickFormat(tester, 'Unsigned Decimal');

        final set = telemetry.named('format.set');
        expect(set, hasLength(1));
        _expectVocabularyValue(
          set.single.properties['format'],
          'unsigned_decimal',
        );
        // The token the assertion above pins is the one the enum produces, so a
        // renamed constant fails here rather than silently changing a dashboard.
        expect(
          telemetryEnumToken(DisplayFormat.unsignedDecimal),
          'unsigned_decimal',
        );
        expect(
          container.read(signalGroupsProvider).entries.first.format,
          DisplayFormat.unsignedDecimal,
        );
      },
    );

    testWidgets('dismissing the menu records nothing', (tester) async {
      final telemetry = _RecordingTelemetryService();
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(clk());
      final entry = container.read(signalGroupsProvider).entries.first;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: ValueColumnRow(entry: entry, signalValue: null),
            ),
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GestureDetector).first),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      // Tap outside the menu to dismiss it without choosing a format.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(telemetry.named('format.set'), isEmpty);
    });
  });

  // ── tool.opened — statistics strip ──────────────────────────────────────────

  group('tool.opened (statistics strip)', () {
    ProviderContainer layoutContainer(_RecordingTelemetryService telemetry) {
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('toggling the strip on records tool statistics once', () {
      final telemetry = _RecordingTelemetryService();
      final c = layoutContainer(telemetry);

      c.read(panelLayoutProvider.notifier).toggleStatisticsStrip();

      final opened = telemetry.named('tool.opened');
      expect(opened, hasLength(1));
      _expectVocabularyValue(opened.single.properties['tool'], 'statistics');
    });

    test('toggling the strip closed again records nothing', () {
      final telemetry = _RecordingTelemetryService();
      final c = layoutContainer(telemetry);
      c.read(panelLayoutProvider.notifier).toggleStatisticsStrip();
      telemetry.events.clear();

      c.read(panelLayoutProvider.notifier).toggleStatisticsStrip();

      expect(c.read(panelLayoutProvider).statisticsStripVisible, isFalse);
      expect(telemetry.named('tool.opened'), isEmpty);
    });

    test('the session-restore setter records nothing', () {
      final telemetry = _RecordingTelemetryService();
      final c = layoutContainer(telemetry);

      c
          .read(panelLayoutProvider.notifier)
          .setStatisticsStripVisible(visible: true);

      expect(c.read(panelLayoutProvider).statisticsStripVisible, isTrue);
      expect(telemetry.named('tool.opened'), isEmpty);
    });
  });

  // ── ai.explain_used ─────────────────────────────────────────────────────────

  group('ai.explain_used', () {
    ProviderContainer explainContainer(
      _RecordingTelemetryService telemetry, {
      AiModelClient? client,
    }) {
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          waveformSourceProvider.overrideWith(
            () => _StubSourceNotifier(FakeWaveformSource.reference()),
          ),
          if (client != null) aiModelClientProvider.overrideWithValue(client),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a successful explanation records the event', () async {
      final telemetry = _RecordingTelemetryService();
      final c = explainContainer(telemetry, client: _CannedClient('ok'));
      c.read(selectedVariablesProvider.notifier).toggle('top.clk');

      await c.read(explainSelectionProvider.notifier).explainCurrentSelection();

      expect(
        c.read(explainSelectionProvider).phase,
        ExplainSelectionPhase.ready,
      );
      final used = telemetry.named('ai.explain_used');
      expect(used, hasLength(1));
      expect(used.single.properties, isEmpty);
    });

    test('an empty selection records nothing', () async {
      final telemetry = _RecordingTelemetryService();
      final c = explainContainer(telemetry, client: _CannedClient('unused'));

      await c.read(explainSelectionProvider.notifier).explainCurrentSelection();

      expect(
        c.read(explainSelectionProvider).phase,
        ExplainSelectionPhase.emptySelection,
      );
      expect(telemetry.named('ai.explain_used'), isEmpty);
    });

    test('an unconfigured model records nothing', () async {
      final telemetry = _RecordingTelemetryService();
      // No client override → the open-core no-op client.
      final c = explainContainer(telemetry);
      c.read(selectedVariablesProvider.notifier).toggle('top.clk');

      await c.read(explainSelectionProvider.notifier).explainCurrentSelection();

      expect(
        c.read(explainSelectionProvider).phase,
        ExplainSelectionPhase.notConfigured,
      );
      expect(telemetry.named('ai.explain_used'), isEmpty);
    });

    test('a failed model request records nothing', () async {
      final telemetry = _RecordingTelemetryService();
      final c = explainContainer(telemetry, client: _ThrowingClient());
      c.read(selectedVariablesProvider.notifier).toggle('top.clk');

      await c.read(explainSelectionProvider.notifier).explainCurrentSelection();

      expect(
        c.read(explainSelectionProvider).phase,
        ExplainSelectionPhase.error,
      );
      expect(telemetry.named('ai.explain_used'), isEmpty);
    });
  });

  // ── cxp.crossprobe — inbound ────────────────────────────────────────────────

  group('cxp.crossprobe (inbound)', () {
    Scope scopeWithClk() => const Scope(
      name: 'top',
      path: 'top',
      type: ScopeType.module,
      variables: [
        Variable(
          name: 'clk',
          varType: VarType.wire,
          direction: VarDirection.input,
          signalRef: 'top.clk',
          scopePath: 'top',
          bitWidth: 1,
        ),
      ],
    );

    ProviderContainer inboundContainer(
      _RecordingTelemetryService telemetry, {
      FakeWaveformDataSource? source,
    }) {
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          settingsServiceProvider.overrideWithValue(
            const _FakeSettingsService(),
          ),
          appSettingsProvider.overrideWith(_FakeAppSettingsNotifier.new),
          if (source != null)
            waveformSourceProvider.overrideWith(
              () => _StubSourceNotifier(source),
            ),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a highlight that lands records honored true', () async {
      final telemetry = _RecordingTelemetryService();
      final c = inboundContainer(
        telemetry,
        source: FakeWaveformDataSource(scopes: [scopeWithClk()]),
      );

      final result = await dispatchCxpHighlight(
        c.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'top.clk'),
      );

      expect(result.honored, isTrue);
      final probes = telemetry.named('cxp.crossprobe');
      expect(probes, hasLength(1));
      _expectVocabularyValue(probes.single.properties['direction'], 'inbound');
      // A real bool, not the string 'true': the Worker types this property as
      // a boolean and a stringly-typed value would land in the wrong column.
      expect(probes.single.properties['honored'], isTrue);
      expect(probes.single.properties['honored'], isA<bool>());
    });

    test('a highlight with no waveform loaded records honored false', () async {
      final telemetry = _RecordingTelemetryService();
      final c = inboundContainer(telemetry);

      final result = await dispatchCxpHighlight(
        c.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'top.clk'),
      );

      expect(result.honored, isFalse);
      final probes = telemetry.named('cxp.crossprobe');
      expect(probes, hasLength(1));
      _expectVocabularyValue(probes.single.properties['direction'], 'inbound');
      expect(probes.single.properties['honored'], isFalse);
      expect(probes.single.properties['honored'], isA<bool>());
    });

    test('an element not in the trace still records, honored false', () async {
      final telemetry = _RecordingTelemetryService();
      final c = inboundContainer(
        telemetry,
        source: FakeWaveformDataSource(scopes: [scopeWithClk()]),
      );

      final result = await dispatchCxpHighlight(
        c.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'top.nosuch'),
      );

      expect(result.honored, isFalse);
      final probes = telemetry.named('cxp.crossprobe');
      expect(probes, hasLength(1));
      expect(probes.single.properties['honored'], isFalse);
    });
  });

  // ── cxp.crossprobe — outbound ───────────────────────────────────────────────

  group('cxp.crossprobe (outbound)', () {
    const peer = PeerIdentity(
      peerId: 'netcrux-1-2',
      productName: 'netcrux',
      productVersion: '0.1.0',
    );

    Widget panelApp({required List<Override> overrides}) => ProviderScope(
      overrides: [productTelemetryConfig, ...overrides],
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: 800,
            height: 800,
            child: WaveCruxCrossProbePanel(),
          ),
        ),
      ),
    );

    List<Override> sendOverrides(
      _RecordingTelemetryService telemetry,
      _FakeCxpServer server,
    ) => [
      waveformSourceProvider.overrideWith(
        () => _StubSourceNotifier(FakeWaveformSource.reference()),
      ),
      cxpServerProvider.overrideWith(() => _FakeServerNotifier(server)),
      cxpPeersProvider.overrideWith(() => _StaticPeers(const [peer])),
      // The focus stores the backend-local ref, which the panel translates to
      // the canonical path before sending.
      selectedSignalProvider.overrideWith(() => _StaticSelection('s_data')),
      telemetryServiceProvider.overrideWithValue(telemetry),
      // Sending a cross-probe is Pro; what is recorded here is the send.
      licenseTierProvider.overrideWithValue(LicenseTier.pro),
    ];

    testWidgets('a delivered send records direction outbound', (tester) async {
      final telemetry = _RecordingTelemetryService();
      final server = _FakeCxpServer(reachable: const [peer]);
      await tester.pumpWidget(
        panelApp(overrides: sendOverrides(telemetry, server)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();

      final probes = telemetry.named('cxp.crossprobe');
      expect(probes, hasLength(1));
      _expectVocabularyValue(probes.single.properties['direction'], 'outbound');
      expect(probes.single.properties['honored'], isTrue);
      expect(probes.single.properties['honored'], isA<bool>());
    });

    testWidgets('a refused ack records the send with honored false', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      final server = _FakeCxpServer(
        reachable: const [peer],
        ackHonored: false,
        ackReason: 'element not found: top.data',
      );
      await tester.pumpWidget(
        panelApp(overrides: sendOverrides(telemetry, server)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();

      final probes = telemetry.named('cxp.crossprobe');
      expect(probes, hasLength(1));
      _expectVocabularyValue(probes.single.properties['direction'], 'outbound');
      expect(probes.single.properties['honored'], isFalse);
    });

    testWidgets('an undelivered send records nothing', (tester) async {
      final telemetry = _RecordingTelemetryService();
      final server = _FakeCxpServer(reachable: const [peer], delivered: false);
      await tester.pumpWidget(
        panelApp(overrides: sendOverrides(telemetry, server)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_netcrux-1-2')));
      await tester.pumpAndSettle();

      expect(telemetry.named('cxp.crossprobe'), isEmpty);
    });
  });

  // ── format.set — the bulk keyboard shortcut ─────────────────────────────────

  group('format.set (viewer shortcut)', () {
    testWidgets('one keypress over a three-signal selection records once', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      late ProviderContainer root;
      await tester.pumpWidget(
        _ViewerHost(
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
          onReady: (c) => root = c,
        ),
      );
      await tester.pumpAndSettle();
      final tabContainer = root
          .read(tabContainerManagerProvider)
          .containerFor(root.read(activeTabIdProvider));
      // Selected through the tab's own container, which is where the screen
      // resolves the selection from.
      tabContainer.read(selectedVariablesProvider.notifier)
        ..toggle('top.a')
        ..toggle('top.b')
        ..toggle('top.c');

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.setFormatIeee754Single),
      );
      await tester.pumpAndSettle();

      final set = telemetry.named('format.set');
      expect(set, hasLength(1));
      _expectVocabularyValue(set.single.properties['format'], 'ieee754_single');
    });

    testWidgets('a keypress with nothing selected records nothing', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      await tester.pumpWidget(
        _ViewerHost(
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
        ),
      );
      await tester.pumpAndSettle();

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.setFormatHexadecimal),
      );
      await tester.pumpAndSettle();

      expect(telemetry.named('format.set'), isEmpty);
    });
  });

  // ── tool.opened — comparison ────────────────────────────────────────────────

  group('tool.opened (comparison)', () {
    testWidgets('a comparison that loads records tool comparison', (
      tester,
    ) async {
      // A loaded diff docks the DiffToolbar, whose Row overflows the default
      // 800x600 test surface — a layout artifact of the narrow pane, not of the
      // instrumentation under test.
      tester.view.physicalSize = const Size(1800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final telemetry = _RecordingTelemetryService();
      await tester.pumpWidget(
        _ViewerHost(
          overrides: [
            telemetryServiceProvider.overrideWithValue(telemetry),
            // The descriptor guard requires a loaded file; this flag is the
            // documented widget-test escape hatch for that branch.
            waveformIsLoadedProvider.overrideWithValue(true),
            openFilePickerProvider.overrideWithValue(_stubOpenPicker('/b.vcd')),
          ],
          tabOverrides: [diffProvider.overrideWith(_LoadedDiffNotifier.new)],
        ),
      );
      await tester.pumpAndSettle();

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.compareWaveforms),
      );
      await tester.pumpAndSettle();

      final opened = telemetry.named('tool.opened');
      expect(opened, hasLength(1));
      _expectVocabularyValue(opened.single.properties['tool'], 'comparison');
    });

    testWidgets('a comparison that fails to load records nothing', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      await tester.pumpWidget(
        _ViewerHost(
          overrides: [
            telemetryServiceProvider.overrideWithValue(telemetry),
            waveformIsLoadedProvider.overrideWithValue(true),
            openFilePickerProvider.overrideWithValue(_stubOpenPicker('/b.vcd')),
          ],
          tabOverrides: [diffProvider.overrideWith(_FailedDiffNotifier.new)],
        ),
      );
      await tester.pumpAndSettle();

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.compareWaveforms),
      );
      await tester.pumpAndSettle();

      expect(telemetry.named('tool.opened'), isEmpty);
    });
  });

  // ── tool.opened — switching activity ────────────────────────────────────────

  group('tool.opened (activity)', () {
    const clk = Variable(
      name: 'clk',
      varType: VarType.wire,
      direction: VarDirection.input,
      signalRef: 'top.clk',
      scopePath: 'top',
      bitWidth: 1,
    );

    testWidgets('a switching-activity run records tool activity', (
      tester,
    ) async {
      // A completed run docks the ActivityReportPanel, whose header Row
      // overflows the default 800x600 surface — a layout artifact of the
      // narrow dock, not of the instrumentation under test.
      tester.view.physicalSize = const Size(1800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final telemetry = _RecordingTelemetryService();
      late ProviderContainer root;
      final source = FakeWaveformDataSource(
        scopes: const [
          Scope(
            name: 'top',
            path: 'top',
            type: ScopeType.module,
            variables: [clk],
          ),
        ],
        signals: {
          'top.clk': const [
            SignalChange(time: 0, value: '0'),
            SignalChange(time: 10, value: '1'),
            SignalChange(time: 20, value: '0'),
          ],
        },
      );
      await tester.pumpWidget(
        _ViewerHost(
          overrides: [
            telemetryServiceProvider.overrideWithValue(telemetry),
            waveformIsLoadedProvider.overrideWithValue(true),
          ],
          tabOverrides: [
            waveformSourceProvider.overrideWith(
              () => _StubSourceNotifier(source),
            ),
          ],
          onReady: (c) => root = c,
        ),
      );
      await tester.pumpAndSettle();
      root
          .read(tabContainerManagerProvider)
          .containerFor(root.read(activeTabIdProvider))
          .read(signalGroupsProvider.notifier)
          .addSignal(clk);

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.analyzeSwitchingActivity),
      );
      await tester.pumpAndSettle();

      final opened = telemetry.named('tool.opened');
      expect(opened, hasLength(1));
      _expectVocabularyValue(opened.single.properties['tool'], 'activity');
    });

    testWidgets('an analysis with no signals on the canvas records nothing', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      await tester.pumpWidget(
        _ViewerHost(
          overrides: [
            telemetryServiceProvider.overrideWithValue(telemetry),
            waveformIsLoadedProvider.overrideWithValue(true),
          ],
        ),
      );
      await tester.pumpAndSettle();

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.analyzeSwitchingActivity),
      );
      await tester.pumpAndSettle();

      expect(telemetry.named('tool.opened'), isEmpty);
    });
  });

  // ── tool.opened — X-Trace ───────────────────────────────────────────────────

  group('tool.opened (x_trace)', () {
    testWidgets('an X-Trace that becomes active records tool x_trace', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetryService();
      late ProviderContainer root;
      await tester.pumpWidget(
        _ViewerHost(
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
          tabOverrides: [
            waveformSourceProvider.overrideWith(
              () => _StubSourceNotifier(FakeWaveformSource.reference()),
            ),
          ],
          onReady: (c) => root = c,
        ),
      );
      await tester.pumpAndSettle();

      // `top.state` is X from tick 5 in the reference trace, so the real trace
      // walk reaches the `isActive` transition the screen listens for.
      await root
          .read(tabContainerManagerProvider)
          .containerFor(root.read(activeTabIdProvider))
          .read(xTraceProvider.notifier)
          .traceX('s_state', 10);
      await tester.pumpAndSettle();

      final opened = telemetry.named('tool.opened');
      expect(opened, hasLength(1));
      _expectVocabularyValue(opened.single.properties['tool'], 'x_trace');
    });
  });

  // ── tool.opened — FSM ───────────────────────────────────────────────────────

  group('tool.opened (fsm)', () {
    testWidgets('an FSM analysis that becomes active records tool fsm', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final telemetry = _RecordingTelemetryService();
      late ProviderContainer root;
      await tester.pumpWidget(
        _ViewerHost(
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
          tabOverrides: [
            waveformSourceProvider.overrideWith(
              () => _StubSourceNotifier(FakeWaveformSource.reference()),
            ),
          ],
          onReady: (c) => root = c,
        ),
      );
      await tester.pumpAndSettle();

      await root
          .read(tabContainerManagerProvider)
          .containerFor(root.read(activeTabIdProvider))
          .read(fsmProvider.notifier)
          .analyzeSignal('s_state');
      await tester.pumpAndSettle();

      final opened = telemetry.named('tool.opened');
      expect(opened, hasLength(1));
      _expectVocabularyValue(opened.single.properties['tool'], 'fsm');
    });
  });
}

/// Exposes a container's [Ref] so the top-level CXP dispatch functions can be
/// called without subclassing a notifier.
final _refProvider = Provider<Ref>((ref) => ref);

/// Preloads [waveformSourceProvider] with an in-memory source.
class _StubSourceNotifier extends WaveformSourceNotifier {
  _StubSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// A configured client that replays a canned response.
class _CannedClient implements AiModelClient {
  _CannedClient(this._response);
  final String _response;
  @override
  bool get isConfigured => true;
  @override
  Stream<AiStreamEvent> send(AiRequest request) async* {
    yield AiTextDelta(_response);
    yield const AiResponseCompleted(finishReason: 'stop');
  }
}

/// A configured client whose stream fails — the `error` phase.
class _ThrowingClient implements AiModelClient {
  @override
  bool get isConfigured => true;
  @override
  Stream<AiStreamEvent> send(AiRequest request) async* {
    throw StateError('model unreachable');
  }
}

class _FakeSettingsService implements WaveCruxSettingsService {
  const _FakeSettingsService();

  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

/// Resolves the settings synchronously so the inbound dispatch never awaits a
/// real on-disk load.
class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _StaticPeers extends CxpPeers {
  _StaticPeers(this._peers);
  final List<PeerIdentity> _peers;
  @override
  List<PeerIdentity> build() => _peers;
}

class _StaticSelection extends SelectedSignalNotifier {
  _StaticSelection(this._selection);
  final String? _selection;
  @override
  String? build() => _selection;
}

/// A [WaveCruxCxpServer] test double: never opens a socket, reports a fixed
/// reachable-peer set, and answers [requestHighlight] from its constructor
/// arguments.
class _FakeCxpServer extends WaveCruxCxpServer {
  _FakeCxpServer({
    required List<PeerIdentity> reachable,
    this.delivered = true,
    this.ackHonored = true,
    this.ackReason,
  }) : _reachable = reachable,
       super(
         productVersion: '0.0.0-test',
         manifestDirectory: '/tmp/does-not-matter',
         onHighlight: _noHighlight,
         onOpenSource: _noOpenSource,
       );

  final List<PeerIdentity> _reachable;
  final bool delivered;
  final bool ackHonored;
  final String? ackReason;

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
  bool sendTo(String peerId, CxpMessage message, {String? summary}) => true;

  @override
  Future<({bool delivered, RequestHighlightAck? ack})> requestHighlight(
    String peerId,
    RequestHighlight request, {
    Duration timeout = const Duration(seconds: 5),
    String? summary,
  }) async => (
    delivered: delivered,
    ack: delivered
        ? RequestHighlightAck(
            inReplyTo: 'req',
            honored: ackHonored,
            reason: ackReason,
          )
        : null,
  );
}

/// Hosts [ViewerScreen] in a container with the tab/pane managers initialised,
/// which the screen reads at build time.
class _ViewerHost extends StatefulWidget {
  const _ViewerHost({
    required this.overrides,
    this.tabOverrides = const [],
    this.onReady,
  });

  final List<Override> overrides;

  /// Appended to every per-tab container — the only way to reach a provider the
  /// screen resolves through the active tab's scope.
  final List<Override> tabOverrides;

  /// Hands the root container to the test so it can drive the active tab's own
  /// container the way the screen does.
  final void Function(ProviderContainer container)? onReady;

  @override
  State<_ViewerHost> createState() => _ViewerHostState();
}

class _ViewerHostState extends State<_ViewerHost> {
  late final TabContainerManager _tcm;
  late final PaneContainerManager _pcm;
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _tcm = TabContainerManager(extraTabOverrides: widget.tabOverrides);
    _pcm = PaneContainerManager();
    _container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(_tcm),
        paneContainerManagerProvider.overrideWithValue(_pcm),
        ...testWorkspaceOverrides(),
        ...widget.overrides,
      ],
    );
    _tcm.init(_container);
    _pcm.init(_container);
    unawaited(_container.wavecruxWorkspace.newTab(displayName: 'New Tab'));
    widget.onReady?.call(_container);
  }

  @override
  void dispose() {
    _tcm.dispose();
    _pcm.dispose();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: _container,
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const ViewerScreen(),
    ),
  );
}

/// Stub [OpenFilePicker] resolving to a single-file result at [path].
OpenFilePicker _stubOpenPicker(String path) =>
    ({dialogTitle, type = FileType.any, allowedExtensions}) async =>
        FilePickerResult([
          PlatformFile(name: path.split('/').last, size: 0, path: path),
        ]);

/// A comparison that loads cleanly — the branch that reaches `tool.opened`.
class _LoadedDiffNotifier extends DiffNotifier {
  @override
  Future<void> loadSecondFile(String path) async {
    state = const DiffState(secondFilePath: '/b.vcd');
  }
}

/// A comparison that fails — an attempt, not an opened tool.
class _FailedDiffNotifier extends DiffNotifier {
  @override
  Future<void> loadSecondFile(String path) async {
    state = const DiffState(error: 'simulated diff error');
  }
}

/// Reports the server as running so the panel enables its send controls.
class _FakeServerNotifier extends CxpServerNotifier {
  _FakeServerNotifier(this._server);
  final WaveCruxCxpServer _server;

  @override
  CxpServerState build() => const CxpServerState(isRunning: true);

  @override
  WaveCruxCxpServer? get server => _server;
}
