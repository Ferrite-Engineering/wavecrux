// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/editor_host/editor_host_capability_copy.dart';
import 'package:wavecrux/domain/enums/editor_host_capability.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/host_bridge/capability_nudge_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_session_provider.dart';
import 'package:wavecrux/shared/widgets/editor_host_boundary.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

/// Widths a VSCode editor panel realistically has: a narrow vertical split, a half-window split,
/// and a maximised editor group.
const _panelWidths = <double>[400, 500, 700, 1200];

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  EditorHostKind hostKind = EditorHostKind.vscode,
  Size size = const Size(700, 600),
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  container.read(editorHostKindProvider.notifier).set(hostKind);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('formatEditorHostParseDuration', () {
    test('matches the Diagnostics pane: ms below a second, s above', () {
      expect(
        formatEditorHostParseDuration(const Duration(milliseconds: 450)),
        '450 ms',
      );
      expect(
        formatEditorHostParseDuration(const Duration(seconds: 12)),
        '12.0 s',
      );
      expect(
        formatEditorHostParseDuration(const Duration(milliseconds: 8400)),
        '8.4 s',
      );
    });
  });

  group('editorHostCapabilityCopy', () {
    testWidgets('every capability resolves a non-empty title and message '
        'in every shipped locale', (tester) async {
      for (final locale in _locales) {
        late L10N l10n;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) {
                l10n = L10N.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final capability in EditorHostCapability.values) {
          final copy = editorHostCapabilityCopy(
            l10n,
            capability,
            parseDuration: const Duration(seconds: 9),
          );
          expect(
            copy.title,
            isNotEmpty,
            reason: '$capability title empty in ${locale.toLanguageTag()}',
          );
          expect(
            copy.message,
            isNotEmpty,
            reason: '$capability message empty in ${locale.toLanguageTag()}',
          );
          // The boundary voice is three-part; a one-clause string is a
          // regression to the "upgrade now" register that voice rules out.
          expect(
            copy.message.length,
            greaterThan(80),
            reason:
                '$capability message looks truncated in '
                '${locale.toLanguageTag()}',
          );
        }
      }
    });

    testWidgets('the slow-parse title carries the MEASURED duration', (
      tester,
    ) async {
      late L10N l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = L10N.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final copy = editorHostCapabilityCopy(
        l10n,
        EditorHostCapability.slowParse,
        parseDuration: const Duration(milliseconds: 8400),
      );
      expect(copy.title, contains('8.4 s'));
    });
  });

  group('EditorHostBoundary', () {
    testWidgets('states the capability, and does not overflow at any '
        'realistic panel width', (tester) async {
      for (final width in _panelWidths) {
        for (final capability in <EditorHostCapability>[
          EditorHostCapability.stage,
          EditorHostCapability.rtlAnnotation,
        ]) {
          await _pump(
            tester,
            EditorHostBoundary(capability: capability),
            size: Size(width, 320),
          );
          expect(
            find.byKey(const Key('editorHostBoundaryTitle')),
            findsOneWidget,
            reason: '$capability title missing at ${width}px',
          );
          expect(
            find.byKey(const Key('editorHostBoundaryMessage')),
            findsOneWidget,
            reason: '$capability message missing at ${width}px',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$capability overflowed at ${width}px',
          );
        }
      }
    });
  });

  group('EditorHostCapabilityNote', () {
    testWidgets('renders nothing when no editor is hosting us', (tester) async {
      await _pump(
        tester,
        const EditorHostCapabilityNote(
          capability: EditorHostCapability.interactiveVcd,
        ),
        hostKind: EditorHostKind.none,
      );
      expect(find.byKey(const Key('editorHostCapabilityNote')), findsNothing);
    });

    testWidgets('states the interactive-VCD boundary under an editor host', (
      tester,
    ) async {
      await _pump(
        tester,
        const EditorHostCapabilityNote(
          capability: EditorHostCapability.interactiveVcd,
        ),
        size: const Size(420, 300),
      );
      expect(find.byKey(const Key('editorHostCapabilityNote')), findsOneWidget);
      expect(find.textContaining('stdin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CapabilityNudgeBanner', () {
    testWidgets('renders nothing while no nudge has been raised', (
      tester,
    ) async {
      await _pump(tester, const CapabilityNudgeBanner());
      expect(find.byKey(const Key('capabilityNudgeBanner')), findsNothing);
    });

    testWidgets('shows the raised nudge and dismisses on the close button', (
      tester,
    ) async {
      final container = await _pump(tester, const CapabilityNudgeBanner());
      container
          .read(editorHostSessionProvider.notifier)
          .set(const EditorHostSession(openedFileBefore: true));
      expect(
        container
            .read(capabilityNudgeProvider.notifier)
            .offerSlowParse(const Duration(milliseconds: 8400)),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('capabilityNudgeBanner')), findsOneWidget);
      expect(find.textContaining('8.4 s'), findsOneWidget);

      // Dismissible is not optional — a notice the user cannot get rid of is
      // an interruption wearing a banner's clothes.
      await tester.tap(find.byKey(const Key('capabilityNudgeDismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('capabilityNudgeBanner')), findsNothing);

      // And dismissal does not re-arm the session.
      expect(
        container
            .read(capabilityNudgeProvider.notifier)
            .offerSlowParse(const Duration(seconds: 30)),
        isFalse,
      );
    });

    testWidgets('the banner and its dismiss control survive a narrow split', (
      tester,
    ) async {
      for (final width in _panelWidths) {
        // Height is the panel's, not the banner's: the banner is a plain
        // (non-Expanded) child of the viewer's Column, so it takes the height
        // it needs and the waveform gets the rest. Constraining it here would
        // test a layout it is never given.
        final container = await _pump(
          tester,
          const Align(
            alignment: Alignment.topCenter,
            child: CapabilityNudgeBanner(),
          ),
          size: Size(width, 600),
        );
        container
            .read(editorHostSessionProvider.notifier)
            .set(const EditorHostSession(openedFileBefore: true));
        container
            .read(capabilityNudgeProvider.notifier)
            .offerSlowParse(const Duration(seconds: 9));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('capabilityNudgeTitle')),
          findsOneWidget,
          reason: 'title missing at ${width}px',
        );
        expect(
          find.byKey(const Key('capabilityNudgeDismiss')),
          findsOneWidget,
          reason: 'dismiss control missing at ${width}px',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'banner overflowed at ${width}px',
        );
      }
    });
  });
}
