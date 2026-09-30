// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import '../../helpers/in_memory_workspace_service.dart';
import '../../helpers/product_telemetry_config.dart';

CollabSessionState _hostSession() => const CollabSessionState(
  sessionId: 's1',
  myParticipantId: 'me',
  hostId: 'me',
  participants: [
    ParticipantInfo(
      id: 'me',
      displayName: 'Me',
      colorIndex: 0,
      viewportStart: 0,
      viewportEnd: 100,
      isHost: true,
    ),
  ],
  sharedMarkers: {},
  isRecording: true,
);

Future<ActionContext> _capture(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  late ActionContext captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [productTelemetryConfig, ...overrides],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            captured = ref.watch(actionContextProvider);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('actionContextProvider', () {
    testWidgets('passes through device class and diagnostics flag', (
      tester,
    ) async {
      final ctx = await _capture(
        tester,
        overrides: [
          deviceClassProvider.overrideWithValue(DeviceClass.tablet),
          diagnosticsEnabledProvider.overrideWithValue(true),
        ],
      );
      expect(ctx.deviceClass, DeviceClass.tablet);
      expect(ctx.diagnosticsEnabled, isTrue);
      expect(ctx.fileLoaded, isFalse);
      expect(ctx.inSession, isFalse);
    });

    testWidgets('fileLoaded follows the active tab filePath', (tester) async {
      await _capture(tester, overrides: testWorkspaceOverrides());
      final el = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(el);
      expect(container.read(actionContextProvider).fileLoaded, isFalse);

      await container.wavecruxWorkspace.openFile('/tmp/x.vcd');
      await tester.pumpAndSettle();
      expect(container.read(actionContextProvider).fileLoaded, isTrue);
    });

    testWidgets('collaboration flags derive from the session', (tester) async {
      final ctx = await _capture(
        tester,
        overrides: [
          collaborationSessionStateProvider.overrideWith(
            (ref) => Stream.value(_hostSession()),
          ),
        ],
      );
      expect(ctx.inSession, isTrue);
      expect(ctx.isHost, isTrue);
      expect(ctx.isRecording, isTrue);
    });
  });
}
