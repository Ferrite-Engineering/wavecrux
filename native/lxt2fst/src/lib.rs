// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// lxt2fst — clean-room converter from GTKWave's legacy LXT (2003 streaming)
// and LXT2 (2005 block-indexed) waveform formats to FST.
//
// The crate provides convert-on-open for legacy `.lxt` / `.lxt2` captures so
// engineers with archives can double-click them into WaveCrux without
// installing GTKWave. The clean-room rule is non-negotiable: GTKWave's
// reader is GPLv2 and is NOT a source of code or constants in this crate.
// The wire-format constants encoded below (LXT/LXT2 magic bytes, header
// field layout, block-prefix layout) were established empirically from
// the small fixtures under `wavecrux/test/fixtures/legacy/` plus the
// publicly-documented format outline. See native/lxt2fst/README.md for
// the dependency choices (fst-writer, flate2) and the status of the
// value-change granule decoder.

#![allow(clippy::not_unsafe_ptr_arg_deref)]

pub mod error;
pub mod fst_writer;
pub mod lxt;
pub mod lxt2;
pub mod lxt_value_decode;
pub mod progress;
pub mod value_decode;

#[cfg(target_arch = "wasm32")]
mod wasm;

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::panic;
use std::ptr;

use crate::error::ConvertError;
use crate::fst_writer::FstOutput;
use crate::progress::ProgressReporter;

// ── ABI version ───────────────────────────────────────────────────────────

/// ABI version. Bump whenever a public C-ABI symbol changes shape.
pub const ABI_VERSION: u32 = 1;

// ── magic-byte detection (also exported via C-ABI) ────────────────────────

/// Recognized legacy formats, as returned by [`detect_format`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LegacyFormat {
    Unknown = 0,
    Lxt = 1,
    Lxt2 = 2,
}

/// Inspect the first 2 bytes of a file and identify the legacy format.
/// The LXT/LXT2 magic words are 16-bit big-endian distinguished values
/// that share no prefix with VCD/FST/GHW, so a 2-byte probe is enough.
pub fn detect_format(head: &[u8]) -> LegacyFormat {
    if head.len() < 2 {
        return LegacyFormat::Unknown;
    }
    let m = ((head[0] as u16) << 8) | (head[1] as u16);
    match m {
        lxt::LXT_MAGIC => LegacyFormat::Lxt,
        lxt2::LXT2_MAGIC => LegacyFormat::Lxt2,
        _ => LegacyFormat::Unknown,
    }
}

// ── high-level Rust API ───────────────────────────────────────────────────

/// Convert a `.lxt` / `.lxt2` file at `in_path` to an FST file at `out_path`.
/// `progress` is an optional throttled callback receiving `(done, total)`
/// — see `progress::ProgressReporter` for the throttling contract.
pub fn convert(
    in_path: &std::path::Path,
    out_path: &std::path::Path,
    progress: Option<&mut dyn FnMut(u64, u64)>,
) -> Result<(), ConvertError> {
    let bytes = std::fs::read(in_path).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => ConvertError::FileNotFound,
        _ => ConvertError::Truncated,
    })?;
    convert_to(&bytes, FstOutput::File(out_path), progress)
}

/// Convert an in-memory `.lxt` / `.lxt2` buffer and return the FST file
/// body. Needs no filesystem, which is what the web build requires; the
/// bytes are identical to what [`convert`] writes to disk.
pub fn convert_bytes(
    input: &[u8],
    progress: Option<&mut dyn FnMut(u64, u64)>,
) -> Result<Vec<u8>, ConvertError> {
    let mut fst = Vec::new();
    convert_to(input, FstOutput::Memory(&mut fst), progress)?;
    Ok(fst)
}

fn convert_to(
    input: &[u8],
    out: FstOutput<'_>,
    progress: Option<&mut dyn FnMut(u64, u64)>,
) -> Result<(), ConvertError> {
    let mut reporter = ProgressReporter::new(progress);
    match detect_format(input) {
        LegacyFormat::Lxt2 => lxt2::convert_lxt2_to_fst(input, out, &mut reporter),
        LegacyFormat::Lxt => lxt::convert_lxt_to_fst(input, out, &mut reporter),
        LegacyFormat::Unknown => Err(ConvertError::MagicMismatch),
    }
}

// ── C-ABI surface ─────────────────────────────────────────────────────────
//
// These symbols ship inside the wellen_ffi native library, which links this
// crate as a Rust dependency (native/wellen_ffi/src/lib.rs). No platform
// bundles a standalone liblxt2fst; the Dart loader resolves `lxt2fst_*` from
// the same library as `wellen_*`, and iOS keeps them alive through
// native/wellen_ffi/Sources/WellenFFIKeepalive/wellen_ffi_keepalive.c.
//
// All exported functions are panic-safe via the `ffi_guard!` macro:
// any panic across the boundary is caught and converted into an internal
// error code, never crossing into the C caller. Mirrors the pattern in
// wellen_ffi/src/lib.rs.

thread_local! {
    /// Per-thread last-error string. Lives as long as the thread or until
    /// the next conversion overwrites it. The C-ABI surface borrows this
    /// pointer to the caller (a static-lifetime guarantee within the
    /// single-shot call semantics documented in lxt2fst.h). Initialized
    /// lazily (CString::new is not const) — first read goes through this
    /// closure.
    static LAST_ERROR: std::cell::RefCell<CString> =
        std::cell::RefCell::new(CString::new(Vec::<u8>::new()).unwrap());
}

fn set_last_error(msg: impl Into<String>) {
    let s = msg.into();
    let cs = CString::new(s).unwrap_or_else(|_| CString::new("internal").unwrap());
    LAST_ERROR.with(|cell| *cell.borrow_mut() = cs);
}

fn clear_last_error() {
    LAST_ERROR.with(|cell| *cell.borrow_mut() = CString::new("").unwrap());
}

macro_rules! ffi_guard {
    ($body:expr) => {{
        let result = panic::catch_unwind(panic::AssertUnwindSafe(|| $body));
        match result {
            Ok(v) => v,
            Err(_) => {
                set_last_error("internal panic in lxt2fst");
                ConvertError::Internal as c_int
            }
        }
    }};
}

/// Returns the ABI version this library was built against. The Dart side
/// rejects mismatched libraries at load time — see lxt2fst.h.
#[unsafe(no_mangle)]
pub extern "C" fn lxt2fst_abi_version() -> u32 {
    ABI_VERSION
}

/// Identify the legacy format from a head-byte slice. Negative lengths
/// are treated as zero. See lxt2fst.h for the constants returned.
#[unsafe(no_mangle)]
pub extern "C" fn lxt2fst_detect_format(head: *const u8, len: usize) -> i32 {
    if head.is_null() || len == 0 {
        return LegacyFormat::Unknown as i32;
    }
    let slice = unsafe { std::slice::from_raw_parts(head, len) };
    detect_format(slice) as i32
}

/// Returns the most recent thread-local error message, or "" if the
/// previous conversion succeeded. The pointer is borrowed and remains
/// valid until the next conversion on the same thread.
#[unsafe(no_mangle)]
pub extern "C" fn lxt2fst_last_error_message() -> *const c_char {
    LAST_ERROR.with(|cell| cell.borrow().as_ptr())
}

/// Progress callback type (matches the `lxt2fst_progress_fn` typedef in
/// lxt2fst.h).
pub type ProgressFn =
    Option<extern "C" fn(done: u64, total: u64, user_data: *mut std::ffi::c_void)>;

/// Single-shot conversion entry. See lxt2fst.h for the contract and the
/// returned error codes.
#[unsafe(no_mangle)]
pub extern "C" fn lxt2fst_convert(
    in_path: *const c_char,
    out_path: *const c_char,
    progress: ProgressFn,
    user_data: *mut std::ffi::c_void,
) -> c_int {
    ffi_guard!({
        clear_last_error();
        if in_path.is_null() || out_path.is_null() {
            set_last_error("null path argument");
            return ConvertError::InvalidArg as c_int;
        }
        let in_str = match unsafe { CStr::from_ptr(in_path) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_last_error("input path is not valid UTF-8");
                return ConvertError::InvalidArg as c_int;
            }
        };
        let out_str = match unsafe { CStr::from_ptr(out_path) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_last_error("output path is not valid UTF-8");
                return ConvertError::InvalidArg as c_int;
            }
        };

        // Bridge the extern "C" progress callback into the
        // `&mut dyn FnMut(u64, u64)` form the Rust side expects, capturing
        // `user_data` in the closure environment. `usize` capture sidesteps
        // pointer-Send concerns inside the catch_unwind boundary.
        let ud = user_data as usize;
        let mut owned_cb: Option<Box<dyn FnMut(u64, u64)>> = progress.map(|cb| {
            let f: Box<dyn FnMut(u64, u64)> =
                Box::new(move |d, t| cb(d, t, ud as *mut std::ffi::c_void));
            f
        });
        // Borrow the boxed closure for the duration of the convert call.
        let cb_ref: Option<&mut dyn FnMut(u64, u64)> = match owned_cb.as_mut() {
            Some(b) => Some(b.as_mut()),
            None => None,
        };

        let r = convert(
            std::path::Path::new(in_str),
            std::path::Path::new(out_str),
            cb_ref,
        );
        match r {
            Ok(()) => ConvertError::Ok as c_int,
            Err(e) => {
                set_last_error(format!("{e:?}"));
                e as c_int
            }
        }
    })
}

// Marker so dead-code lints don't trip on `ptr` re-export when the wasm
// target is disabled.
#[doc(hidden)]
pub fn _unused() {
    let _ = ptr::null::<u8>();
}
