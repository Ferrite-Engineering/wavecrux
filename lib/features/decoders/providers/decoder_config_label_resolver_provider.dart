// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Resolves an ARB key declared on a [DecoderParameter] (via `labelKey`,
/// `descriptionKey`, or `enumLabelKeys`) to a localized display string.
///
/// Returns the raw key unchanged when it is not a recognised decoder config
/// label — this keeps user-contributed plugin decoders (whose authored keys
/// are not in the open-core catalog) rendering their raw strings rather than
/// throwing.
typedef DecoderConfigLabelResolver = String Function(String key);

/// Builds a [DecoderConfigLabelResolver] for a given [BuildContext].
///
/// The factory takes a `BuildContext` because the resolver needs access to
/// localization classes, which are looked up via inherited widgets
/// (`L10N.of(context)`).
typedef DecoderConfigLabelResolverFactory =
    DecoderConfigLabelResolver Function(
      BuildContext context,
    );

/// Open-core extension point that supplies the ARB-key resolver used by
/// `DecoderConfigDialog` when rendering a protocol decoder's parameter
/// labels, descriptions, and enum value labels.
///
/// The open-core default resolves the built-in decoders' config keys (see
/// [_openCoreKeyToGetter]) and returns the raw key as a fallback. This mirrors
/// the Stage widget `stageConfigLabelResolverFactoryProvider` pattern: a
/// Pro overlay can override this provider with a factory that also
/// consults the Pro localization catalog for Pro decoder keys, falling back to
/// the open-core resolver (and then to the raw key) when a key is unknown.
///
/// Without this provider, the dialog would render raw ARB keys (e.g.
/// "spiParamCpol") in the parameters section.
final decoderConfigLabelResolverFactoryProvider =
    Provider<DecoderConfigLabelResolverFactory>(
      (_) => _openCoreFactory,
    );

DecoderConfigLabelResolver _openCoreFactory(BuildContext context) {
  return (key) {
    // Lazy L10N lookup: only resolve `L10N.of(context)` when the key actually
    // matches one of the open-core ARB-backed labels. Unknown keys fall
    // through to identity without touching the context — this keeps the
    // default factory usable from unit tests that don't run a full widget
    // tree (e.g. the resolver-provider tests).
    final mapped = _openCoreKeyToGetter(key);
    if (mapped == null) return key;
    return mapped(L10N.of(context));
  };
}

/// Returns the [L10N] getter for [key], or `null` when [key] is not a known
/// open-core decoder config label.
String Function(L10N l)? _openCoreKeyToGetter(String key) {
  switch (key) {
    // ── SPI ──────────────────────────────────────────────────────────────
    case 'spiParamCpol':
      return (l) => l.spiParamCpol;
    case 'spiParamCpolDescription':
      return (l) => l.spiParamCpolDescription;
    case 'spiChoiceCpol0':
      return (l) => l.spiChoiceCpol0;
    case 'spiChoiceCpol1':
      return (l) => l.spiChoiceCpol1;
    case 'spiParamCpha':
      return (l) => l.spiParamCpha;
    case 'spiParamCphaDescription':
      return (l) => l.spiParamCphaDescription;
    case 'spiChoiceCpha0':
      return (l) => l.spiChoiceCpha0;
    case 'spiChoiceCpha1':
      return (l) => l.spiChoiceCpha1;
    case 'spiParamBitOrder':
      return (l) => l.spiParamBitOrder;
    case 'spiParamBitOrderDescription':
      return (l) => l.spiParamBitOrderDescription;
    case 'spiChoiceBitOrderMsb':
      return (l) => l.spiChoiceBitOrderMsb;
    case 'spiChoiceBitOrderLsb':
      return (l) => l.spiChoiceBitOrderLsb;
    case 'spiParamWordSize':
      return (l) => l.spiParamWordSize;
    case 'spiParamWordSizeDescription':
      return (l) => l.spiParamWordSizeDescription;
    case 'spiParamCsActiveLevel':
      return (l) => l.spiParamCsActiveLevel;
    case 'spiParamCsActiveLevelDescription':
      return (l) => l.spiParamCsActiveLevelDescription;
    case 'spiChoiceCsActiveLevel0':
      return (l) => l.spiChoiceCsActiveLevel0;
    case 'spiChoiceCsActiveLevel1':
      return (l) => l.spiChoiceCsActiveLevel1;
    // ── I²C ──────────────────────────────────────────────────────────────
    case 'i2cParamAddressBits':
      return (l) => l.i2cParamAddressBits;
    case 'i2cParamAddressBitsDescription':
      return (l) => l.i2cParamAddressBitsDescription;
    case 'i2cChoiceAddressBits7':
      return (l) => l.i2cChoiceAddressBits7;
    case 'i2cChoiceAddressBits10':
      return (l) => l.i2cChoiceAddressBits10;
    // ── RISC-V ───────────────────────────────────────────────────────────
    case 'riscvParamXlen':
      return (l) => l.riscvParamXlen;
    case 'riscvParamXlenDescription':
      return (l) => l.riscvParamXlenDescription;
    case 'riscvParamExtM':
      return (l) => l.riscvParamExtM;
    case 'riscvParamExtMDescription':
      return (l) => l.riscvParamExtMDescription;
    case 'riscvParamExtA':
      return (l) => l.riscvParamExtA;
    case 'riscvParamExtADescription':
      return (l) => l.riscvParamExtADescription;
    case 'riscvParamExtF':
      return (l) => l.riscvParamExtF;
    case 'riscvParamExtFDescription':
      return (l) => l.riscvParamExtFDescription;
    case 'riscvParamExtD':
      return (l) => l.riscvParamExtD;
    case 'riscvParamExtDDescription':
      return (l) => l.riscvParamExtDDescription;
    case 'riscvParamExtC':
      return (l) => l.riscvParamExtC;
    case 'riscvParamExtCDescription':
      return (l) => l.riscvParamExtCDescription;
    // ── AHB-Lite ─────────────────────────────────────────────────────────
    case 'ahbLiteParamAddrWidth':
      return (l) => l.ahbLiteParamAddrWidth;
    case 'ahbLiteParamAddrWidthDescription':
      return (l) => l.ahbLiteParamAddrWidthDescription;
    case 'ahbLiteParamDataWidth':
      return (l) => l.ahbLiteParamDataWidth;
    case 'ahbLiteParamDataWidthDescription':
      return (l) => l.ahbLiteParamDataWidthDescription;
    case 'ahbLiteParamCheckAlignment':
      return (l) => l.ahbLiteParamCheckAlignment;
    case 'ahbLiteParamCheckAlignmentDescription':
      return (l) => l.ahbLiteParamCheckAlignmentDescription;
    case 'ahbLiteParamWaitStateThreshold':
      return (l) => l.ahbLiteParamWaitStateThreshold;
    case 'ahbLiteParamWaitStateThresholdDescription':
      return (l) => l.ahbLiteParamWaitStateThresholdDescription;
    // ── Wishbone ─────────────────────────────────────────────────────────
    case 'wishboneParamRevision':
      return (l) => l.wishboneParamRevision;
    case 'wishboneParamRevisionDescription':
      return (l) => l.wishboneParamRevisionDescription;
    case 'wishboneChoiceRevisionB3':
      return (l) => l.wishboneChoiceRevisionB3;
    case 'wishboneChoiceRevisionB4':
      return (l) => l.wishboneChoiceRevisionB4;
    case 'wishboneParamAddrWidth':
      return (l) => l.wishboneParamAddrWidth;
    case 'wishboneParamAddrWidthDescription':
      return (l) => l.wishboneParamAddrWidthDescription;
    case 'wishboneParamDataWidth':
      return (l) => l.wishboneParamDataWidth;
    case 'wishboneParamDataWidthDescription':
      return (l) => l.wishboneParamDataWidthDescription;
    case 'wishboneParamGranularity':
      return (l) => l.wishboneParamGranularity;
    case 'wishboneParamGranularityDescription':
      return (l) => l.wishboneParamGranularityDescription;
    case 'wishboneParamEndianness':
      return (l) => l.wishboneParamEndianness;
    case 'wishboneParamEndiannessDescription':
      return (l) => l.wishboneParamEndiannessDescription;
    case 'wishboneChoiceEndiannessLittle':
      return (l) => l.wishboneChoiceEndiannessLittle;
    case 'wishboneChoiceEndiannessBig':
      return (l) => l.wishboneChoiceEndiannessBig;
    case 'wishboneParamCheckAlignment':
      return (l) => l.wishboneParamCheckAlignment;
    case 'wishboneParamCheckAlignmentDescription':
      return (l) => l.wishboneParamCheckAlignmentDescription;
    // ── SPI Flash (stacked) ──────────────────────────────────────────────
    case 'spiFlashParamVendorPreset':
      return (l) => l.spiFlashParamVendorPreset;
    case 'spiFlashParamVendorPresetDescription':
      return (l) => l.spiFlashParamVendorPresetDescription;
    case 'spiFlashChoiceVendorGeneric':
      return (l) => l.spiFlashChoiceVendorGeneric;
    case 'spiFlashChoiceVendorWinbond':
      return (l) => l.spiFlashChoiceVendorWinbond;
    case 'spiFlashChoiceVendorMacronix':
      return (l) => l.spiFlashChoiceVendorMacronix;
    case 'spiFlashChoiceVendorMicron':
      return (l) => l.spiFlashChoiceVendorMicron;
    case 'spiFlashChoiceVendorSpansion':
      return (l) => l.spiFlashChoiceVendorSpansion;
    case 'spiFlashChoiceVendorIssi':
      return (l) => l.spiFlashChoiceVendorIssi;
    case 'spiFlashParamAddressWidth':
      return (l) => l.spiFlashParamAddressWidth;
    case 'spiFlashParamAddressWidthDescription':
      return (l) => l.spiFlashParamAddressWidthDescription;
    case 'spiFlashChoiceAddr24':
      return (l) => l.spiFlashChoiceAddr24;
    case 'spiFlashChoiceAddr32':
      return (l) => l.spiFlashChoiceAddr32;
    case 'spiFlashParamDummyCycles':
      return (l) => l.spiFlashParamDummyCycles;
    case 'spiFlashParamDummyCyclesDescription':
      return (l) => l.spiFlashParamDummyCyclesDescription;
  }
  return null;
}
