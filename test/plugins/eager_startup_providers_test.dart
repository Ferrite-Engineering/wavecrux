// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/plugins/eager_startup_providers.dart';

void main() {
  group('eagerStartupProvidersProvider', () {
    test('open-core default is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final hooks = container.read(eagerStartupProvidersProvider);
      expect(hooks, isEmpty);
    });

    test('Pro overlay-style override surfaces the registered providers', () {
      final sideEffecting = Provider<int>((_) => 7);
      final container = ProviderContainer(
        overrides: [
          eagerStartupProvidersProvider.overrideWithValue(
            <EagerStartupHook>[sideEffecting],
          ),
        ],
      );
      addTearDown(container.dispose);

      final hooks = container.read(eagerStartupProvidersProvider);
      expect(hooks, hasLength(1));
      expect(hooks.single, same(sideEffecting));
      // The host holds a container subscription on each entry; the
      // registration contract is what is under test here. Production
      // wiring is covered by `app.dart`'s startup gate and by the Pro
      // overlay's live-app trend journey.
    });

    test(
      'a read-realized listener provider observes nothing; a subscribed one '
      'observes every event',
      () async {
        // The exact trap this seam's contract exists to prevent. Riverpod
        // pauses a provider that has no listener of its own — and the
        // pause propagates into the `ref.listen` subscriptions the
        // provider installed in its constructor. Realizing such a
        // provider with a one-shot `read` therefore constructs it and
        // then immediately stops it observing: the stream events never
        // arrive and the side effect silently never runs.
        //
        // This is the shape of `licenseTierChangeAuditListenerProvider`
        // — a `Provider<void>` wrapping a `ref.listen` — so the host MUST
        // hold a subscription. It listens to `licenseTierProvider` rather
        // than a stream; the trap is the same either way, and a stream is
        // the easier one to make observable in a test.
        final events = StreamController<int>.broadcast();
        addTearDown(events.close);
        final source = StreamProvider<int>((_) => events.stream);
        final observed = <int>[];
        final listener = Provider<void>((ref) {
          ref.listen(source, (_, next) => next.whenData(observed.add));
        });

        final readRealized = ProviderContainer()..read(listener);
        await Future<void>.delayed(Duration.zero);
        events.add(1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          observed,
          isEmpty,
          reason:
              'a read-realized listener provider is paused and drops events '
              '— this is why the startup seam holds subscriptions',
        );
        readRealized.dispose();

        observed.clear();
        final subscribed = ProviderContainer();
        final sub = subscribed.listen<Object?>(listener, (_, _) {});
        await Future<void>.delayed(Duration.zero);
        events.add(2);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(observed, <int>[2]);
        sub.close();
        subscribed.dispose();
      },
    );
  });
}
