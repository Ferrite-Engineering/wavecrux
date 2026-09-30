// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/sdk/manifest/_yaml_emitter.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_parameter.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_validation_error.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/bit_field_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/boolean_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/enum_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalizer_chain.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';
import 'package:yaml/yaml.dart';

/// Strict YAML parser for [StageWidgetManifest].
///
/// Parses by walking [YamlNode]s rather than the materialised primitive
/// tree so every error carries the original source line and column. The
/// parser collects every validation failure into a single
/// [ManifestValidationException] rather than failing at the first error,
/// so authors see the full list per iteration.
///
/// Public entry points:
///
/// - [parseStageWidgetManifest] — `String → StageWidgetManifest`
/// - [serializeStageWidgetManifest] — `StageWidgetManifest → String`
///
/// Both are pure functions; parser state lives entirely on the stack.
StageWidgetManifest parseStageWidgetManifest(String source) {
  final errors = <ManifestValidationError>[];
  final root = _loadOrEmpty(source, errors);
  if (root == null) {
    throw ManifestValidationException(errors);
  }
  if (root is! YamlMap) {
    errors.add(_typeError(root, '/', 'a map'));
    throw ManifestValidationException(errors);
  }
  final manifest = _ManifestParser(errors).parseRoot(root);
  if (errors.isNotEmpty) {
    throw ManifestValidationException(errors);
  }
  return manifest!;
}

/// Serializes a [StageWidgetManifest] back to canonical YAML. Round-trip
/// through [parseStageWidgetManifest] yields an equal manifest.
String serializeStageWidgetManifest(StageWidgetManifest manifest) {
  return emitYaml(_ManifestSerializer().toMap(manifest));
}

YamlNode? _loadOrEmpty(
  String source,
  List<ManifestValidationError> errors,
) {
  if (source.trim().isEmpty) {
    errors.add(
      const ManifestValidationError(
        message: 'Manifest source is empty',
        path: '/',
        line: 1,
        column: 1,
      ),
    );
    return null;
  }
  try {
    return loadYamlNode(source);
  } on YamlException catch (e) {
    errors.add(
      ManifestValidationError(
        message: 'YAML syntax error: ${e.message}',
        path: '/',
        line: e.span?.start.line == null ? null : e.span!.start.line + 1,
        column: e.span?.start.column == null ? null : e.span!.start.column + 1,
      ),
    );
    return null;
  }
}

ManifestValidationError _typeError(YamlNode node, String path, String want) =>
    ManifestValidationError(
      message: 'Expected $want, got ${_describeType(node)}',
      path: path,
      line: node.span.start.line + 1,
      column: node.span.start.column + 1,
    );

String _describeType(YamlNode node) {
  if (node is YamlMap) return 'a map';
  if (node is YamlList) return 'a list';
  if (node is YamlScalar) {
    final v = node.value;
    if (v == null) return 'null';
    return '${v.runtimeType}';
  }
  return node.runtimeType.toString();
}

class _ManifestParser {
  _ManifestParser(this.errors);

  final List<ManifestValidationError> errors;

  StageWidgetManifest? parseRoot(YamlMap root) {
    _rejectUnknownKeys(root, '/', const {
      'id',
      'version',
      'display_name',
      'category',
      'icon_asset_path',
      'signal_bindings',
      'parameters',
      'runtime',
      'runtime_asset_path',
      'required_api_version',
    });

    final id = _requireString(root, 'id', '/id');
    final version = _requireString(root, 'version', '/version');
    final displayName = _parseLocalized(
      root.nodes['display_name'],
      '/display_name',
      required: true,
    );
    final category = _parseEnum<StageWidgetCategory>(
      root.nodes['category'],
      '/category',
      StageWidgetCategory.values,
      _categoryWire,
      required: true,
    );
    final runtime = _parseEnum<ManifestRuntime>(
      root.nodes['runtime'],
      '/runtime',
      ManifestRuntime.values,
      (v) => v.wireName,
      required: true,
    );
    final runtimeAssetPath = _requireString(
      root,
      'runtime_asset_path',
      '/runtime_asset_path',
    );
    final requiredApiVersion = _requireInt(
      root,
      'required_api_version',
      '/required_api_version',
      min: 1,
    );
    final iconAssetPath = _optionalString(
      root,
      'icon_asset_path',
      '/icon_asset_path',
    );

    final bindingsNode = root.nodes['signal_bindings'];
    final signalBindings = bindingsNode == null
        ? <ManifestSignalBinding>[]
        : _parseSignalBindings(bindingsNode);

    final paramsNode = root.nodes['parameters'];
    final parameters = paramsNode == null
        ? <ManifestParameter>[]
        : _parseParameters(paramsNode, signalBindings);

    if (id == null ||
        version == null ||
        displayName == null ||
        category == null ||
        runtime == null ||
        runtimeAssetPath == null ||
        requiredApiVersion == null) {
      return null;
    }

    return StageWidgetManifest(
      id: id,
      version: version,
      displayName: displayName,
      category: category,
      runtime: runtime,
      runtimeAssetPath: runtimeAssetPath,
      requiredApiVersion: requiredApiVersion,
      iconAssetPath: iconAssetPath,
      signalBindings: signalBindings,
      parameters: parameters,
    );
  }

  // ── Field helpers ──────────────────────────────────────────────────────

  String? _requireString(YamlMap map, String key, String path) {
    final node = map.nodes[key];
    if (node == null) {
      errors.add(_missing(map, key, path));
      return null;
    }
    if (node is! YamlScalar || node.value is! String) {
      errors.add(_typeError(node, path, 'a string'));
      return null;
    }
    final value = node.value as String;
    if (value.isEmpty) {
      errors.add(
        ManifestValidationError(
          message: 'Field "$key" must not be empty',
          path: path,
          line: node.span.start.line + 1,
          column: node.span.start.column + 1,
        ),
      );
      return null;
    }
    return value;
  }

  String? _optionalString(YamlMap map, String key, String path) {
    final node = map.nodes[key];
    if (node == null) return null;
    if (node is! YamlScalar || node.value is! String) {
      errors.add(_typeError(node, path, 'a string'));
      return null;
    }
    return node.value as String;
  }

  int? _requireInt(YamlMap map, String key, String path, {int? min}) {
    final node = map.nodes[key];
    if (node == null) {
      errors.add(_missing(map, key, path));
      return null;
    }
    if (node is! YamlScalar || node.value is! int) {
      errors.add(_typeError(node, path, 'an integer'));
      return null;
    }
    final value = node.value as int;
    if (min != null && value < min) {
      errors.add(
        ManifestValidationError(
          message: 'Field "$key" must be >= $min, got $value',
          path: path,
          line: node.span.start.line + 1,
          column: node.span.start.column + 1,
        ),
      );
      return null;
    }
    return value;
  }

  ManifestValidationError _missing(YamlNode parent, String key, String path) =>
      ManifestValidationError(
        message: 'Required field "$key" is missing',
        path: path,
        line: parent.span.start.line + 1,
        column: parent.span.start.column + 1,
      );

  T? _parseEnum<T>(
    YamlNode? node,
    String path,
    List<T> values,
    String Function(T) wire, {
    required bool required,
  }) {
    if (node == null) {
      if (required) {
        errors.add(
          ManifestValidationError(
            message: 'Required field is missing',
            path: path,
          ),
        );
      }
      return null;
    }
    if (node is! YamlScalar || node.value is! String) {
      errors.add(_typeError(node, path, 'an enum string'));
      return null;
    }
    final raw = node.value as String;
    for (final v in values) {
      if (wire(v) == raw) return v;
    }
    final allowed = values.map(wire).join(', ');
    errors.add(
      ManifestValidationError(
        message: 'Invalid value "$raw"; expected one of: $allowed',
        path: path,
        line: node.span.start.line + 1,
        column: node.span.start.column + 1,
      ),
    );
    return null;
  }

  LocalizedString? _parseLocalized(
    YamlNode? node,
    String path, {
    required bool required,
  }) {
    if (node == null) {
      if (required) {
        errors.add(
          ManifestValidationError(
            message: 'Required field is missing',
            path: path,
          ),
        );
      }
      return null;
    }
    if (node is YamlScalar) {
      if (node.value is! String) {
        errors.add(_typeError(node, path, 'a string or locale map'));
        return null;
      }
      return LocalizedString.single(node.value as String);
    }
    if (node is YamlMap) {
      final entries = <String, String>{};
      node.nodes.forEach((key, value) {
        final keyText = key is YamlScalar
            ? key.value
            : (key is YamlNode ? key.toString() : key.toString());
        if (keyText is! String || keyText.isEmpty) {
          errors.add(
            ManifestValidationError(
              message: 'Locale-map keys must be non-empty strings',
              path: path,
              line: (key is YamlNode) ? key.span.start.line + 1 : null,
              column: (key is YamlNode) ? key.span.start.column + 1 : null,
            ),
          );
          return;
        }
        if (value is! YamlScalar || value.value is! String) {
          errors.add(
            _typeError(
              value,
              '$path/$keyText',
              'a localized string',
            ),
          );
          return;
        }
        entries[keyText] = value.value as String;
      });
      if (entries.isEmpty) {
        errors.add(
          ManifestValidationError(
            message: 'Locale map must not be empty',
            path: path,
            line: node.span.start.line + 1,
            column: node.span.start.column + 1,
          ),
        );
        return null;
      }
      return LocalizedString.localized(entries);
    }
    errors.add(_typeError(node, path, 'a string or locale map'));
    return null;
  }

  List<ManifestSignalBinding> _parseSignalBindings(YamlNode node) {
    if (node is! YamlList) {
      errors.add(_typeError(node, '/signal_bindings', 'a list'));
      return [];
    }
    final out = <ManifestSignalBinding>[];
    final seenNames = <String>{};
    for (var i = 0; i < node.length; i++) {
      final item = node.nodes[i];
      final path = '/signal_bindings/$i';
      if (item is! YamlMap) {
        errors.add(_typeError(item, path, 'a map'));
        continue;
      }
      final binding = _parseSignalBinding(item, path, seenNames);
      if (binding != null) out.add(binding);
    }
    return out;
  }

  ManifestSignalBinding? _parseSignalBinding(
    YamlMap map,
    String path,
    Set<String> seenNames,
  ) {
    _rejectUnknownKeys(map, path, const {
      'name',
      'description',
      'direction',
      'signal_type',
      'bit_width',
      'value_range',
      'required',
      'default_policy',
    });

    final name = _requireString(map, 'name', '$path/name');
    final description = _requireString(map, 'description', '$path/description');
    final signalType = _parseEnum<SignalType>(
      map.nodes['signal_type'],
      '$path/signal_type',
      SignalType.values,
      (v) => v.wireName,
      required: true,
    );
    final direction =
        _parseEnum<BindingDirection>(
          map.nodes['direction'],
          '$path/direction',
          BindingDirection.values,
          (v) => v.wireName,
          required: false,
        ) ??
        BindingDirection.input;
    final bitWidth = _parseBitWidthRange(
      map.nodes['bit_width'],
      '$path/bit_width',
    );
    final valueRange = _parseValueRange(
      map.nodes['value_range'],
      '$path/value_range',
    );
    final requiredFlag = _parseBool(
      map.nodes['required'],
      '$path/required',
      defaultValue: true,
    );
    final defaultPolicy =
        _parseEnum<DefaultPolicy>(
          map.nodes['default_policy'],
          '$path/default_policy',
          DefaultPolicy.values,
          (v) => v.wireName,
          required: false,
        ) ??
        DefaultPolicy.holdLast;

    if (name == null || description == null || signalType == null) {
      return null;
    }
    if (!seenNames.add(name)) {
      errors.add(
        ManifestValidationError(
          message: 'Duplicate binding name "$name"',
          path: '$path/name',
          line: map.span.start.line + 1,
          column: map.span.start.column + 1,
        ),
      );
    }
    if (signalType == SignalType.scalar && bitWidth != null) {
      errors.add(
        ManifestValidationError(
          message: 'Scalar bindings cannot declare a bit_width',
          path: '$path/bit_width',
        ),
      );
    }
    return ManifestSignalBinding(
      name: name,
      description: description,
      signalType: signalType,
      direction: direction,
      bitWidth: bitWidth,
      valueRange: valueRange,
      required: requiredFlag,
      defaultPolicy: defaultPolicy,
    );
  }

  BitWidthRange? _parseBitWidthRange(YamlNode? node, String path) {
    if (node == null) return null;
    if (node is! YamlMap) {
      errors.add(_typeError(node, path, 'a map with min/max'));
      return null;
    }
    _rejectUnknownKeys(node, path, const {'min', 'max'});
    int? readBound(String key) {
      final n = node.nodes[key];
      if (n == null) return null;
      if (n is! YamlScalar || n.value is! int) {
        errors.add(_typeError(n, '$path/$key', 'an integer'));
        return null;
      }
      final v = n.value as int;
      if (v < 0) {
        errors.add(
          ManifestValidationError(
            message: '"$key" must be >= 0, got $v',
            path: '$path/$key',
            line: n.span.start.line + 1,
            column: n.span.start.column + 1,
          ),
        );
        return null;
      }
      return v;
    }

    final min = readBound('min');
    final max = readBound('max');
    if (min != null && max != null && max < min) {
      errors.add(
        ManifestValidationError(
          message: 'bit_width.max ($max) must be >= bit_width.min ($min)',
          path: path,
          line: node.span.start.line + 1,
          column: node.span.start.column + 1,
        ),
      );
      return null;
    }
    return BitWidthRange(min: min, max: max);
  }

  ValueRange? _parseValueRange(YamlNode? node, String path) {
    if (node == null) return null;
    if (node is! YamlMap) {
      errors.add(_typeError(node, path, 'a map with min/max'));
      return null;
    }
    _rejectUnknownKeys(node, path, const {'min', 'max'});
    double? readBound(String key) {
      final n = node.nodes[key];
      if (n == null) {
        errors.add(_missing(node, key, '$path/$key'));
        return null;
      }
      if (n is! YamlScalar || (n.value is! num)) {
        errors.add(_typeError(n, '$path/$key', 'a number'));
        return null;
      }
      return (n.value as num).toDouble();
    }

    final min = readBound('min');
    final max = readBound('max');
    if (min == null || max == null) return null;
    if (min == max) {
      errors.add(
        ManifestValidationError(
          message: 'value_range.min must differ from value_range.max',
          path: path,
          line: node.span.start.line + 1,
          column: node.span.start.column + 1,
        ),
      );
      return null;
    }
    return ValueRange(min: min, max: max);
  }

  bool _parseBool(
    YamlNode? node,
    String path, {
    required bool defaultValue,
  }) {
    if (node == null) return defaultValue;
    if (node is! YamlScalar || node.value is! bool) {
      errors.add(_typeError(node, path, 'a bool'));
      return defaultValue;
    }
    return node.value as bool;
  }

  List<ManifestParameter> _parseParameters(
    YamlNode node,
    List<ManifestSignalBinding> bindings,
  ) {
    if (node is! YamlList) {
      errors.add(_typeError(node, '/parameters', 'a list'));
      return [];
    }
    final out = <ManifestParameter>[];
    final bindingNames = bindings.map((b) => b.name).toSet();
    for (var i = 0; i < node.length; i++) {
      final item = node.nodes[i];
      final path = '/parameters/$i';
      if (item is! YamlMap) {
        errors.add(_typeError(item, path, 'a map'));
        continue;
      }
      _rejectUnknownKeys(item, path, const {'binding', 'normalizer'});
      final binding = _requireString(item, 'binding', '$path/binding');
      final normNode = item.nodes['normalizer'];
      if (normNode == null) {
        errors.add(_missing(item, 'normalizer', '$path/normalizer'));
        continue;
      }
      final normalizer = _parseNormalizer(normNode, '$path/normalizer');
      if (binding == null || normalizer == null) continue;
      if (!bindingNames.contains(binding)) {
        errors.add(
          ManifestValidationError(
            message: 'Parameter references unknown binding "$binding"',
            path: '$path/binding',
            line: item.span.start.line + 1,
            column: item.span.start.column + 1,
          ),
        );
        continue;
      }
      out.add(ManifestParameter(binding: binding, normalizer: normalizer));
    }
    return out;
  }

  ValueNormalizer? _parseNormalizer(YamlNode node, String path) {
    if (node is! YamlMap) {
      errors.add(_typeError(node, path, 'a normalizer map'));
      return null;
    }
    // Chain shorthand: { chain: [ {kind: …}, {kind: …} ] }
    if (node.nodes.containsKey('chain')) {
      _rejectUnknownKeys(node, path, const {'chain'});
      final chainNode = node.nodes['chain']!;
      if (chainNode is! YamlList || chainNode.isEmpty) {
        errors.add(
          _typeError(
            chainNode,
            '$path/chain',
            'a non-empty list of normalizer specs',
          ),
        );
        return null;
      }
      final stages = <ValueNormalizer>[];
      for (var i = 0; i < chainNode.length; i++) {
        final stage = _parseNormalizer(chainNode.nodes[i], '$path/chain/$i');
        if (stage != null) stages.add(stage);
      }
      if (stages.isEmpty) return null;
      return NormalizerChain(stages);
    }

    final kindNode = node.nodes['kind'];
    if (kindNode == null) {
      errors.add(_missing(node, 'kind', '$path/kind'));
      return null;
    }
    if (kindNode is! YamlScalar || kindNode.value is! String) {
      errors.add(_typeError(kindNode, '$path/kind', 'a string'));
      return null;
    }
    final kind = kindNode.value as String;
    switch (kind) {
      case 'linear':
        return _parseLinear(node, path);
      case 'enum':
        return _parseEnumNormalizer(node, path);
      case 'bit_field':
        return _parseBitField(node, path);
      case 'boolean':
        return _parseBoolean(node, path);
      default:
        errors.add(
          ManifestValidationError(
            message:
                'Unknown normalizer kind "$kind"; expected one of: '
                'linear, enum, bit_field, boolean',
            path: '$path/kind',
            line: kindNode.span.start.line + 1,
            column: kindNode.span.start.column + 1,
          ),
        );
        return null;
    }
  }

  XZPolicy? _parseXZPolicy(YamlNode? node, String path) => _parseEnum<XZPolicy>(
    node,
    path,
    XZPolicy.values,
    (v) {
      switch (v) {
        case XZPolicy.propagate:
          return 'propagate';
        case XZPolicy.asDefault:
          return 'as_default';
        case XZPolicy.bestEffort:
          return 'best_effort';
      }
    },
    required: false,
  );

  LinearNormalizer? _parseLinear(YamlMap node, String path) {
    _rejectUnknownKeys(node, path, const {
      'kind',
      'input_min',
      'input_max',
      'output_min',
      'output_max',
      'clamp',
      'xz_policy',
      'default_value',
    });
    final inputMin = _requireDouble(node, 'input_min', '$path/input_min');
    final inputMax = _requireDouble(node, 'input_max', '$path/input_max');
    final outputMin =
        _optionalDouble(node, 'output_min', '$path/output_min') ?? 0.0;
    final outputMax =
        _optionalDouble(node, 'output_max', '$path/output_max') ?? 1.0;
    final clamp = _parseBool(
      node.nodes['clamp'],
      '$path/clamp',
      defaultValue: true,
    );
    final xz =
        _parseXZPolicy(node.nodes['xz_policy'], '$path/xz_policy') ??
        XZPolicy.propagate;
    final defaultValue =
        _optionalDouble(node, 'default_value', '$path/default_value') ?? 0.0;
    if (inputMin == null || inputMax == null) return null;
    if (inputMin == inputMax) {
      errors.add(
        ManifestValidationError(
          message: 'input_min must differ from input_max',
          path: path,
          line: node.span.start.line + 1,
          column: node.span.start.column + 1,
        ),
      );
      return null;
    }
    return LinearNormalizer(
      inputMin: inputMin,
      inputMax: inputMax,
      outputMin: outputMin,
      outputMax: outputMax,
      clamp: clamp,
      xzPolicy: xz,
      defaultValue: defaultValue,
    );
  }

  EnumNormalizer? _parseEnumNormalizer(YamlMap node, String path) {
    _rejectUnknownKeys(node, path, const {
      'kind',
      'labels',
      'default_label',
      'xz_policy',
    });
    final labelsNode = node.nodes['labels'];
    if (labelsNode == null) {
      errors.add(_missing(node, 'labels', '$path/labels'));
      return null;
    }
    if (labelsNode is! YamlMap) {
      errors.add(
        _typeError(
          labelsNode,
          '$path/labels',
          'a map of integer keys to label strings',
        ),
      );
      return null;
    }
    final labels = <Object, String>{};
    labelsNode.nodes.forEach((rawKey, rawVal) {
      final keyVal = rawKey is YamlScalar ? rawKey.value : rawKey;
      if (keyVal is! int) {
        errors.add(
          ManifestValidationError(
            message: 'enum label keys must be integers',
            path: '$path/labels',
            line: (rawKey is YamlNode) ? rawKey.span.start.line + 1 : null,
            column: (rawKey is YamlNode) ? rawKey.span.start.column + 1 : null,
          ),
        );
        return;
      }
      if (rawVal is! YamlScalar || rawVal.value is! String) {
        errors.add(
          _typeError(
            rawVal,
            '$path/labels/$keyVal',
            'a label string',
          ),
        );
        return;
      }
      labels[keyVal] = rawVal.value as String;
    });
    if (labels.isEmpty) return null;
    final defaultLabel = _optionalString(
      node,
      'default_label',
      '$path/default_label',
    );
    final xz =
        _parseXZPolicy(node.nodes['xz_policy'], '$path/xz_policy') ??
        XZPolicy.propagate;
    return EnumNormalizer(
      labels: labels,
      defaultLabel: defaultLabel,
      xzPolicy: xz,
    );
  }

  BitFieldNormalizer? _parseBitField(YamlMap node, String path) {
    _rejectUnknownKeys(node, path, const {
      'kind',
      'high_bit',
      'low_bit',
      'sub',
    });
    final highBit = _requireInt(node, 'high_bit', '$path/high_bit', min: 0);
    final lowBit = _requireInt(node, 'low_bit', '$path/low_bit', min: 0);
    if (highBit == null || lowBit == null) return null;
    if (highBit < lowBit) {
      errors.add(
        ManifestValidationError(
          message: 'high_bit ($highBit) must be >= low_bit ($lowBit)',
          path: path,
          line: node.span.start.line + 1,
          column: node.span.start.column + 1,
        ),
      );
      return null;
    }
    final subNode = node.nodes['sub'];
    final sub = subNode == null ? null : _parseNormalizer(subNode, '$path/sub');
    return BitFieldNormalizer(highBit: highBit, lowBit: lowBit, sub: sub);
  }

  BooleanNormalizer? _parseBoolean(YamlMap node, String path) {
    _rejectUnknownKeys(node, path, const {
      'kind',
      'reduction',
      'xz_policy',
      'default_value',
    });
    final reduction =
        _parseEnum<BooleanReduction>(
          node.nodes['reduction'],
          '$path/reduction',
          BooleanReduction.values,
          (v) => v.name,
          required: false,
        ) ??
        BooleanReduction.lsb;
    final xz =
        _parseXZPolicy(node.nodes['xz_policy'], '$path/xz_policy') ??
        XZPolicy.propagate;
    final defaultNode = node.nodes['default_value'];
    final defaultValue =
        defaultNode != null &&
        _parseBool(defaultNode, '$path/default_value', defaultValue: false);
    return BooleanNormalizer(
      reduction: reduction,
      xzPolicy: xz,
      defaultValue: defaultValue,
    );
  }

  double? _requireDouble(YamlMap map, String key, String path) {
    final node = map.nodes[key];
    if (node == null) {
      errors.add(_missing(map, key, path));
      return null;
    }
    if (node is! YamlScalar || node.value is! num) {
      errors.add(_typeError(node, path, 'a number'));
      return null;
    }
    return (node.value as num).toDouble();
  }

  double? _optionalDouble(YamlMap map, String key, String path) {
    final node = map.nodes[key];
    if (node == null) return null;
    if (node is! YamlScalar || node.value is! num) {
      errors.add(_typeError(node, path, 'a number'));
      return null;
    }
    return (node.value as num).toDouble();
  }

  void _rejectUnknownKeys(YamlMap map, String path, Set<String> known) {
    map.nodes.forEach((key, _) {
      final keyText = key is YamlScalar ? key.value : key;
      if (keyText is! String) {
        errors.add(
          ManifestValidationError(
            message: 'Map keys must be strings',
            path: path,
            line: (key is YamlNode) ? key.span.start.line + 1 : null,
            column: (key is YamlNode) ? key.span.start.column + 1 : null,
          ),
        );
        return;
      }
      if (!known.contains(keyText)) {
        errors.add(
          ManifestValidationError(
            message:
                'Unknown field "$keyText"; expected one of: '
                '${(known.toList()..sort()).join(', ')}',
            path: '$path/$keyText',
            line: (key is YamlNode) ? key.span.start.line + 1 : null,
            column: (key is YamlNode) ? key.span.start.column + 1 : null,
          ),
        );
      }
    });
  }
}

String _categoryWire(StageWidgetCategory c) {
  switch (c) {
    case StageWidgetCategory.primitive:
      return 'primitive';
    case StageWidgetCategory.peripheral:
      return 'peripheral';
    case StageWidgetCategory.instrument:
      return 'instrument';
    case StageWidgetCategory.board:
      return 'board';
    case StageWidgetCategory.protocol:
      return 'protocol';
    case StageWidgetCategory.custom:
      return 'custom';
  }
}

class _ManifestSerializer {
  Map<String, Object?> toMap(StageWidgetManifest m) {
    final out = <String, Object?>{
      'id': m.id,
      'version': m.version,
      'display_name': m.displayName.toYamlValue(),
      'category': _categoryWire(m.category),
      'runtime': m.runtime.wireName,
      'runtime_asset_path': m.runtimeAssetPath,
      'required_api_version': m.requiredApiVersion,
    };
    if (m.iconAssetPath != null) out['icon_asset_path'] = m.iconAssetPath;
    if (m.signalBindings.isNotEmpty) {
      out['signal_bindings'] = m.signalBindings
          .map(_bindingToMap)
          .toList(growable: false);
    }
    if (m.parameters.isNotEmpty) {
      out['parameters'] = m.parameters
          .map(_parameterToMap)
          .toList(growable: false);
    }
    return out;
  }

  Map<String, Object?> _bindingToMap(ManifestSignalBinding b) {
    final out = <String, Object?>{
      'name': b.name,
      'description': b.description,
      'signal_type': b.signalType.wireName,
    };
    if (b.direction != BindingDirection.input) {
      out['direction'] = b.direction.wireName;
    }
    if (b.bitWidth != null) {
      out['bit_width'] = <String, Object?>{
        if (b.bitWidth!.min != null) 'min': b.bitWidth!.min,
        if (b.bitWidth!.max != null) 'max': b.bitWidth!.max,
      };
    }
    if (b.valueRange != null) {
      out['value_range'] = <String, Object?>{
        'min': b.valueRange!.min,
        'max': b.valueRange!.max,
      };
    }
    if (!b.required) out['required'] = false;
    if (b.defaultPolicy != DefaultPolicy.holdLast) {
      out['default_policy'] = b.defaultPolicy.wireName;
    }
    return out;
  }

  Map<String, Object?> _parameterToMap(ManifestParameter p) => {
    'binding': p.binding,
    'normalizer': _normalizerToMap(p.normalizer),
  };

  Map<String, Object?> _normalizerToMap(ValueNormalizer n) {
    if (n is NormalizerChain) {
      return {
        'chain': n.stages.map(_normalizerToMap).toList(growable: false),
      };
    }
    if (n is LinearNormalizer) {
      return {
        'kind': 'linear',
        'input_min': n.inputMin,
        'input_max': n.inputMax,
        'output_min': n.outputMin,
        'output_max': n.outputMax,
        if (!n.clamp) 'clamp': false,
        if (n.xzPolicy != XZPolicy.propagate)
          'xz_policy': _xzPolicyWire(n.xzPolicy),
        if (n.defaultValue != 0.0) 'default_value': n.defaultValue,
      };
    }
    if (n is EnumNormalizer) {
      final labels = <String, Object?>{
        for (final entry in n.labels.entries) entry.key.toString(): entry.value,
      };
      return {
        'kind': 'enum',
        'labels': labels,
        if (n.defaultLabel != null) 'default_label': n.defaultLabel,
        if (n.xzPolicy != XZPolicy.propagate)
          'xz_policy': _xzPolicyWire(n.xzPolicy),
      };
    }
    if (n is BitFieldNormalizer) {
      return {
        'kind': 'bit_field',
        'high_bit': n.highBit,
        'low_bit': n.lowBit,
        if (n.sub != null) 'sub': _normalizerToMap(n.sub!),
      };
    }
    if (n is BooleanNormalizer) {
      return {
        'kind': 'boolean',
        if (n.reduction != BooleanReduction.lsb) 'reduction': n.reduction.name,
        if (n.xzPolicy != XZPolicy.propagate)
          'xz_policy': _xzPolicyWire(n.xzPolicy),
        if (n.defaultValue) 'default_value': true,
      };
    }
    throw StateError('Unknown normalizer kind: ${n.runtimeType}');
  }

  String _xzPolicyWire(XZPolicy p) {
    switch (p) {
      case XZPolicy.propagate:
        return 'propagate';
      case XZPolicy.asDefault:
        return 'as_default';
      case XZPolicy.bestEffort:
        return 'best_effort';
    }
  }
}
