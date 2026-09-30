// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Captured-fixture sweep for [UartDecoder].
//
// Every `<name>.fst` (or `.vcd` / `.vcd.zst`) in
// `test/fixtures/protocol/uart/captured/` is discovered and decoded against
// the WellenProvider FFI backend, with per-fixture configuration read from a
// sibling `<name>.fixture.json`. Decoded transactions are snapshot-matched
// against `<name>.expected_transactions.json`.
//
// Adding a captured fixture is purely additive — drop in the three sibling
// files and regenerate the snapshot:
//
//   REGENERATE=1 flutter test test/services/decoders/uart_captured_fixtures_test.dart
//
// Then hand-verify a few anchor transactions, document them in
// `captured/PROVENANCE.md`, and commit. The static guardrails in
// `test/static/captured_fixture_*` enforce the companion-file and
// PROVENANCE invariants. The shared sweep harness lives in
// `_captured_sweep.dart`.

import 'package:wavecrux/services/decoders/uart_decoder.dart';

import '_captured_sweep.dart';

void main() {
  registerCapturedSweep(
    decoderId: 'uart',
    groupName: 'UartDecoder',
    fixturesDir: 'test/fixtures/protocol/uart/captured',
    build: UartDecoder.new,
  );
}
