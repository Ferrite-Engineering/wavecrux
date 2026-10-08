// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/collaboration_available_provider.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/services/collaboration/noop_collaboration_service.dart';

void main() {
  test('the open-source default (no-op service) offers no collaboration', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(collaborationAvailableProvider), isFalse);
  });

  test('an explicitly bound no-op service is still unavailable', () {
    final container = ProviderContainer(
      overrides: [
        collaborationServiceProvider.overrideWithValue(
          const NoopCollaborationService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(collaborationAvailableProvider), isFalse);
  });
}
