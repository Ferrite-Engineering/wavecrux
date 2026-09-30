// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: device-class layout gating (structural presence/
// absence of RtlSourcePanel at various surface sizes), not locale-sensitive
// text rendering. No CJK/RenderFlex risk — see wavecrux/CLAUDE.md's locale
// sweep rule for the render-object/gesture-math carve-out this file falls
// under.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/rtl_source/widgets/rtl_source_panel.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Mirrors the right-pane selection logic in `ViewerScreen.build` so we can
/// verify the gating in isolation: the [RtlSourcePanel] only appears when
/// the device class is desktop AND the panel layout has it visible.
class _RightPaneTestHarness extends ConsumerWidget {
  const _RightPaneTestHarness({required this.size});
  final Size size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Force the device class for this test by setting the displaySize
    // notifier directly.
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: _Inner(size: size),
    );
  }
}

class _Inner extends ConsumerStatefulWidget {
  const _Inner({required this.size});
  final Size size;
  @override
  ConsumerState<_Inner> createState() => _InnerState();
}

class _InnerState extends ConsumerState<_Inner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(displaySizeProvider.notifier).set(widget.size);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dc = ref.watch(deviceClassProvider);
    final rtlVisible = ref.watch(panelLayoutProvider).rtlSourceVisible;
    final isDesktop = dc == DeviceClass.desktop;
    if (isDesktop && rtlVisible) {
      return const RtlSourcePanel();
    }
    return const SizedBox(key: Key('not-rtl-pane'));
  }
}

Widget _wrap(Size size, {bool rtlVisible = true}) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Builder(
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          if (rtlVisible) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(panelLayoutProvider.notifier)
                  .setRtlSourceVisible(visible: true);
            });
          }
          return Scaffold(
            body: _RightPaneTestHarness(size: size),
          );
        },
      ),
    ),
  ),
);

void main() {
  group('Device-class gating for RtlSourcePanel', () {
    testWidgets('phone size (400x800) does NOT show the RTL panel', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(const Size(400, 800)));
      await tester.pumpAndSettle();
      expect(find.byType(RtlSourcePanel), findsNothing);
      expect(find.byKey(const Key('not-rtl-pane')), findsOneWidget);
    });

    testWidgets('phone-landscape (800x400) does NOT show the RTL panel', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(const Size(800, 400)));
      await tester.pumpAndSettle();
      expect(find.byType(RtlSourcePanel), findsNothing);
    });

    testWidgets('tablet size (800x900) does NOT show the RTL panel', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(const Size(800, 900)));
      await tester.pumpAndSettle();
      expect(find.byType(RtlSourcePanel), findsNothing);
    });

    testWidgets(
      'desktop size (1400x900) DOES show the RTL panel when visible',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_wrap(const Size(1400, 900)));
        await tester.pumpAndSettle();
        expect(find.byType(RtlSourcePanel), findsOneWidget);
      },
    );

    testWidgets('desktop with rtlVisible=false does NOT show the panel', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(const Size(1400, 900), rtlVisible: false));
      await tester.pumpAndSettle();
      expect(find.byType(RtlSourcePanel), findsNothing);
    });
  });

  group('rtlStemsLoadedProvider', () {
    test('returns false when no stems are loaded', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(rtlStemsLoadedProvider), isFalse);
    });
  });
}
