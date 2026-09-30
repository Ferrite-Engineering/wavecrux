// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';

/// Translates WaveCrux's native element references into and out of canonical
/// [ElementId] form for the Cross-Tool eXchange Protocol (CXP).
///
/// WaveCrux speaks four [ElementKind]s natively:
///
/// * [ElementKind.signal] — hierarchical signal paths such as
///   `top.cpu.alu.sum[31:0]`. The canonical [ElementId.path] is the full
///   hierarchical path. WaveCrux preserves bit-extract slices
///   (`data[31:24]`) verbatim because a sliced and an unsliced reference
///   are *different* references in WaveCrux's signal-list model — a peer
///   that wants the underlying vector should send the un-sliced form.
/// * [ElementKind.scope] — module / generate-block / begin-end scope
///   paths such as `top.cpu`. The canonical path matches WaveCrux's
///   `Scope.path` directly.
/// * [ElementKind.marker] — named markers (`a`–`z`). The canonical path
///   is the single lowercase letter; the resolver rejects any other
///   marker name.
/// * [ElementKind.source] — file-line source citations (e.g. for RTL
///   source annotation). The canonical path uses the `file:line` form,
///   optionally followed by `:column`, exactly as the RTL annotation
///   feature surfaces them.
///
/// Edge cases the resolver intentionally documents:
///
/// * **Generate-block instance naming.** VCD writers emit names like
///   `genblk1[3]`, `genblk2.if[0]`, etc. Those names round-trip through
///   the resolver as-is — square brackets are preserved.
/// * **Escape characters.** VCD's `\foo[3]` escape form is preserved.
///   WaveCrux does not strip the leading backslash; cross-tool peers
///   should agree on the same VCD convention before comparing.
/// * **Bit slices vs. underlying vectors.** WaveCrux's signal-list keys
///   bit slices distinctly from their parent vectors. A canonical
///   `top.bus.data[31:24]` resolves to that specific slice; an
///   un-sliced `top.bus.data` resolves to the whole vector. The
///   resolver does NOT silently normalise slices away.
/// * **Yosys `$N` synthetic names.** A VCD produced from a netlist may
///   contain synthesizer-generated names that look like `$0\out[31:0]`.
///   WaveCrux sees them as opaque strings; a peer product sees them as
///   elaborated wires. Round-tripping a `$N` name across the two
///   products only works if both ends already share the same elaboration
///   convention — the resolver passes the string through unchanged but
///   makes no attempt at translation.
@immutable
class WaveCruxNameResolver implements NameResolver {
  /// Const constructor — the resolver is stateless.
  const WaveCruxNameResolver();

  @override
  ElementId? toCanonical({
    required ElementKind kind,
    required String local,
  }) {
    if (local.isEmpty) return null;
    // `ElementKind` is an open wire type, so switch on `known` — the
    // retained mirror enum — to keep the exhaustiveness check, and treat
    // the `null` case (a kind minted by a peer built against a later
    // protocol revision) as "not ours".
    switch (kind.known) {
      case KnownElementKind.signal:
      case KnownElementKind.scope:
      case KnownElementKind.source:
        return ElementId(kind: kind, path: local);
      case KnownElementKind.marker:
        if (!_isMarkerName(local)) return null;
        return ElementId(kind: kind, path: local);
      case KnownElementKind.instance:
      case KnownElementKind.net:
      case KnownElementKind.port:
      case KnownElementKind.rule:
      case KnownElementKind.test:
      case KnownElementKind.breakpoint:
        // WaveCrux does not natively author these kinds. They may still
        // arrive inbound from a peer product (instance, rule, …);
        // those are handled by [toLocal] rather than [toCanonical].
        return null;
      case null:
        // Unrecognised kind from a newer peer. Ignore it gracefully:
        // WaveCrux has no local object to name, so there is nothing to
        // canonicalise.
        return null;
    }
  }

  @override
  String? toLocal(ElementId id) {
    if (id.path.isEmpty) return null;
    switch (id.kind.known) {
      case KnownElementKind.signal:
      case KnownElementKind.scope:
      case KnownElementKind.source:
        return id.path;
      case KnownElementKind.marker:
        if (!_isMarkerName(id.path)) return null;
        return id.path;
      case KnownElementKind.instance:
      case KnownElementKind.net:
      case KnownElementKind.port:
        // A peer-supplied instance / net / port reference is treated as a
        // signal-like hierarchical path — WaveCrux's `findVariables` can
        // still match by `fullPath` so the request_highlight handler has
        // a chance of resolving the element even though we don't natively
        // emit these kinds.
        return id.path;
      case KnownElementKind.rule:
      case KnownElementKind.test:
      case KnownElementKind.breakpoint:
        // These element kinds belong to peer products (rule, breakpoint,
        // …) and have no natural WaveCrux mapping.
        return null;
      case null:
        // A kind this build has never heard of, minted by a peer built
        // against a later protocol revision. Ignore it gracefully rather
        // than guessing that its path is signal-like — forward-compat is
        // the whole point of the kind vocabulary being open.
        return null;
    }
  }

  /// Whether [name] is a valid WaveCrux marker reference: a single
  /// lowercase ASCII letter `a`–`z`.
  static bool _isMarkerName(String name) {
    if (name.length != 1) return false;
    final code = name.codeUnitAt(0);
    return code >= 0x61 && code <= 0x7A;
  }
}
