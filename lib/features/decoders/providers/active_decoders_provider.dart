// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/license/tier_unlocked_provider.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';

part 'active_decoders_provider.g.dart';

/// Captures decoder restore/signal-binding issues into the issue-reporter buffer.
final _log = Logger('wavecrux.decoders');

/// Manages the list of active protocol decoder instances in the viewer.
///
/// Each instance has a unique [ActiveDecoder.id], a registry key
/// ([ActiveDecoder.decoderId]), a signal-binding / parameter [DecoderConfig],
/// and the [DecodedTransaction]s produced by the most recent [decodeAll] run.
///
/// **The run asks the tier.** The decoder picker gates activation, but it is
/// not the only way a decoder arrives: [restoreDecoders] puts back whatever a
/// session saved, and the Pro overlay registers its decoders at every tier.
/// So [decodeAll] runs a decoder only when [tierUnlocked] admits its
/// [DecoderDefinition.requiredTier], and gives a withheld one no
/// transactions. The instance itself stays in [state], so [snapshot] writes it
/// back and its row can say why it is empty (`DecoderListEntry`). A change of
/// licence re-runs the set, so a withheld decoder follows the licence both
/// ways without a restart.
@Riverpod(keepAlive: true)
class ActiveDecodersNotifier extends _$ActiveDecodersNotifier {
  int _nextId = 0;

  /// Per-decoder-type next instance number. Monotonically increasing; numbers
  /// are never reused after removal so "SPI #1" cannot reappear after deletion.
  final Map<String, int> _nextInstanceNumbers = {};

  /// Persisted decoders this build cannot instantiate, carried verbatim from
  /// [restoreDecoders] to [snapshot] so a save does not delete them.
  ///
  /// They are not [ActiveDecoder]s and deliberately never reach [state]: there
  /// is no factory for them and nothing to decode. [heldDecodersProvider]
  /// publishes them so the signal list can show each one as "not available in
  /// this build" with its id; every change to this list is made together with
  /// a [state] assignment, which is what lets that provider follow it.
  ///
  /// Without it, opening a session in a build missing one of its decoders and
  /// then saving destroyed that decoder's configuration permanently — the
  /// viewer has no undo, and the user got no warning because from their side
  /// nothing happened. The case is not only a Pro decoder on the Open Core
  /// viewer: the FFI plugin loader registers at load time, so a plugin that is
  /// uninstalled, moved, or simply failed to load that session strands every
  /// decoder it supplied.
  ///
  /// Restoring is a whole-set replacement, so this is replaced with it rather
  /// than accumulated.
  List<PersistedDecoder> _unavailable = const [];

  @override
  List<ActiveDecoder> build() {
    ref
      ..listen<bool>(betaPeriodProvider, (_, _) => _rerunOnTierChange())
      ..listen<LicenseTier>(
        licenseTierProvider,
        (_, _) => _rerunOnTierChange(),
      );
    // Reset with [state]: the two describe one session's decoder set between
    // them, and a build that empties one while the other kept a previous
    // session's entries would let [snapshot] resurrect them.
    _unavailable = const [];
    return const [];
  }

  /// The tier [decoderId] needs. An unregistered id needs nothing: it cannot
  /// run anyway, and [restoreDecoders] never admits one.
  static LicenseTier _requiredTier(String decoderId) =>
      DecoderRegistry.instance.getDefinition(decoderId)?.requiredTier ??
      LicenseTier.openCore;

  /// Re-runs the set when the licence moves, but only if some active decoder
  /// is gated: an all-open-core set decodes the same at every tier.
  void _rerunOnTierChange() {
    final gated = state.any(
      (d) => _requiredTier(d.decoderId) != LicenseTier.openCore,
    );
    if (gated) unawaited(decodeAll());
  }

  /// Adds a new decoder instance with the given [decoderId] and [config].
  ///
  /// Assigns a per-type [ActiveDecoder.instanceNumber] that is unique and
  /// never reused.  The new instance has an empty transaction list until
  /// [decodeAll] is called.
  ///
  /// This is the one seam a user activation passes through, which is why the
  /// `decoder.opened` counter lives here rather than at the config dialog:
  /// [restoreDecoders] (session reopen), [applyCompositionRecipe] (a
  /// collaboration follower mirroring the host) and [updateConfig] (editing an
  /// existing instance) all reach the same state without anyone choosing a
  /// decoder, and counting them would inflate the one usage number used to
  /// decide which protocols earn maintenance.
  void addDecoder(String decoderId, DecoderConfig config) {
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'decoder.opened',
            properties: <String, Object?>{
              // A runtime-loaded plugin reports the literal `plugin`, never its
              // own id: the SigRok bridge alone contributes ~130 decoders whose
              // names we neither choose nor document, and an id we did not
              // author is the user's vocabulary, not ours. Built-in and Pro ids
              // are lower_snake by the `DecoderDefinition.id` convention, so
              // they satisfy the Worker's value class as they stand.
              'decoder': DecoderRegistry.instance.isUserSupplied(decoderId)
                  ? 'plugin'
                  : decoderId,
            },
          ),
        );

    // The AUDIT event, beside the telemetry one and deliberately not the same
    // shape. Telemetry maps a user-supplied plugin to the literal `plugin`
    // because the SigRok bridge alone contributes ~130 decoder names we neither
    // choose nor document, and an id we did not author has no place in an
    // aggregate metric we publish. None of that reasoning survives the move to
    // audit: this file is the ORGANIZATION's record of ITS OWN machine, and an
    // administrator asking "which decoder ran against our bus traces" is asking
    // exactly the question `plugin` refuses to answer. The real id goes in,
    // with a flag saying whether it came from us.
    ref
        .read(cruxAuditRecorderProvider)
        .record(
          WaveCruxAuditKinds.decoderActivated,
          payload: <String, Object?>{
            'decoder': decoderId,
            'userSupplied': DecoderRegistry.instance.isUserSupplied(decoderId),
          },
        );

    final id = 'decoder_${_nextId++}';
    final instanceNumber = _nextInstanceNumbers[decoderId] ?? 1;
    _nextInstanceNumbers[decoderId] = instanceNumber + 1;
    state = [
      ...state,
      ActiveDecoder(
        id: id,
        decoderId: decoderId,
        config: config,
        instanceNumber: instanceNumber,
      ),
    ];
  }

  /// Removes the decoder instance identified by [id].
  void removeDecoder(String id) {
    state = state.where((d) => d.id != id).toList();
  }

  /// The persisted decoders this build cannot instantiate, held for
  /// [snapshot]. Read it through [heldDecodersProvider], which rebuilds when
  /// it changes.
  List<PersistedDecoder> get heldDecoders => _unavailable;

  /// Drops the held decoder at [index] of [heldDecoders], so the next save no
  /// longer writes it. The user's explicit choice; nothing else discards one.
  void removeHeldDecoder(int index) {
    if (index < 0 || index >= _unavailable.length) return;
    _unavailable = List.unmodifiable([..._unavailable]..removeAt(index));
    // A fresh list notifies [heldDecodersProvider]; the decoders are unchanged.
    state = [...state];
  }

  /// Removes all active decoders and clears all decoded transactions.
  ///
  /// Called by [WaveformSourceNotifier] whenever a new file is opened or the
  /// current file is closed, so stale decoder state from the previous file is
  /// never shown alongside a different waveform.
  void clearAll() {
    _nextId = 0;
    _nextInstanceNumbers.clear();
    // Held-but-unrenderable decoders belong to the session being closed. Left
    // here they would be written into the *next* file's session, which is the
    // one way this preservation could invent decoders rather than keep them.
    final hadHeld = _unavailable.isNotEmpty;
    _unavailable = const [];
    // Only emit when there is actually something to clear. openFile() calls
    // clearAll() synchronously while a mobile drawer's per-tab
    // UncontrolledProviderScope is (re)building; a redundant `state = const []`
    // on an already-empty list still notifies (the prior value may be a
    // non-canonical `[]`), and that mid-build notify makes ValueColumnPanel —
    // which watches this provider — throw "markNeedsBuild during build". A no-op
    // when already empty avoids the spurious notify and is behaviorally
    // identical on every platform (clearing nothing changes nothing).
    if (state.isNotEmpty || hadHeld) state = const [];
  }

  /// Captures the live decoder set as a list of [PersistedDecoder]
  /// records suitable for round-tripping through the `.wavecrux`
  /// session document.
  ///
  /// `id` and `transactions` are intentionally NOT carried over — see
  /// [PersistedDecoder] for the rationale. The relative order of the
  /// returned list matches the runtime order, which is the order the
  /// transaction-table tabs render.
  ///
  /// [_unavailable] rides along at the end. Appended rather than returned to
  /// its original position because the user may add, remove and reorder
  /// decoders after the restore, which makes a remembered index a lie within
  /// one session. A decoder that comes back last in the build that can finally
  /// run it is a cosmetic loss; being deleted is not.
  List<PersistedDecoder> snapshot() => [
    for (final d in state)
      PersistedDecoder(
        decoderId: d.decoderId,
        instanceNumber: d.instanceNumber,
        config: d.config,
      ),
    ..._unavailable,
  ];

  /// Replaces the active decoder set with [persisted] in a single state
  /// assignment, preserving each entry's `instanceNumber` so post-restart
  /// labels ("SPI #2") match the user's pre-quit view.
  ///
  /// Entries whose `decoderId` is not in [DecoderRegistry.instance]
  /// (Pro decoder opened on Open Core, uninstalled user plugin, future
  /// decoder from a newer build) are skipped silently — a single
  /// warning (`package:logging`) records the IDs for diagnostic-after-the-fact.
  /// No snackbar, no exception: the cross-tier-open case must keep the
  /// rest of the session restore working.
  ///
  /// A registered decoder is restored whatever its tier. Whether it may run
  /// is [decodeAll]'s question, asked live; restoring it regardless is what
  /// keeps a Pro decoder in the session through a stretch at Open Core.
  ///
  /// Bumps the per-type instance counter past every restored entry so
  /// a subsequent [addDecoder] call assigns the next unused number for
  /// that decoder type. The transaction lists start empty; the caller
  /// is expected to invoke [decodeAll] after the source is ready.
  ///
  /// [holdUnavailable] keeps the entries this build cannot instantiate in
  /// [_unavailable], so a later [snapshot] writes them back instead of
  /// deleting them. True for a session restore, which is the case the holding
  /// exists for. False for a collaboration follower ([applyCompositionRecipe]),
  /// which is mirroring somebody else's view rather than reopening its own
  /// document, already tells the user what it could not render, and has no
  /// business writing the host's decoders into the follower's session.
  void restoreDecoders(
    List<PersistedDecoder> persisted, {
    bool holdUnavailable = true,
  }) {
    final restored = <ActiveDecoder>[];
    final unavailable = <PersistedDecoder>[];
    for (final p in persisted) {
      if (!DecoderRegistry.instance.isRegistered(p.decoderId)) {
        unavailable.add(p);
        continue;
      }
      final id = 'decoder_${_nextId++}';
      restored.add(
        ActiveDecoder(
          id: id,
          decoderId: p.decoderId,
          config: p.config,
          instanceNumber: p.instanceNumber,
        ),
      );
      final next = _nextInstanceNumbers[p.decoderId] ?? 1;
      if (p.instanceNumber >= next) {
        _nextInstanceNumbers[p.decoderId] = p.instanceNumber + 1;
      }
    }
    if (unavailable.isNotEmpty) {
      _log.warning(
        'SessionService restore — ${unavailable.length} persisted decoder(s) '
        'not in DecoderRegistry: '
        '${unavailable.map((p) => p.decoderId).join(", ")}. This is expected '
        'when a Pro decoder is opened on the Open Core viewer or when a user '
        'plugin was uninstalled since the session was saved. They are held '
        'unrendered and written back on save, not dropped.',
      );
    }
    _unavailable = holdUnavailable ? List.unmodifiable(unavailable) : const [];
    state = restored;
  }

  // ── view-composition recipe seams ──────────────────────────────────

  /// Serialize the active decoders into a **signal-identity-based** recipe:
  /// each binding value (a backend-local `signalRef`) is rewritten to its
  /// canonical signal path via [resolver] so a follower on any backend can
  /// re-bind. The decoder id, instance number, and parameters ride along
  /// unchanged; a follower with the decoder registered runs it on local data
  /// (the identity hash guarantees input parity).
  List<PersistedDecoder> toCompositionRecipe(
    SignalIdentityResolver resolver,
  ) => [
    for (final d in state)
      PersistedDecoder(
        decoderId: d.decoderId,
        instanceNumber: d.instanceNumber,
        config: DecoderConfig(
          signalBindings: {
            for (final e in d.config.signalBindings.entries)
              e.key: e.value.isEmpty ? e.value : resolver.pathForRef(e.value),
          },
          parameters: d.config.parameters,
        ),
      ),
  ];

  /// Apply a presenter's decoder [recipe], rewriting each binding's canonical
  /// path back to the follower's local `signalRef` via [resolver] and replacing
  /// the active decoder set. Decoders whose id is not registered in the
  /// follower's build (a Pro decoder on Open Core) are dropped by
  /// [restoreDecoders] and reported. Bindings whose path no local variable
  /// matches are bound to the empty string (the decoder sees nulls and renders
  /// no transactions) and reported.
  ///
  /// Returns the missing-reference degradation sets. The caller is expected to
  /// invoke [decodeAll] afterwards (the bridge does, against the follower's
  /// freshly-opened waveform) — mirroring the session-restore contract.
  ({List<String> missingDecoderIds, List<String> missingSignalPaths})
  applyCompositionRecipe(
    List<PersistedDecoder> recipe,
    SignalIdentityResolver resolver,
  ) {
    final missingDecoderIds = <String>[];
    final missingSignalPaths = <String>[];
    final resolved = <PersistedDecoder>[];
    for (final p in recipe) {
      if (!DecoderRegistry.instance.isRegistered(p.decoderId)) {
        missingDecoderIds.add(p.decoderId);
      }
      final bindings = <String, String>{};
      for (final e in p.config.signalBindings.entries) {
        if (e.value.isEmpty) {
          bindings[e.key] = '';
          continue;
        }
        final ref = resolver.refForPath(e.value);
        if (ref == null) {
          missingSignalPaths.add(e.value);
          bindings[e.key] = '';
        } else {
          bindings[e.key] = ref;
        }
      }
      resolved.add(
        PersistedDecoder(
          decoderId: p.decoderId,
          instanceNumber: p.instanceNumber,
          config: DecoderConfig(
            signalBindings: bindings,
            parameters: p.config.parameters,
          ),
        ),
      );
    }
    // restoreDecoders drops unregistered ids here rather than holding them for
    // the next save: we have already recorded them above for the degradation
    // banner, so the follower is told, and a mirrored view is the host's
    // document, not one to write the host's decoders into.
    restoreDecoders(resolved, holdUnavailable: false);
    return (
      missingDecoderIds: missingDecoderIds,
      missingSignalPaths: missingSignalPaths,
    );
  }

  /// Replaces the [DecoderConfig] for the decoder instance identified by [id]
  /// without changing its [ActiveDecoder.instanceNumber] or position.
  void updateConfig(String id, DecoderConfig config) {
    state = [
      for (final ActiveDecoder d in state)
        if (d.id == id) d.copyWith(config: config) else d,
    ];
  }

  /// Runs all active decoders against the loaded waveform and updates
  /// [ActiveDecoder.transactions] on each instance.
  ///
  /// Executes in two passes:
  ///
  /// **Pass 1 — base decoders** (no [DecoderDefinition.parentDecoderId]).
  /// Each decoder receives raw signal data via [SignalValueQuery] and
  /// [SignalChangesQuery] callbacks built from the loaded waveform.
  ///
  /// **Pass 2 — stacked decoders** ([StackedDecoder] implementors).
  /// Each stacked decoder receives the merged, time-sorted transactions from
  /// all active Pass-1 instances whose [ActiveDecoder.decoderId] matches the
  /// stacked decoder's [DecoderDefinition.parentDecoderId].
  ///
  /// Loads any unloaded signals referenced in each decoder's bindings before
  /// running. No-ops when no waveform is loaded or [state] is empty.
  ///
  /// A decoder whose tier this seat does not have is not run, in either
  /// pass: it keeps its place with no transactions, so nothing downstream (the
  /// transaction lane, the table, an assistant tool reading transactions) has
  /// anything of it to show. The tier is read once per run, so one run never
  /// mixes two answers.
  Future<void> decodeAll() async {
    final source = ref.read(waveformSourceProvider).value;
    if (source == null || state.isEmpty) return;

    // Read directly, not through `tierUnlockedProvider`: this also runs from
    // the licence listener in [build], where the derived provider may not yet
    // have seen the change.
    final beta = ref.read(betaPeriodProvider);
    final tier = ref.read(licenseTierProvider);
    final withheld = <String>{
      for (final d in state)
        if (!tierUnlocked(
          _requiredTier(d.decoderId),
          beta: beta,
          tier: tier,
        ))
          d.id,
    };

    final startTime = source.startTime;
    final endTime = source.endTime;
    final timescale = source.timescale;

    // ── helpers ──────────────────────────────────────────────────────────────

    Future<
      (
        String? Function(String, int),
        List<(int, String)> Function(String, int, int),
      )
    >
    buildCallbacks(Map<String, String> bindings) async {
      for (final signalRef in bindings.values) {
        if (signalRef.isNotEmpty && !source.isSignalLoaded(signalRef)) {
          try {
            await source.loadSignal(signalRef);
          } on Exception catch (e) {
            // Signal load failures are non-fatal; the decoder will see nulls
            // for this binding and should handle them gracefully — but record
            // why, so "decoder shows nothing" reports carry the root cause.
            _log.warning('Decoder signal "$signalRef" failed to load: $e');
          }
        }
      }
      String? query(String logicalName, int time) {
        final signalRef = bindings[logicalName];
        if (signalRef == null || signalRef.isEmpty) return null;
        return source.valueAt(signalRef, time);
      }

      List<(int, String)> changesQuery(String logicalName, int start, int end) {
        final signalRef = bindings[logicalName];
        if (signalRef == null || signalRef.isEmpty) return [];
        return source
            .changesInRange(signalRef, start, end)
            .map((c) => (c.time, c.value))
            .toList();
      }

      return (query, changesQuery);
    }

    // ── Pass 1: base decoders ─────────────────────────────────────────────────

    final updated = <ActiveDecoder>[];
    // Map from decoderId → merged transactions from all pass-1 instances.
    final parentTransactions = <String, List<DecodedTransaction>>{};

    for (final active in state) {
      if (withheld.contains(active.id)) {
        updated.add(active.copyWith(transactions: const []));
        continue;
      }
      final def = DecoderRegistry.instance.getDefinition(active.decoderId);
      if (def?.parentDecoderId != null) {
        // Stacked decoder — defer to pass 2.
        updated.add(active);
        continue;
      }

      final factory = DecoderRegistry.instance.getFactory(active.decoderId);
      if (factory == null) {
        updated.add(active);
        continue;
      }

      final (query, changesQuery) = await buildCallbacks(
        active.config.signalBindings,
      );
      final decoder = factory(active.config);
      List<DecodedTransaction> transactions;
      try {
        transactions = decoder.decode(
          startTime,
          endTime,
          query,
          changesQuery,
          timescale: timescale,
        );
      } on Exception catch (_) {
        transactions = const [];
      }
      // Sort once at the provider boundary by ascending startTime. Decoders
      // that emit at completion time (AXI4-full and friends) produce unsorted,
      // overlapping transactions; TransactionPainter's binary-searched visible
      // window and the transaction table both require ascending startTime.
      final sorted = [...transactions]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      updated.add(active.copyWith(transactions: sorted));

      // Accumulate for stacked-decoder consumption.
      parentTransactions.update(
        active.decoderId,
        (existing) => [...existing, ...sorted],
        ifAbsent: () => [...sorted],
      );
    }

    // ── Pass 2: stacked decoders ──────────────────────────────────────────────

    final finalState = <ActiveDecoder>[];
    for (final active in updated) {
      final def = DecoderRegistry.instance.getDefinition(active.decoderId);
      final parentId = def?.parentDecoderId;
      // A withheld stacked decoder already has its empty list from pass 1.
      if (parentId == null || withheld.contains(active.id)) {
        finalState.add(active);
        continue;
      }

      final factory = DecoderRegistry.instance.getFactory(active.decoderId);
      if (factory == null) {
        finalState.add(active);
        continue;
      }

      // Merge all parent transactions sorted by startTime. Copy into a fresh
      // growable list before sorting: when the parent decoder is not active
      // (or produced nothing), the lookup falls back to a `const []`, and
      // sorting that throws `Unsupported operation: Cannot modify an
      // unmodifiable list`. A stacked decoder can legitimately outlive its
      // parent, so this path must not crash.
      final parentTxs = [...?parentTransactions[parentId]]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      final (query, changesQuery) = await buildCallbacks(
        active.config.signalBindings,
      );
      final decoder = factory(active.config);

      List<DecodedTransaction> transactions;
      if (decoder is StackedDecoder) {
        transactions = decoder.decodeStacked(
          parentTxs,
          startTime,
          endTime,
          query,
          changesQuery,
          timescale: timescale,
        );
      } else {
        // Fallback: run as a base decoder if not implementing StackedDecoder.
        transactions = decoder.decode(
          startTime,
          endTime,
          query,
          changesQuery,
          timescale: timescale,
        );
      }
      // Same provider-boundary sort as pass 1: stacked decoders may also emit
      // out of startTime order.
      final sorted = [...transactions]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      finalState.add(active.copyWith(transactions: sorted));
    }

    state = finalState;
  }
}

/// The session decoders this build cannot load (a Pro decoder on the Open Core
/// viewer, or one from a plugin that is missing or failed to load), held by
/// [ActiveDecodersNotifier] so a save writes them back.
///
/// The signal list renders one "not available in this build" row per entry,
/// after the active decoders, and the canvas and value column reserve a
/// matching blank lane so the three columns stay aligned. A collaboration
/// follower holds none ([ActiveDecodersNotifier.applyCompositionRecipe]), so
/// it neither shows nor saves them.
@Riverpod(keepAlive: true)
List<PersistedDecoder> heldDecoders(Ref ref) {
  // The notifier changes its held list only together with a state assignment,
  // so watching the state is what re-reads it.
  ref.watch(activeDecodersProvider);
  return ref.read(activeDecodersProvider.notifier).heldDecoders;
}
