// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Captured-fixture sweep for [ApbDecoder].
//
// Every `<name>.fst` (or `.vcd` / `.vcd.zst`) in
// `test/fixtures/protocol/apb/captured/` is discovered and decoded against
// the WellenProvider FFI backend, with per-fixture configuration read from
// a sibling `<name>.fixture.json`. Decoded transactions are snapshot-matched
// against `<name>.expected_transactions.json`.
//
// Adding a captured fixture is purely additive — drop in the three sibling
// files and regenerate the snapshot:
//
//   REGENERATE=1 flutter test test/services/decoders/apb_captured_fixtures_test.dart
//
// The shared sweep harness lives in `_captured_sweep.dart`.

import 'package:wavecrux/services/decoders/apb_decoder.dart';

import '_captured_sweep.dart';

void main() {
  registerCapturedSweep(
    decoderId: 'apb',
    groupName: 'ApbDecoder',
    fixturesDir: 'test/fixtures/protocol/apb/captured',
    build: ApbDecoder.new,
  );
}
