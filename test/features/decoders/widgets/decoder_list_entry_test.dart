// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/features/decoders/constants/transaction_lane_constants.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_list_entry.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Notifier override that pre-seeds `displaySizeProvider` so
/// `deviceClassProvider` resolves to a touch class without waiting for
/// `DisplaySizeFeed` to push a size on the first frame.
class _FixedDisplaySizeNotifier extends DisplaySizeNotifier {
  _FixedDisplaySizeNotifier(this._size);
  final Size _size;
  @override
  Size? build() => _size;
}

const _config = DecoderConfig(signalBindings: {});

DecoderDefinition _def(String id, String name) => DecoderDefinition(
  id: id,
  displayName: name,
  description: '',
  requiredSignals: const [],
);

ActiveDecoder _decoder(
  String id,
  String decoderId, {
  int instanceNumber = 1,
}) => ActiveDecoder(
  id: id,
  decoderId: decoderId,
  config: _config,
  instanceNumber: instanceNumber,
);

class _FixedDecodersNotifier extends ActiveDecodersNotifier {
  _FixedDecodersNotifier(this._initial);
  final List<ActiveDecoder> _initial;
  @override
  List<ActiveDecoder> build() => _initial;
}

/// Sets up a [DecoderListEntry] inside an [UncontrolledProviderScope] so the
/// test can inspect provider state after the widget dispatches mutations
/// (the production widget reads decoders from
/// [activeDecodersProvider]; tests need access to the same
/// container to assert the post-tap state).
({Widget widget, ProviderContainer container}) _build({
  required ActiveDecoder decoder,
  int index = 0,
  Locale? locale,
  ThemeData? theme,
  Size? size,
  Size? displaySize,
}) {
  final container = ProviderContainer(
    overrides: [
      activeDecodersProvider.overrideWith(
        () => _FixedDecodersNotifier([decoder]),
      ),
      if (displaySize != null)
        displaySizeProvider.overrideWith(
          () => _FixedDisplaySizeNotifier(displaySize),
        ),
    ],
  );
  // Default to a desktop host platform so MobileMetrics resolves to the
  // desktop table when the test does not opt into a mobile host. Without
  // this override, Flutter's test default (android) makes
  // `isMobileHost == true` and the desktop branch never executes.
  final widget = UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      theme: theme ?? ThemeData(platform: TargetPlatform.macOS),
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: size?.width ?? 400,
          child: DecoderListEntry(decoder: decoder, index: index),
        ),
      ),
    ),
  );
  return (widget: widget, container: container);
}

void main() {
  setUp(() {
    DecoderRegistry.instance.clear();
    DecoderRegistry.instance.register(
      _def('spi', 'SPI'),
      // Factory unused in these tests — passing a no-op throws if invoked.
      (cfg) => throw UnimplementedError('test factory'),
    );
  });
  tearDown(DecoderRegistry.instance.clear);

  // ── locale sweep ──────────────────────────────────────────────────────
  group('DecoderListEntry — locale sweep', () {
    for (final tag in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('renders without exception in $tag', (tester) async {
        final parts = tag.split('_');
        final locale = parts.length == 2
            ? Locale(parts[0], parts[1])
            : Locale(parts[0]);
        final setup = _build(
          decoder: _decoder('d0', 'spi'),
          locale: locale,
        );
        addTearDown(setup.container.dispose);
        await tester.pumpWidget(setup.widget);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── content ──────────────────────────────────────────────────────────
  testWidgets('renders the decoder instance label', (tester) async {
    final setup = _build(decoder: _decoder('d0', 'spi', instanceNumber: 2));
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();
    // `decoderInstanceLabel` formats as "{baseName} #{number}".
    expect(find.text('SPI #2'), findsOneWidget);
  });

  testWidgets('renders fallback name when decoder is not registered', (
    tester,
  ) async {
    DecoderRegistry.instance.clear(); // de-register everything
    final setup = _build(decoder: _decoder('d0', 'unknown_id'));
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();
    // Falls back to the registry key when no definition exists.
    expect(find.text('unknown_id #1'), findsOneWidget);
  });

  testWidgets('row height matches transactionLaneHeight', (tester) async {
    final setup = _build(decoder: _decoder('d0', 'spi'));
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(DecoderListEntry),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (container.constraints?.maxHeight ?? 0) == transactionLaneHeight,
      isTrue,
    );
  });

  // ── Touch device class affordance gating ──────────────────────────────
  //
  // The decoder row is fixed at `transactionLaneHeight` (28 dp) so it
  // stays aligned with the canvas transaction lane. The 44 dp touch
  // target floor (ARCHITECTURE.md §3.1.8.3) cannot fit inside a 28 dp
  // row, so on touch the always-visible remove button is hidden — the
  // long-press context menu's Remove item replaces it. Both branches
  // are tested so a regression in either gating direction is caught.
  testWidgets('remove button is hidden on touch device class', (tester) async {
    final setup = _build(
      decoder: _decoder('d0', 'spi'),
      // 800 × 1100 → tablet device class (touch).
      displaySize: const Size(800, 1100),
    );
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();
    final closeIcon = find.descendant(
      of: find.byType(DecoderListEntry),
      matching: find.byIcon(Icons.close),
    );
    expect(
      closeIcon,
      findsNothing,
      reason:
          'in-row remove button must not render on touch — long-press '
          'menu provides removal there',
    );
  });

  testWidgets('remove button is visible on desktop device class', (
    tester,
  ) async {
    final setup = _build(
      decoder: _decoder('d0', 'spi'),
      // 1400 × 900 → desktop device class.
      displaySize: const Size(1400, 900),
    );
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();
    final closeIcon = find.descendant(
      of: find.byType(DecoderListEntry),
      matching: find.byIcon(Icons.close),
    );
    expect(closeIcon, findsOneWidget);
  });

  // ── tap remove ────────────────────────────────────────────────────────
  testWidgets('tapping the remove button removes the decoder', (tester) async {
    final setup = _build(decoder: _decoder('d0', 'spi'));
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();
    expect(setup.container.read(activeDecodersProvider).length, 1);

    await tester.tap(
      find.descendant(
        of: find.byType(DecoderListEntry),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();

    expect(setup.container.read(activeDecodersProvider), isEmpty);
  });

  // ── filter clears when removing the active filtered decoder ───────────
  testWidgets('removing a decoder clears the table filter when active', (
    tester,
  ) async {
    final setup = _build(decoder: _decoder('d0', 'spi'));
    addTearDown(setup.container.dispose);
    // Pre-set filter to the decoder we are about to remove.
    setup.container
        .read(transactionTableFilterProvider.notifier)
        .setDecoderFilter('d0');
    expect(
      setup.container.read(transactionTableFilterProvider).decoderIdFilter,
      'd0',
    );

    await tester.pumpWidget(setup.widget);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(DecoderListEntry),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();

    expect(
      setup.container.read(transactionTableFilterProvider).decoderIdFilter,
      isNull,
      reason: 'filter must be cleared when its target decoder is removed',
    );
  });

  testWidgets('removing a different decoder leaves the filter untouched', (
    tester,
  ) async {
    final setup = _build(decoder: _decoder('d0', 'spi'));
    addTearDown(setup.container.dispose);
    setup.container
        .read(transactionTableFilterProvider.notifier)
        .setDecoderFilter('d_other');
    await tester.pumpWidget(setup.widget);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(DecoderListEntry),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();

    expect(
      setup.container.read(transactionTableFilterProvider).decoderIdFilter,
      'd_other',
    );
  });

  // ── context menu ─────────────────────────────────────────────────────
  testWidgets('right-click opens context menu with Configure + Remove', (
    tester,
  ) async {
    final setup = _build(decoder: _decoder('d0', 'spi'));
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();

    final l10n = L10N.of(tester.element(find.byType(DecoderListEntry)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DecoderListEntry)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text(l10n.decoderLaneConfigure), findsOneWidget);
    expect(find.text(l10n.decoderLaneRemove), findsOneWidget);
    // Path-header item per ARCHITECTURE.md §3.1.8.14 — full instance label
    // appears as the first non-interactive entry.
    expect(find.text('SPI #1'), findsWidgets);
  });

  testWidgets('selecting Remove from context menu removes the decoder', (
    tester,
  ) async {
    final setup = _build(decoder: _decoder('d0', 'spi'));
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();

    final l10n = L10N.of(tester.element(find.byType(DecoderListEntry)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DecoderListEntry)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.decoderLaneRemove));
    await tester.pumpAndSettle();

    expect(setup.container.read(activeDecodersProvider), isEmpty);
  });

  // ── touch: long-press path replaces the missing in-row button ────────
  testWidgets('long-press on touch opens context menu with Remove', (
    tester,
  ) async {
    final setup = _build(
      decoder: _decoder('d0', 'spi'),
      // Tablet device class on a mobile host triggers PlatformContextMenu's
      // long-press branch (see PlatformContextMenu's
      // shouldEnableLongPressContextMenu rules).
      displaySize: const Size(800, 1100),
      theme: ThemeData(platform: TargetPlatform.iOS),
    );
    addTearDown(setup.container.dispose);
    await tester.pumpWidget(setup.widget);
    await tester.pump();

    final l10n = L10N.of(tester.element(find.byType(DecoderListEntry)));
    await tester.longPress(find.byType(DecoderListEntry));
    await tester.pumpAndSettle();

    expect(find.text(l10n.decoderLaneConfigure), findsOneWidget);
    expect(find.text(l10n.decoderLaneRemove), findsOneWidget);

    await tester.tap(find.text(l10n.decoderLaneRemove));
    await tester.pumpAndSettle();
    expect(setup.container.read(activeDecodersProvider), isEmpty);
  });

  // ── color matches palette index ──────────────────────────────────────
  testWidgets('lane color is consistent across indices', (tester) async {
    // Two indices → two distinct palette entries unless they wrap.
    final color0 = transactionLaneColorForIndex(0);
    final color1 = transactionLaneColorForIndex(1);
    expect(color0, isNot(color1));
    expect(color0, transactionLanePalette[0]);
    expect(color1, transactionLanePalette[1]);
  });
}
