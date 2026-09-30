// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A ceiling on how much of this app any one file is allowed to be.
///
/// A suite audit found `viewer_screen.dart` at 3,219 lines while the
/// other three products kept their largest UI file under 900. Nothing was
/// broken — the analyzer was clean and coverage was 85.6% — so this is not a
/// defect guard. It is a ratchet, and its whole value is that it cannot be
/// satisfied by intending to fix something later.
///
/// ## Why the limit is 1,100 and not 900
///
/// 900 is what the three sibling products manage, and it is the number worth
/// aiming at. This guard asserts **what was actually achieved**, because a
/// limit set to a number the tree does not meet is a limit with an exemption
/// list, and an exemption list is how a ratchet stops ratcheting.
///
/// `viewer_screen.dart` came down 3,219 → 1,089 across six part files. The
/// remainder is `build` (214 lines) and `_buildTabContent` (238) — one render
/// composition where the first delegates straight into the second — plus
/// lifecycle and state plumbing. Splitting *those* across files would mean
/// reading the screen's rendering across a file boundary, which makes the
/// thing this guard is about worse rather than better.
///
/// Lower it when the tree allows. Do not raise it.
///
/// ## The allowance list is eleven files, and each is a named piece of work
///
/// These are not exemptions in the "we gave up" sense — each is a specific
/// deferred decomposition with a reason it was not folded into the
/// viewer-screen split, recorded
/// beside it below. A file may only be added here by deciding to, in a commit
/// that says why.
///
/// Eleven is a lot, and saying so is the point: it is the honest size of the
/// backlog this finding sits on top of, rather than one file that happened to
/// get audited. Three are the paint path and stay. The clearest next one is
/// `annotations_panel.dart` — eleven widget classes in a single file.
void main() {
  test('no UI file exceeds the house limit', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = p.relative(entity.path).replaceAll(r'\', '/');
      // Generated code is not written by hand and not read by hand.
      if (rel.contains('/l10n/') || rel.endsWith('.g.dart')) continue;
      if (_allowance.containsKey(rel)) continue;

      final length = entity.readAsLinesSync().length;
      if (length > _limit) offenders.add('$rel ($length lines)');
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          'These files are over the $_limit-line house limit:\n'
          '${offenders.join('\n')}\n\n'
          'Split by *cohesion*, not by line count — the viewer screen split '
          'into file I/O, tools, annotations, reactions and widgets because '
          'those are the things somebody reads separately. A part file keeps '
          'private access, so members move verbatim with no promotions and no '
          'import churn (see viewer_screen_file_io.dart for the argument, '
          'including what part-splitting does *not* buy). If the file '
          'genuinely cannot be split, add it to _allowance with a reason — in '
          'a commit that argues for it.',
    );
  });

  /// An allowance that no longer applies is worse than no allowance: it is a
  /// standing permission nobody re-examines, attached to a file that has
  /// already been fixed.
  test('every allowance is still needed', () {
    final stale = <String>[];
    for (final entry in _allowance.entries) {
      final file = File(entry.key);
      if (!file.existsSync()) {
        stale.add('${entry.key} — no longer exists');
        continue;
      }
      final length = file.readAsLinesSync().length;
      if (length <= _limit) {
        stale.add('${entry.key} — now $length lines, under the limit');
      }
    }

    expect(
      stale,
      isEmpty,
      reason:
          'These allowances have outlived their reason:\n${stale.join('\n')}\n\n'
          'Delete the entry. The file is inside the limit now, and leaving the '
          'allowance means the next thing that grows past it does so silently.',
    );
  });
}

/// Hand-written lines, excluding generated code.
const _limit = 1100;

/// Files over the limit, each with the reason it was not part of the
/// viewer-screen split.
///
/// None was in scope for a finding about the viewer screen. Three of them —
/// the canvas, its render object, and the annotation overlay that hit-tests
/// over it — are the paint path the performance rules put off limits, and
/// those are permanent rather than deferred.
const _allowance = <String, String>{
  'lib/features/viewer/widgets/waveform_canvas.dart':
      'The waveform canvas. Performance-critical paint path — the '
      'performance rules put it off limits, and the viewer-screen split '
      'explicitly excluded it.',
  'lib/features/viewer/rendering/waveform_canvas_render_object.dart':
      'The canvas render object. Same paint path, same exclusion.',
  'lib/features/viewer/widgets/signal_list_panel.dart':
      'The signal list. A decomposition worth doing on its own terms — it has '
      'the same interleaved-concerns shape the viewer screen had — but it is '
      'a separate piece of work with its own regression surface.',
  'lib/features/annotations/widgets/annotation_overlay.dart':
      'The annotation overlay. Hit-testing and painting over the canvas, so '
      'it inherits the paint path caution even though it is not the canvas.',
  'lib/app.dart':
      'The app shell: routing, theming, provider scopes and platform wiring '
      'in one composition root. Splitting a composition root tends to hide '
      'what it composes, so this needs a design decision rather than a split.',
  'lib/services/host_bridge/host_bridge_messages.dart':
      'Wire-protocol message definitions. Long because the protocol is, and '
      'flat by design — a reader looks up one message, not the file.',
  'lib/domain/interfaces/collaboration_service.dart':
      'The Enterprise collaboration extension point: one abstract interface '
      'plus its no-op default, and the models the contract is written in. '
      'Long because the contract is wide, and splitting an interface from the '
      'types it is expressed in makes the contract harder to read, not easier.',
  'lib/services/collaboration/collab_viewer_bridge.dart':
      'The bridge between collaboration events and viewer state. One class '
      'with a long method-per-event surface; it splits along the event taxonomy '
      'or not at all, which is a design decision rather than a file split.',
  'lib/features/annotations/widgets/annotations_panel.dart':
      'The annotations panel — eleven widget classes in one file, so this is '
      'the clearest remaining split in the tree and the natural next one after '
      'the viewer screen. Not folded into that split because it is a different '
      'surface with its own regression tests.',
  'lib/services/decoders/ffi/ffi_decoder_loader_io.dart':
      'The FFI decoder loader: six classes wrapping the native boundary, '
      'including the struct layouts. Splitting the layouts from the calls that '
      'use them is how an ABI mismatch stops being obvious on inspection.',
  'lib/services/remote/cxp/cxp_inbound_handlers.dart':
      'The CXP inbound dispatch. One exhaustive switch over the protocol, '
      'which is the property that makes an unhandled message fail to compile.',
};
