// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';

void main() {
  late ProviderContainer container;
  SignalLoadProgress notifier() =>
      container.read(signalLoadProgressProvider.notifier);
  SignalLoadProgressState state() => container.read(signalLoadProgressProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('starts idle and hidden', () {
    expect(state().active, isFalse);
    expect(state().fraction, isNull);
  });

  test('begin activates with a total and zero loaded', () {
    notifier().begin(50);
    expect(state().active, isTrue);
    expect(state().total, 50);
    expect(state().loaded, 0);
    expect(state().fraction, 0.0);
  });

  test('begin(0) stays inactive (nothing to load)', () {
    notifier().begin(0);
    expect(state().active, isFalse);
  });

  test('advance accumulates and clamps at total', () {
    notifier().begin(3);
    notifier().advance();
    expect(state().loaded, 1);
    expect(state().fraction, closeTo(1 / 3, 1e-9));
    notifier()
      ..advance()
      ..advance()
      ..advance(); // one past total
    expect(state().loaded, 3);
    expect(state().fraction, 1.0);
  });

  test('advance is a no-op when idle', () {
    notifier().advance();
    expect(state().active, isFalse);
    expect(state().loaded, 0);
  });

  test('requestCancel sets the flag only while active', () {
    notifier().requestCancel();
    expect(state().cancelRequested, isFalse);
    notifier()
      ..begin(10)
      ..requestCancel();
    expect(state().cancelRequested, isTrue);
  });

  test('begin resets a prior cancel request', () {
    notifier()
      ..begin(5)
      ..requestCancel();
    expect(state().cancelRequested, isTrue);
    notifier().begin(8);
    expect(state().cancelRequested, isFalse);
    expect(state().total, 8);
  });

  test('finish returns to idle', () {
    notifier()
      ..begin(5)
      ..advance()
      ..finish();
    expect(state().active, isFalse);
    expect(state().loaded, 0);
    expect(state().total, 0);
  });

  test('begin defaults to the loading phase', () {
    notifier().begin(5);
    expect(state().phase, SignalLoadPhase.loading);
  });

  test('begin can start in the adding phase; finish resets to loading', () {
    notifier().begin(5, phase: SignalLoadPhase.adding);
    expect(state().phase, SignalLoadPhase.adding);
    notifier().finish();
    expect(state().phase, SignalLoadPhase.loading);
  });

  test('setLoaded sets the absolute count, clamped to total', () {
    notifier()
      ..begin(10, phase: SignalLoadPhase.adding)
      ..setLoaded(7);
    expect(state().loaded, 7);
    notifier().setLoaded(25);
    expect(state().loaded, 10);
    notifier().setLoaded(-3);
    expect(state().loaded, 0);
  });

  test('setLoaded is a no-op while idle', () {
    notifier().setLoaded(5);
    expect(state().active, isFalse);
    expect(state().loaded, 0);
  });

  test('finishPhase idles the batch only when phases match', () {
    notifier().begin(5, phase: SignalLoadPhase.adding);
    notifier().finishPhase(SignalLoadPhase.loading);
    expect(
      state().active,
      isTrue,
      reason: 'a loading-phase finish must not clear the adding batch',
    );
    notifier().finishPhase(SignalLoadPhase.adding);
    expect(state().active, isFalse);
  });

  test(
    'adding-phase hold cannot clobber a loading batch that superseded it',
    () {
      // The bulk-add flow holds the adding batch; meanwhile the canvas's
      // refresh begins the loading batch. The hold's finish must be a no-op.
      notifier().begin(1000, phase: SignalLoadPhase.adding);
      notifier().begin(40);
      notifier().finishPhase(SignalLoadPhase.adding);
      expect(state().active, isTrue);
      expect(state().total, 40);
      expect(state().phase, SignalLoadPhase.loading);
    },
  );

  test('finishPhase is a no-op while idle', () {
    notifier().finishPhase(SignalLoadPhase.loading);
    expect(state().active, isFalse);
  });

  test('beginIndeterminate activates with no total yet', () {
    notifier().beginIndeterminate(phase: SignalLoadPhase.adding);
    expect(state().active, isTrue);
    expect(state().total, 0);
    expect(state().fraction, isNull);
    expect(state().phase, SignalLoadPhase.adding);
  });

  test('beginIndeterminate resets a prior cancel; begin then sizes it', () {
    notifier()
      ..begin(10)
      ..requestCancel()
      ..beginIndeterminate(phase: SignalLoadPhase.adding);
    expect(state().cancelRequested, isFalse);

    // A cancel during the walk is visible to the walk.
    notifier().requestCancel();
    expect(state().cancelRequested, isTrue);

    notifier().begin(300, phase: SignalLoadPhase.adding);
    expect(state().total, 300);
    expect(state().fraction, 0.0);
  });
}
