// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';
import 'package:wavecrux/services/logging/log_verbosity_level.dart';

void main() {
  test('each LogVerbosity maps to its documented Level threshold', () {
    expect(LogVerbosity.quiet.threshold, Level.WARNING);
    expect(LogVerbosity.normal.threshold, Level.INFO);
    expect(LogVerbosity.detailed.threshold, Level.FINE);
    expect(LogVerbosity.verbose.threshold, Level.ALL);
  });

  test('lower verbosity is a stricter (higher) threshold', () {
    expect(
      LogVerbosity.quiet.threshold > LogVerbosity.normal.threshold,
      isTrue,
    );
    expect(
      LogVerbosity.normal.threshold > LogVerbosity.detailed.threshold,
      isTrue,
    );
    expect(
      LogVerbosity.detailed.threshold > LogVerbosity.verbose.threshold,
      isTrue,
    );
  });
}
