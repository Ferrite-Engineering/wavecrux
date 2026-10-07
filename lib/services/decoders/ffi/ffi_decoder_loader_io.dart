// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/interfaces/decoder_plugin_loader.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_info.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/ffi/decoder_abi_bindings.g.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_allowlist.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_directory_resolver.dart';

const String _logChannel = 'wavecrux.decoders.plugins';

/// Where plugin faults go: the issue-reporter buffer and, at SEVERE, stderr.
/// `developer.log` emits nothing from a release build, and a plugin that
/// fails to load or to decode is exactly what a plugin author, or a user
/// filing a report, needs to see there.
final _pluginLog = Logger(_logChannel);

/// Diagnostic log target, handed each message with its [Level]. Tests
/// override it to capture messages.
typedef PluginLoaderLogger = void Function(Level level, String message);

/// Faults ([Level.WARNING] and up) to [_pluginLog]; anything quieter is a
/// debugging trace and stays on `developer.log`.
void _defaultLog(Level level, String message) {
  if (level >= Level.WARNING) {
    _pluginLog.log(level, message);
  } else {
    developer.log(message, name: _logChannel, level: level.value);
  }
}

/// Indirection so tests can stub `DynamicLibrary.open` and feed the
/// loader fake bindings without producing a real shared library on
/// every run. Production callers leave it at the default.
typedef DynamicLibraryOpener = ffi.DynamicLibrary Function(String path);

ffi.DynamicLibrary _defaultOpener(String path) => ffi.DynamicLibrary.open(path);

/// File extensions the loader treats as candidate plugin shared
/// libraries. Linux: `.so`. macOS: `.dylib`. Windows: `.dll`.
const _libraryExtensions = <String>{'.so', '.dylib', '.dll'};

/// Desktop `dart:ffi`-backed implementation of [DecoderPluginLoader].
///
/// Walks the directories surfaced by [PluginDirectoryResolver],
/// `DynamicLibrary.open()`s every candidate file, validates the ABI
/// version, calls `wavecrux_decoder_register`, decodes each contributed
/// decoder's manifest into the open-core [DecoderDefinition] shape, and
/// registers a [DecoderFactory] adapter into
/// [DecoderRegistry.instance].
///
/// Per-plugin failure isolation is mandatory: every error path
/// (`dlopen` failure, ABI mismatch, missing symbol, malformed manifest,
/// duplicate decoder id, plugin panic during register) logs a
/// diagnostic on the `wavecrux.decoders.plugins` channel and proceeds
/// to the next plugin. [scan] never throws past its boundary.
class FfiDecoderLoader implements DecoderPluginLoader {
  /// Constructs a loader.
  ///
  /// [resolver] computes the directories to scan. [registry] receives
  /// successfully loaded decoders — defaults to
  /// [DecoderRegistry.instance] but tests inject a fresh registry so
  /// they don't leak state across cases.
  ///
  /// [userConfiguredDirectories] / [envVarRaw] mirror
  /// `AppSettings.userPluginDirectories` and the
  /// `WAVECRUX_DECODER_PATH` environment variable. The defaults are
  /// empty so simple test setups don't need to opt out of either
  /// source. [pluginLoadingDisabled] short-circuits the scan to an
  /// empty result without touching the filesystem; [perPluginDisabled]
  /// keeps a discovered plugin in the result list with status
  /// [DecoderPluginLoadStatus.disabled] but does not call its register
  /// entry point.
  FfiDecoderLoader({
    required PluginDirectoryResolver resolver,
    DecoderRegistry? registry,
    PluginAllowlist allowlist = PluginAllowlist.absent,
    PluginLoadObserver? onPluginLoad,
    List<String> userConfiguredDirectories = const <String>[],
    String? envVarRaw,
    bool pluginLoadingDisabled = false,
    Map<String, bool> perPluginDisabled = const <String, bool>{},
    DynamicLibraryOpener opener = _defaultOpener,
    PluginLoaderLogger logger = _defaultLog,
  }) : _resolver = resolver,
       _registry = registry ?? DecoderRegistry.instance,
       _userConfiguredDirectories = List<String>.unmodifiable(
         userConfiguredDirectories,
       ),
       _envVarRaw = envVarRaw,
       _pluginLoadingDisabled = pluginLoadingDisabled,
       _perPluginDisabled = Map<String, bool>.unmodifiable(perPluginDisabled),
       _opener = opener,
       _allowlist = allowlist,
       _onPluginLoad = onPluginLoad,
       _log = logger;

  final PluginDirectoryResolver _resolver;
  final DecoderRegistry _registry;
  final List<String> _userConfiguredDirectories;
  final String? _envVarRaw;
  final bool _pluginLoadingDisabled;
  final Map<String, bool> _perPluginDisabled;
  final DynamicLibraryOpener _opener;

  /// The organization's approved-plugin list.
  ///
  /// [PluginAllowlist.absent] — the default, and the state of every build with
  /// no policy file — constrains nothing.
  final PluginAllowlist _allowlist;

  /// Notified once per candidate plugin, refused or not.
  ///
  /// The audit producer's hook. Nullable so open core's own tests and any
  /// caller that does not audit pay nothing.
  final PluginLoadObserver? _onPluginLoad;

  final PluginLoaderLogger _log;

  // Tracks every successfully-loaded plugin so [dispose] (and a
  // subsequent rescan) can unregister the contributed decoders.
  final List<_LoadedPlugin> _loadedPlugins = <_LoadedPlugin>[];

  // Decoder ids that are already taken — populated as plugins register
  // so a second plugin contributing the same id is rejected.
  final Set<String> _knownDecoderIds = <String>{};

  bool _disposed = false;

  @override
  Future<List<DecoderPluginInfo>> scan() async {
    if (_disposed) return const <DecoderPluginInfo>[];

    // Re-running scan unloads anything we registered last time so
    // `Reload plugins` works without leaking duplicate ids on the next
    // call to register.
    _unloadAll();

    if (_pluginLoadingDisabled) {
      _log(
        Level.FINE,
        'plugin loading disabled in AppSettings — skipping discovery '
        '(filesystem not touched)',
      );
      return const <DecoderPluginInfo>[];
    }

    final directories = _resolver.resolveDirectories(
      userConfigured: _userConfiguredDirectories,
      envVarRaw: _envVarRaw,
    );

    // Seed the known-id set with anything already in the registry so
    // plugin contributions can never shadow built-in decoders.
    _knownDecoderIds
      ..clear()
      ..addAll(
        _registry.listDecoders().map((d) => d.id),
      );

    final results = <DecoderPluginInfo>[];
    final pathCtx = p.context;
    final visitedPaths = <String>{};

    for (final dir in directories) {
      Iterable<FileSystemEntity> entries;
      try {
        entries = dir.listSync();
      } on FileSystemException catch (e) {
        _log(
          Level.WARNING,
          'cannot list plugin directory ${dir.path}: ${e.message} — '
          'skipping',
        );
        continue;
      }

      // Sort by file name for deterministic test output.
      final files = entries.whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final ext = pathCtx.extension(file.path).toLowerCase();
        if (!_libraryExtensions.contains(ext)) continue;

        final absolute = pathCtx.normalize(pathCtx.absolute(file.path));
        if (!visitedPaths.add(absolute)) continue;

        final pluginId = absolute;

        // The organization's allowlist, ahead of every other gate.
        //
        // FIRST, and deliberately: `DynamicLibrary.open` runs the library's
        // initializers, so a plugin gets to execute code before anything this
        // process does with it. A check performed after opening would be a
        // check performed after the thing it exists to prevent. It also sits
        // ahead of the per-plugin disable, because the organization's decision
        // is not one a user's Settings toggle should be able to reorder.
        //
        // With no policy file `isConfigured` is false and this is one boolean
        // per file — every existing user, including the SigRok bridge, loads
        // exactly as before.
        if (_allowlist.isConfigured && !_allowlist.allowsFile(absolute)) {
          final digest = PluginAllowlist.digestOfFile(absolute);
          _log(
            Level.WARNING,
            digest == null
                ? 'refused ${pathCtx.basename(absolute)}: the organization’s '
                      'policy lists approved plugins by content hash and this '
                      'file could not be read to hash it'
                : 'refused ${pathCtx.basename(absolute)}: not in the '
                      'organization’s approved-plugin list '
                      '(${formatPluginDigest(digest)})',
          );
          _onPluginLoad?.call(
            PluginLoadEvent(
              displayName: pathCtx.basename(absolute),
              digest: digest,
              refused: true,
            ),
          );
          results.add(
            DecoderPluginInfo(
              pluginId: pluginId,
              displayName: pathCtx.basename(absolute),
              filePath: absolute,
              declaredAbiVersion: 0,
              loadStatus: DecoderPluginLoadStatus.notAllowlisted,
            ),
          );
          continue;
        }

        if (_perPluginDisabled[pluginId] ?? false) {
          results.add(
            DecoderPluginInfo(
              pluginId: pluginId,
              displayName: pathCtx.basename(absolute),
              filePath: absolute,
              declaredAbiVersion: 0,
              loadStatus: DecoderPluginLoadStatus.disabled,
            ),
          );
          continue;
        }

        _onPluginLoad?.call(
          PluginLoadEvent(
            displayName: pathCtx.basename(absolute),
            digest: PluginAllowlist.digestOfFile(absolute),
            refused: false,
          ),
        );
        results.add(_loadOne(absolute, pluginId));
      }
    }

    return results;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unloadAll();
  }

  void _unloadAll() {
    for (final loaded in _loadedPlugins) {
      loaded.decoderIds.forEach(_registry.unregister);
    }
    _loadedPlugins.clear();
    _knownDecoderIds
      ..clear()
      ..addAll(_registry.listDecoders().map((d) => d.id));
  }

  DecoderPluginInfo _loadOne(String absolutePath, String pluginId) {
    final fallbackName = p.context.basename(absolutePath);

    ffi.DynamicLibrary lib;
    try {
      lib = _opener(absolutePath);
    } on Object catch (e) {
      final msg = 'cannot open shared library "$absolutePath": $e';
      _log(Level.SEVERE, msg);
      return DecoderPluginInfo(
        pluginId: pluginId,
        displayName: fallbackName,
        filePath: absolutePath,
        declaredAbiVersion: 0,
        loadStatus: DecoderPluginLoadStatus.loadError,
        errorMessage: msg,
      );
    }

    final WavecruxDecoderAbi abi;
    try {
      abi = WavecruxDecoderAbi(lib);
    } on Object catch (e) {
      final msg = 'cannot bind plugin entry points in "$absolutePath": $e';
      _log(Level.SEVERE, msg);
      return DecoderPluginInfo(
        pluginId: pluginId,
        displayName: fallbackName,
        filePath: absolutePath,
        declaredAbiVersion: 0,
        loadStatus: DecoderPluginLoadStatus.missingSymbol,
        errorMessage: msg,
      );
    }

    int declaredVersion;
    try {
      declaredVersion = abi.wavecrux_decoder_abi_version();
    } on Object catch (e) {
      final msg =
          'plugin "$absolutePath" panicked from wavecrux_decoder_abi_version: $e';
      _log(Level.SEVERE, msg);
      return DecoderPluginInfo(
        pluginId: pluginId,
        displayName: fallbackName,
        filePath: absolutePath,
        declaredAbiVersion: 0,
        loadStatus: DecoderPluginLoadStatus.missingSymbol,
        errorMessage: msg,
      );
    }

    final declaredMajor = (declaredVersion >> 16) & 0xFFFF;
    if (declaredMajor != WAVECRUX_DECODER_ABI_MAJOR) {
      final msg =
          'plugin "$absolutePath" reports ABI major $declaredMajor; host '
          'requires $WAVECRUX_DECODER_ABI_MAJOR — rebuild against the '
          'current wavecrux_decoder.h';
      _log(Level.SEVERE, msg);
      return DecoderPluginInfo(
        pluginId: pluginId,
        displayName: fallbackName,
        filePath: absolutePath,
        declaredAbiVersion: declaredVersion,
        loadStatus: DecoderPluginLoadStatus.abiMismatch,
        errorMessage: msg,
      );
    }

    // Two-call register: first invocation passes a NULL-shaped buffer
    // so the plugin can size its slot count; second invocation receives
    // a buffer big enough to hold every decoder.
    final List<_RawDecoderDef> rawDefs;
    try {
      rawDefs = _invokeRegister(abi, absolutePath);
    } on _PluginLoadException catch (e) {
      _log(Level.SEVERE, e.message);
      return DecoderPluginInfo(
        pluginId: pluginId,
        displayName: fallbackName,
        filePath: absolutePath,
        declaredAbiVersion: declaredVersion,
        loadStatus: e.status,
        errorMessage: e.message,
      );
    } on Object catch (e) {
      final msg =
          'plugin "$absolutePath" panicked from wavecrux_decoder_register: $e';
      _log(Level.SEVERE, msg);
      return DecoderPluginInfo(
        pluginId: pluginId,
        displayName: fallbackName,
        filePath: absolutePath,
        declaredAbiVersion: declaredVersion,
        loadStatus: DecoderPluginLoadStatus.loadError,
        errorMessage: msg,
      );
    }

    if (rawDefs.isEmpty) {
      final msg =
          'plugin "$absolutePath" returned zero decoders from register — '
          'nothing to load';
      _log(Level.SEVERE, msg);
      return DecoderPluginInfo(
        pluginId: pluginId,
        displayName: fallbackName,
        filePath: absolutePath,
        declaredAbiVersion: declaredVersion,
        loadStatus: DecoderPluginLoadStatus.loadError,
        errorMessage: msg,
      );
    }

    final registered = <String>[];
    final firstDisplay = rawDefs.first.displayName;
    String? firstFailureMessage;

    for (final raw in rawDefs) {
      DecoderDefinition def;
      try {
        def = _adaptDefinition(raw);
      } on FormatException catch (e) {
        final detail =
            'plugin "$absolutePath" decoder "${raw.id}" has an invalid '
            'manifest: ${e.message}';
        firstFailureMessage ??= detail;
        _log(Level.WARNING, detail);
        continue;
      }

      if (_knownDecoderIds.contains(def.id)) {
        final detail =
            'plugin "$absolutePath" tried to register decoder id '
            '"${def.id}" which is already taken — registration rejected';
        firstFailureMessage ??= detail;
        _log(Level.WARNING, detail);
        continue;
      }

      final factory = _buildFactory(raw);
      // `userSupplied: true` — the id came from the plugin's manifest, so it is
      // the plugin author's vocabulary and must never reach telemetry verbatim.
      _registry.register(def, factory, userSupplied: true);
      _knownDecoderIds.add(def.id);
      registered.add(def.id);
    }

    if (registered.isEmpty) {
      // Every contribution was rejected — surface the first failure.
      final msg =
          firstFailureMessage ??
          'plugin "$absolutePath" produced no usable decoders';
      return DecoderPluginInfo(
        pluginId: pluginId,
        displayName: fallbackName,
        filePath: absolutePath,
        declaredAbiVersion: declaredVersion,
        loadStatus:
            firstFailureMessage != null &&
                firstFailureMessage.contains('invalid manifest')
            ? DecoderPluginLoadStatus.manifestInvalid
            : DecoderPluginLoadStatus.loadError,
        errorMessage: msg,
      );
    }

    _loadedPlugins.add(_LoadedPlugin(library: lib, decoderIds: registered));

    // Optional ABI 1.1 self-identification. A plugin contributing many
    // decoders (e.g. the SigRok bridge's ~130) can name itself rather
    // than borrowing its first decoder's display name. Absent symbols
    // fall back to the prior behavior.
    final reportedName = _readOptionalPluginString(
      lib,
      'wavecrux_decoder_plugin_name',
      absolutePath,
    );
    final reportedDescription = _readOptionalPluginString(
      lib,
      'wavecrux_decoder_plugin_description',
      absolutePath,
    );

    return DecoderPluginInfo(
      pluginId: pluginId,
      displayName: (reportedName != null && reportedName.isNotEmpty)
          ? reportedName
          : firstDisplay,
      filePath: absolutePath,
      declaredAbiVersion: declaredVersion,
      loadStatus: DecoderPluginLoadStatus.loaded,
      errorMessage: firstFailureMessage,
      registeredDecoderIds: List<String>.unmodifiable(registered),
      pluginDescription:
          (reportedDescription != null && reportedDescription.isNotEmpty)
          ? reportedDescription
          : null,
    );
  }

  /// Reads an optional `const char* (*)(void)` plugin self-description
  /// symbol. Returns null when the symbol is absent (older ABI 1.0
  /// plugins), returns NULL at runtime, or the call panics — every one
  /// of which is a benign "plugin declined to identify itself" outcome
  /// that must not fail the load.
  String? _readOptionalPluginString(
    ffi.DynamicLibrary lib,
    String symbol,
    String absolutePath,
  ) {
    try {
      if (!lib.providesSymbol(symbol)) return null;
      final fn = lib
          .lookupFunction<
            ffi.Pointer<ffi.Char> Function(),
            ffi.Pointer<ffi.Char> Function()
          >(symbol);
      final ptr = fn();
      if (ptr == ffi.nullptr) return null;
      return ptr.cast<Utf8>().toDartString();
    } on Object catch (e) {
      _log(
        Level.WARNING,
        'plugin "$absolutePath" failed reading optional symbol "$symbol": $e',
      );
      return null;
    }
  }

  /// Calls `wavecrux_decoder_register` using the standard C two-pass
  /// idiom: first to discover the slot count, then with a buffer large
  /// enough to hold every decoder.
  List<_RawDecoderDef> _invokeRegister(
    WavecruxDecoderAbi abi,
    String absolutePath,
  ) {
    final countPtr = calloc<ffi.Size>();
    try {
      countPtr.value = 0;
      var rc = abi.wavecrux_decoder_register(ffi.nullptr, countPtr);
      if (rc != WC_DECODER_OK && rc != WC_DECODER_NEED_MORE_SLOTS) {
        throw _PluginLoadException(
          DecoderPluginLoadStatus.loadError,
          'plugin "$absolutePath" returned register-error rc=$rc on the '
          'sizing call',
        );
      }

      final slotCount = countPtr.value;
      if (slotCount == 0) {
        return const <_RawDecoderDef>[];
      }

      final defs = calloc<WcDecoderDef>(slotCount);
      try {
        countPtr.value = slotCount;
        rc = abi.wavecrux_decoder_register(defs, countPtr);
        if (rc != WC_DECODER_OK) {
          throw _PluginLoadException(
            DecoderPluginLoadStatus.loadError,
            'plugin "$absolutePath" returned register-error rc=$rc on the '
            'populate call',
          );
        }
        final populated = countPtr.value;
        final out = <_RawDecoderDef>[];
        for (var i = 0; i < populated; i++) {
          final entry = (defs + i).ref;
          out.add(_RawDecoderDef.fromStruct(entry));
        }
        return out;
      } finally {
        calloc.free(defs);
      }
    } finally {
      calloc.free(countPtr);
    }
  }

  DecoderDefinition _adaptDefinition(_RawDecoderDef raw) {
    final Map<String, Object?> manifest;
    try {
      final decoded = jsonDecode(raw.manifestJson);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException(
          'manifest top-level value must be a JSON object',
        );
      }
      manifest = decoded;
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      throw FormatException('invalid manifest JSON: $e');
    }

    final required = _decodeBindings(manifest['signals']);
    final optional = _decodeBindings(manifest['optional_signals']);
    final params = _decodeParameters(manifest['parameters']);
    final category = _decodeCategory(manifest['category']);
    final tier = _decodeTier(manifest['required_tier']);

    // Stamp the binding declaration order onto the raw def so the
    // per-instance decoder can pack signal values into the WcSample
    // bits buffer in the order the plugin declared them. Required
    // bindings come first, then optional bindings — same order the
    // host's binding dialog presents them.
    raw.attachBindings(<_BindingSpec>[
      for (final b in required)
        _BindingSpec(name: b.name, bitWidth: b.bitWidth ?? 1, optional: false),
      for (final b in optional)
        _BindingSpec(name: b.name, bitWidth: b.bitWidth ?? 1, optional: true),
    ]);

    return DecoderDefinition(
      id: raw.id,
      displayName: raw.displayName,
      description: (manifest['description'] as String?) ?? '',
      requiredSignals: required,
      optionalSignals: optional,
      parameters: params,
      category: category,
      requiredTier: tier,
    );
  }

  List<SignalBinding> _decodeBindings(Object? raw) {
    if (raw == null) return const <SignalBinding>[];
    if (raw is! List) {
      throw const FormatException('signals must be a JSON array');
    }
    return raw
        .map<SignalBinding>((entry) {
          if (entry is! Map) {
            throw const FormatException(
              'each signal entry must be a JSON object',
            );
          }
          final name = entry['name'];
          if (name is! String || name.isEmpty) {
            throw const FormatException('signal entry is missing "name"');
          }
          final description = (entry['description'] as String?) ?? '';
          final width = entry['bit_width'];
          final int? bitWidth;
          if (width == null) {
            bitWidth = null;
          } else if (width is int) {
            bitWidth = width;
          } else {
            throw FormatException(
              'signal "$name" has non-integer bit_width: $width',
            );
          }
          return SignalBinding(
            name: name,
            description: description,
            bitWidth: bitWidth,
          );
        })
        .toList(growable: false);
  }

  List<DecoderParameter> _decodeParameters(Object? raw) {
    if (raw == null) return const <DecoderParameter>[];
    if (raw is! List) {
      throw const FormatException('parameters must be a JSON array');
    }
    return raw
        .map<DecoderParameter>((entry) {
          if (entry is! Map) {
            throw const FormatException(
              'each parameter entry must be a JSON object',
            );
          }
          final name = entry['name'];
          if (name is! String || name.isEmpty) {
            throw const FormatException('parameter entry is missing "name"');
          }
          final kind = entry['kind'];
          if (kind is! String) {
            throw FormatException('parameter "$name" is missing "kind"');
          }
          final type = _parameterTypeOf(kind);
          final enumValues = (entry['enum_values'] as List?)?.cast<String>();
          return DecoderParameter(
            name: name,
            type: type,
            defaultValue: entry['default'] ?? _defaultForType(type),
            description: (entry['description'] as String?) ?? '',
            displayName: entry['display_name'] as String?,
            enumValues: enumValues,
            enumLabels: _decodeEnumLabels(
              name,
              entry['enum_labels'],
              enumValues,
            ),
          );
        })
        .toList(growable: false);
  }

  /// `enum_labels` as a value-to-label map. The documented shape is a JSON
  /// object keyed by value; a JSON array is read as labels for
  /// `enum_values` in the same order, the shape a plugin author reaches
  /// for first. Anything else names the parameter in a [FormatException]
  /// rather than failing a cast.
  Map<String, String>? _decodeEnumLabels(
    String parameter,
    Object? raw,
    List<String>? enumValues,
  ) {
    if (raw == null) return null;
    if (raw is Map) {
      return {
        for (final MapEntry(:key, :value) in raw.entries)
          '$key': value is String
              ? value
              : throw FormatException(
                  'parameter "$parameter": enum_labels values must be '
                  'strings',
                ),
      };
    }
    if (raw is List) {
      if (enumValues == null || raw.length != enumValues.length) {
        throw FormatException(
          'parameter "$parameter": an enum_labels array needs one label '
          'per enum_values entry; use an object {"<value>": "<label>"} '
          'otherwise',
        );
      }
      return {
        for (var i = 0; i < raw.length; i++)
          enumValues[i]: raw[i] is String
              ? raw[i] as String
              : throw FormatException(
                  'parameter "$parameter": enum_labels entries must be '
                  'strings',
                ),
      };
    }
    throw FormatException(
      'parameter "$parameter": enum_labels must be an object '
      '{"<value>": "<label>"}',
    );
  }

  DecoderParameterType _parameterTypeOf(String kind) {
    switch (kind) {
      case 'bool':
      case 'boolean':
        return DecoderParameterType.boolean;
      case 'int':
      case 'integer':
        return DecoderParameterType.integer;
      case 'enum':
      case 'enumeration':
        return DecoderParameterType.enumeration;
      case 'string':
        return DecoderParameterType.string;
      default:
        throw FormatException('unknown parameter kind "$kind"');
    }
  }

  Object _defaultForType(DecoderParameterType type) {
    switch (type) {
      case DecoderParameterType.boolean:
        return false;
      case DecoderParameterType.integer:
        return 0;
      case DecoderParameterType.enumeration:
      case DecoderParameterType.string:
        return '';
    }
  }

  DecoderCategory _decodeCategory(Object? raw) {
    if (raw == null) return DecoderCategory.userPlugin;
    if (raw is! String) {
      throw FormatException('category must be a string, got $raw');
    }
    for (final value in DecoderCategory.values) {
      if (value.name == raw) return value;
    }
    return DecoderCategory.userPlugin;
  }

  LicenseTier _decodeTier(Object? raw) {
    if (raw == null) return LicenseTier.openCore;
    if (raw is! String) {
      throw FormatException('required_tier must be a string, got $raw');
    }
    for (final value in LicenseTier.values) {
      if (value.name == raw) return value;
    }
    return LicenseTier.openCore;
  }

  DecoderFactory _buildFactory(_RawDecoderDef raw) {
    return (DecoderConfig config) {
      return _PluginProtocolDecoder(raw: raw, config: config);
    };
  }
}

/// Carrier for the not-yet-disposed [DynamicLibrary] handle of a
/// successfully loaded plugin plus the decoder ids it contributed.
class _LoadedPlugin {
  _LoadedPlugin({required this.library, required this.decoderIds});
  // Held so the library is not unloaded by GC (DynamicLibrary itself
  // is reference-counted by the OS; keeping the reference alive is
  // sufficient on every supported platform).
  final ffi.DynamicLibrary library;
  final List<String> decoderIds;
}

/// Pure-Dart copy of a plugin's `WcDecoderDef` entry. Strings are
/// copied out of the plugin's `.rodata` so the loader does not depend
/// on the plugin keeping them mapped while Dart code runs.
class _RawDecoderDef {
  _RawDecoderDef({
    required this.id,
    required this.displayName,
    required this.manifestJson,
    required this.create,
    required this.feed,
    required this.flush,
    required this.destroy,
  });

  factory _RawDecoderDef.fromStruct(WcDecoderDef entry) {
    return _RawDecoderDef(
      id: entry.id.cast<Utf8>().toDartString(),
      displayName: entry.display_name.cast<Utf8>().toDartString(),
      manifestJson: entry.manifest_json.cast<Utf8>().toDartString(),
      create: entry.create,
      feed: entry.feed,
      flush: entry.flush,
      destroy: entry.destroy,
    );
  }

  final String id;
  final String displayName;
  final String manifestJson;
  final WcDecoderCreateFn create;
  final WcDecoderFeedFn feed;
  final WcDecoderFlushFn flush;
  final WcDecoderDestroyFn destroy;

  // Late-bound binding declaration order, populated by
  // `_adaptDefinition` once the manifest JSON has been parsed.
  // `_PluginProtocolDecoder` reads this to pack signal values into
  // `WcSample.bits_ptr` in the order the plugin declared them.
  List<_BindingSpec> bindings = const <_BindingSpec>[];

  void attachBindings(List<_BindingSpec> b) {
    bindings = List<_BindingSpec>.unmodifiable(b);
  }
}

/// Manifest-derived metadata about a single signal binding the plugin
/// declared. The loader keeps the bindings in declaration order so it
/// can pack signal values into `WcSample.bits_ptr` deterministically.
class _BindingSpec {
  const _BindingSpec({
    required this.name,
    required this.bitWidth,
    required this.optional,
  });
  final String name;
  final int bitWidth;
  final bool optional;
}

/// Plugin-backed [ProtocolDecoder] adapter. Each invocation of
/// [decode] constructs a fresh native handle, walks the bound-signal
/// changes, fans them through `feed`, drains transactions via
/// `flush`, and tears down the handle.
class _PluginProtocolDecoder implements ProtocolDecoder {
  _PluginProtocolDecoder({required _RawDecoderDef raw, required this.config})
    : _raw = raw;

  final _RawDecoderDef _raw;
  final DecoderConfig config;

  @override
  DecoderDefinition get definition {
    // The factory constructs us with a [_RawDecoderDef] but the
    // [ProtocolDecoder] interface expects a [DecoderDefinition]. We
    // never call this getter from production code (the registry holds
    // the canonical definition), but providing a minimal shape keeps
    // the contract honest.
    return DecoderDefinition(
      id: _raw.id,
      displayName: _raw.displayName,
      description: '',
      requiredSignals: const <SignalBinding>[],
      category: DecoderCategory.userPlugin,
    );
  }

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final create = _raw.create
        .asFunction<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>)>();
    final feed = _raw.feed
        .asFunction<
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<WcSample>,
            ffi.Pointer<WcTransaction>,
            ffi.Pointer<ffi.Size>,
          )
        >();
    final flush = _raw.flush
        .asFunction<
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<WcTransaction>,
            ffi.Pointer<ffi.Size>,
          )
        >();
    final destroy = _raw.destroy
        .asFunction<void Function(ffi.Pointer<ffi.Void>)>();

    // The instance's lifecycle is one rule: `destroy` runs exactly once for
    // every handle `create` returned, and never for a NULL one. The ABI
    // forbids touching a handle after `destroy`, so a second call is a double
    // free in any plugin that frees its state there. Everything that does not
    // need the instance, allocations included, is done before `create`, and
    // everything after it sits inside the one `try` whose `finally` destroys
    // it. No other path calls `destroy`.
    final transactions = <DecodedTransaction>[];

    // Build the unified change timeline across every bound signal.
    final timestamps = _collectTimestamps(
      changesQuery: changesQuery,
      startTime: startTime,
      endTime: endTime,
    );

    // Compute the femtosecond-per-tick factor from the file's
    // timescale so the plugin sees `WcSample.timestamp_fs` as actual
    // femtoseconds, matching the documented header contract. Plugins
    // are protocol-aware and need physical units to time pulse
    // durations (e.g. 1-Wire's 480 µs reset window, USB's 12 MHz bit
    // period). Falls back to 1 ns/tick (1e6 fs/tick) when the file
    // declares no timescale — same fallback the SVA service uses.
    final fsPerTick = _fsPerTick(timescale);

    // Walk the manifest bindings in declaration order. Only bindings
    // the host actually wired up (present in `config.signalBindings`)
    // contribute bits — unbound optionals are skipped. The total
    // signal-bit count drives both `WcSample.bit_width` and the buffer
    // size (the documented 4-state encoding uses 2 buffer bits per
    // signal bit, so the buffer is `(2 * bitsPerSample + 7) / 8` bytes).
    final activeBindings = <_BindingSpec>[];
    var bitsPerSample = 0;
    for (final spec in _raw.bindings) {
      if (config.signalBindings.containsKey(spec.name)) {
        activeBindings.add(spec);
        bitsPerSample += spec.bitWidth;
      }
    }
    // 32-byte minimum keeps the legacy test_plugin.c (which doesn't read
    // bits_ptr but does receive the buffer) operating identically and
    // gives small-bus decoders room without re-allocating.
    final encodedBytes = (2 * bitsPerSample + 7) >> 3;
    final scratchBytes = encodedBytes < 32 ? 32 : encodedBytes;

    final samplePtr = calloc<WcSample>();
    final bitsPtr = calloc<ffi.Uint8>(scratchBytes);
    final txCountPtr = calloc<ffi.Size>();
    var txBufferLen = 16;
    var txBuffer = calloc<WcTransaction>(txBufferLen);

    ffi.Pointer<ffi.Void> handle = ffi.nullptr;
    try {
      final configJsonPtr = _serializeConfig(config).toNativeUtf8();
      try {
        handle = create(configJsonPtr.cast<ffi.Char>());
      } on Object catch (e) {
        _pluginLog.severe(
          'plugin decoder "${_raw.id}" panicked from create: $e',
        );
        return const <DecodedTransaction>[];
      } finally {
        calloc.free(configJsonPtr);
      }
      if (handle == ffi.nullptr) {
        _pluginLog.severe(
          'plugin decoder "${_raw.id}" returned NULL from create',
        );
        return const <DecodedTransaction>[];
      }

      for (final ts in timestamps) {
        // Zero the buffer between samples and re-pack the current
        // value of every bound signal at this timestamp using the
        // 4-state encoding documented in `wavecrux_decoder.h` — two
        // buffer bits per signal bit, low bit = level (0 / 1), high
        // bit = unknown flag (set for X / Z). Plugins that only care
        // about the level read `bits_ptr[byte] & (1 << shift)` and
        // ignore the unknown flag; plugins that need to disambiguate
        // X / Z from logic levels mask the high bit.
        for (var i = 0; i < scratchBytes; i++) {
          (bitsPtr + i).value = 0;
        }
        var bitOffset = 0;
        for (final spec in activeBindings) {
          final raw = query(spec.name, ts);
          _packBindingValue(
            buffer: bitsPtr,
            bufferLenBytes: scratchBytes,
            bitOffset: bitOffset,
            bitWidth: spec.bitWidth,
            value: raw,
          );
          bitOffset += spec.bitWidth;
        }
        final tsFs = ts < 0 ? 0 : ts * fsPerTick;
        samplePtr.ref
          ..timestamp_fs = tsFs
          ..bits_ptr = bitsPtr
          ..bit_width = bitsPerSample;
        // The struct's reserved trailing field is zero-initialised by
        // calloc and inaccessible from Dart (private setter on the
        // ffigen-generated struct).

        var pending = true;
        while (pending) {
          txCountPtr.value = txBufferLen;
          int rc;
          try {
            rc = feed(handle, samplePtr, txBuffer, txCountPtr);
          } on Object catch (e) {
            _pluginLog.severe(
              'plugin decoder "${_raw.id}" panicked from feed: $e',
            );
            return transactions;
          }
          if (rc == WC_DECODER_NEED_MORE_SLOTS) {
            calloc.free(txBuffer);
            txBufferLen = txCountPtr.value <= 0
                ? txBufferLen * 2
                : txCountPtr.value;
            txBuffer = calloc<WcTransaction>(txBufferLen);
            continue;
          }
          if (rc != WC_DECODER_OK) {
            _pluginLog.severe(
              'plugin decoder "${_raw.id}" returned feed-error rc=$rc',
            );
            return transactions;
          }
          _drainTransactions(
            txBuffer,
            txCountPtr.value,
            transactions,
            fsPerTick,
          );
          pending = false;
        }
      }

      // Final flush to drain any in-flight state.
      var pending = true;
      while (pending) {
        txCountPtr.value = txBufferLen;
        int rc;
        try {
          rc = flush(handle, txBuffer, txCountPtr);
        } on Object catch (e) {
          _pluginLog.severe(
            'plugin decoder "${_raw.id}" panicked from flush: $e',
          );
          break;
        }
        if (rc == WC_DECODER_NEED_MORE_SLOTS) {
          calloc.free(txBuffer);
          txBufferLen = txCountPtr.value <= 0
              ? txBufferLen * 2
              : txCountPtr.value;
          txBuffer = calloc<WcTransaction>(txBufferLen);
          continue;
        }
        if (rc != WC_DECODER_OK) {
          _pluginLog.severe(
            'plugin decoder "${_raw.id}" returned flush-error rc=$rc',
          );
          break;
        }
        _drainTransactions(
          txBuffer,
          txCountPtr.value,
          transactions,
          fsPerTick,
        );
        pending = false;
      }
    } finally {
      if (handle != ffi.nullptr) {
        try {
          destroy(handle);
        } on Object catch (e) {
          _pluginLog.warning(
            'plugin decoder "${_raw.id}" panicked from destroy: $e',
          );
        }
      }
      calloc
        ..free(samplePtr)
        ..free(bitsPtr)
        ..free(txCountPtr)
        ..free(txBuffer);
    }

    return transactions;
  }

  /// The instance configuration handed to the plugin's `create`.
  ///
  /// `decoder_id` names the decoder being instantiated: a plugin that
  /// serves several decoders through one entry point (the Sigrok bridge
  /// shim) selects the decoder from it and returns NULL without it.
  /// Parameter values travel under both `parameters` (the documented
  /// key) and `options` (the key the Sigrok bridge reads).
  String _serializeConfig(DecoderConfig config) {
    return jsonEncode(<String, Object?>{
      'decoder_id': _raw.id,
      'signal_bindings': config.signalBindings,
      'parameters': config.parameters,
      'options': config.parameters,
    });
  }

  /// Femtoseconds-per-tick for the file's [Timescale]. Falls back to
  /// 1 ns / tick (= 10^6 fs / tick) when the file declares no
  /// timescale or the unit is unknown — same fallback WaveCrux's SVA
  /// service uses for the same reason. Returns an `int` because every
  /// supported unit / factor combination yields an integer fs count.
  int _fsPerTick(Timescale? timescale) {
    if (timescale == null) return 1000000; // 1 ns default
    final exp = timescale.unit.exponent;
    if (exp == null) return 1000000;
    // fs/tick = factor × 10^(exp + 15). All supported (factor, unit)
    // combinations produce a non-negative exponent, so plain integer
    // multiplication is safe.
    final shift = exp + 15;
    if (shift < 0) return 1000000;
    var multiplier = 1;
    for (var i = 0; i < shift; i++) {
      multiplier *= 10;
    }
    return timescale.factor * multiplier;
  }

  /// [fs] in whole ticks, rounded down. A `uint64` above 2^63 reaches
  /// Dart as a negative `int`, so that range divides as unsigned.
  static int _fsToTicksFloor(int fs, int fsPerTick) {
    if (fs >= 0) return fs ~/ fsPerTick;
    final unsigned = BigInt.from(fs).toUnsigned(64);
    return (unsigned ~/ BigInt.from(fsPerTick)).toInt();
  }

  /// [fs] in whole ticks, rounded up.
  static int _fsToTicksCeil(int fs, int fsPerTick) {
    final exact = fs >= 0
        ? fs % fsPerTick == 0
        : BigInt.from(fs).toUnsigned(64) % BigInt.from(fsPerTick) ==
              BigInt.zero;
    final floor = _fsToTicksFloor(fs, fsPerTick);
    return exact ? floor : floor + 1;
  }

  /// Pack a single binding's value into the WcSample bits buffer using
  /// the documented 4-state encoding: 2 buffer bits per signal bit,
  /// low bit = level, high bit = unknown flag (set for X / Z values).
  ///
  /// VCD scalar values arrive as a single character (`"0"`, `"1"`,
  /// `"x"`, `"z"`); vector values arrive as MSB-first strings (e.g.
  /// `"01101"` for the 5-bit literal 13). Strings shorter than the
  /// declared bit width are zero-extended on the MSB side, mirroring
  /// VCD's own zero-extension rule. A null `value` (signal not yet
  /// loaded) packs as zeros.
  void _packBindingValue({
    required ffi.Pointer<ffi.Uint8> buffer,
    required int bufferLenBytes,
    required int bitOffset,
    required int bitWidth,
    required String? value,
  }) {
    if (bitWidth <= 0) return;
    final raw = value;
    for (var i = 0; i < bitWidth; i++) {
      // LSB at bit position 0; MSB at bit position bitWidth-1.
      // The VCD value string is MSB-first, so signal bit i comes from
      // raw[raw.length - 1 - i] (or zero if the string is shorter).
      var level = false;
      var unknown = false;
      if (raw != null && raw.isNotEmpty) {
        final idx = raw.length - 1 - i;
        if (idx >= 0) {
          final c = raw.codeUnitAt(idx);
          // '0' = 0x30, '1' = 0x31, 'x'/'X' = 0x78/0x58, 'z'/'Z' = 0x7A/0x5A.
          if (c == 0x31) {
            level = true;
          } else if (c == 0x78 || c == 0x58) {
            unknown = true;
          } else if (c == 0x7A || c == 0x5A) {
            unknown = true;
          }
        }
      }
      // 2 buffer bits per signal bit at offset (bitOffset + i).
      final encodedBitPos = (bitOffset + i) * 2;
      final byteIndex = encodedBitPos >> 3;
      final shift = encodedBitPos & 7;
      if (byteIndex >= bufferLenBytes) return; // defence against short buf
      var b = (buffer + byteIndex).value;
      if (level) {
        b |= 1 << shift;
      }
      if (unknown && shift + 1 < 8) {
        b |= 1 << (shift + 1);
      } else if (unknown && byteIndex + 1 < bufferLenBytes) {
        // The unknown bit straddles a byte boundary — write it into the
        // next byte.
        var b2 = (buffer + byteIndex + 1).value;
        b2 |= 1;
        (buffer + byteIndex + 1).value = b2;
      }
      (buffer + byteIndex).value = b;
    }
  }

  List<int> _collectTimestamps({
    required SignalChangesQuery changesQuery,
    required int startTime,
    required int endTime,
  }) {
    final stamps = <int>{};
    for (final logical in config.signalBindings.keys) {
      try {
        final changes = changesQuery(logical, startTime, endTime);
        for (final entry in changes) {
          stamps.add(entry.$1);
        }
      } on Object catch (_) {
        // The host sometimes can't materialise changes for a logical
        // name (signal not yet loaded). Skip that signal — the test
        // plugin can still receive at least the start-time tick below.
      }
    }
    if (stamps.isEmpty) {
      stamps.add(startTime);
    }
    final sorted = stamps.toList()..sort();
    return sorted;
  }

  /// Copies the plugin's transactions into [out], converting their
  /// femtosecond times back into the file's ticks.
  ///
  /// The header defines `start_fs` / `end_fs` as femtoseconds, the same
  /// unit `decode` converts `WcSample.timestamp_fs` into, while every
  /// [DecodedTransaction] is placed in ticks. The start rounds down and
  /// the end rounds up, so a transaction shorter than one tick still
  /// covers the tick it happened in.
  void _drainTransactions(
    ffi.Pointer<WcTransaction> buffer,
    int count,
    List<DecodedTransaction> out,
    int fsPerTick,
  ) {
    for (var i = 0; i < count; i++) {
      final tx = (buffer + i).ref;
      final label = tx.label.cast<Utf8>().toDartString();
      final fieldsJson = tx.fields_json.cast<Utf8>().toDartString();
      final fields = _parseFieldsJson(fieldsJson);
      out.add(
        DecodedTransaction(
          startTime: _fsToTicksFloor(tx.start_fs, fsPerTick),
          endTime: _fsToTicksCeil(tx.end_fs, fsPerTick),
          label: label,
          fields: fields,
          isError: tx.is_error != 0,
        ),
      );
    }
  }

  Map<String, String> _parseFieldsJson(String raw) {
    if (raw.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      final out = <String, String>{};
      decoded.forEach((key, value) {
        if (key is String) {
          out[key] = value?.toString() ?? '';
        }
      });
      return out;
    } on FormatException {
      return const <String, String>{};
    }
  }
}

/// Internal sentinel used to surface a load failure with a typed
/// status from helper methods inside [FfiDecoderLoader._loadOne].
class _PluginLoadException implements Exception {
  _PluginLoadException(this.status, this.message);
  final DecoderPluginLoadStatus status;
  final String message;
}
