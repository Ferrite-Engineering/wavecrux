// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';

/// Global registry for protocol decoder plugins.
///
/// Decoders register themselves at app startup (or when dynamically loaded).
/// The UI queries the registry to list available decoders and to instantiate
/// a specific decoder when the user configures one.
///
/// Usage:
/// ```dart
/// DecoderRegistry.instance.register(SpiDecoder.definition, SpiDecoder.new);
/// ```
class DecoderRegistry {
  DecoderRegistry._();

  /// Creates an isolated registry — for tests that need to assert
  /// without leaking decoder registrations across cases. Production
  /// code uses [instance].
  @visibleForTesting
  DecoderRegistry.forTesting();

  static final DecoderRegistry instance = DecoderRegistry._();

  final Map<String, DecoderDefinition> _definitions = {};
  final Map<String, DecoderFactory> _factories = {};
  final Set<String> _userSuppliedIds = {};

  /// Register a decoder by its [definition] and a [factory] that constructs it.
  ///
  /// Replaces any existing registration with the same [DecoderDefinition.id].
  ///
  /// [userSupplied] marks a decoder whose id was chosen outside this codebase
  /// — the FFI plugin loader passes `true`. It is recorded here rather than
  /// inferred later because [DecoderCategory] cannot answer the question: a
  /// plugin manifest may declare any built-in category, so
  /// `category == DecoderCategory.userPlugin` is a default, not a guarantee.
  /// See [isUserSupplied].
  void register(
    DecoderDefinition definition,
    DecoderFactory factory, {
    bool userSupplied = false,
  }) {
    _definitions[definition.id] = definition;
    _factories[definition.id] = factory;
    if (userSupplied) {
      _userSuppliedIds.add(definition.id);
    } else {
      _userSuppliedIds.remove(definition.id);
    }
  }

  /// Whether [id] came from a runtime-loaded plugin rather than from the
  /// open-core or Pro decoder sets.
  ///
  /// The distinction is a privacy boundary, not a cosmetic one. Built-in and
  /// Pro decoder ids are application vocabulary that appears in our own
  /// documentation, so telemetry may report them verbatim; a plugin's id is
  /// chosen by whoever wrote the plugin, is unbounded in cardinality, and is
  /// exactly the class of user-chosen string telemetry must never carry. Unregistered
  /// ids count as user-supplied — a decoder we did not register is one whose
  /// provenance we cannot vouch for.
  bool isUserSupplied(String id) =>
      _userSuppliedIds.contains(id) || !_definitions.containsKey(id);

  /// Returns the [DecoderDefinition] for [id], or `null` if not registered.
  DecoderDefinition? getDefinition(String id) => _definitions[id];

  /// Returns the [DecoderFactory] for [id], or `null` if not registered.
  DecoderFactory? getFactory(String id) => _factories[id];

  /// Returns metadata for every registered decoder, sorted by display name.
  List<DecoderDefinition> listDecoders() {
    return _definitions.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  /// Returns definitions for every decoder that stacks on [parentId].
  ///
  /// A decoder is considered stacked when its
  /// [DecoderDefinition.parentDecoderId] equals [parentId]. Returns an empty
  /// list if no stacked decoders are registered for that parent.
  List<DecoderDefinition> listStackedDecoders(String parentId) {
    return _definitions.values
        .where((d) => d.parentDecoderId == parentId)
        .toList();
  }

  /// Returns every registered decoder grouped by [DecoderCategory].
  ///
  /// Categories with no registered decoders are omitted. Within each
  /// category the entries are sorted by display name. The returned map
  /// preserves [DecoderCategory.values] declaration order, which is the
  /// fixed display order in the picker UI (locale-independent).
  Map<DecoderCategory, List<DecoderDefinition>> listByCategory() {
    final result = <DecoderCategory, List<DecoderDefinition>>{};
    for (final category in DecoderCategory.values) {
      final entries =
          _definitions.values.where((d) => d.category == category).toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
      if (entries.isNotEmpty) {
        result[category] = entries;
      }
    }
    return result;
  }

  /// Returns `true` when a decoder with [id] is registered.
  bool isRegistered(String id) => _definitions.containsKey(id);

  /// Removes the decoder with [id] from the registry. Returns `true`
  /// when a registration was actually removed.
  ///
  /// Intended for the user-contributed plugin loader to unregister
  /// plugin-contributed decoders
  /// when a plugin's library is unloaded — for example during the
  /// Settings → Decoders → Plugins "Reload plugins" action. Built-in
  /// decoders are typically not unregistered at runtime.
  bool unregister(String id) {
    final hadDef = _definitions.remove(id) != null;
    _factories.remove(id);
    _userSuppliedIds.remove(id);
    return hadDef;
  }

  /// Removes all registrations — intended for use in tests only.
  void clear() {
    _definitions.clear();
    _factories.clear();
    _userSuppliedIds.clear();
  }
}
