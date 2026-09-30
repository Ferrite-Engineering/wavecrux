// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point: additional Settings categories contributed by an
/// overlay, appended after the built-in open-core categories.
///
/// Open-core returns an empty list, so the Settings screen is unchanged. The
/// closed-source Pro overlay overrides this binding to append the
/// Enterprise **Collaboration** category (display name, default mode, relay
/// URL) without forking the open-core settings screen.
///
/// The entry type is the suite-shared [CruxSettingsExtraCategory]
/// (crux_settings_ui) — stable id, required icon, context-taking
/// label/body builders so the overlay localizes via its own `L10NPro` —
/// replacing the app-local `SettingsCategoryBuilder` typedef (one seam shape
/// shared by every Crux app instead of three per-app ones).
final extraSettingsCategoriesProvider =
    Provider<List<CruxSettingsExtraCategory>>((_) => const []);
