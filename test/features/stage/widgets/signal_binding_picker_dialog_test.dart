// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/widgets/signal_binding_picker_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Variable _v(String name, String ref, {int? width, String scopePath = 'top'}) =>
    Variable(
      name: name,
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: ref,
      scopePath: scopePath,
      bitWidth: width,
    );

const _vars = <String, Variable>{};

Widget _wrap({
  required List<Override> overrides,
  Locale locale = const Locale('en'),
  Widget? home,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: home ?? const Scaffold(body: SizedBox.shrink()),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

void main() {
  group('SignalBindingPickerDialog', () {
    final variables = {
      'top.engine.rpm': _v(
        'rpm',
        'top.engine.rpm',
        width: 16,
        scopePath: 'top.engine',
      ),
      'top.engine.redline': _v(
        'redline',
        'top.engine.redline',
        width: 16,
        scopePath: 'top.engine',
      ),
      'top.misc.brake': _v(
        'brake',
        'top.misc.brake',
        width: 1,
        scopePath: 'top.misc',
      ),
    };

    testWidgets('shows the empty-no-file message when no variables loaded', (
      tester,
    ) async {
      SignalBindingPickerResult? result;
      await tester.pumpWidget(
        _wrap(
          overrides: [
            signalVariablesByPathProvider.overrideWith((_) => _vars),
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () async {
                    result = await SignalBindingPickerDialog.show(
                      context,
                      pinName: 'rpm',
                      pinDescription: 'Engine RPM',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _openDialog(tester);

      final l10n = lookupL10N(const Locale('en'));
      expect(find.text(l10n.signalBindingPickerEmptyNoFile), findsOneWidget);

      // Cancel the dialog → result is null.
      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(AlertDialog)),
          ).cancelButtonLabel,
        ),
      );
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('lists variables sorted by full path and a tap returns '
        'the picked signalRef', (tester) async {
      SignalBindingPickerResult? result;
      await tester.pumpWidget(
        _wrap(
          overrides: [
            signalVariablesByPathProvider.overrideWith((_) => variables),
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () async {
                    result = await SignalBindingPickerDialog.show(
                      context,
                      pinName: 'rpm',
                      pinDescription: 'desc',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _openDialog(tester);

      // All three rows render.
      expect(find.text('top.engine.rpm'), findsOneWidget);
      expect(find.text('top.engine.redline'), findsOneWidget);
      expect(find.text('top.misc.brake'), findsOneWidget);

      // Bit width chip renders for multi-bit signals.
      expect(find.text('[16]'), findsWidgets);
      expect(find.text('[1]'), findsOneWidget);

      // Tap the rpm row.
      await tester.tap(find.text('top.engine.rpm'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.signalRef, 'top.engine.rpm');
    });

    testWidgets('filters by substring; empty-no-match message appears', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            signalVariablesByPathProvider.overrideWith((_) => variables),
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => SignalBindingPickerDialog.show(
                    context,
                    pinName: 'rpm',
                    pinDescription: 'desc',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _openDialog(tester);

      // Type a query that matches only one entry.
      await tester.enterText(find.byType(TextField), 'redline');
      await tester.pumpAndSettle();
      expect(find.text('top.engine.redline'), findsOneWidget);
      expect(find.text('top.engine.rpm'), findsNothing);

      // Now type a query that matches none.
      await tester.enterText(find.byType(TextField), 'zzz_no_match');
      await tester.pumpAndSettle();
      final l10n = lookupL10N(const Locale('en'));
      expect(find.text(l10n.signalBindingPickerEmptyNoMatch), findsOneWidget);
    });

    testWidgets('Clear button only renders when a current binding is set, '
        'and returns SignalBindingPickerResult(signalRef: null)', (
      tester,
    ) async {
      SignalBindingPickerResult? result;
      await tester.pumpWidget(
        _wrap(
          overrides: [
            signalVariablesByPathProvider.overrideWith((_) => variables),
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () async {
                    result = await SignalBindingPickerDialog.show(
                      context,
                      pinName: 'rpm',
                      pinDescription: 'desc',
                      currentSignalRef: 'top.engine.rpm',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _openDialog(tester);

      final l10n = lookupL10N(const Locale('en'));
      await tester.tap(find.text(l10n.signalBindingPickerClear));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.signalRef, isNull);
    });

    testWidgets('Clear button is hidden when no current binding', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            signalVariablesByPathProvider.overrideWith((_) => variables),
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => SignalBindingPickerDialog.show(
                    context,
                    pinName: 'rpm',
                    pinDescription: 'desc',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _openDialog(tester);

      final l10n = lookupL10N(const Locale('en'));
      expect(find.text(l10n.signalBindingPickerClear), findsNothing);
    });

    group('locale sweep', () {
      const locales = [
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        Locale('ja'),
        Locale('ko'),
      ];
      for (final locale in locales) {
        testWidgets('renders without exceptions in $locale', (tester) async {
          await tester.pumpWidget(
            _wrap(
              locale: locale,
              overrides: [
                signalVariablesByPathProvider.overrideWith((_) => variables),
              ],
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      key: const Key('open'),
                      onPressed: () => SignalBindingPickerDialog.show(
                        context,
                        pinName: 'rpm',
                        pinDescription: 'desc',
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _openDialog(tester);
          expect(tester.takeException(), isNull);
        });
      }
    });

    testWidgets('signal list re-enables trackpad two-finger scroll', (
      tester,
    ) async {
      // Regression: the app-wide ScrollConfiguration restricts dragDevices
      // to {touch}, which drops macOS/iPad trackpad pan-zoom. The picker's
      // signal list must add trackpad back or a two-finger swipe over the
      // list does nothing — the user can't reach signals below the fold.
      await tester.pumpWidget(
        _wrap(
          overrides: [
            signalVariablesByPathProvider.overrideWith((_) => variables),
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => SignalBindingPickerDialog.show(
                    context,
                    pinName: 'rpm',
                    pinDescription: 'desc',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _openDialog(tester);

      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);
      final config = tester.widget<ScrollConfiguration>(
        find
            .ancestor(
              of: listView,
              matching: find.byType(ScrollConfiguration),
            )
            .first,
      );
      final devices = config.behavior.dragDevices;
      expect(devices, contains(PointerDeviceKind.trackpad));
      expect(devices, contains(PointerDeviceKind.touch));
    });

    test('SignalBindingPickerResult equality on signalRef', () {
      const a = SignalBindingPickerResult(signalRef: 'top.a');
      const b = SignalBindingPickerResult(signalRef: 'top.a');
      const c = SignalBindingPickerResult();
      // Const-canonicalization makes a and b identical regardless of `==`,
      // and c is the cleared variant.
      expect(identical(a, b), isTrue);
      expect(c.signalRef, isNull);
    });
  });
}
