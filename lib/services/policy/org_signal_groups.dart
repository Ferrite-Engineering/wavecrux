// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// `products.wavecrux.signalGroups` — the organization's standard signal
/// groupings.
///
/// **Registering a key is not implementing the feature it configures.** C5
/// registered this one and nothing read it. This is the feature.
///
/// ### What it buys
///
/// A team looking at the same SoC every day groups the same signals every day:
/// the AXI write channel, the reset tree, the DFT chain. Today each engineer
/// rebuilds those groups by hand on every new capture, and two engineers'
/// groupings drift apart — which is exactly the state a design review does not
/// want to start from.
///
/// ### Patterns, not signal lists
///
/// A group is a **name plus glob patterns**, matched against the loaded
/// waveform's signal paths. A literal list of paths would be an organization
/// standard that only fits one design and one hierarchy; `top.*.axi_aw*` fits
/// the family. Two wildcards, deliberately:
///
/// * `*` matches within one path segment
/// * `**` matches across segments
///
/// That is the whole vocabulary. A regular expression would be more powerful
/// and would put a language nobody can review into a signed file — and a
/// mistyped one silently matches nothing, which is a group that appears empty
/// for reasons no engineer can see.
///
/// ### It offers; it does not impose
///
/// The organization's groups are applied when signals are added, and the user
/// may then move, rename, ungroup or delete them exactly as if they had made
/// them. Under a **locked** key they are re-applied on each add rather than
/// frozen in place — locking says *these groups exist*, not *this pane may not
/// be rearranged*, and a viewer that fought the user's own layout would be
/// worse than no feature.
library;

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/core/license/enterprise_feature_gate.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/services/policy/org_object_policy_key.dart';

/// One organization-standard grouping.
@immutable
final class OrgSignalGroup {
  /// Creates an [OrgSignalGroup].
  const OrgSignalGroup({
    required this.name,
    required this.patterns,
    this.collapsed = false,
  });

  /// The group header's name.
  final String name;

  /// Glob patterns matched against signal paths.
  final List<String> patterns;

  /// Whether the group starts collapsed.
  ///
  /// Worth having: the reset tree is a group you want to *exist* and rarely
  /// want to *look at*, and a standard grouping that expanded forty signals
  /// nobody asked for would be uninstalled within a day.
  final bool collapsed;

  /// Whether [signalPath] belongs in this group.
  bool matches(String signalPath) {
    for (final pattern in patterns) {
      if (globMatches(pattern, signalPath)) return true;
    }
    return false;
  }
}

/// The organization's groupings.
@immutable
final class OrgSignalGroups {
  /// Creates an [OrgSignalGroups].
  const OrgSignalGroups({required this.groups, required this.locked});

  /// Parses the policy value.
  ///
  /// Shape: a list of `{ "name": …, "patterns": [...], "collapsed": bool }`.
  /// An entry missing a name or with no usable pattern is dropped rather than
  /// failing the key — one malformed group must not cost the other five.
  factory OrgSignalGroups.fromPolicyEntry(OrgPolicyEntry? entry) {
    final raw = entry?.value;
    if (raw is! List) return none;
    final groups = <OrgSignalGroup>[];
    for (final element in raw) {
      if (element is! Map<String, Object?>) continue;
      final name = element['name'];
      if (name is! String || name.trim().isEmpty) continue;
      final patternsRaw = element['patterns'];
      if (patternsRaw is! List) continue;
      final patterns = <String>[
        for (final pattern in patternsRaw)
          if (pattern is String && pattern.trim().isNotEmpty) pattern.trim(),
      ];
      if (patterns.isEmpty) continue;
      final collapsed = element['collapsed'];
      groups.add(
        OrgSignalGroup(
          name: name.trim(),
          patterns: List<String>.unmodifiable(patterns),
          collapsed: collapsed is bool && collapsed,
        ),
      );
    }
    if (groups.isEmpty) return none;
    return OrgSignalGroups(
      groups: List<OrgSignalGroup>.unmodifiable(groups),
      locked: entry!.locked,
    );
  }

  /// The organization set nothing.
  static const OrgSignalGroups none = OrgSignalGroups(
    groups: <OrgSignalGroup>[],
    locked: false,
  );

  /// The groupings, in the order the file declares them.
  ///
  /// Order is honoured rather than sorted: an administrator listing the reset
  /// tree last meant it to be last.
  final List<OrgSignalGroup> groups;

  /// Whether the organization locked them.
  final bool locked;

  /// Whether the organization configured anything.
  bool get isEmpty => groups.isEmpty;

  /// The first group [signalPath] belongs to, or `null`.
  ///
  /// **First, not every.** A signal in two groups would have to be duplicated
  /// or arbitrarily assigned, and duplicating a trace in a waveform viewer is
  /// how a reader ends up comparing a signal against itself. Declaration order
  /// is the tie-break, which makes overlap a thing an administrator controls
  /// rather than a thing that surprises them.
  OrgSignalGroup? groupFor(String signalPath) {
    for (final group in groups) {
      if (group.matches(signalPath)) return group;
    }
    return null;
  }
}

/// Matches [path] against a glob [pattern].
///
/// `*` matches within one `.`-separated segment; `**` matches across segments.
/// Everything else is literal, including regex metacharacters — a pattern in a
/// signed file must mean what it looks like it means.
bool globMatches(String pattern, String path) {
  final buffer = StringBuffer('^');
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == '*') {
      if (i + 1 < pattern.length && pattern[i + 1] == '*') {
        buffer.write('.*');
        i++;
      } else {
        buffer.write('[^.]*');
      }
      continue;
    }
    buffer.write(RegExp.escape(char));
  }
  buffer.write(r'$');
  return RegExp(buffer.toString()).hasMatch(path);
}

/// The organization's signal groupings, from the signed policy file.
///
/// Resolves to [OrgSignalGroups.none] with no policy file, which is every
/// default install — signals are added exactly as they were before. Also
/// [OrgSignalGroups.none] on a seat whose tier does not include the
/// Enterprise administration surface, with the tier decided before the parse
/// so nobody is sent to fix a file a licence would refuse anyway; the
/// withheld case is reported through `orgPolicyWithheldByTierProvider`.
final orgSignalGroupsProvider = Provider<OrgSignalGroups>((ref) {
  if (!enterpriseFeatureUnlocked(
    beta: ref.watch(betaPeriodProvider),
    tier: ref.watch(licenseTierProvider),
  )) {
    return OrgSignalGroups.none;
  }
  return OrgSignalGroups.fromPolicyEntry(
    readOrgPolicyEntry(
      ref.watch(cruxPolicyProvider).document.products,
      productId: WaveCruxPolicyKeys.productId,
      key: WaveCruxPolicyKeys.signalGroups,
    ),
  );
}, name: 'orgSignalGroupsProvider');

/// Arranges [entries] into the organization's standard groups.
///
/// Returns the entries unchanged when the organization configured nothing,
/// which is every default install — so this is one early return on the hot
/// "Add All in Scope" path rather than a cost every user pays.
///
/// **Ungrouped signals keep their order and come last.** A signal the
/// organization did not anticipate must not vanish into a catch-all or be
/// silently reordered away from its neighbours; it stays where it was,
/// relative to the others like it, after the groups.
///
/// **Groups the capture has no signals for are omitted**, not rendered empty.
/// An organization standard covering the whole SoC would otherwise put twelve
/// empty headers above a capture of one block, which reads as a feature that
/// does not work.
List<SignalEntry> applyOrgSignalGroups(
  List<SignalEntry> entries,
  OrgSignalGroups org,
) {
  if (org.isEmpty) return entries;

  final grouped = <String, List<SignalEntry>>{};
  final ungrouped = <SignalEntry>[];
  for (final entry in entries) {
    // Only bound signals are grouped. A header, separator or comment the user
    // already placed is theirs, and rearranging it would be the feature
    // fighting the layout rather than seeding it.
    final path = entry.kind == SignalEntryKind.signal ? entry.signalPath : null;
    final group = path == null ? null : org.groupFor(path);
    if (group == null) {
      ungrouped.add(entry);
      continue;
    }
    (grouped[group.name] ??= <SignalEntry>[]).add(entry);
  }

  return <SignalEntry>[
    for (final group in org.groups)
      if (grouped[group.name] case final children?)
        SignalEntry.group(
          groupName: group.name,
          collapsed: group.collapsed,
          children: children,
        ),
    ...ungrouped,
  ];
}
