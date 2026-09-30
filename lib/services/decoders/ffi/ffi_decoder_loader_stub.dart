// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Web / non-`dart:io` no-op implementation of [DecoderPluginLoader].
//
// Constructor parameters mirror the desktop implementation so callers
// can instantiate the same way on every platform; on Web they are
// accepted and ignored because runtime native code loading is
// unavailable.
//
// ignore_for_file: avoid_unused_constructor_parameters

import 'package:wavecrux/domain/interfaces/decoder_plugin_loader.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_info.dart';

/// Web / non-`dart:io` no-op implementation of [DecoderPluginLoader].
///
/// Flutter Web cannot load native shared libraries at runtime, so the
/// user-contributed decoder plugin feature is unavailable there. The
/// stub exists so that the rest of the app can reference
/// [DecoderPluginLoader] uniformly across all build targets.
class FfiDecoderLoader implements DecoderPluginLoader {
  /// Constructs a stub loader. The arguments accepted by the desktop
  /// constructor are accepted here so that callers can instantiate the
  /// same way regardless of platform; on Web all of them are ignored.
  FfiDecoderLoader({
    Object? resolver,
    Object? registry,
    List<String>? userConfiguredDirectories,
    String? envVarRaw,
    bool pluginLoadingDisabled = false,
    Map<String, bool> perPluginDisabled = const <String, bool>{},
    Object? allowlist,
    Object? onPluginLoad,
  });

  @override
  Future<List<DecoderPluginInfo>> scan() async => const <DecoderPluginInfo>[];

  @override
  void dispose() {}
}
