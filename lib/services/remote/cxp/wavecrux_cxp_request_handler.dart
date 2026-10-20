// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';

/// What WaveCrux does when a peer asks, behind the shared CXP runtime.
///
/// Each request lands on the same code the WCP front door uses, so there is one
/// implementation of "highlight this signal" and "open this waveform". The
/// runtime sends every acknowledgement and asks for the user's attention, so
/// nothing here replies on the wire.
class WaveCruxCxpRequestHandler extends CruxCxpRequestHandler {
  /// Creates the handler over [_ref], the root container's `Ref`.
  WaveCruxCxpRequestHandler(this._ref);

  final Ref _ref;

  @override
  Future<CruxCxpHandlerResult> highlight(
    RequestHighlight request,
    PeerIdentity from,
  ) => dispatchCxpHighlight(
    _ref,
    request.element,
    request.metadata,
    request.coordinate,
  );

  @override
  Future<CruxCxpHandlerResult> openSource(
    RequestOpenSource request,
    PeerIdentity from,
  ) => dispatchCxpOpenSource(
    _ref,
    request.filePath,
    request.line,
    request.column,
  );

  @override
  Future<CruxCxpHandlerResult> openArtifact(
    RequestOpenArtifact request,
    PeerIdentity from,
  ) => dispatchCxpOpenArtifact(
    _ref,
    request.designId,
    request.artifactKind,
    request.path,
  );

  @override
  void selection(NotifySelection message, PeerIdentity from) =>
      handleInboundSelection(_ref, message.elements, message.metadata);
}
