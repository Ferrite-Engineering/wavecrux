// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point through which the Pro/Enterprise overlay
/// contributes additional [LocalizationsDelegate]s without forking
/// `WaveCruxApp` or `bootstrap`.
///
/// The open-core default returns an empty list — `WaveCruxApp.build`
/// concatenates this list with `L10N.localizationsDelegates` and passes the
/// combined sequence to `MaterialApp.router`. The overlay's `proOverrides`
/// replaces this provider with one that returns Pro-specific delegates
/// (e.g. `L10NPro.delegate`) so widgets in the Pro repo can resolve their
/// own `Localizations.of<T>` lookup.
final extraLocalizationsDelegatesProvider =
    Provider<List<LocalizationsDelegate<Object?>>>((_) => const []);
