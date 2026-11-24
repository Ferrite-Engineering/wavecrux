// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/annotations/annotation_clipboard.dart';
import 'package:wavecrux/features/annotations/providers/active_tab_annotation_copy_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

/// What Copy puts on the clipboard for a selected annotation: the time and
/// signal its Annotations panel row shows, then the note as written.
void main() {
  const ns = TimeFormatService(
    timescale: Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
  );

  Annotation note(
    String id,
    AnnotationAnchor anchor, {
    String text = '',
    int createdSecond = 0,
  }) => Annotation(
    id: id,
    shape: AnnotationShape.callout,
    anchor: anchor,
    authorName: 'Ada',
    createdAt: DateTime.utc(2026, 11, 22, 12, 0, createdSecond),
    text: text,
  );

  group('annotationClipboardText', () {
    test('a point note on a signal: time and signal, then the note', () {
      final a = note(
        'a',
        const PointAnchor(time: 200, rowId: 'top.req'),
        text: 'req asserts here, one clock before the bus is driven',
      );
      expect(
        annotationClipboardText([a], ns),
        '200 ns  top.req\n'
        'req asserts here, one clock before the bus is driven',
      );
    });

    test('the note is copied as written, Markdown included, and the author '
        'is left out', () {
      final a = note(
        'a',
        const PointAnchor(time: 1500, rowId: 'top.ack'),
        text: 'Handshake **stalls** after `req`\n\n- see [spec](https://x.y)',
      );
      final copied = annotationClipboardText([a], ns);
      expect(
        copied,
        '1.5 µs  top.ack\n'
        'Handshake **stalls** after `req`\n\n- see [spec](https://x.y)',
      );
      expect(copied, isNot(contains('Ada')));
    });

    test('a range reads as the panel shows it, and a range on no signal has '
        'no signal', () {
      final a = note(
        'a',
        const RangeAnchor(startTime: 400, endTime: 200),
        text: 'burst',
      );
      expect(annotationClipboardText([a], ns), '200 ns – 400 ns\nburst');
      expect(
        annotationClipboardText([a], ns).split('\n').first,
        annotationTimeLabel(a, ns),
      );
    });

    test('a range confined to a signal carries it', () {
      final a = note(
        'a',
        const RangeAnchor(startTime: 200, endTime: 400, rowId: 'top.bus'),
        text: 'burst',
      );
      expect(
        annotationClipboardText([a], ns),
        '200 ns – 400 ns  top.bus\nburst',
      );
    });

    test('a note with no text copies its header alone', () {
      final a = note('a', const PointAnchor(time: 0, rowId: 'top.clk'));
      expect(annotationClipboardText([a], ns), '0 ns  top.clk');
    });

    test('without a timescale the time is in ticks, as the panel shows it', () {
      final a = note(
        'a',
        const PointAnchor(time: 200, rowId: 'top.req'),
        text: 'x',
      );
      expect(
        annotationClipboardText([a], const TimeFormatService()),
        '200 ticks  top.req\nx',
      );
    });

    test('several notes are blocks in time order, then creation order, '
        'separated by a blank line', () {
      final late = note(
        'late',
        const PointAnchor(time: 900, rowId: 'top.c'),
        text: 'third',
      );
      final early = note(
        'early',
        const RangeAnchor(startTime: 100, endTime: 300),
        text: 'first',
      );
      final tieB = note(
        'tieB',
        const PointAnchor(time: 500, rowId: 'top.b'),
        text: 'second b',
        createdSecond: 2,
      );
      final tieA = note(
        'tieA',
        const PointAnchor(time: 500, rowId: 'top.a'),
        text: 'second a',
        createdSecond: 1,
      );
      expect(
        annotationClipboardText([late, tieB, early, tieA], ns),
        '100 ns – 300 ns\nfirst\n'
        '\n'
        '500 ns  top.a\nsecond a\n'
        '\n'
        '500 ns  top.b\nsecond b\n'
        '\n'
        '900 ns  top.c\nthird',
      );
    });

    test('no notes copy nothing', () {
      expect(annotationClipboardText(const [], ns), isEmpty);
    });
  });

  group('activeTabAnnotationCopyTextProvider', () {
    late TabContainerManager tcm;
    late ProviderContainer root;

    setUp(() {
      tcm = TabContainerManager();
      root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
    });

    tearDown(() {
      tcm.dispose();
      root.dispose();
    });

    // The composed list is a derived provider, which tells its listeners on
    // the container's next flush rather than at once.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('is the selected annotation of the active tab, and null without '
        'one', () async {
      final sub = root.listen(activeTabAnnotationCopyTextProvider, (_, _) {});
      addTearDown(sub.close);
      expect(root.read(activeTabAnnotationCopyTextProvider), isNull);

      final tab = tcm.containerFor(root.read(activeTabIdProvider));
      tab
          .read(annotationsProvider.notifier)
          .add(
            note(
              'n1',
              const PointAnchor(time: 200, rowId: 'top.req'),
              text: 'req **rises**',
            ),
          );
      // An annotation that exists but is not selected copies nothing.
      expect(root.read(activeTabAnnotationCopyTextProvider), isNull);

      tab.read(annotationSelectedProvider.notifier).selected = 'n1';
      // No file is loaded, so no timescale: ticks, as the panel shows.
      expect(
        root.read(activeTabAnnotationCopyTextProvider),
        '200 ticks  top.req\nreq **rises**',
      );

      // Editing the note changes what Copy copies.
      tab.read(annotationsProvider.notifier).setText('n1', 'edited');
      await settle();
      expect(
        root.read(activeTabAnnotationCopyTextProvider),
        '200 ticks  top.req\nedited',
      );

      tab.read(annotationSelectedProvider.notifier).clear();
      expect(root.read(activeTabAnnotationCopyTextProvider), isNull);
    });

    test('a selection naming a deleted annotation copies nothing', () async {
      final sub = root.listen(activeTabAnnotationCopyTextProvider, (_, _) {});
      addTearDown(sub.close);
      final tab = tcm.containerFor(root.read(activeTabIdProvider));
      tab
          .read(annotationsProvider.notifier)
          .add(note('n1', const PointAnchor(time: 1, rowId: 'top.a')));
      tab.read(annotationSelectedProvider.notifier).selected = 'n1';
      expect(root.read(activeTabAnnotationCopyTextProvider), isNotNull);
      tab.read(annotationsProvider.notifier).remove('n1');
      await settle();
      expect(root.read(activeTabAnnotationCopyTextProvider), isNull);
    });

    testWidgets('a change that lands while a frame is building waits for the '
        'end of the frame', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final sub = root.listen(activeTabAnnotationCopyTextProvider, (_, _) {});
      final tab = tcm.containerFor(root.read(activeTabIdProvider));
      tab
          .read(annotationsProvider.notifier)
          .add(note('n1', const PointAnchor(time: 1, rowId: 'top.a')));

      // A persistent frame callback runs in the phase where widgets build,
      // which is where a StatusBar mounting flushes the tab's providers and
      // reaches this provider's listeners.
      var fired = false;
      String? duringFrame = 'unset';
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (fired) return;
        fired = true;
        tab.read(annotationSelectedProvider.notifier).selected = 'n1';
        duringFrame = root.read(activeTabAnnotationCopyTextProvider);
      });
      tester.binding.scheduleFrame();
      await tester.pump();

      expect(fired, isTrue);
      expect(duringFrame, isNull, reason: 'not written mid-frame');
      expect(root.read(activeTabAnnotationCopyTextProvider), '1 ticks  top.a');

      // Tear down inside the body: disposing a container schedules a timer
      // that flutter_test wants gone before the body returns.
      sub.close();
      tcm.dispose();
      root.dispose();
      await tester.pump(const Duration(seconds: 1));
      tcm = TabContainerManager();
      root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
    });

    test('another tab selecting an annotation does not bleed in', () {
      final sub = root.listen(activeTabAnnotationCopyTextProvider, (_, _) {});
      addTearDown(sub.close);
      final other = tcm.containerFor(TabId.generate());
      other
          .read(annotationsProvider.notifier)
          .add(note('o1', const PointAnchor(time: 1, rowId: 'top.a')));
      other.read(annotationSelectedProvider.notifier).selected = 'o1';
      expect(root.read(activeTabAnnotationCopyTextProvider), isNull);
    });
  });
}
