// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_io/crux_io.dart' show revealInFileManager;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/tools/widgets/generate_test_vcd_dialog.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/dev_tools/vcd_generator_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// Records [openFile] calls without performing any I/O or FFI work.
class _TrackingSourceNotifier extends WaveformSourceNotifier {
  String? lastOpenedPath;

  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncData(null);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    lastOpenedPath = path;
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Wraps the dialog inside an UncontrolledProviderScope with a fully-wired
/// TabContainerManager. The per-tab waveformSourceNotifier override (via
/// `extraTabOverrides`) routes per-tab `openFile` calls into our
/// [_TrackingSourceNotifier] so the test can assert the file load was
/// dispatched without spinning up the wellen FFI.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.source,
    required this.savePicker,
    required this.child,
    this.revealLauncher,
    this.generatorService,
  });

  final _TrackingSourceNotifier source;
  final SaveVcdPicker savePicker;
  final RevealLauncher? revealLauncher;
  final VcdGeneratorService? generatorService;
  final Widget child;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final TabContainerManager _tcm;
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _tcm = TabContainerManager(
      extraTabOverrides: [
        waveformSourceProvider.overrideWith(() => widget.source),
      ],
    );
    _container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(_tcm),
        // Use the in-memory workspace (no path_provider). Without this the
        // workspace AsyncNotifier resolves its dir via getApplicationSupport-
        // Directory(), which throws MissingPluginException on the Windows
        // test host — the tab never appends and the dialog never dismisses.
        ...testWorkspaceOverrides(),
      ],
    );
    _tcm.init(_container);
  }

  @override
  void dispose() {
    _tcm.dispose();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UncontrolledProviderScope(container: _container, child: widget.child);
}

Widget _wrap({
  required _TrackingSourceNotifier source,
  required SaveVcdPicker savePicker,
  RevealLauncher? revealLauncher,
  VcdGeneratorService? generatorService,
  Locale locale = const Locale('en'),
}) {
  return _Harness(
    source: source,
    savePicker: savePicker,
    revealLauncher: revealLauncher,
    generatorService: generatorService,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => GenerateTestVcdDialog(
                generatorService: generatorService ?? VcdGeneratorService(),
                savePicker: savePicker,
                revealLauncher: revealLauncher,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Directory? tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wavecrux_gen_test_');
  });
  tearDown(() {
    final dir = tempDir;
    if (dir != null && dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  // ── Locale sweep ─────────────────────────────────────────────────────────────

  group('GenerateTestVcdDialog — locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        final source = _TrackingSourceNotifier();
        Future<String?> picker({
          required String dialogTitle,
          required String fileName,
        }) async => null;
        await tester.pumpWidget(
          _wrap(source: source, savePicker: picker, locale: locale),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── Structure ─────────────────────────────────────────────────────────────

  group('GenerateTestVcdDialog — structure', () {
    testWidgets('renders all controls', (tester) async {
      final source = _TrackingSourceNotifier();
      Future<String?> picker({
        required String dialogTitle,
        required String fileName,
      }) async => null;
      await tester.pumpWidget(_wrap(source: source, savePicker: picker));
      await tester.tap(find.text('open'));
      await tester.pump();

      // Title + sliders + toggles + seed + buttons.
      expect(find.text('Generate Test VCD'), findsOneWidget);
      expect(find.text('Signal Count'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Include Analog Signals'), findsOneWidget);
      expect(find.text('Include X/Z Values'), findsOneWidget);
      expect(find.text('Random Seed'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2));
      // Three action buttons: Close, Generate & Reveal, Generate & Open.
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Generate & Open in New Tab'), findsOneWidget);
      expect(find.text('Generate & Reveal in Finder/Explorer'), findsOneWidget);
      expect(find.text('No destination chosen'), findsOneWidget);
    });

    testWidgets(
      'Generate buttons are disabled until destination is chosen',
      (tester) async {
        final source = _TrackingSourceNotifier();
        Future<String?> picker({
          required String dialogTitle,
          required String fileName,
        }) async => null;
        await tester.pumpWidget(_wrap(source: source, savePicker: picker));
        await tester.tap(find.text('open'));
        await tester.pump();

        final openBtn = tester.widget<FilledButton>(
          find.byKey(const Key('generate_test_vcd_generate_and_open')),
        );
        expect(openBtn.onPressed, isNull);

        final revealBtn = tester.widget<OutlinedButton>(
          find.byKey(const Key('generate_test_vcd_generate_and_reveal')),
        );
        expect(revealBtn.onPressed, isNull);
      },
    );

    testWidgets(
      'choosing a destination enables generate buttons and shows the path',
      (tester) async {
        final source = _TrackingSourceNotifier();
        final destPath = p.join(tempDir!.path, 'choice.vcd');
        Future<String?> picker({
          required String dialogTitle,
          required String fileName,
        }) async => destPath;

        await tester.pumpWidget(_wrap(source: source, savePicker: picker));
        await tester.tap(find.text('open'));
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('generate_test_vcd_choose_destination')),
        );
        await tester.pump();

        // The path is rendered in the destination row.
        expect(find.text(destPath), findsOneWidget);

        final openBtn = tester.widget<FilledButton>(
          find.byKey(const Key('generate_test_vcd_generate_and_open')),
        );
        expect(openBtn.onPressed, isNotNull);

        final revealBtn = tester.widget<OutlinedButton>(
          find.byKey(const Key('generate_test_vcd_generate_and_reveal')),
        );
        expect(revealBtn.onPressed, isNotNull);
      },
    );
  });

  // ── Generate & Open in New Tab ────────────────────────────────────────────

  group('GenerateTestVcdDialog — Generate & Open in New Tab', () {
    testWidgets(
      'writes the file, appends a tab, and dismisses the dialog',
      (tester) async {
        final source = _TrackingSourceNotifier();
        final destPath = p.join(tempDir!.path, 'open.vcd');
        Future<String?> picker({
          required String dialogTitle,
          required String fileName,
        }) async => destPath;

        await tester.pumpWidget(_wrap(source: source, savePicker: picker));
        await tester.tap(find.text('open'));
        await tester.pump();

        // Pick a destination.
        await tester.tap(
          find.byKey(const Key('generate_test_vcd_choose_destination')),
        );
        await tester.pump();

        // Find the ProviderContainer so we can read the tab list after the
        // dialog closes.
        final BuildContext ctx = tester.element(find.text('open'));
        final container = ProviderScope.containerOf(ctx);

        // Tap "Generate & Open in New Tab" (ensure it's scrolled into view).
        final openFinder = find.byKey(
          const Key('generate_test_vcd_generate_and_open'),
        );
        await tester.ensureVisible(openFinder);
        await tester.pump();
        // Use runAsync so the real file-system write inside the dialog's
        // callback runs to completion before we assert on the side-effects.
        await tester.runAsync(() async {
          await tester.tap(openFinder);
          // Pump repeatedly with real Future.delayed gaps so the real-Zone
          // file-write microtask actually resumes the await continuation.
          // Plain `tester.pump` under runAsync isn't enough on its own to
          // tick real microtasks reliably.
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(Duration.zero);
          }
        });
        // After runAsync the async chain has completed and Navigator.pop
        // has fired. Tick the dialog's exit animation outside runAsync.
        await tester.pump(const Duration(milliseconds: 300));

        // File was written.
        expect(File(destPath).existsSync(), isTrue);
        // Dialog is dismissed (title no longer in the tree).
        expect(find.text('Generate Test VCD'), findsNothing);

        // A new tab was appended for the generated file.
        final tabs = container.read(tabListProvider);
        expect(tabs, hasLength(1));
        expect(tabs.single.filePath, destPath);

        // The waveform source notifier was asked to open the file.
        expect(source.lastOpenedPath, destPath);

        // Detach the widget tree and drain Riverpod's auto-dispose scheduler
        // so [TabListNotifier._awaitWorkspace]'s zero-duration polling
        // timers don't survive into the framework's pending-timer check.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  });

  // ── Generate & Reveal ─────────────────────────────────────────────────────

  group('GenerateTestVcdDialog — Generate & Reveal', () {
    testWidgets(
      'writes the file, calls the reveal launcher, dismisses the dialog',
      (tester) async {
        final source = _TrackingSourceNotifier();
        final destPath = p.join(tempDir!.path, 'reveal.vcd');
        Future<String?> picker({
          required String dialogTitle,
          required String fileName,
        }) async => destPath;

        String? revealedPath;
        Future<void> revealer(String path) async {
          revealedPath = path;
        }

        await tester.pumpWidget(
          _wrap(
            source: source,
            savePicker: picker,
            revealLauncher: revealer,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('generate_test_vcd_choose_destination')),
        );
        await tester.pump();

        final revealFinder = find.byKey(
          const Key('generate_test_vcd_generate_and_reveal'),
        );
        await tester.ensureVisible(revealFinder);
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(revealFinder);
          // Pump repeatedly so the real-Zone file-write microtask resumes,
          // then the launcher fires, then Navigator.pop runs its animation.
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(Duration.zero);
          }
        });
        await tester.pump(const Duration(milliseconds: 300));

        expect(File(destPath).existsSync(), isTrue);
        expect(revealedPath, destPath);
        expect(find.text('Generate Test VCD'), findsNothing);
        // No tab was added — reveal is a side-channel action.
        final BuildContext ctx = tester.element(find.text('open'));
        final container = ProviderScope.containerOf(ctx);
        expect(container.read(tabListProvider), isEmpty);
      },
    );

    // With nothing injected, the button reveals through crux_io's shared
    // helper rather than a local copy of it.
    test('the default reveal is the shared file-manager reveal', () {
      expect(identical(defaultRevealLauncher, revealInFileManager), isTrue);
    });

    // The Windows reveal, driven with the generated file's path on a Windows
    // host laid out with a synthetic PATH so the branch runs on every CI
    // machine. Explorer selects the file only when `/select,<path>` arrives
    // as one argument; split in two, it opens the folder and selects nothing.
    test(
      'on Windows, Explorer gets `/select,<path>` as one argument',
      () async {
        final path = p.join(tempDir!.path, 'reveal.vcd');
        final spawned = <(String, List<String>)>[];
        final revealed = await revealInFileManager(
          path,
          operatingSystem: 'windows',
          environment: const {'PATH': r'C:\rtl;C:\Windows'},
          exists: (candidate) => candidate == r'C:\Windows\explorer.EXE',
          runCommand: (exe, args) async {
            spawned.add((exe, args));
            return 0;
          },
        );
        expect(revealed, isTrue);
        expect(spawned, hasLength(1));
        expect(spawned.single.$1, r'C:\Windows\explorer.EXE');
        expect(spawned.single.$2, ['/select,$path']);
      },
    );
  });

  // ── Close ────────────────────────────────────────────────────────────────

  group('GenerateTestVcdDialog — Close', () {
    testWidgets('Close button dismisses the dialog', (tester) async {
      final source = _TrackingSourceNotifier();
      Future<String?> picker({
        required String dialogTitle,
        required String fileName,
      }) async => null;

      await tester.pumpWidget(_wrap(source: source, savePicker: picker));
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.text('Generate Test VCD'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Generate Test VCD'), findsNothing);
    });
  });

  // ── Open path (Tools menu / command palette) ────────────────────────────
  //
  // The Tools menu and the command palette both dispatch to
  // [GenerateTestVcdDialog.show(context)] (via ShortcutAction.generateTestVcd
  // in [`ViewerScreen._handleShortcut`]). Exercising the static entry-point
  // covers both surfaces without bootstrapping the full ViewerScreen.
  group('GenerateTestVcdDialog — entry point', () {
    testWidgets(
      'GenerateTestVcdDialog.show opens the dialog (Tools menu + command palette path)',
      (tester) async {
        final source = _TrackingSourceNotifier();
        await tester.pumpWidget(
          _Harness(
            source: source,
            savePicker:
                ({
                  required dialogTitle,
                  required fileName,
                }) async => null,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: TextButton(
                    onPressed: () => GenerateTestVcdDialog.show(ctx),
                    child: const Text('open via show'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open via show'));
        await tester.pumpAndSettle();

        expect(
          find.text('Generate Test VCD'),
          findsOneWidget,
          reason: 'GenerateTestVcdDialog.show must mount the dialog',
        );

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Generate Test VCD'), findsNothing);
      },
    );
  });

  // ── Touch target compliance ──────────────────────────────────────────────

  group('GenerateTestVcdDialog — touch target compliance', () {
    testWidgets('action buttons meet 44 dp height', (tester) async {
      final source = _TrackingSourceNotifier();
      Future<String?> picker({
        required String dialogTitle,
        required String fileName,
      }) async => null;
      await tester.pumpWidget(_wrap(source: source, savePicker: picker));
      await tester.tap(find.text('open'));
      await tester.pump();

      for (final key in const [
        Key('generate_test_vcd_choose_destination'),
        Key('generate_test_vcd_generate_and_reveal'),
        Key('generate_test_vcd_generate_and_open'),
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(
          size.height,
          greaterThanOrEqualTo(36),
          reason: 'Button $key should be at least 36 dp tall',
        );
      }
    });
  });

  // The save picker is its own window. Where the app window stays live behind
  // it — a portal or zenity process on Linux, the browser — the dialog can
  // close first, and the chosen path then arrives at a disposed State.
  testWidgets('a save picker answering after the dialog closed does not '
      'touch the disposed dialog', (tester) async {
    final source = _TrackingSourceNotifier();
    final chosen = Completer<String?>();
    Future<String?> picker({
      required String dialogTitle,
      required String fileName,
    }) => chosen.future;
    await tester.pumpWidget(_wrap(source: source, savePicker: picker));
    await tester.tap(find.text('open'));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('generate_test_vcd_choose_destination')),
    );
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(GenerateTestVcdDialog), findsNothing);

    chosen.complete(p.join(tempDir!.path, 'late.vcd'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
