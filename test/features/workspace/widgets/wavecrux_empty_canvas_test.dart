// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/app_info/application_build_info.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/workspace/providers/recent_lists.dart';
import 'package:wavecrux/features/workspace/widgets/wavecrux_empty_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// WaveCruxEmptyCanvas composes WaveCrux content into the package
// crux.EmptyCanvasState shell. These tests replace the deleted
// empty_canvas_state_test.dart, preserving the locale sweep and the key
// affordance assertions. The package shell itself is covered by
// crux_workspace's empty_canvas_state_test.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // The header's GlowingAppIcon runs perpetual AnimationControllers (.repeat),
  // so pumpAndSettle never completes. Advance a bounded number of frames to let
  // layout and the build-info resolve instead. (Same constraint the About
  // dialog test documents.)
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Widget harness(
    Locale locale,
    DeviceClass deviceClass, {
    VoidCallback? onOpenSample,
  }) => ProviderScope(
    overrides: [
      deviceClassProvider.overrideWithValue(deviceClass),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: WaveCruxEmptyCanvas(
          onOpenFile: () {},
          onOpenRecentFile: (_) async {},
          onOpenSample: onOpenSample,
          onOpenWorkspace: () {},
          onOpenRecentWorkspace: (_) async {},
        ),
      ),
    ),
  );

  testWidgets('renders without exception across the four locales', (
    tester,
  ) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await tester.pumpWidget(harness(locale, DeviceClass.desktop));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'locale $locale');
      expect(
        find.byKey(const Key('empty_canvas_state')),
        findsOneWidget,
        reason: 'locale $locale',
      );
    }
  });

  testWidgets('shows the running version under the header', (tester) async {
    // The welcome/empty canvas is the only always-visible version surface on
    // web (no native menu bar to host About), so the muted version line must
    // render once build info resolves. (PackageInfo has no platform channel
    // in flutter_test, so the provider is overridden with a resolved value.)
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          applicationBuildInfoProvider.overrideWith(
            (_) async => const ApplicationBuildInfo(
              version: '9.9.9',
              buildNumber: '7',
              gitSha: 'abc1234',
              os: 'macos',
              architecture: 'arm64',
              flutterVersion: '3.44.2',
              dartVersion: '3.12.2',
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: WaveCruxEmptyCanvas(
              onOpenFile: () {},
              onOpenRecentFile: (_) async {},
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    final versionText = find.byKey(const Key('empty_canvas_version'));
    expect(versionText, findsOneWidget);
    expect(
      tester.widget<Text>(versionText).data,
      'Version 9.9.9',
    );
  });

  testWidgets('renders the open-file affordances (keys preserved)', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const Locale('en'), DeviceClass.desktop));
    await settle(tester);
    expect(find.byKey(const Key('emptyCanvasOpenFileButton')), findsOneWidget);
    // There is intentionally no new-tab affordance: a blank tab is a dead-end
    // (opening a file always spawns a fresh tab), so the button was removed.
    expect(find.byKey(const Key('emptyCanvasNewTabButton')), findsNothing);
    // Open Workspace is tablet/desktop only.
    expect(
      find.byKey(const Key('emptyCanvasOpenWorkspaceButton')),
      findsOneWidget,
    );
  });

  testWidgets('hides Open Workspace on phone widths', (tester) async {
    await tester.pumpWidget(harness(const Locale('en'), DeviceClass.phone));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('emptyCanvasOpenWorkspaceButton')),
      findsNothing,
    );
  });

  testWidgets('invokes onOpenFile when the open-file button is tapped', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceClassProvider.overrideWithValue(DeviceClass.desktop),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: WaveCruxEmptyCanvas(
              onOpenFile: () => opened = true,
              onOpenRecentFile: (_) async {},
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('emptyCanvasOpenFileButton')));
    expect(opened, isTrue);
  });

  // The bundled-sample button is what makes the app demonstrate itself with
  // no user-supplied file. It is not a nicety: App Store review rejected
  // 0.1.0 (2) under guideline 2.2 partly because a reviewer on an iPhone —
  // which cannot produce a VCD locally — found the welcome screen's only
  // action led to an empty file picker, so the app appeared to do nothing.
  // These tests pin the affordance's presence on every device class.
  testWidgets('shows the sample-waveform button and fires its callback', (
    tester,
  ) async {
    var openedSample = false;
    await tester.pumpWidget(
      harness(
        const Locale('en'),
        DeviceClass.desktop,
        onOpenSample: () => openedSample = true,
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('emptyCanvasOpenSampleButton')));
    expect(openedSample, isTrue);
  });

  testWidgets('offers the sample button on phone, where it matters most', (
    tester,
  ) async {
    // Phone drops "Open Workspace…" (onOpenWorkspace is nulled at phone
    // class), so without the sample button the phone welcome screen has
    // exactly one action and no way to reach any content. Regression guard
    // for the App Store rejection.
    for (final deviceClass in const [
      DeviceClass.phone,
      DeviceClass.phoneLandscape,
      DeviceClass.tablet,
      DeviceClass.desktop,
    ]) {
      await tester.pumpWidget(
        harness(const Locale('en'), deviceClass, onOpenSample: () {}),
      );
      await settle(tester);
      expect(
        find.byKey(const Key('emptyCanvasOpenSampleButton')),
        findsOneWidget,
        reason: 'device class $deviceClass',
      );
    }
  });

  testWidgets('omits the sample button when no callback is supplied', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const Locale('en'), DeviceClass.desktop));
    await settle(tester);
    expect(find.byKey(const Key('emptyCanvasOpenSampleButton')), findsNothing);
  });

  testWidgets('sample button renders across the four locales', (tester) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await tester.pumpWidget(
        harness(locale, DeviceClass.phone, onOpenSample: () {}),
      );
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'locale $locale');
      expect(
        find.byKey(const Key('emptyCanvasOpenSampleButton')),
        findsOneWidget,
        reason: 'locale $locale',
      );
    }
  });

  group('the Recent lists', () {
    late Directory dir;
    late String present;
    const missing = '/definitely/not/a/real/dir/gone.vcd';

    setUp(() {
      dir = Directory.systemTemp.createTempSync('wavecrux_recent_');
      present = (File('${dir.path}/here.vcd')..writeAsStringSync('x')).path;
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    Future<({ProviderContainer container, List<String> opened})> pumpRecents(
      WidgetTester tester, {
      List<String> files = const <String>[],
      List<String> workspaces = const <String>[],
      bool withWorkspaces = true,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'recent_files': files,
        'recent_workspaces': workspaces,
      });
      final opened = <String>[];
      final container = ProviderContainer(
        overrides: [deviceClassProvider.overrideWithValue(DeviceClass.desktop)],
      );
      addTearDown(container.dispose);
      await container.read(recentFiles.provider.notifier).restored;
      await container.read(recentWorkspaces.provider.notifier).restored;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: WaveCruxEmptyCanvas(
                onOpenFile: () {},
                onOpenRecentFile: (path) async => opened.add(path),
                onOpenWorkspace: withWorkspaces ? () {} : null,
                onOpenRecentWorkspace: withWorkspaces
                    ? (path) async => opened.add(path)
                    : null,
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      return (container: container, opened: opened);
    }

    testWidgets('a recent file opens through the product loader', (
      tester,
    ) async {
      final env = await pumpRecents(tester, files: [present]);
      await tester.tap(find.text('here.vcd'));
      await settle(tester);
      expect(env.opened, [present]);
      expect(env.container.read(recentFiles.provider).first, present);
    });

    testWidgets('a file that is gone is greyed and says so', (tester) async {
      await pumpRecents(tester, files: [present, missing]);
      expect(find.text('File not found'), findsOneWidget);
    });

    testWidgets('opening a file that is gone drops it and opens nothing', (
      tester,
    ) async {
      final env = await pumpRecents(tester, files: [present, missing]);
      await tester.tap(find.text('gone.vcd'));
      await settle(tester);
      expect(env.opened, isEmpty);
      expect(env.container.read(recentFiles.provider), [present]);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a row has its own remove button', (tester) async {
      final env = await pumpRecents(tester, files: [present]);
      await tester.tap(find.byKey(const ValueKey('cruxRecentRemove')));
      await settle(tester);
      expect(env.container.read(recentFiles.provider), isEmpty);
    });

    testWidgets('Clear Recent empties the list and says so', (tester) async {
      final env = await pumpRecents(tester, files: [present]);
      await tester.tap(
        find.byKey(const ValueKey('cruxRecentClear:recentFiles')),
      );
      await settle(tester);
      expect(env.container.read(recentFiles.provider), isEmpty);
      expect(find.text('here.vcd'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('the workspaces list is shown only where workspaces open', (
      tester,
    ) async {
      await pumpRecents(
        tester,
        workspaces: ['/tmp/a.wavecrux-workspace'],
        withWorkspaces: false,
      );
      expect(find.text('a.wavecrux-workspace'), findsNothing);

      await pumpRecents(
        tester,
        workspaces: ['/tmp/a.wavecrux-workspace'],
      );
      expect(find.text('a.wavecrux-workspace'), findsOneWidget);
    });
  });
}
