// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';

/// Adapts a parsed [StageWidgetManifest] to the open-core [StageWidget]
/// interface so the Stage picker dialog can list custom widgets alongside
/// built-ins.
///
/// The picker reads [id], [displayName], [description], [category] and
/// [requiredSignals]/[optionalSignals]; it does not draw the widget itself.
/// Rendering is performed by `CustomStageWidgetRenderer` once the user
/// drops the widget onto a Stage panel — that path looks the descriptor
/// back up by [id] in the live registry to retrieve the runtime factories.
class ManifestStageWidget extends StageWidget {
  /// Wraps [manifest] together with the [localeCode] used for display-name
  /// resolution.
  const ManifestStageWidget({
    required this.manifest,
    required this.localeCode,
  });

  /// Parsed bundle manifest backing this widget.
  final StageWidgetManifest manifest;

  /// Locale used to resolve [displayName]. The Pro overlay reads the
  /// active locale from `appSettingsProvider` and rebuilds custom
  /// widgets when it changes; tests pass a fixed locale.
  final String localeCode;

  @override
  String get id => manifest.id;

  @override
  String get displayName => manifest.displayName.resolve(localeCode);

  @override
  String get description => manifest.displayName.resolve(localeCode);

  @override
  StageWidgetCategory get category => manifest.category;

  @override
  List<SignalBinding> get requiredSignals => [
    for (final binding in manifest.signalBindings)
      if (binding.required) _toCoreBinding(binding),
  ];

  @override
  List<SignalBinding> get optionalSignals => [
    for (final binding in manifest.signalBindings)
      if (!binding.required) _toCoreBinding(binding),
  ];

  static SignalBinding _toCoreBinding(ManifestSignalBinding binding) {
    final width = binding.bitWidth?.min ?? binding.bitWidth?.max;
    return SignalBinding(
      name: binding.name,
      description: binding.description,
      bitWidth: width,
    );
  }
}
