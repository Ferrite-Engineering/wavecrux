// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A single tab entry in the last-session manifest.
///
/// Captures only the information needed to restore the tab on next launch:
/// the file path (which tells us what waveform to load) and the optional
/// session file path (which tells us where to restore signals/cursors/zoom).
///
/// Pure Dart — no Flutter imports.
@immutable
class LastSessionTab {
  const LastSessionTab({
    required this.filePath,
    this.sessionFilePath,
  });

  /// Deserializes from the JSON map stored inside [LastSessionManifest].
  factory LastSessionTab.fromJson(Map<String, Object?> json) {
    return LastSessionTab(
      filePath: json['filePath'] as String? ?? '',
      sessionFilePath: json['sessionFilePath'] as String?,
    );
  }

  /// The absolute path of the waveform file this tab was showing.
  final String filePath;

  /// The `.wavecrux` session file associated with this tab, if any.
  final String? sessionFilePath;

  Map<String, Object?> toJson() => {
    'filePath': filePath,
    if (sessionFilePath != null) 'sessionFilePath': sessionFilePath,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LastSessionTab &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          sessionFilePath == other.sessionFilePath;

  @override
  int get hashCode => Object.hash(filePath, sessionFilePath);

  @override
  String toString() =>
      'LastSessionTab(filePath: $filePath, sessionFilePath: $sessionFilePath)';
}

/// Lightweight manifest written to `{appSupportDir}/last_session.json` on
/// quit and read on the next cold start to restore the previous workspace.
///
/// The manifest only stores enough information to *reopen* tabs; per-tab
/// state (cursor, zoom, signal groups) is fully captured in each tab's
/// `.wavecrux` session file.
///
/// Pure Dart — no Flutter imports.
@immutable
class LastSessionManifest {
  const LastSessionManifest({required this.tabs});

  /// Deserializes from the JSON object stored in `last_session.json`.
  factory LastSessionManifest.fromJson(Map<String, Object?> json) {
    final rawTabs = json['tabs'];
    final tabs = <LastSessionTab>[];
    if (rawTabs is List) {
      for (final raw in rawTabs) {
        if (raw is Map<String, Object?>) {
          tabs.add(LastSessionTab.fromJson(raw));
        }
      }
    }
    return LastSessionManifest(tabs: List.unmodifiable(tabs));
  }

  /// An empty manifest with no tabs to restore.
  static const empty = LastSessionManifest(tabs: []);

  /// Ordered list of tabs to restore (top-to-bottom → left-to-right in tab bar).
  final List<LastSessionTab> tabs;

  Map<String, Object?> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LastSessionManifest) return false;
    if (other.tabs.length != tabs.length) return false;
    for (var i = 0; i < tabs.length; i++) {
      if (other.tabs[i] != tabs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(tabs);

  @override
  String toString() => 'LastSessionManifest(tabs: $tabs)';
}
