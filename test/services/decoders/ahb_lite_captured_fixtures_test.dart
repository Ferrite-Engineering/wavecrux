// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Captured-fixture sweep for [AhbLiteDecoder].
//
// Every `<name>.fst` (or `.vcd` / `.vcd.zst`) in
// `test/fixtures/protocol/ahb_lite/captured/` is discovered and decoded
// against the WellenProvider FFI backend, with per-fixture configuration
// read from a sibling `<name>.fixture.json`. Decoded transactions are
// snapshot-matched against `<name>.expected_transactions.json`.
//
// Adding a captured fixture is purely additive — drop in the three sibling
// files and regenerate the snapshot:
//
//   REGENERATE=1 flutter test test/services/decoders/ahb_lite_captured_fixtures_test.dart
//
// The shared sweep harness lives in `_captured_sweep.dart`.

import 'package:wavecrux/services/decoders/ahb_lite_decoder.dart';

import '_captured_sweep.dart';

void main() {
  registerCapturedSweep(
    decoderId: 'ahb_lite',
    groupName: 'AhbLiteDecoder',
    fixturesDir: 'test/fixtures/protocol/ahb_lite/captured',
    build: AhbLiteDecoder.new,
  );
}
