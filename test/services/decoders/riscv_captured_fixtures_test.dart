// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Captured-fixture sweep for [RiscvDecoder].
//
// Every `<name>.fst` (or `.vcd` / `.vcd.zst`) in
// `test/fixtures/protocol/riscv/captured/` is discovered and decoded
// against the WellenProvider FFI backend, with per-fixture configuration
// read from a sibling `<name>.fixture.json`. Decoded transactions are
// snapshot-matched against `<name>.expected_transactions.json`.
//
// Adding a captured fixture is purely additive — drop in the three sibling
// files and regenerate the snapshot:
//
//   REGENERATE=1 flutter test test/services/decoders/riscv_captured_fixtures_test.dart
//
// Unlike the other open-core sweep tests, `RiscvDecoder` takes a second
// constructor argument — the bundled ISA TOML asset table. The factory
// passed to the sweep harness closes over a single shared
// `IsaDecoderAssets` loaded once from `assets/decoders/isa/riscv/*.toml`.
//
// The shared sweep harness lives in `_captured_sweep.dart`.

import 'dart:io';

import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/decoders/isa/riscv_decoder.dart';

import '_captured_sweep.dart';

void main() {
  final assets = _loadRiscvAssets();
  registerCapturedSweep(
    decoderId: 'riscv',
    groupName: 'RiscvDecoder',
    fixturesDir: 'test/fixtures/protocol/riscv/captured',
    build: (config) => RiscvDecoder(config, assets),
  );
}

InstructionSet _loadAsset(String name) => parseInstructionSetToml(
  File('assets/decoders/isa/riscv/$name.toml').readAsStringSync(),
  sourceLabel: '$name.toml',
);

IsaDecoderAssets _loadRiscvAssets() => IsaDecoderAssets.fromMap({
  'RV32I': _loadAsset('RV32I'),
  'RV32M': _loadAsset('RV32M'),
  'RV32A': _loadAsset('RV32A'),
  'RV32F': _loadAsset('RV32F'),
  'RV32C-lower': _loadAsset('RV32C-lower'),
  'RV64I': _loadAsset('RV64I'),
  'RV64M': _loadAsset('RV64M'),
  'RV64A': _loadAsset('RV64A'),
  'RV64D': _loadAsset('RV64D'),
  'RV64C-lower': _loadAsset('RV64C-lower'),
});
