// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// A provider the host app must keep alive for the whole app session.
///
/// The host holds a real `ProviderContainer.listen` subscription on each
/// entry rather than a one-shot `read`. That distinction is load-bearing:
/// Riverpod disposes/pauses a provider that has no listener, so a
/// side-effecting provider realized by `read` alone can be torn down
/// again — taking its `ref.listen` subscriptions with it — the moment the
/// read returns. A held subscription pins the provider (and everything it
/// watches) for as long as the app is running.
typedef EagerStartupHook = ProviderListenable<Object?>;

/// Open-core extension point that names providers the host app must
/// realize and keep alive at startup.
///
/// The host subscribes to each entry against the ROOT
/// `ProviderContainer` — not through a widget `ref.watch` — so liveness
/// is independent of which widgets happen to be mounted, of route
/// changes, and of whether any production widget incidentally watches
/// the same provider.
///
/// Useful for fire-and-forget Pro/Enterprise overlays that install
/// side-effecting `ref.listen` subscriptions in their constructor — e.g.
/// the Pro overlay's licence-tier audit listener, which has to notice a
/// tier change whether or not any licence UI happens to be on screen.
/// Without an eager-realization hook those providers stay un-constructed
/// (Riverpod is lazy by default) and their side effects never start.
///
/// Ported from `lintcrux`, which built this seam first and where the
/// identical file lives at the identical path. It is the same mechanism
/// deliberately: an app-wide "realize this and keep it alive" hook is not
/// a place for two designs.
///
/// Only providers whose subject is app-wide belong here. A provider that
/// must observe PER-TAB state goes in `perTabStartupProvidersProvider`
/// instead; realized at root it resolves the empty root-scope instances
/// and its side effect silently never fires.
///
/// Open-core default is an empty list — nothing gets eagerly realized.
/// The Pro overlay's `proOverrides` replaces this provider
/// with the list of providers it wants pinned at boot.
final eagerStartupProvidersProvider = Provider<List<EagerStartupHook>>(
  (_) => const <EagerStartupHook>[],
);
