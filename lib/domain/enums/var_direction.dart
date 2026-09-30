// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The port direction of a variable as declared in the source file.
///
/// VCD files do not carry direction information; all variables from VCD
/// sources will have [unknown].
enum VarDirection {
  unknown,
  implicit,
  input,
  output,
  inout,
  buffer,
  linkage,
}
