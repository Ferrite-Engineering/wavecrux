// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Completes when this launch's licence tier is known.
///
/// The tier resolves after startup: the stored credential is read from the
/// keychain asynchronously and deliberately not awaited, so until it answers
/// every launch reads as Open Core. A gate is right to follow the live tier
/// wherever it moves. A **one-shot** bootstrap step that reads the tier once
/// and acts on it is not: on a cold start it can run first and act on Open
/// Core. Such a step awaits this barrier instead of growing its own late-apply
/// hook.
///
/// Open core's tier is a constant, so it is known from the start and this
/// completes at once. The Pro overlay overrides it with its licence service's
/// startup future.
///
/// Not for a reporter that should follow later changes, and not for a gate:
/// after this completes the tier can still move (an activation, an expiry),
/// and anything that must track that watches `licenseTierProvider`.
final FutureProvider<void> licenseResolvedProvider = FutureProvider<void>(
  (ref) async {},
  name: 'licenseResolvedProvider',
);

/// The longest a bootstrap step waits on [licenseResolvedProvider] before it
/// goes ahead on whatever tier is current. Resolving a stored credential is
/// an offline keychain read; a licence service that has not answered by now
/// is stuck, and a step held on it forever would be a worse failure than one
/// that acts on Open Core.
const Duration kLicenseResolvedWait = Duration(seconds: 5);

/// Waits for [licenseResolvedProvider] in [container], at most [timeout].
///
/// Never throws: a licence service that failed or timed out leaves the tier
/// where it is, which is what the caller then reads.
Future<void> awaitLicenseResolved(
  ProviderContainer container, {
  Duration timeout = kLicenseResolvedWait,
}) async {
  try {
    await container.read(licenseResolvedProvider.future).timeout(timeout);
  } on Object {
    // Timed out or failed: go ahead on the current tier.
  }
}
