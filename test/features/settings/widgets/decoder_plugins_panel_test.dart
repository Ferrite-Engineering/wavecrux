// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/interfaces/decoder_plugin_loader.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_info.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/widgets/decoder_plugins_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader_provider.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

/// In-memory fake [DecoderPluginLoader] that returns whatever list of
/// plugins the test seeded. Tracks scan invocations so refresh() can
/// be verified.
class _FakePluginLoader implements DecoderPluginLoader {
  _FakePluginLoader(this._plugins);

  final List<DecoderPluginInfo> _plugins;
  int scanCount = 0;

  @override
  Future<List<DecoderPluginInfo>> scan() async {
    scanCount++;
    return _plugins;
  }

  @override
  void dispose() {}
}

DecoderPluginInfo _info({
  required String id,
  required DecoderPluginLoadStatus status,
  String? error,
  int abi = 0x00010000,
  List<String> decoderIds = const <String>[],
  String? description,
}) => DecoderPluginInfo(
  pluginId: id,
  displayName: 'plugin-$id',
  filePath: '/plugins/$id.so',
  declaredAbiVersion: abi,
  loadStatus: status,
  errorMessage: error,
  registeredDecoderIds: decoderIds,
  pluginDescription: description,
);

Widget _wrap({
  required AppSettings initialSettings,
  required _FakePluginLoader loader,
  Locale locale = const Locale('en'),
}) {
  final mock = _MockSettingsService();
  when(mock.load).thenAnswer((_) async => initialSettings);
  when(() => mock.save(any())).thenAnswer((_) async {});

  return ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(mock),
      decoderPluginLoaderProvider.overrideWith((_) async => loader),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ],
      locale: locale,
      home: const Scaffold(
        body: SingleChildScrollView(child: DecoderPluginsPanel()),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
    decoderPluginsAppSupportDirectory = () async => Directory.systemTemp;
    decoderPluginsLaunchUrl = (_) async => true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Locale sweep ───────────────────────────────────────────────────────────

  group('DecoderPluginsPanel locale sweep', () {
    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        final loader = _FakePluginLoader(const <DecoderPluginInfo>[]);
        await tester.pumpWidget(
          _wrap(
            initialSettings: const AppSettings().copyWith(
              pluginSafetyAcknowledged: true,
            ),
            loader: loader,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Locale sweep over a populated card so the decoder-count plural and
  // the plugin description render in every locale (catches CJK overflow).
  group('DecoderPluginsPanel populated-card locale sweep', () {
    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets(
        'renders a loaded bridge card without exceptions in $locale',
        (tester) async {
          final loader = _FakePluginLoader(<DecoderPluginInfo>[
            _info(
              id: 'bridge',
              status: DecoderPluginLoadStatus.loaded,
              decoderIds: List<String>.generate(111, (i) => 'sigrok.d$i'),
              description: 'GPLv3+ libsigrokdecode bridge',
            ),
          ]);
          await tester.pumpWidget(
            _wrap(
              initialSettings: const AppSettings().copyWith(
                pluginSafetyAcknowledged: true,
              ),
              loader: loader,
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ── Decoder count + plugin description on a loaded card ─────────────────────

  testWidgets('loaded plugin card shows decoder count and description', (
    tester,
  ) async {
    final loader = _FakePluginLoader(<DecoderPluginInfo>[
      _info(
        id: 'bridge',
        status: DecoderPluginLoadStatus.loaded,
        decoderIds: List<String>.generate(111, (i) => 'sigrok.d$i'),
        description: 'GPLv3+ libsigrokdecode bridge',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
        ),
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.decoderPluginsDecoderCount(111)), findsOneWidget);
    expect(find.text('GPLv3+ libsigrokdecode bridge'), findsOneWidget);
  });

  testWidgets('non-loaded plugin card shows no decoder count', (tester) async {
    final loader = _FakePluginLoader(<DecoderPluginInfo>[
      _info(
        id: 'broken',
        status: DecoderPluginLoadStatus.loadError,
        error: 'dlopen fail',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
        ),
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.decoderPluginsDecoderCount(0)), findsNothing);
  });

  // ── Empty state when zero plugins are discovered ───────────────────────────

  testWidgets('renders empty state when no plugins are discovered', (
    tester,
  ) async {
    final loader = _FakePluginLoader(const <DecoderPluginInfo>[]);
    await tester.pumpWidget(
      _wrap(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
        ),
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.decoderPluginsEmptyNoPlugins), findsOneWidget);
    expect(loader.scanCount, greaterThanOrEqualTo(1));
  });

  // ── Status display for all four load-status states ─────────────────────────

  testWidgets('renders all load-status chips correctly', (tester) async {
    final plugins = <DecoderPluginInfo>[
      _info(id: 'a', status: DecoderPluginLoadStatus.loaded),
      _info(
        id: 'b',
        status: DecoderPluginLoadStatus.abiMismatch,
        error: 'major mismatch',
      ),
      _info(
        id: 'c',
        status: DecoderPluginLoadStatus.missingSymbol,
        error: 'no symbol',
      ),
      _info(
        id: 'd',
        status: DecoderPluginLoadStatus.manifestInvalid,
        error: 'bad json',
      ),
      _info(
        id: 'e',
        status: DecoderPluginLoadStatus.loadError,
        error: 'dlopen fail',
      ),
      _info(id: 'f', status: DecoderPluginLoadStatus.disabled),
    ];
    final loader = _FakePluginLoader(plugins);

    await tester.pumpWidget(
      _wrap(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
        ),
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.decoderPluginStatusLoaded), findsOneWidget);
    expect(find.text(l10n.decoderPluginStatusAbiMismatch), findsOneWidget);
    expect(find.text(l10n.decoderPluginStatusMissingSymbol), findsOneWidget);
    expect(find.text(l10n.decoderPluginStatusManifestInvalid), findsOneWidget);
    expect(find.text(l10n.decoderPluginStatusLoadError), findsOneWidget);
    expect(find.text(l10n.decoderPluginStatusDisabled), findsOneWidget);

    // Error messages shown inline on the failing rows.
    expect(find.text('major mismatch'), findsOneWidget);
    expect(find.text('no symbol'), findsOneWidget);
    expect(find.text('bad json'), findsOneWidget);
    expect(find.text('dlopen fail'), findsOneWidget);
  });

  // ── Acknowledgment banner gates discovery ──────────────────────────────────

  testWidgets('shows acknowledgment banner when not acknowledged', (
    tester,
  ) async {
    final loader = _FakePluginLoader(const <DecoderPluginInfo>[]);
    await tester.pumpWidget(
      _wrap(
        initialSettings: const AppSettings(),
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.decoderPluginsBannerNeedsAck), findsOneWidget);
    expect(find.text(l10n.decoderPluginsBannerReview), findsOneWidget);
  });

  testWidgets('shows disabled banner when plugin loading is disabled', (
    tester,
  ) async {
    final loader = _FakePluginLoader(const <DecoderPluginInfo>[]);
    await tester.pumpWidget(
      _wrap(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
          pluginLoadingDisabled: true,
        ),
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.decoderPluginsBannerDisabled), findsOneWidget);
    expect(find.text(l10n.decoderPluginsBannerEnable), findsOneWidget);
  });

  // ── Reload button re-runs discovery ─────────────────────────────────────────

  testWidgets('Reload plugins button re-runs scan()', (tester) async {
    final loader = _FakePluginLoader(const <DecoderPluginInfo>[]);
    await tester.pumpWidget(
      _wrap(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
        ),
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();
    final initialScans = loader.scanCount;

    final l10n = await L10N.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.decoderPluginsReload));
    await tester.pumpAndSettle();

    expect(loader.scanCount, greaterThan(initialScans));
  });

  // ── Per-plugin disable toggle ──────────────────────────────────────────────

  testWidgets('disable toggle updates AppSettings.perPluginDisabled', (
    tester,
  ) async {
    final plugin = _info(id: 'x', status: DecoderPluginLoadStatus.loaded);
    final loader = _FakePluginLoader(<DecoderPluginInfo>[plugin]);

    final mock = _MockSettingsService();
    when(mock.load).thenAnswer(
      (_) async => const AppSettings().copyWith(pluginSafetyAcknowledged: true),
    );
    when(() => mock.save(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(mock),
          decoderPluginLoaderProvider.overrideWith((_) async => loader),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(
            body: SingleChildScrollView(child: DecoderPluginsPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Toggle off (i.e. disable the plugin).
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // Verify save was called with perPluginDisabled containing the plugin id.
    verify(
      () => mock.save(
        any(
          that: predicate<AppSettings>(
            (s) => s.perPluginDisabled[plugin.pluginId] ?? false,
          ),
        ),
      ),
    ).called(1);
  });

  // ── Directory list management ──────────────────────────────────────────────

  testWidgets('user directories are listed with remove buttons', (
    tester,
  ) async {
    final loader = _FakePluginLoader(const <DecoderPluginInfo>[]);
    final mock = _MockSettingsService();
    when(mock.load).thenAnswer(
      (_) async => const AppSettings().copyWith(
        pluginSafetyAcknowledged: true,
        userPluginDirectories: <String>['/opt/plugins', '/var/plugins'],
      ),
    );
    when(() => mock.save(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(mock),
          decoderPluginLoaderProvider.overrideWith((_) async => loader),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(
            body: SingleChildScrollView(child: DecoderPluginsPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('/opt/plugins'), findsOneWidget);
    expect(find.text('/var/plugins'), findsOneWidget);

    // Tap the remove button for the first directory.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    verify(
      () => mock.save(
        any(
          that: predicate<AppSettings>(
            (s) =>
                !s.userPluginDirectories.contains('/opt/plugins') &&
                s.userPluginDirectories.contains('/var/plugins'),
          ),
        ),
      ),
    ).called(1);
  });

  testWidgets('renders no-directories placeholder when empty', (tester) async {
    final loader = _FakePluginLoader(const <DecoderPluginInfo>[]);
    await tester.pumpWidget(
      _wrap(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
        ),
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.decoderPluginsNoUserDirectories), findsOneWidget);
  });
}
