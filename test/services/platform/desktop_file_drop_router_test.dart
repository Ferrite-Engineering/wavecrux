// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/platform/desktop_file_drop_router.dart';

void main() {
  group('DesktopFileDropRouter', () {
    late DesktopFileDropRouter router;
    late List<List<String>> delivered;
    late bool accepting;
    late DesktopFileDropHandler handler;

    setUp(() {
      router = DesktopFileDropRouter();
      delivered = [];
      accepting = true;
      handler = DesktopFileDropHandler(
        canAccept: () => accepting,
        onDrop: (paths) async => delivered.add(paths),
      );
    });

    test('with no handler it accepts nothing and delivers nothing', () async {
      expect(router.canAccept, isFalse);
      expect(await router.deliver(['/a.vcd']), isFalse);
    });

    test('delivers to the attached handler', () async {
      router.attach(handler);
      expect(router.canAccept, isTrue);
      expect(await router.deliver(['/a.vcd', '/b.fst']), isTrue);
      expect(delivered, [
        ['/a.vcd', '/b.fst'],
      ]);
    });

    test('asks the handler at delivery time, not only on entry', () async {
      router.attach(handler);
      accepting = false;
      expect(router.canAccept, isFalse);
      expect(await router.deliver(['/a.vcd']), isFalse);
      expect(delivered, isEmpty);
    });

    test('an empty drop is not delivered', () async {
      router.attach(handler);
      expect(await router.deliver(const []), isFalse);
      expect(delivered, isEmpty);
    });

    test('the returned detach removes the handler', () async {
      router.attach(handler)();
      expect(router.canAccept, isFalse);
      expect(await router.deliver(['/a.vcd']), isFalse);
    });

    test('detaching a replaced handler leaves its successor attached', () {
      final detachFirst = router.attach(handler);
      final successor = DesktopFileDropHandler(
        canAccept: () => true,
        onDrop: (_) async {},
      );
      router.attach(successor);
      detachFirst();
      expect(router.canAccept, isTrue);
    });

    test('delivers in open order: .gtkw sessions after everything else', () {
      router.attach(handler);
      return router
          .deliver(['/s.gtkw', '/a.vcd', '/T.GTKW', '/b.fst'])
          .then(
            (_) => expect(delivered.single, [
              '/a.vcd',
              '/b.fst',
              '/s.gtkw',
              '/T.GTKW',
            ]),
          );
    });
  });

  group('DesktopFileDropRouter.isGtkwPath', () {
    test('matches the extension case-insensitively', () {
      expect(DesktopFileDropRouter.isGtkwPath('/x/y.gtkw'), isTrue);
      expect(DesktopFileDropRouter.isGtkwPath(r'C:\x\Y.GTKW'), isTrue);
    });

    test('does not match other files', () {
      expect(DesktopFileDropRouter.isGtkwPath('/x/y.vcd'), isFalse);
      expect(DesktopFileDropRouter.isGtkwPath('/x/gtkw'), isFalse);
      expect(DesktopFileDropRouter.isGtkwPath('/x/y.gtkw.bak'), isFalse);
    });
  });

  group('DesktopFileDropRouter.openOrder', () {
    test('keeps drop order within each group', () {
      expect(
        DesktopFileDropRouter.openOrder(['/2.gtkw', '/b', '/1.gtkw', '/a']),
        ['/b', '/a', '/2.gtkw', '/1.gtkw'],
      );
    });

    test('leaves a drop with no .gtkw unchanged', () {
      expect(DesktopFileDropRouter.openOrder(['/b.vcd', '/a.vcd']), [
        '/b.vcd',
        '/a.vcd',
      ]);
    });
  });
}
