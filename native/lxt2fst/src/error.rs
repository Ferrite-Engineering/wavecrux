// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Error codes for the lxt2fst conversion path.
//
// The discriminant values are part of the public C-ABI (see lxt2fst.h) and
// MUST stay in sync with the LXT2FST_ERR_* #defines there. Adding a new
// variant requires bumping ABI_VERSION in src/lib.rs.

use std::os::raw::c_int;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum ConvertError {
    Ok = 0,
    FileNotFound = 1,
    MagicMismatch = 2,
    Truncated = 3,
    WriteFailed = 4,
    Oom = 5,
    /// A recognized but currently unimplemented encoding (e.g., string
    /// value-change granules under active reverse-engineering — see
    /// README and src/lxt2.rs). Distinct from `MagicMismatch` so callers
    /// can surface a clear "this LXT2 file exercises a code path we
    /// haven't shipped yet" diagnostic rather than implying the file is
    /// corrupt.
    Unsupported = 6,
    /// Panic-safety net tripped at the FFI boundary.
    Internal = 7,
    InvalidArg = 8,
}

impl From<ConvertError> for c_int {
    fn from(e: ConvertError) -> c_int {
        e as c_int
    }
}

impl std::fmt::Display for ConvertError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            ConvertError::Ok => "ok",
            ConvertError::FileNotFound => "file not found",
            ConvertError::MagicMismatch => "magic-byte mismatch (not an LXT/LXT2 file)",
            ConvertError::Truncated => "truncated or malformed legacy file",
            ConvertError::WriteFailed => "FST write failed",
            ConvertError::Oom => "out of memory",
            ConvertError::Unsupported => "unsupported LXT2 encoding (clean-room decoder gap)",
            ConvertError::Internal => "internal error",
            ConvertError::InvalidArg => "invalid argument",
        };
        f.write_str(s)
    }
}

impl std::error::Error for ConvertError {}
