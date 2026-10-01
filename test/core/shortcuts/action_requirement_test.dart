// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Unit coverage for the atomic enablement requirements the descriptor table
// is now built from.
//
// `ActionDescriptor.isEnabled` used to be one opaque closure per action, which
// answered "enabled?" but not "why not?" — so the keyboard's parity guard
// could only fail silently. Enablement is now a *list* of named
// [ActionRequirement]s: the enabled answer is unchanged (every requirement
// satisfied), and the unsatisfied one is addressable, which is what the viewer
// turns into a localized hint.
//
// These tests pin the two properties that decomposition has to preserve:
// each requirement reads exactly the [ActionContext] field it names, and a
// multi-requirement action reports the FIRST unmet one (so the hint is the
// most fundamental remedy, not an arbitrary one).

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/action_requirement.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

ActionContext _ctx({
  bool fileLoaded = false,
  bool cursorPresent = false,
  bool markersPresent = false,
  bool annotationsPresent = false,
  bool signalsDisplayed = false,
  bool diffActive = false,
  bool patternMatchesPresent = false,
  bool cocotbLogLoaded = false,
  bool stageViewVisible = false,
  bool streamingActive = false,
  bool diagnosticsEnabled = false,
  bool hasSelection = false,
  bool aiModelConfigured = false,
  bool inSession = false,
  bool isHost = false,
  bool isRecording = false,
  int paneCount = 1,
  // Both default to FALSE here although `ActionContext` defaults them to true
  // (so production literals and the no-file case behave as they always did) —
  // a "blank" context in this file means *no state present*, and the
  // everything-unmet property below depends on it staying that way.
  bool canZoomOut = false,
  bool canZoomIn = false,
}) => ActionContext(
  fileLoaded: fileLoaded,
  deviceClass: DeviceClass.desktop,
  cursorPresent: cursorPresent,
  annotationsPresent: annotationsPresent,
  signalsDisplayed: signalsDisplayed,
  markersPresent: markersPresent,
  diffActive: diffActive,
  patternMatchesPresent: patternMatchesPresent,
  cocotbLogLoaded: cocotbLogLoaded,
  stageViewVisible: stageViewVisible,
  streamingActive: streamingActive,
  diagnosticsEnabled: diagnosticsEnabled,
  hasSelection: hasSelection,
  aiModelConfigured: aiModelConfigured,
  inSession: inSession,
  isHost: isHost,
  isRecording: isRecording,
  paneCount: paneCount,
  canZoomOut: canZoomOut,
  canZoomIn: canZoomIn,
);

void main() {
  group('ActionRequirement.isSatisfiedBy', () {
    test('each simple requirement tracks its own context field', () {
      final satisfying = <ActionRequirement, ActionContext>{
        ActionRequirement.fileLoaded: _ctx(fileLoaded: true),
        ActionRequirement.cursorPresent: _ctx(cursorPresent: true),
        ActionRequirement.markersPresent: _ctx(markersPresent: true),
        ActionRequirement.annotationsPresent: _ctx(annotationsPresent: true),
        ActionRequirement.diffActive: _ctx(diffActive: true),
        ActionRequirement.patternMatchesPresent: _ctx(
          patternMatchesPresent: true,
        ),
        ActionRequirement.cocotbLogLoaded: _ctx(cocotbLogLoaded: true),
        ActionRequirement.stageViewVisible: _ctx(stageViewVisible: true),
        ActionRequirement.streamingActive: _ctx(streamingActive: true),
        ActionRequirement.diagnosticsEnabled: _ctx(diagnosticsEnabled: true),
        ActionRequirement.hasSelection: _ctx(hasSelection: true),
        ActionRequirement.signalsDisplayed: _ctx(signalsDisplayed: true),
        ActionRequirement.aiModelConfigured: _ctx(aiModelConfigured: true),
        ActionRequirement.notInSession: _ctx(),
        ActionRequirement.inSession: _ctx(inSession: true),
        ActionRequirement.isHost: _ctx(inSession: true, isHost: true),
        ActionRequirement.isParticipant: _ctx(inSession: true),
        ActionRequirement.recordingAvailable: _ctx(isRecording: true),
        ActionRequirement.singlePane: _ctx(),
        ActionRequirement.multiPane: _ctx(paneCount: 2),
        ActionRequirement.canZoomOut: _ctx(canZoomOut: true),
        ActionRequirement.canZoomIn: _ctx(canZoomIn: true),
      };

      // Exhaustiveness: a new requirement must be added here too, otherwise it
      // ships with no unit coverage of its predicate.
      expect(satisfying.keys, containsAll(ActionRequirement.values));

      for (final entry in satisfying.entries) {
        expect(
          entry.key.isSatisfiedBy(entry.value),
          isTrue,
          reason: '${entry.key} should be satisfied by its own context',
        );
      }
    });

    test('the empty context leaves everything unmet except the negatives', () {
      // `notInSession` and `singlePane` are the two requirements a blank
      // context satisfies — they assert the ABSENCE of state.
      final met = ActionRequirement.values
          .where((r) => r.isSatisfiedBy(_ctx()))
          .toSet();
      expect(met, {
        ActionRequirement.notInSession,
        ActionRequirement.singlePane,
      });
    });

    test('participant is a non-host member of a live session', () {
      expect(
        ActionRequirement.isParticipant.isSatisfiedBy(
          _ctx(inSession: true, isHost: true),
        ),
        isFalse,
      );
      expect(
        ActionRequirement.isParticipant.isSatisfiedBy(_ctx(isHost: true)),
        isFalse,
        reason: 'host flag without a session is not a participant',
      );
    });

    test('a recording is available while in session or while recording', () {
      expect(
        ActionRequirement.recordingAvailable.isSatisfiedBy(
          _ctx(inSession: true),
        ),
        isTrue,
      );
      expect(
        ActionRequirement.recordingAvailable.isSatisfiedBy(
          _ctx(isRecording: true),
        ),
        isTrue,
      );
      expect(ActionRequirement.recordingAvailable.isSatisfiedBy(_ctx()), false);
    });
  });

  group('unmetActionRequirement', () {
    test('is null exactly when the action is enabled', () {
      final ctx = _ctx(fileLoaded: true, cursorPresent: true);
      for (final action in ShortcutAction.values) {
        expect(
          unmetActionRequirement(action, ctx) == null,
          isActionEnabled(action, ctx),
          reason: '$action: enablement and reason must agree',
        );
      }
    });

    test('reports the first unmet requirement, most fundamental first', () {
      // Jump to Start requires a file AND a cursor. With neither, the useful
      // remedy is "load a file" — telling the user to place a cursor in an
      // empty viewer would be wrong.
      expect(
        unmetActionRequirement(ShortcutAction.jumpToStart, _ctx()),
        ActionRequirement.fileLoaded,
      );
      expect(
        unmetActionRequirement(
          ShortcutAction.jumpToStart,
          _ctx(fileLoaded: true),
        ),
        ActionRequirement.cursorPresent,
      );
    });

    test('Add Decoder with no file names the file requirement', () {
      // The specific regression this follow-on restores: the Add Decoder
      // shortcut with no waveform loaded must tell the user to load one.
      expect(
        unmetActionRequirement(ShortcutAction.addDecoder, _ctx()),
        ActionRequirement.fileLoaded,
      );
    });

    test('every disabled action can name a reason', () {
      // If any descriptor were to gain enablement logic that is not expressed
      // as requirements, it would be disabled with nothing to say — the exact
      // silent-inert regression this work closes.
      const ctx = ActionContext(
        fileLoaded: false,
        deviceClass: DeviceClass.desktop,
      );
      for (final action in ShortcutAction.values) {
        if (isActionEnabled(action, ctx)) continue;
        expect(
          unmetActionRequirement(action, ctx),
          isNotNull,
          reason: '$action is disabled but cannot explain why',
        );
      }
    });
  });
}
