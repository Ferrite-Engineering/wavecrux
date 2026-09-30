// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';

/// One additional protocol-decoder registration contributed by an overlay
/// build (typically the closed-source Pro overlay registering
/// AXI4-full, USB, PCIe TLP, and similar Pro/Enterprise decoders).
typedef ExtraDecoderRegistration = ({
  DecoderDefinition definition,
  DecoderFactory factory,
});

/// Open-core extension point through which the Pro/Enterprise overlay
/// contributes additional protocol decoders without forking
/// [DecoderRegistry] or `bootstrap`.
///
/// The open-core default returns an empty list — `bootstrap` registers the
/// open-core decoders directly into [DecoderRegistry.instance] and the
/// overlay's `proOverrides` replaces this provider with one that returns
/// the Pro-tier decoder registrations. `WaveCruxApp.initState` reads the
/// active provider once at app startup and registers each contributed
/// decoder into [DecoderRegistry.instance].
///
/// Decoder definitions returned here should set their
/// [DecoderDefinition.requiredTier] so the picker UI can render a
/// `FeatureTierBadge` and route activation through `FeatureGate.isAvailable`.
final extraDecodersProvider = Provider<List<ExtraDecoderRegistration>>(
  (_) => const [],
);
