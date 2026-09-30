// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The data type of a [DecoderParameter] value.
enum DecoderParameterType {
  /// True/false toggle (e.g. "active-low chip select").
  boolean,

  /// Signed or unsigned integer (e.g. "baud rate", "bit order").
  integer,

  /// One of a fixed set of named choices (e.g. "clock polarity: CPOL0/CPOL1").
  enumeration,

  /// Arbitrary text string (e.g. "filter expression").
  string,
}
