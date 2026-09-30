// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/pcap_to_vcd_dialog_opener_provider.dart';

void main() {
  group('pcapToVcdDialogOpenerProvider', () {
    test('default opener is non-null and can be read from a container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final opener = container.read(pcapToVcdDialogOpenerProvider);
      expect(opener, isNotNull);
    });

    testWidgets(
      'default opener runs without throwing when invoked with a real context',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          ProviderScope(
            child: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        );

        final container = ProviderScope.containerOf(capturedContext);
        final opener = container.read(pcapToVcdDialogOpenerProvider);

        expect(() => opener(capturedContext), returnsNormally);
      },
    );

    testWidgets(
      'can be overridden by a Pro-style opener that mounts a dialog',
      (tester) async {
        var openCount = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pcapToVcdDialogOpenerProvider.overrideWithValue((_) {
                openCount++;
              }),
            ],
            child: Builder(
              builder: (context) {
                // Trigger the opener as soon as the widget tree is built.
                final container = ProviderScope.containerOf(context);
                container.read(pcapToVcdDialogOpenerProvider)(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(openCount, 1);
      },
    );
  });
}
