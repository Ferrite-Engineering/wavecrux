// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Captured-fixture sweep for [I2cDecoder].
//
// Every `<name>.fst` (or `.vcd` / `.vcd.zst`) in
// `test/fixtures/protocol/i2c/captured/` is discovered and decoded
// against the WellenProvider FFI backend, with per-fixture configuration
// read from a sibling `<name>.fixture.json`. Decoded transactions are
// snapshot-matched against `<name>.expected_transactions.json`.
//
// Adding a captured fixture is purely additive — drop in the three sibling
// files and regenerate the snapshot:
//
//   REGENERATE=1 flutter test test/services/decoders/i2c_captured_fixtures_test.dart
//
// The shared sweep harness lives in `_captured_sweep.dart`.

import 'package:wavecrux/services/decoders/i2c_decoder.dart';

import '_captured_sweep.dart';

void main() {
  registerCapturedSweep(
    decoderId: 'i2c',
    groupName: 'I2cDecoder',
    fixturesDir: 'test/fixtures/protocol/i2c/captured',
    build: I2cDecoder.new,
  );
}
