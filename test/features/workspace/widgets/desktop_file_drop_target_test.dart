// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/workspace/providers/desktop_file_drop_provider.dart';
import 'package:wavecrux/features/workspace/widgets/desktop_file_drop_target.dart';
import 'package:wavecrux/features/workspace/widgets/file_drop_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/platform/desktop_file_drop_router.dart';

/// Stands in for `desktop_drop` through the widget's drop-target seam.
class _FakeDrag {
  int builds = 0;
  late VoidCallback enter;
  late VoidCallback exit;
  late ValueChanged<List<String>> drop;

  Widget build({
    required Widget child,
    required VoidCallback onEntered,
    required VoidCallback onExited,
    required ValueChanged<List<String>> onDropped,
  }) {
    builds++;
    enter = onEntered;
    exit = onExited;
    drop = onDropped;
    return child;
  }
}

class _Fixture {
  _Fixture({bool attach = true}) {
    if (attach) {
      container
          .read(desktopFileDropRouterProvider)
          .attach(
            DesktopFileDropHandler(
              canAccept: () => accepting,
              onDrop: (paths) async => delivered.add(paths),
            ),
          );
    }
  }

  final container = ProviderContainer();
  final drag = _FakeDrag();
  final delivered = <List<String>>[];
  bool accepting = true;

  Widget app({
    Locale locale = const Locale('en'),
    DesktopDropTargetBuilder? builder,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      builder: (context, child) => DesktopFileDropTarget(
        dropTargetBuilder: builder ?? drag.build,
        child: child ?? const SizedBox(),
      ),
      home: const Scaffold(body: Text('window content')),
    ),
  );
}

void main() {
  final desktop = TargetPlatformVariant.desktop();

  testWidgets(
    'off a native desktop host it renders the app untouched',
    variant: TargetPlatformVariant.mobile(),
    (tester) async {
      final f = _Fixture();
      addTearDown(f.container.dispose);
      await tester.pumpWidget(f.app());
      expect(find.text('window content'), findsOneWidget);
      expect(f.drag.builds, 0, reason: 'no drop target is built on mobile');
    },
  );

  testWidgets(
    'a drag over the window shows the overlay; leaving hides it',
    variant: desktop,
    (tester) async {
      final f = _Fixture();
      addTearDown(f.container.dispose);
      await tester.pumpWidget(f.app());
      expect(find.byType(FileDropOverlay), findsNothing);

      f.drag.enter();
      await tester.pump();
      expect(find.byType(FileDropOverlay), findsOneWidget);
      expect(find.text('window content'), findsOneWidget);

      f.drag.exit();
      await tester.pump();
      expect(find.byType(FileDropOverlay), findsNothing);
      expect(f.delivered, isEmpty);
    },
  );

  testWidgets(
    'a drop hides the overlay and delivers the paths in open order',
    variant: desktop,
    (tester) async {
      final f = _Fixture();
      addTearDown(f.container.dispose);
      await tester.pumpWidget(f.app());
      f.drag.enter();
      await tester.pump();
      f.drag.drop(['/w.gtkw', '/a.vcd']);
      await tester.pump();
      expect(find.byType(FileDropOverlay), findsNothing);
      expect(f.delivered, [
        ['/a.vcd', '/w.gtkw'],
      ]);
    },
  );

  testWidgets(
    'no overlay and no delivery when the viewer cannot accept a drop',
    variant: desktop,
    (tester) async {
      final f = _Fixture()..accepting = false;
      addTearDown(f.container.dispose);
      await tester.pumpWidget(f.app());
      f.drag.enter();
      await tester.pump();
      expect(find.byType(FileDropOverlay), findsNothing);
      f.drag.drop(['/a.vcd']);
      await tester.pump();
      expect(f.delivered, isEmpty);
    },
  );

  testWidgets(
    'no overlay when no viewer is attached',
    variant: desktop,
    (tester) async {
      final f = _Fixture(attach: false);
      addTearDown(f.container.dispose);
      await tester.pumpWidget(f.app());
      f.drag.enter();
      await tester.pump();
      expect(find.byType(FileDropOverlay), findsNothing);
    },
  );

  testWidgets(
    'entering and leaving never remounts the window content',
    variant: desktop,
    (tester) async {
      final f = _Fixture();
      addTearDown(f.container.dispose);
      await tester.pumpWidget(f.app());
      final before = tester.element(find.text('window content'));
      f.drag.enter();
      await tester.pump();
      f.drag.exit();
      await tester.pump();
      expect(tester.element(find.text('window content')), same(before));
    },
  );

  testWidgets(
    'the production builder turns a desktop_drop drop into paths',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      // One pass through the real plugin's Dart side, fed the messages its
      // macOS runner sends, to pin the one conversion the seam hides.
      final f = _Fixture();
      addTearDown(f.container.dispose);
      await tester.pumpWidget(f.app(builder: pluginDesktopDropTarget));

      Future<void> send(String method, Object? args) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'desktop_drop',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            (_) {},
          );

      await send('entered', <double>[20, 20]);
      await tester.pump();
      expect(find.byType(FileDropOverlay), findsOneWidget);

      await send('performOperation_macos', [
        {'path': '/tmp/a.vcd', 'isDirectory': false},
        {'path': '/tmp/design', 'isDirectory': true},
      ]);
      await tester.pump();
      expect(find.byType(FileDropOverlay), findsNothing);
      expect(f.delivered, [
        ['/tmp/a.vcd', '/tmp/design'],
      ]);
    },
  );

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets(
        'the overlay renders in $locale',
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
        (tester) async {
          final f = _Fixture();
          addTearDown(f.container.dispose);
          await tester.pumpWidget(f.app(locale: locale));
          f.drag.enter();
          await tester.pump();
          expect(find.byType(FileDropOverlay), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
