// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Whether the signal search interprets the query as a plain substring or
/// a glob pattern (with `*` and `?` wildcards).
enum SearchMode {
  /// Case-insensitive substring: the query is matched literally (no wildcards).
  substring,

  /// Glob pattern: `*` matches any sequence of characters, `?` matches exactly
  /// one character. Case-insensitive.
  glob,
}
