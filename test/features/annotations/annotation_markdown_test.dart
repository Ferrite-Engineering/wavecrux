// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxDesktopTokens;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_markdown.dart';
import 'package:wavecrux/features/annotations/widgets/annotations_panel.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

/// The Annotations panel draws a note's text as Markdown; nothing else does.
///
/// Links are the one part that can reach outside the app, so the scheme filter
/// and the explicit-activation rule are tested directly, not through the
/// package's own behaviour.

const _multiLine =
    'Handshake **stalls** after `req` rises.\n'
    '\n'
    '- first item\n'
    '- second item\n'
    '\n'
    '```\n'
    'assign ack = req & ~busy;\n'
    '```\n'
    '\n'
    'See [the spec](https://example.com/spec).';

Future<void> _pumpMarkdown(
  WidgetTester tester,
  String text, {
  VoidCallback? onLinkFailed,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 400,
        child: AnnotationMarkdown(text: text, onLinkFailed: onLinkFailed),
      ),
    ),
  ),
);

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: 8,
);

Annotation _ann(String id, String text) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: const PointAnchor(time: 300, rowId: 'top.data'),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 12),
  text: text,
);

Future<void> _pumpPanel(
  WidgetTester tester,
  List<Annotation> annotations, {
  bool desktop = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      annotationStatusesProvider.overrideWithValue({
        for (final a in annotations) a.id: AnnotationStatus.resolved,
      }),
    ],
  );
  addTearDown(container.dispose);
  container
    ..listen(signalGroupsProvider, (_, _) {})
    ..listen(timeMapperProvider, (_, _) {})
    ..listen(annotationsProvider, (_, _) {})
    ..listen(annotationLayersProvider, (_, _) {});
  container.read(signalGroupsProvider.notifier).addSignal(_v('data'));
  container
      .read(timeMapperProvider.notifier)
      .initialize(startTime: 0, endTime: 1000, viewportWidth: 800);
  annotations.forEach(container.read(annotationsProvider.notifier).add);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          extensions: [if (desktop) const CruxDesktopTokens()],
        ),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: SizedBox(width: 500, height: 600, child: AnnotationsPanel()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late Future<bool> Function(Uri, {LaunchMode mode}) original;
  late List<Uri> launched;

  setUp(() {
    original = annotationLaunchUrl;
    launched = <Uri>[];
    annotationLaunchUrl = (uri, {mode = LaunchMode.externalApplication}) async {
      launched.add(uri);
      return true;
    };
  });
  tearDown(() => annotationLaunchUrl = original);

  group('link scheme filter', () {
    test('http and https with a host are allowed', () {
      expect(isSafeNoteLink('http://example.com'), isTrue);
      expect(isSafeNoteLink('https://example.com/a?b=c#d'), isTrue);
      expect(isSafeNoteLink('HTTPS://EXAMPLE.COM'), isTrue);
      expect(isSafeNoteLink('  https://example.com  '), isTrue);
    });

    test('every other scheme and form is refused', () {
      for (final href in <String?>[
        null,
        '',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'data:text/html,<b>x</b>',
        'mailto:a@example.com',
        'ftp://example.com/x',
        'vscode://file/etc/passwd',
        'wavecrux://open?x=1',
        '/relative/path',
        'relative.html',
        '//example.com/protocol-relative',
        'https://',
        'http:///nohost',
      ]) {
        expect(isSafeNoteLink(href), isFalse, reason: '$href must not open');
      }
    });
  });

  group('rendering', () {
    testWidgets('paragraphs, emphasis, code, list and block render', (
      tester,
    ) async {
      await _pumpMarkdown(tester, _multiLine);

      // Emphasis and code marks are consumed, never shown.
      expect(find.textContaining('**', findRichText: true), findsNothing);
      expect(find.textContaining('`', findRichText: true), findsNothing);
      expect(
        find.textContaining(
          'Handshake stalls after req rises.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('first item', findRichText: true), findsOneWidget);
      expect(find.text('second item', findRichText: true), findsOneWidget);
      expect(
        find.text('assign ack = req & ~busy;', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('the spec', findRichText: true), findsOneWidget);
    });

    testWidgets('bold is bold and inline code is monospace', (tester) async {
      await _pumpMarkdown(tester, '**loud** and `code`');
      final spans = <InlineSpan>[];
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(AnnotationMarkdown),
          matching: find.byType(RichText),
        ),
      );
      rich.text.visitChildren((s) {
        spans.add(s);
        return true;
      });
      final loud = spans.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'loud',
      );
      final code = spans.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'code',
      );
      expect(loud.style?.fontWeight, FontWeight.bold);
      expect(code.style?.fontFamily, 'monospace');
    });

    testWidgets('a plain note reads exactly as it was written', (tester) async {
      await _pumpMarkdown(tester, 'req stays high for 3 cycles');
      expect(find.text('req stays high for 3 cycles'), findsOneWidget);
    });

    testWidgets('a single newline stays a line break', (tester) async {
      await _pumpMarkdown(tester, 'line one\nline two');
      expect(
        find.text('line one\nline two', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('an image draws its alt text and loads nothing', (
      tester,
    ) async {
      await _pumpMarkdown(tester, '![probe shot](https://example.com/p.png)');
      expect(find.byType(Image), findsNothing);
      expect(find.text('probe shot'), findsOneWidget);
    });

    testWidgets('raw HTML is not interpreted', (tester) async {
      await _pumpMarkdown(tester, '<img src="https://example.com/x.png">hi');
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('the text is selectable for copy', (tester) async {
      await _pumpMarkdown(tester, _multiLine);
      expect(
        find.descendant(
          of: find.byType(SelectionArea),
          matching: find.byType(AnnotationMarkdown),
        ),
        findsNothing,
        reason: 'the area wraps the rendered body, not the reverse',
      );
      expect(
        find.descendant(
          of: find.byType(AnnotationMarkdown),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
      // A selection across the rendered text copies the note's text.
      final area = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            clipboard.add(args['text']! as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      area.selectAll();
      await tester.pump();
      // The keyboard route, which is the one a desktop user has. A click on
      // the text puts focus on the area; the test does the same directly.
      Focus.of(
        tester.element(find.text('first item', findRichText: true)),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(clipboard, hasLength(1));
      final selected = clipboard.single;
      expect(selected, contains('Handshake stalls after req rises.'));
      expect(selected, contains('assign ack = req & ~busy;'));
      expect(selected, contains('the spec'));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('screen reader text is the note text without markup', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpMarkdown(tester, 'Handshake **stalls** after `req` rises.');
      expect(
        find.bySemanticsLabel('Handshake stalls after req rises.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'\*\*|`')), findsNothing);
      handle.dispose();
    });
  });

  group('links', () {
    testWidgets('nothing opens on render or hover', (tester) async {
      await _pumpMarkdown(tester, '[spec](https://example.com/spec)');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('spec')));
      await tester.pump();
      expect(launched, isEmpty);
    });

    testWidgets('a click opens the destination, once', (tester) async {
      await _pumpMarkdown(tester, '[spec](https://example.com/spec)');
      await tester.tap(find.text('spec'));
      await tester.pump();
      expect(launched, [Uri.parse('https://example.com/spec')]);
    });

    testWidgets('the link is a keyboard stop and Enter opens it', (
      tester,
    ) async {
      await _pumpMarkdown(tester, 'a [spec](https://example.com/spec) b');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(launched, isEmpty, reason: 'focus alone must not open it');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(launched, [Uri.parse('https://example.com/spec')]);
    });

    testWidgets('Space opens a focused link as well', (tester) async {
      await _pumpMarkdown(tester, '[spec](https://example.com/spec)');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(launched, hasLength(1));
    });

    testWidgets('the destination is shown in the tooltip', (tester) async {
      await _pumpMarkdown(tester, '[spec](https://example.com/spec)');
      expect(
        find.byTooltip('https://example.com/spec'),
        findsOneWidget,
        reason: 'the label can say anything, the destination must be visible',
      );
    });

    testWidgets('a link is announced as a link', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpMarkdown(tester, '[spec](https://example.com/spec)');
      expect(
        tester.getSemantics(find.text('spec')),
        matchesSemantics(
          label: 'spec',
          isLink: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          tooltip: 'https://example.com/spec',
        ),
      );
      handle.dispose();
    });

    for (final href in <String>[
      'file:///etc/passwd',
      'javascript:alert(1)',
      'vscode://file/x',
      'mailto:a@example.com',
      '/relative',
    ]) {
      testWidgets('$href renders as text and never opens', (tester) async {
        await _pumpMarkdown(tester, '[label]($href)');
        expect(find.text('label'), findsOneWidget);
        expect(find.byType(InkWell), findsNothing);
        await tester.tap(find.text('label'));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(launched, isEmpty);
      });
    }

    testWidgets('a refused launch tells the user', (tester) async {
      annotationLaunchUrl =
          (uri, {mode = LaunchMode.externalApplication}) async => false;
      var failed = 0;
      await _pumpMarkdown(
        tester,
        '[spec](https://example.com/spec)',
        onLinkFailed: () => failed++,
      );
      await tester.tap(find.text('spec'));
      await tester.pump();
      expect(failed, 1);
    });

    testWidgets('a launcher that throws is reported, not raised', (
      tester,
    ) async {
      annotationLaunchUrl = (uri, {mode = LaunchMode.externalApplication}) =>
          throw StateError('no browser');
      var failed = 0;
      await _pumpMarkdown(
        tester,
        '[spec](https://example.com/spec)',
        onLinkFailed: () => failed++,
      );
      await tester.tap(find.text('spec'));
      await tester.pump();
      expect(failed, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('in the Annotations panel', () {
    testWidgets('a multi-line note renders as Markdown in its row', (
      tester,
    ) async {
      await _pumpPanel(tester, [_ann('a1', _multiLine)]);
      expect(find.byType(AnnotationMarkdown), findsOneWidget);
      expect(find.text('first item', findRichText: true), findsOneWidget);
      expect(find.textContaining('**', findRichText: true), findsNothing);
    });

    for (final desktop in [true, false]) {
      testWidgets(
        'a one-line note row is as tall as a plain-text one '
        '(${desktop ? 'desktop' : 'phone'})',
        (tester) async {
          final row = find.byKey(const ValueKey('annotation-row-a1'));
          await _pumpPanel(tester, [
            _ann('a1', 'short note'),
          ], desktop: desktop);
          final plain = tester.getSize(row).height;
          // Desktop rows never fall under the 40 px two-line height.
          if (desktop) expect(plain, greaterThanOrEqualTo(40));

          // Unmount between pumps so provider disposal timers run out.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await _pumpPanel(
            tester,
            [_ann('a1', '**short** `note`')],
            desktop: desktop,
          );
          expect(
            tester.getSize(row).height,
            plain,
            reason: 'Markdown on one line must not grow the row',
          );

          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await _pumpPanel(tester, [_ann('a1', _multiLine)], desktop: desktop);
          expect(tester.getSize(row).height, greaterThan(plain));
        },
      );
    }

    testWidgets('one line of Markdown is one Text line high', (tester) async {
      await _pumpMarkdown(tester, 'short note');
      final markdown = tester.getSize(find.byType(AnnotationMarkdown)).height;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('short note', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
      expect(markdown, tester.getSize(find.text('short note')).height);
    });

    testWidgets('tapping the row text still selects the note', (tester) async {
      await _pumpPanel(tester, [_ann('a1', 'short note')]);
      await tester.tap(find.text('short note'));
      // The double-tap window (edit) has to lapse before the tap resolves.
      await tester.pump(const Duration(milliseconds: 400));
      final row = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('annotation-row-a1')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((row.decoration as BoxDecoration?)?.border, isNotNull);
    });

    testWidgets('the stored text is untouched', (tester) async {
      final note = _ann('a1', _multiLine);
      await _pumpPanel(tester, [note]);
      expect(note.text, _multiLine);
    });
  });
}
