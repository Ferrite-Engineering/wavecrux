// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A signal/port/net/reg declaration found in an HDL source file.
@immutable
class HdlSignal {
  const HdlSignal({required this.name, required this.lineNumber});

  /// The declared identifier (no ranges, no type).
  final String name;

  /// 1-based line of the declaration.
  final int lineNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HdlSignal &&
          name == other.name &&
          lineNumber == other.lineNumber;

  @override
  int get hashCode => Object.hash(name, lineNumber);

  @override
  String toString() => 'HdlSignal($name@$lineNumber)';
}

/// A child-module / component instantiation found inside a module body.
@immutable
class HdlInstance {
  const HdlInstance({
    required this.moduleType,
    required this.instanceName,
    required this.lineNumber,
  });

  /// The name of the module/entity being instantiated (used to resolve the
  /// hierarchy during elaboration).
  final String moduleType;

  /// The instance label (becomes the child scope's path component).
  final String instanceName;

  /// 1-based line of the instantiation.
  final int lineNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HdlInstance &&
          moduleType == other.moduleType &&
          instanceName == other.instanceName &&
          lineNumber == other.lineNumber;

  @override
  int get hashCode => Object.hash(moduleType, instanceName, lineNumber);

  @override
  String toString() => 'HdlInstance($moduleType $instanceName@$lineNumber)';
}

/// A parsed HDL module (Verilog `module` / SystemVerilog `module` / VHDL
/// `entity`+`architecture`): its declaration site, the signals it declares,
/// and the child modules it instantiates. The intermediate representation the
/// [StemsGenerator] elaborates into a hierarchical stems file.
@immutable
class HdlModule {
  const HdlModule({
    required this.name,
    required this.sourceFile,
    required this.declarationLine,
    this.signals = const [],
    this.instances = const [],
  });

  /// Module / entity name (the key used to resolve instantiations).
  final String name;

  /// Source file this module was parsed from.
  final String sourceFile;

  /// 1-based line of the `module`/`entity` keyword.
  final int declarationLine;

  final List<HdlSignal> signals;
  final List<HdlInstance> instances;

  /// Merges [other] (same [name]) into this module — used when a VHDL entity
  /// and its architecture(s) are parsed separately, or a module spans files.
  /// Signals/instances are unioned (de-duplicated by name); the declaration
  /// site of `this` wins (the entity/first declaration).
  HdlModule mergedWith(HdlModule other) {
    final sigByName = <String, HdlSignal>{
      for (final s in signals) s.name: s,
    };
    for (final s in other.signals) {
      sigByName.putIfAbsent(s.name, () => s);
    }
    final instByName = <String, HdlInstance>{
      for (final i in instances) i.instanceName: i,
    };
    for (final i in other.instances) {
      instByName.putIfAbsent(i.instanceName, () => i);
    }
    return HdlModule(
      name: name,
      sourceFile: sourceFile,
      declarationLine: declarationLine,
      signals: sigByName.values.toList(),
      instances: instByName.values.toList(),
    );
  }

  @override
  String toString() =>
      'HdlModule($name @ $sourceFile:$declarationLine, '
      '${signals.length} sigs, ${instances.length} insts)';
}
