// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// FFI boundary: every extern "C" function takes raw pointers by design.
// Marking them all `unsafe fn` is incorrect for a C-callable API.
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::cell::RefCell;
use std::collections::HashSet;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::panic;

use wellen::{
    Hierarchy, ScopeRef, ScopeType, SignalRef, TimescaleUnit, VarDirection, VarRef, VarType, simple,
};

// ── LXT/LXT2 → FST converter ─────────────────────────────────────────────────
//
// Linking the lxt2fst crate makes this library export its C ABI as well
// (`lxt2fst_abi_version`, `lxt2fst_detect_format`, `lxt2fst_convert`,
// `lxt2fst_last_error_message` — see native/lxt2fst/include/lxt2fst.h). The
// `pub use` is what pulls the crate, and so its `#[unsafe(no_mangle)]`
// functions, into the cdylib/staticlib; nothing here calls it. Dart resolves
// both symbol families from one DynamicLibrary, and iOS keeps the lxt2fst ones
// through Sources/WellenFFIKeepalive/wellen_ffi_keepalive.c.
pub use lxt2fst as _lxt2fst;

// ── file format constants (mirrored in wellen_ffi.h) ─────────────────────────

pub const FORMAT_UNKNOWN: i32 = 0;
pub const FORMAT_VCD: i32 = 1;
pub const FORMAT_FST: i32 = 2;
pub const FORMAT_GHW: i32 = 3;

// ── opaque handle ─────────────────────────────────────────────────────────────

pub struct WellenHandle {
    waveform: simple::Waveform,
    last_error: CString,
    date: CString,
    version: CString,
    // Stable C-string storage for names (indexed by ScopeRef/VarRef index).
    scope_names: Vec<CString>,
    var_names: Vec<CString>,
    // Diagnostics fields.
    file_format: i32,
    total_transitions: u64,
    loaded_refs: HashSet<u32>,
}

impl WellenHandle {
    fn new(waveform: simple::Waveform, file_format: i32) -> Box<Self> {
        let h = waveform.hierarchy();
        let date = CString::new(h.date()).unwrap_or_default();
        let version = CString::new(h.version()).unwrap_or_default();
        // Indexed by `ScopeRef::index()` / `VarRef::index()`, which is what the
        // C side hands back. Placed by index rather than collected in iteration
        // order: since wellen 0.25 `all_scopes()` / `all_vars()` walk the tree
        // recursively, so their order is no longer the storage order the refs
        // count in, and a cache built by `collect()` handed out the wrong name
        // — or null — for every ref past the first divergence.
        let mut scope_names: Vec<CString> = Vec::new();
        for s in h.all_scopes() {
            let i = s.index();
            if scope_names.len() <= i {
                scope_names.resize_with(i + 1, CString::default);
            }
            scope_names[i] = CString::new(h[s].name(h)).unwrap_or_default();
        }
        let mut var_names: Vec<CString> = Vec::new();
        for v in h.all_vars() {
            let i = v.index();
            if var_names.len() <= i {
                var_names.resize_with(i + 1, CString::default);
            }
            var_names[i] = CString::new(h[v].name(h)).unwrap_or_default();
        }
        Box::new(WellenHandle {
            waveform,
            last_error: CString::new("").unwrap(),
            date,
            version,
            scope_names,
            var_names,
            file_format,
            total_transitions: 0,
            loaded_refs: HashSet::new(),
        })
    }

    fn set_error(&mut self, msg: &str) {
        self.last_error = CString::new(msg).unwrap_or_default();
    }

    fn hier(&self) -> &Hierarchy {
        self.waveform.hierarchy()
    }

    fn scope_ref(&self, idx: u64) -> Option<ScopeRef> {
        ScopeRef::from_index(idx as usize)
    }

    fn var_ref(&self, idx: u64) -> Option<VarRef> {
        VarRef::from_index(idx as usize)
    }

    fn signal_ref(idx: u32) -> SignalRef {
        SignalRef::from_index(idx as usize).expect("signal_ref index 0 is invalid per wellen spec")
    }
}

// ── helpers ───────────────────────────────────────────────────────────────────

/// Wraps a call that could panic; on panic sets an error code.
macro_rules! ffi_guard {
    ($handle:expr, $err_ret:expr, $body:expr) => {{
        if ($handle as *const ()).is_null() {
            return $err_ret;
        }
        let result = panic::catch_unwind(panic::AssertUnwindSafe(|| $body));
        match result {
            Ok(v) => v,
            Err(_) => {
                if let Some(h) = unsafe { ($handle as *mut WellenHandle).as_mut() } {
                    h.set_error("internal panic");
                }
                $err_ret
            }
        }
    }};
}

fn scope_type_to_int(st: ScopeType) -> i32 {
    match st {
        ScopeType::Module => 0,
        ScopeType::Task => 1,
        ScopeType::Function => 2,
        ScopeType::Begin => 3,
        ScopeType::Fork => 4,
        ScopeType::Generate => 5,
        ScopeType::Struct => 6,
        ScopeType::Union => 7,
        ScopeType::Class => 8,
        ScopeType::Interface => 9,
        ScopeType::Package => 10,
        ScopeType::Program => 11,
        ScopeType::VhdlArchitecture => 20,
        ScopeType::VhdlProcedure => 21,
        ScopeType::VhdlFunction => 22,
        ScopeType::VhdlRecord => 23,
        ScopeType::VhdlProcess => 24,
        ScopeType::VhdlBlock => 25,
        ScopeType::VhdlForGenerate => 26,
        ScopeType::VhdlIfGenerate => 27,
        ScopeType::VhdlGenerate => 28,
        ScopeType::VhdlPackage => 29,
        ScopeType::GhwGeneric => 30,
        ScopeType::VhdlArray => 31,
        // ScopeType is #[non_exhaustive] — map any future variants to Module.
        _ => 0,
    }
}

fn var_type_to_int(vt: VarType) -> i32 {
    match vt {
        VarType::Event => 0,
        VarType::Integer => 1,
        VarType::Parameter => 2,
        VarType::Real => 3,
        VarType::Reg => 4,
        VarType::Supply0 => 5,
        VarType::Supply1 => 6,
        VarType::Time => 7,
        VarType::Tri => 8,
        VarType::TriAnd => 9,
        VarType::TriOr => 10,
        VarType::TriReg => 11,
        VarType::Tri0 => 12,
        VarType::Tri1 => 13,
        VarType::WAnd => 14,
        VarType::Wire => 15,
        VarType::WOr => 16,
        VarType::String => 17,
        VarType::Port => 18,
        VarType::SparseArray => 19,
        VarType::RealTime => 20,
        VarType::Bit => 30,
        VarType::Logic => 31,
        VarType::Int => 32,
        VarType::ShortInt => 33,
        VarType::LongInt => 34,
        VarType::Byte => 35,
        VarType::Enum => 36,
        VarType::ShortReal => 37,
        VarType::Boolean => 40,
        VarType::BitVector => 41,
        VarType::StdLogic => 42,
        VarType::StdLogicVector => 43,
        VarType::StdULogic => 44,
        VarType::StdULogicVector => 45,
        VarType::RealParameter => 46,
        // wellen 0.24 added EventParameter (a parameter of `event` type). Distinct
        // FFI code, mirrored by WELLEN_VAR_EVENT_PARAMETER in wellen_ffi.h and
        // VarType.eventParameter on the Dart side.
        VarType::EventParameter => 47,
    }
}

fn var_dir_to_int(d: VarDirection) -> i32 {
    match d {
        VarDirection::Unknown => 0,
        VarDirection::Implicit => 1,
        VarDirection::Input => 2,
        VarDirection::Output => 3,
        VarDirection::InOut => 4,
        VarDirection::Buffer => 5,
        VarDirection::Linkage => 6,
    }
}

fn timescale_unit_exp(u: TimescaleUnit) -> i32 {
    match u {
        TimescaleUnit::FemtoSeconds => -15,
        TimescaleUnit::PicoSeconds => -12,
        TimescaleUnit::NanoSeconds => -9,
        TimescaleUnit::MicroSeconds => -6,
        TimescaleUnit::MilliSeconds => -3,
        TimescaleUnit::Seconds => 0,
        // AttoSeconds (1e-18) and ZeptoSeconds (1e-21) are finer than
        // anything a real simulator produces.  Map to their physical
        // exponents; the Dart side's wildcard arm maps them to unknown.
        TimescaleUnit::AttoSeconds => -18,
        TimescaleUnit::ZeptoSeconds => -21,
        TimescaleUnit::Unknown => i32::MIN,
    }
}

/// Write a Rust string into a caller-supplied `*mut u8` buffer.
/// Returns the number of bytes written (not including null terminator),
/// or -1 if the buffer is too small.
fn write_str_buf(s: &str, buf: *mut u8, buf_len: u32) -> i32 {
    let bytes = s.as_bytes();
    let needed = bytes.len() + 1;
    if buf.is_null() || needed > buf_len as usize {
        return -1;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, bytes.len());
        *buf.add(bytes.len()) = 0;
    }
    bytes.len() as i32
}

/// Find the largest time ≤ `target` in the time table. Returns None if the table
/// is empty or all times are greater than `target`.
fn find_time_table_idx(time_table: &[u64], target: u64) -> Option<u32> {
    match time_table.partition_point(|&t| t <= target) {
        0 => None,
        pos => Some((pos - 1) as u32),
    }
}

// ── lifecycle ─────────────────────────────────────────────────────────────────

fn detect_format(path: &str) -> i32 {
    match path
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_lowercase()
        .as_str()
    {
        "vcd" => FORMAT_VCD,
        "fst" => FORMAT_FST,
        "ghw" => FORMAT_GHW,
        _ => FORMAT_UNKNOWN,
    }
}

thread_local! {
    /// Human-readable reason for the most recent failed `wellen_open` on
    /// this thread. Open failures return a null handle — there is no handle
    /// to attach an error to — so the reason is stashed here and retrieved
    /// via `wellen_last_open_error`.
    static LAST_OPEN_ERROR: RefCell<CString> = RefCell::new(CString::new("").unwrap());
}

fn set_last_open_error(msg: String) {
    LAST_OPEN_ERROR.with(|e| {
        *e.borrow_mut() = CString::new(msg).unwrap_or_default();
    });
}

/// Open a waveform file (VCD, FST, or GHW). Returns an opaque handle on
/// success, or null on failure. After a null return, call
/// `wellen_last_open_error` (no handle required) to retrieve wellen's
/// human-readable reason — surfaced to the user so a malformed file
/// reports *why* it failed instead of a generic "couldn't open" message.
///
/// The returned handle must be freed with `wellen_close`.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_open(path: *const c_char) -> *mut WellenHandle {
    // Clear any stale reason so the getter reads empty after a success.
    set_last_open_error(String::new());
    let result = panic::catch_unwind(|| {
        let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_last_open_error("file path is not valid UTF-8".to_string());
                return None;
            }
        };
        let fmt = detect_format(path_str);
        match simple::read(path_str) {
            Ok(w) => Some(WellenHandle::new(w, fmt)),
            Err(e) => {
                set_last_open_error(format!("{e}"));
                None
            }
        }
    });
    match result {
        Ok(Some(boxed)) => Box::into_raw(boxed),
        Ok(None) => std::ptr::null_mut(),
        Err(_) => {
            set_last_open_error("internal error while reading the file".to_string());
            std::ptr::null_mut()
        }
    }
}

/// Return the reason for the most recent failed `wellen_open` on the
/// calling thread, or an empty string if the last open succeeded. Unlike
/// `wellen_last_error`, this takes no handle (open failures produce none).
/// The pointer is valid until the next `wellen_open` on this thread.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_last_open_error() -> *const c_char {
    LAST_OPEN_ERROR.with(|e| e.borrow().as_ptr())
}

/// Free a handle returned by `wellen_open`.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_close(handle: *mut WellenHandle) {
    if !handle.is_null() {
        unsafe { drop(Box::from_raw(handle)) };
    }
}

/// Return the last error message for this handle (empty string if none).
/// The pointer is valid until the next call on this handle.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_last_error(handle: *const WellenHandle) -> *const c_char {
    match unsafe { handle.as_ref() } {
        Some(h) => h.last_error.as_ptr(),
        None => c"".as_ptr(),
    }
}

// ── metadata ──────────────────────────────────────────────────────────────────

/// Fill `*factor_out` and `*unit_exp_out` with the timescale.
/// `unit_exp_out` is the power-of-10 exponent (e.g. -9 for nanoseconds).
/// Returns 1 if a timescale was present, 0 if not.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_get_timescale(
    handle: *mut WellenHandle,
    factor_out: *mut u32,
    unit_exp_out: *mut i32,
) -> c_int {
    ffi_guard!(handle, 0, {
        let h = unsafe { &*handle };
        match h.hier().timescale() {
            Some(ts) => {
                unsafe {
                    if !factor_out.is_null() {
                        *factor_out = ts.factor;
                    }
                    if !unit_exp_out.is_null() {
                        *unit_exp_out = timescale_unit_exp(ts.unit);
                    }
                }
                1
            }
            None => 0,
        }
    })
}

/// Return the last time in the time table (i.e. simulation end time in ticks).
#[unsafe(no_mangle)]
pub extern "C" fn wellen_time_end(handle: *const WellenHandle) -> u64 {
    ffi_guard!(handle, 0, {
        let h = unsafe { &*handle };
        h.waveform.time_table().last().copied().unwrap_or(0)
    })
}

/// Return a null-terminated string with the simulation date. Pointer valid
/// for the lifetime of the handle.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_date(handle: *const WellenHandle) -> *const c_char {
    match unsafe { handle.as_ref() } {
        Some(h) => h.date.as_ptr(),
        None => c"".as_ptr(),
    }
}

/// Return a null-terminated string with the simulator version. Pointer valid
/// for the lifetime of the handle.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_version(handle: *const WellenHandle) -> *const c_char {
    match unsafe { handle.as_ref() } {
        Some(h) => h.version.as_ptr(),
        None => c"".as_ptr(),
    }
}

// ── hierarchy counts ──────────────────────────────────────────────────────────

/// Total number of scopes in the hierarchy.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_num_scopes(handle: *const WellenHandle) -> u64 {
    ffi_guard!(handle, 0, unsafe { &*handle }.scope_names.len() as u64)
}

/// Total number of variables in the hierarchy.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_num_vars(handle: *const WellenHandle) -> u64 {
    ffi_guard!(handle, 0, unsafe { &*handle }.var_names.len() as u64)
}

// ── root-level items ──────────────────────────────────────────────────────────

/// Write indices of top-level scopes into `out` (capacity `max`).
/// Returns number written, or -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_root_scopes(handle: *const WellenHandle, out: *mut u64, max: u64) -> i64 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        let out_slice = unsafe { std::slice::from_raw_parts_mut(out, max as usize) };
        let mut count = 0usize;
        for sr in h.hier().scopes() {
            if count >= max as usize {
                break;
            }
            out_slice[count] = sr.index() as u64;
            count += 1;
        }
        count as i64
    })
}

/// Write indices of top-level variables into `out` (capacity `max`).
/// Returns number written, or -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_root_vars(handle: *const WellenHandle, out: *mut u64, max: u64) -> i64 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        let out_slice = unsafe { std::slice::from_raw_parts_mut(out, max as usize) };
        let mut count = 0usize;
        for vr in h.hier().vars() {
            if count >= max as usize {
                break;
            }
            out_slice[count] = vr.index() as u64;
            count += 1;
        }
        count as i64
    })
}

// ── scope properties ──────────────────────────────────────────────────────────

/// Return a null-terminated scope name. Pointer valid for the lifetime of the
/// handle. Returns null if `scope_idx` is out of range.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_scope_name(handle: *const WellenHandle, scope_idx: u64) -> *const c_char {
    match unsafe { handle.as_ref() } {
        Some(h) => h
            .scope_names
            .get(scope_idx as usize)
            .map(|s| s.as_ptr())
            .unwrap_or(std::ptr::null()),
        None => std::ptr::null(),
    }
}

/// Return the scope type as an integer (see `WELLEN_SCOPE_*` constants in the
/// header). Returns -1 if `scope_idx` is out of range.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_scope_type(handle: *const WellenHandle, scope_idx: u64) -> i32 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        match h.scope_ref(scope_idx) {
            Some(sr) => scope_type_to_int(h.hier()[sr].scope_type()),
            None => -1,
        }
    })
}

/// Write child scope indices of `scope_idx` into `out` (capacity `max`).
/// Returns count written, or -1 on error / invalid index.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_scope_child_scopes(
    handle: *const WellenHandle,
    scope_idx: u64,
    out: *mut u64,
    max: u64,
) -> i64 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        let sr = match h.scope_ref(scope_idx) {
            Some(s) => s,
            None => return -1,
        };
        let out_slice = unsafe { std::slice::from_raw_parts_mut(out, max as usize) };
        let mut count = 0usize;
        for child in h.hier()[sr].scopes(h.hier()) {
            if count >= max as usize {
                break;
            }
            out_slice[count] = child.index() as u64;
            count += 1;
        }
        count as i64
    })
}

/// Write child variable indices of `scope_idx` into `out` (capacity `max`).
/// Returns count written, or -1 on error / invalid index.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_scope_child_vars(
    handle: *const WellenHandle,
    scope_idx: u64,
    out: *mut u64,
    max: u64,
) -> i64 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        let sr = match h.scope_ref(scope_idx) {
            Some(s) => s,
            None => return -1,
        };
        let out_slice = unsafe { std::slice::from_raw_parts_mut(out, max as usize) };
        let mut count = 0usize;
        for child in h.hier()[sr].vars(h.hier()) {
            if count >= max as usize {
                break;
            }
            out_slice[count] = child.index() as u64;
            count += 1;
        }
        count as i64
    })
}

// ── variable properties ───────────────────────────────────────────────────────

/// Return a null-terminated variable name. Pointer valid for the lifetime of
/// the handle. Returns null if `var_idx` is out of range.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_var_name(handle: *const WellenHandle, var_idx: u64) -> *const c_char {
    match unsafe { handle.as_ref() } {
        Some(h) => h
            .var_names
            .get(var_idx as usize)
            .map(|s| s.as_ptr())
            .unwrap_or(std::ptr::null()),
        None => std::ptr::null(),
    }
}

/// Return the variable type as an integer (see `WELLEN_VAR_*` constants).
/// Returns -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_var_type(handle: *const WellenHandle, var_idx: u64) -> i32 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        match h.var_ref(var_idx) {
            Some(vr) => var_type_to_int(h.hier()[vr].var_type()),
            None => -1,
        }
    })
}

/// Return the variable direction as an integer (see `WELLEN_DIR_*` constants).
/// Returns -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_var_direction(handle: *const WellenHandle, var_idx: u64) -> i32 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        match h.var_ref(var_idx) {
            Some(vr) => var_dir_to_int(h.hier()[vr].direction()),
            None => -1,
        }
    })
}

/// Return the bit width of a variable (0 if unavailable / not a bit-vector).
#[unsafe(no_mangle)]
pub extern "C" fn wellen_var_length(handle: *const WellenHandle, var_idx: u64) -> u32 {
    ffi_guard!(handle, 0, {
        let h = unsafe { &*handle };
        match h.var_ref(var_idx) {
            Some(vr) => h.hier()[vr].length(h.hier()).unwrap_or(0),
            None => 0,
        }
    })
}

/// Return the signal reference (opaque u32) used for loading / querying
/// this variable's signal data. Returns `u32::MAX` on error.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_var_signal_ref(handle: *const WellenHandle, var_idx: u64) -> u32 {
    ffi_guard!(handle, u32::MAX, {
        let h = unsafe { &*handle };
        match h.var_ref(var_idx) {
            Some(vr) => h.hier()[vr].signal_ref().index() as u32,
            None => u32::MAX,
        }
    })
}

// ── signal loading ────────────────────────────────────────────────────────────

/// Load signal data for the given `signal_ref` (obtained via
/// `wellen_var_signal_ref`). Returns 0 on success, -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_load_signal(handle: *mut WellenHandle, signal_ref: u32) -> c_int {
    ffi_guard!(handle, -1, {
        let h = unsafe { &mut *handle };
        let sr = WellenHandle::signal_ref(signal_ref);
        h.waveform.load_signals(&[sr]);
        // Update total_transitions once per unique signal ref.
        if h.loaded_refs.insert(signal_ref) {
            let count = h
                .waveform
                .get_signal(sr)
                .map(|s| s.iter_changes().count() as u64)
                .unwrap_or(0);
            h.total_transitions += count;
        }
        0
    })
}

/// Unload a previously loaded signal to free memory.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_unload_signal(handle: *mut WellenHandle, signal_ref: u32) -> c_int {
    ffi_guard!(handle, -1, {
        let h = unsafe { &mut *handle };
        let sr = WellenHandle::signal_ref(signal_ref);
        h.waveform.unload_signals(&[sr]);
        0
    })
}

// ── value queries ─────────────────────────────────────────────────────────────

/// Write the signal value at simulation time `time` (in ticks) into
/// `value_buf` as a null-terminated string.
///
/// Returns number of bytes written (not including null), -1 if the signal is
/// not loaded or has no value at/before `time`, or -2 if the buffer is too
/// small.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_value_at(
    handle: *const WellenHandle,
    signal_ref: u32,
    time: u64,
    value_buf: *mut u8,
    buf_len: u32,
) -> i32 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        let sr = WellenHandle::signal_ref(signal_ref);
        let signal = match h.waveform.get_signal(sr) {
            Some(s) => s,
            None => return -1,
        };
        let time_table = h.waveform.time_table();
        let tbl_idx = match find_time_table_idx(time_table, time) {
            Some(i) => i,
            None => return -1,
        };
        let offset = match signal.get_offset(tbl_idx) {
            Some(o) => o,
            None => return -1,
        };
        let val = signal.get_value_at(&offset, 0);
        let s = val.to_string();
        let r = write_str_buf(&s, value_buf, buf_len);
        if r == -1 { -2 } else { r }
    })
}

/// Collect all value changes for `signal_ref` in the half-open time interval
/// `[start_time, end_time)` and write them into the provided flat buffers.
///
/// - `out_times`: `u64` array, receives the tick of each change
/// - `out_value_buf`: flat byte buffer for null-terminated value strings
/// - `value_buf_len`: total capacity of `out_value_buf`
/// - `out_offsets`: `u32` array, offset into `out_value_buf` for each change
/// - `max_count`: capacity of `out_times` and `out_offsets` arrays
///
/// Returns the number of changes written, or a negative value on error:
///   -1  signal not loaded
///   -2  output buffers too small (partial results NOT written)
#[unsafe(no_mangle)]
pub extern "C" fn wellen_signal_changes(
    handle: *const WellenHandle,
    signal_ref: u32,
    start_time: u64,
    end_time: u64,
    out_times: *mut u64,
    out_value_buf: *mut u8,
    value_buf_len: u32,
    out_offsets: *mut u32,
    max_count: i64,
) -> i64 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        let sr = WellenHandle::signal_ref(signal_ref);
        let signal = match h.waveform.get_signal(sr) {
            Some(s) => s,
            None => return -1,
        };
        let time_table = h.waveform.time_table();

        // Collect matching changes first to check capacity.
        let mut entries: Vec<(u64, String)> = Vec::new();
        for (tbl_idx, val) in signal.iter_changes() {
            let t = time_table[tbl_idx as usize];
            if t >= end_time {
                break;
            }
            if t >= start_time {
                entries.push((t, val.to_string()));
            }
        }

        // Verify capacity.
        let needed_count = entries.len() as i64;
        if needed_count > max_count {
            return -2;
        }
        let needed_buf: usize = entries.iter().map(|(_, s)| s.len() + 1).sum();
        if needed_buf > value_buf_len as usize {
            return -2;
        }

        // Write into caller buffers.
        let times_slice = unsafe { std::slice::from_raw_parts_mut(out_times, entries.len()) };
        let offsets_slice = unsafe { std::slice::from_raw_parts_mut(out_offsets, entries.len()) };
        let val_buf_slice =
            unsafe { std::slice::from_raw_parts_mut(out_value_buf, value_buf_len as usize) };

        let mut buf_pos = 0u32;
        for (i, (t, s)) in entries.iter().enumerate() {
            times_slice[i] = *t;
            offsets_slice[i] = buf_pos;
            let bytes = s.as_bytes();
            val_buf_slice[buf_pos as usize..buf_pos as usize + bytes.len()].copy_from_slice(bytes);
            val_buf_slice[buf_pos as usize + bytes.len()] = 0;
            buf_pos += bytes.len() as u32 + 1;
        }
        needed_count
    })
}

/// Find the next value change strictly after `after_time`.
///
/// On success, writes the change time to `*out_time` and the value string into
/// `value_buf` (null-terminated) and returns 1.
/// Returns 0 if there is no next transition, -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_next_transition(
    handle: *const WellenHandle,
    signal_ref: u32,
    after_time: u64,
    out_time: *mut u64,
    value_buf: *mut u8,
    buf_len: u32,
) -> i32 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        let sr = WellenHandle::signal_ref(signal_ref);
        let signal = match h.waveform.get_signal(sr) {
            Some(s) => s,
            None => return -1,
        };
        let time_table = h.waveform.time_table();
        for (tbl_idx, val) in signal.iter_changes() {
            let t = time_table[tbl_idx as usize];
            if t > after_time {
                unsafe { *out_time = t };
                let s = val.to_string();
                let r = write_str_buf(&s, value_buf, buf_len);
                return if r >= 0 { 1 } else { -2 };
            }
        }
        0
    })
}

/// Find the last value change strictly before `before_time`.
///
/// On success, writes the change time to `*out_time` and the value string into
/// `value_buf` (null-terminated) and returns 1.
/// Returns 0 if there is no previous transition, -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_prev_transition(
    handle: *const WellenHandle,
    signal_ref: u32,
    before_time: u64,
    out_time: *mut u64,
    value_buf: *mut u8,
    buf_len: u32,
) -> i32 {
    ffi_guard!(handle, -1, {
        let h = unsafe { &*handle };
        let sr = WellenHandle::signal_ref(signal_ref);
        let signal = match h.waveform.get_signal(sr) {
            Some(s) => s,
            None => return -1,
        };
        let time_table = h.waveform.time_table();
        let mut found_time: Option<u64> = None;
        let mut found_val: Option<String> = None;
        for (tbl_idx, val) in signal.iter_changes() {
            let t = time_table[tbl_idx as usize];
            if t >= before_time {
                break;
            }
            found_time = Some(t);
            found_val = Some(val.to_string());
        }
        match (found_time, found_val) {
            (Some(t), Some(s)) => {
                unsafe { *out_time = t };
                let r = write_str_buf(&s, value_buf, buf_len);
                if r >= 0 { 1 } else { -2 }
            }
            _ => 0,
        }
    })
}

// ── diagnostics ───────────────────────────────────────────────────────────────

/// Return the file format of the opened waveform.
/// Returns WELLEN_FORMAT_VCD (1), WELLEN_FORMAT_FST (2), WELLEN_FORMAT_GHW (3),
/// or WELLEN_FORMAT_UNKNOWN (0) if the format could not be determined.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_file_format(handle: *const WellenHandle) -> i32 {
    match unsafe { handle.as_ref() } {
        Some(h) => h.file_format,
        None => FORMAT_UNKNOWN,
    }
}

/// Return the total number of value changes across all signals that have been
/// loaded via `wellen_load_signal`. The count grows as more signals are loaded.
/// Returns 0 if no signals have been loaded yet.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_total_transition_count(handle: *const WellenHandle) -> u64 {
    match unsafe { handle.as_ref() } {
        Some(h) => h.total_transitions,
        None => 0,
    }
}

/// Return the number of value changes for the given `signal_ref`.
/// The signal must be loaded first via `wellen_load_signal`; returns 0 if not loaded.
#[unsafe(no_mangle)]
pub extern "C" fn wellen_signal_transition_count(
    handle: *const WellenHandle,
    signal_ref: u32,
) -> u64 {
    ffi_guard!(handle, 0, {
        let h = unsafe { &*handle };
        let sr = WellenHandle::signal_ref(signal_ref);
        match h.waveform.get_signal(sr) {
            Some(signal) => signal.iter_changes().count() as u64,
            None => 0,
        }
    })
}

/// Return an approximate memory usage in bytes for the waveform data held by
/// this handle. This is an estimate, not an exact allocation count:
///   time_table entries × 8 bytes
///   + scope metadata × 200 bytes
///   + variable metadata × 100 bytes
///   + loaded signal changes × 16 bytes (estimated storage per change)
#[unsafe(no_mangle)]
pub extern "C" fn wellen_memory_usage_bytes(handle: *const WellenHandle) -> u64 {
    ffi_guard!(handle, 0, {
        let h = unsafe { &*handle };
        let time_bytes = h.waveform.time_table().len() as u64 * 8;
        let hier_bytes = h.scope_names.len() as u64 * 200 + h.var_names.len() as u64 * 100;
        let signal_bytes = h.total_transitions * 16;
        time_bytes + hier_bytes + signal_bytes
    })
}

// ── tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn open_test_vcd() -> (*mut WellenHandle, std::path::PathBuf) {
        // Use a thread-unique file name so parallel test runs don't collide.
        let tid = std::thread::current().id();
        let filename = format!("wellen_ffi_test_{tid:?}.vcd").replace(['(', ')'], "_");
        open_test_vcd_at(std::env::temp_dir().join(filename))
    }

    fn open_test_vcd_at(path: std::path::PathBuf) -> (*mut WellenHandle, std::path::PathBuf) {
        let content = b"$timescale 1ns $end\n\
            $scope module top $end\n\
            $var wire 1 ! clk $end\n\
            $var wire 8 \" data $end\n\
            $upscope $end\n\
            $enddefinitions $end\n\
            #0 0! b00000000 \"\n\
            #10 1!\n\
            #20 0! b00000001 \"\n\
            #30 1!\n\
            #40 0!\n";
        std::fs::write(&path, content).unwrap();
        let cpath = CString::new(path.to_str().unwrap()).unwrap();
        (wellen_open(cpath.as_ptr()), path)
    }

    /// The linked lxt2fst C ABI converts a committed LXT2 fixture, and this
    /// library's own reader opens the result — the full desktop/mobile
    /// convert-on-open round trip inside the one shipped library.
    #[test]
    fn linked_lxt2fst_converts_and_wellen_opens_the_result() {
        assert_eq!(_lxt2fst::lxt2fst_abi_version(), _lxt2fst::ABI_VERSION);

        let src = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../test/fixtures/legacy/simple_counter.lxt2"
        );
        let dst = std::env::temp_dir().join("wellen_ffi_linked_lxt2fst.fst");
        let _ = std::fs::remove_file(&dst);
        let c_src = CString::new(src).unwrap();
        let c_dst = CString::new(dst.to_str().unwrap()).unwrap();
        let code =
            _lxt2fst::lxt2fst_convert(c_src.as_ptr(), c_dst.as_ptr(), None, std::ptr::null_mut());
        assert_eq!(code, 0, "lxt2fst_convert failed");

        let h = wellen_open(c_dst.as_ptr());
        assert!(!h.is_null(), "wellen could not open the converted FST");
        assert_eq!(wellen_file_format(h), FORMAT_FST);
        wellen_close(h);
        let _ = std::fs::remove_file(&dst);
    }

    #[test]
    fn test_open_close() {
        let (h, _tmp) = open_test_vcd();
        assert!(!h.is_null());
        wellen_close(h);
    }

    #[test]
    fn test_metadata() {
        let (h, _tmp) = open_test_vcd();
        // wellen 0.20+ adds a synthetic root scope, so scope count is 2
        // (synthetic root + "top"). The public API correctly returns 1 root
        // scope via wellen_root_scopes.
        assert_eq!(wellen_num_scopes(h), 2);
        assert_eq!(wellen_num_vars(h), 2);
        assert!(wellen_time_end(h) > 0);
        wellen_close(h);
    }

    #[test]
    fn test_hierarchy_traversal() {
        let (h, _tmp) = open_test_vcd();
        let mut root_scopes = [0u64; 8];
        let n = wellen_root_scopes(h, root_scopes.as_mut_ptr(), 8);
        assert_eq!(n, 1);
        let scope_idx = root_scopes[0];

        let name_ptr = wellen_scope_name(h, scope_idx);
        let name = unsafe { CStr::from_ptr(name_ptr) }.to_str().unwrap();
        assert_eq!(name, "top");

        let mut child_vars = [0u64; 8];
        let nv = wellen_scope_child_vars(h, scope_idx, child_vars.as_mut_ptr(), 8);
        assert_eq!(nv, 2);

        let clk_name_ptr = wellen_var_name(h, child_vars[0]);
        let clk_name = unsafe { CStr::from_ptr(clk_name_ptr) }.to_str().unwrap();
        assert_eq!(clk_name, "clk");

        assert_eq!(wellen_var_length(h, child_vars[0]), 1);
        assert_eq!(wellen_var_length(h, child_vars[1]), 8);
        wellen_close(h);
    }

    #[test]
    fn test_signal_load_and_value_at() {
        let (h, _tmp) = open_test_vcd();
        let mut root_scopes = [0u64; 8];
        wellen_root_scopes(h, root_scopes.as_mut_ptr(), 8);
        let mut child_vars = [0u64; 8];
        wellen_scope_child_vars(h, root_scopes[0], child_vars.as_mut_ptr(), 8);

        let sig_ref = wellen_var_signal_ref(h, child_vars[0]); // clk
        assert_ne!(sig_ref, u32::MAX);
        assert_eq!(wellen_load_signal(h, sig_ref), 0);

        let mut buf = [0u8; 64];
        // At t=0 clk=0, at t=10 clk=1
        let r0 = wellen_value_at(h, sig_ref, 0, buf.as_mut_ptr(), 64);
        assert!(r0 > 0);
        let v0 = std::str::from_utf8(&buf[..r0 as usize]).unwrap();
        assert_eq!(v0, "0");

        let r10 = wellen_value_at(h, sig_ref, 10, buf.as_mut_ptr(), 64);
        assert!(r10 > 0);
        let v10 = std::str::from_utf8(&buf[..r10 as usize]).unwrap();
        assert_eq!(v10, "1");

        wellen_close(h);
    }

    #[test]
    fn test_signal_changes() {
        let (h, _tmp) = open_test_vcd();
        let mut root_scopes = [0u64; 8];
        wellen_root_scopes(h, root_scopes.as_mut_ptr(), 8);
        let mut child_vars = [0u64; 8];
        wellen_scope_child_vars(h, root_scopes[0], child_vars.as_mut_ptr(), 8);

        let sig_ref = wellen_var_signal_ref(h, child_vars[0]); // clk
        wellen_load_signal(h, sig_ref);

        let mut times = [0u64; 16];
        let mut val_buf = [0u8; 256];
        let mut offsets = [0u32; 16];

        let count = wellen_signal_changes(
            h,
            sig_ref,
            0,
            50,
            times.as_mut_ptr(),
            val_buf.as_mut_ptr(),
            256,
            offsets.as_mut_ptr(),
            16,
        );
        assert!(count > 0);
        assert_eq!(times[0], 0);

        wellen_close(h);
    }

    #[test]
    fn test_transitions() {
        let (h, _tmp) = open_test_vcd();
        let mut root_scopes = [0u64; 8];
        wellen_root_scopes(h, root_scopes.as_mut_ptr(), 8);
        let mut child_vars = [0u64; 8];
        wellen_scope_child_vars(h, root_scopes[0], child_vars.as_mut_ptr(), 8);

        let sig_ref = wellen_var_signal_ref(h, child_vars[0]);
        wellen_load_signal(h, sig_ref);

        let mut out_time = 0u64;
        let mut buf = [0u8; 64];

        let r = wellen_next_transition(h, sig_ref, 0, &mut out_time, buf.as_mut_ptr(), 64);
        assert_eq!(r, 1);
        assert_eq!(out_time, 10);

        let r2 = wellen_prev_transition(h, sig_ref, 20, &mut out_time, buf.as_mut_ptr(), 64);
        assert_eq!(r2, 1);
        assert_eq!(out_time, 10);

        wellen_close(h);
    }

    #[test]
    fn test_null_handle_safety() {
        assert_eq!(wellen_num_scopes(std::ptr::null()), 0);
        assert_eq!(wellen_time_end(std::ptr::null()), 0);
        assert!(!wellen_last_error(std::ptr::null()).is_null());
    }

    #[test]
    fn test_open_error_message_on_malformed_vcd() {
        // Scalar value changes must be "<value><id>" with no space; the
        // space here makes wellen report "expected an id for a value
        // change" — the exact malformation that produced a useless generic
        // error before this getter existed.
        let content = b"$timescale 1ns $end\n\
            $scope module top $end\n\
            $var wire 1 ! clk $end\n\
            $upscope $end\n\
            $enddefinitions $end\n\
            #0\n\
            0 !\n";
        let path = std::env::temp_dir().join("wellen_ffi_test_malformed.vcd");
        std::fs::write(&path, content).unwrap();
        let cpath = CString::new(path.to_str().unwrap()).unwrap();

        let h = wellen_open(cpath.as_ptr());
        assert!(h.is_null(), "malformed VCD must fail to open");

        let err = unsafe { CStr::from_ptr(wellen_last_open_error()) }
            .to_str()
            .unwrap();
        assert!(!err.is_empty(), "open failure must carry a reason");
        assert!(
            err.contains("id for a value change") || err.to_lowercase().contains("vcd"),
            "error should describe the VCD problem, got: {err}"
        );
    }

    #[test]
    fn test_open_error_cleared_after_success() {
        // A failure sets the thread-local; a subsequent success clears it.
        let bad = std::env::temp_dir().join("wellen_ffi_test_bad.vcd");
        std::fs::write(&bad, b"not a waveform at all\n").unwrap();
        let cbad = CString::new(bad.to_str().unwrap()).unwrap();
        let h0 = wellen_open(cbad.as_ptr());
        assert!(h0.is_null());
        assert!(
            !unsafe { CStr::from_ptr(wellen_last_open_error()) }
                .to_bytes()
                .is_empty()
        );

        let (h, _tmp) = open_test_vcd();
        assert!(!h.is_null(), "valid VCD should open");
        assert!(
            unsafe { CStr::from_ptr(wellen_last_open_error()) }
                .to_bytes()
                .is_empty(),
            "successful open should clear the error"
        );
        wellen_close(h);
    }

    #[test]
    fn test_file_format_vcd() {
        let (h, _tmp) = open_test_vcd();
        assert!(!h.is_null(), "test VCD should open successfully");
        assert_eq!(wellen_file_format(h), FORMAT_VCD);
        wellen_close(h);
    }

    #[test]
    fn test_file_format_unknown_extension() {
        // Write the same content but with an unrecognised extension.
        let content = b"$timescale 1ns $end\n\
            $scope module top $end\n\
            $var wire 1 ! clk $end\n\
            $upscope $end\n\
            $enddefinitions $end\n\
            #0 0!\n";
        let path = std::env::temp_dir().join("wellen_ffi_test_fmt.dat");
        std::fs::write(&path, content).unwrap();
        let cpath = CString::new(path.to_str().unwrap()).unwrap();
        let h = wellen_open(cpath.as_ptr());
        // wellen can still parse it, but the format should be unknown.
        if !h.is_null() {
            assert_eq!(wellen_file_format(h), FORMAT_UNKNOWN);
            wellen_close(h);
        }
    }

    #[test]
    fn test_null_handle_file_format() {
        assert_eq!(wellen_file_format(std::ptr::null()), FORMAT_UNKNOWN);
    }

    #[test]
    fn test_total_transition_count() {
        let (h, _tmp) = open_test_vcd();

        // Before loading any signals, count should be 0.
        assert_eq!(wellen_total_transition_count(h), 0);

        let mut root_scopes = [0u64; 8];
        wellen_root_scopes(h, root_scopes.as_mut_ptr(), 8);
        let mut child_vars = [0u64; 8];
        wellen_scope_child_vars(h, root_scopes[0], child_vars.as_mut_ptr(), 8);

        // Load clk (5 changes: 0,10,20,30,40).
        let clk_ref = wellen_var_signal_ref(h, child_vars[0]);
        wellen_load_signal(h, clk_ref);
        let after_clk = wellen_total_transition_count(h);
        assert!(after_clk > 0, "total should grow after loading clk");

        // Load data (2 changes: 0,20).
        let data_ref = wellen_var_signal_ref(h, child_vars[1]);
        wellen_load_signal(h, data_ref);
        let after_data = wellen_total_transition_count(h);
        assert!(
            after_data > after_clk,
            "total should grow after loading data"
        );

        // Loading clk again must not double-count.
        wellen_load_signal(h, clk_ref);
        assert_eq!(wellen_total_transition_count(h), after_data);

        wellen_close(h);
    }

    #[test]
    fn test_signal_transition_count() {
        let (h, _tmp) = open_test_vcd();
        let mut root_scopes = [0u64; 8];
        wellen_root_scopes(h, root_scopes.as_mut_ptr(), 8);
        let mut child_vars = [0u64; 8];
        wellen_scope_child_vars(h, root_scopes[0], child_vars.as_mut_ptr(), 8);

        let clk_ref = wellen_var_signal_ref(h, child_vars[0]);

        // Not yet loaded — should return 0.
        assert_eq!(wellen_signal_transition_count(h, clk_ref), 0);

        wellen_load_signal(h, clk_ref);
        // The test VCD has clk toggling at 0,10,20,30,40 → 5 changes.
        assert_eq!(wellen_signal_transition_count(h, clk_ref), 5);

        wellen_close(h);
    }

    #[test]
    fn test_null_handle_diagnostics() {
        assert_eq!(wellen_total_transition_count(std::ptr::null()), 0);
        assert_eq!(wellen_signal_transition_count(std::ptr::null(), 1), 0);
        assert_eq!(wellen_memory_usage_bytes(std::ptr::null()), 0);
    }

    /// Simulates the exact sequence the Dart worker performs when opening a file:
    ///   wellen_open → wellen_time_end → wellen_num_scopes → wellen_num_vars →
    ///   wellen_root_scopes → traverse hierarchy → load/count/unload every signal.
    /// Exercises the aliased-signal and empty-$dumpall characteristics of
    /// direction_test.vcd.
    #[test]
    fn test_direction_test_vcd_full_open_sequence() {
        let path = "test-data/direction_test.vcd";
        if !std::path::Path::new(path).exists() {
            return; // skip if not present on this machine
        }

        let cpath = CString::new(path).unwrap();
        let h = wellen_open(cpath.as_ptr());
        assert!(
            !h.is_null(),
            "wellen_open returned null for direction_test.vcd"
        );

        let end_time = wellen_time_end(h);
        assert!(end_time > 0, "end_time should be > 0; got {end_time}");

        let num_scopes = wellen_num_scopes(h);
        let num_vars = wellen_num_vars(h);
        assert!(num_vars > 0, "num_vars should be > 0; got {num_vars}");

        // Collect root scopes (mirrors _buildRootScopes in Dart).
        let mut root_buf = [0u64; 32];
        let root_count = wellen_root_scopes(h, root_buf.as_mut_ptr(), 32);
        assert!(root_count > 0, "no root scopes returned");

        // Recursively collect all unique signal refs (mirrors _countTotalTransitions).
        fn collect_signal_refs(
            h: *const WellenHandle,
            scope_idx: u64,
            num_scopes: u64,
            num_vars: u64,
            out: &mut std::collections::HashSet<u32>,
        ) {
            let mut cs_buf = vec![0u64; num_scopes as usize];
            let cs_count = wellen_scope_child_scopes(h, scope_idx, cs_buf.as_mut_ptr(), num_scopes);
            for &child in cs_buf.iter().take(cs_count.max(0) as usize) {
                collect_signal_refs(h, child, num_scopes, num_vars, out);
            }
            let mut var_buf = vec![0u64; num_vars as usize];
            let v_count = wellen_scope_child_vars(h, scope_idx, var_buf.as_mut_ptr(), num_vars);
            for &var in var_buf.iter().take(v_count.max(0) as usize) {
                let sr = wellen_var_signal_ref(h, var);
                if sr != u32::MAX {
                    out.insert(sr);
                }
            }
        }
        let mut all_refs = std::collections::HashSet::new();
        for &root in root_buf.iter().take(root_count as usize) {
            collect_signal_refs(h, root, num_scopes, num_vars, &mut all_refs);
        }
        assert!(!all_refs.is_empty(), "no signal refs found");

        // Load / count / unload every unique signal ref.
        let mut total: u64 = 0;
        for &sr in &all_refs {
            let rc = wellen_load_signal(h, sr);
            assert_eq!(rc, 0, "wellen_load_signal failed for signal_ref {sr}");
            total += wellen_signal_transition_count(h, sr);
            wellen_unload_signal(h, sr);
        }
        assert!(
            total > 0,
            "total transition count should be > 0; got {total}"
        );

        wellen_close(h);
    }

    #[test]
    fn test_memory_usage_bytes() {
        let (h, _tmp) = open_test_vcd();
        // Without any loaded signals, we still have time_table + hierarchy overhead.
        let base = wellen_memory_usage_bytes(h);
        assert!(base > 0, "memory estimate should be non-zero after open");

        // After loading a signal the estimate should grow.
        let mut root_scopes = [0u64; 8];
        wellen_root_scopes(h, root_scopes.as_mut_ptr(), 8);
        let mut child_vars = [0u64; 8];
        wellen_scope_child_vars(h, root_scopes[0], child_vars.as_mut_ptr(), 8);
        let clk_ref = wellen_var_signal_ref(h, child_vars[0]);
        wellen_load_signal(h, clk_ref);

        let after_load = wellen_memory_usage_bytes(h);
        assert!(
            after_load >= base,
            "memory estimate should not shrink after loading a signal"
        );

        wellen_close(h);
    }
}

/// Deterministic reproduction harness for the intermittent SIGBUS observed
/// when "Add all in scope" is run against the captured RISC-V (picorv32)
/// trace (`riscv_picorv32_wb_ez.fst`).
///
/// The crash is a wild native read (KERN_PROTECTION_FAILURE at a page-aligned
/// address far inside reserved address space) on the wellen worker thread,
/// during the bulk load + change-query pass that "Add all in scope" drives.
/// Because `ffi_guard!` wraps every entry point in `catch_unwind`, a Rust
/// panic (e.g. a bounds check) would surface as an error code, not a SIGBUS —
/// so reaching a real signal means the fault is genuine memory unsafety inside
/// wellen's compressed-signal decode, not a recoverable panic.
///
/// This module exercises the EXACT sequence the Dart worker performs for
/// "Add all in scope":
///   wellen_open → enumerate every signal ref → for each:
///     wellen_load_signal → wellen_signal_changes([0, end+1)) with the same
///     growing-buffer doubling logic as `_fetchAllChanges` in
///     `wellen_provider_io.dart`.
///
/// Two entry points:
///   * `captured_riscv_add_all_in_scope_does_not_crash` — single bounded pass,
///     runs in the normal suite as the regression test for the fix.
///   * `captured_riscv_add_all_in_scope_stress` — `#[ignore]`d loop that
///     re-opens the file and replays the whole sequence N times
///     (`WELLEN_REPRO_ITERS`, default 200) to make the heap/timing-dependent
///     fault deterministic. Run under AddressSanitizer to name the exact
///     out-of-bounds read:
///     `RUSTFLAGS="-Zsanitizer=address" cargo +nightly test
///     --target aarch64-apple-darwin captured_riscv_add_all_in_scope_stress
///     -- --ignored --nocapture`
#[cfg(test)]
mod captured_riscv_repro {
    use super::*;
    use std::collections::HashSet;
    use std::ffi::CString;

    /// Committed captured fixture, resolved relative to this crate. The path is
    /// `<repo>/verification/fixtures/protocol/riscv/captured/...` and this crate
    /// lives at `<repo>/native/wellen_ffi`, so climb two directories.
    const FIXTURE: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../verification/fixtures/protocol/riscv/captured/riscv_picorv32_wb_ez.fst"
    );

    fn open_fixture() -> Option<*mut WellenHandle> {
        if !std::path::Path::new(FIXTURE).exists() {
            return None; // skip on machines without the captured corpus
        }
        let cpath = CString::new(FIXTURE).unwrap();
        let h = wellen_open(cpath.as_ptr());
        assert!(!h.is_null(), "wellen_open returned null for {FIXTURE}");
        Some(h)
    }

    /// Recursively collect every unique signal ref by walking the hierarchy,
    /// mirroring `_buildRootScopes` / `_countTotalTransitions` on the Dart side.
    fn collect_signal_refs(h: *const WellenHandle) -> Vec<u32> {
        let num_scopes = wellen_num_scopes(h);
        let num_vars = wellen_num_vars(h);

        fn walk(
            h: *const WellenHandle,
            scope_idx: u64,
            num_scopes: u64,
            num_vars: u64,
            out: &mut HashSet<u32>,
        ) {
            let mut cs_buf = vec![0u64; num_scopes as usize];
            let cs_count = wellen_scope_child_scopes(h, scope_idx, cs_buf.as_mut_ptr(), num_scopes);
            for &child in cs_buf.iter().take(cs_count.max(0) as usize) {
                walk(h, child, num_scopes, num_vars, out);
            }
            let mut var_buf = vec![0u64; num_vars as usize];
            let v_count = wellen_scope_child_vars(h, scope_idx, var_buf.as_mut_ptr(), num_vars);
            for &var in var_buf.iter().take(v_count.max(0) as usize) {
                let sr = wellen_var_signal_ref(h, var);
                if sr != u32::MAX {
                    out.insert(sr);
                }
            }
        }

        let mut root_buf = vec![0u64; num_scopes.max(1) as usize];
        let root_count = wellen_root_scopes(h, root_buf.as_mut_ptr(), num_scopes.max(1));
        let mut refs = HashSet::new();
        for &root in root_buf.iter().take(root_count.max(0) as usize) {
            walk(h, root, num_scopes, num_vars, &mut refs);
        }
        refs.into_iter().collect()
    }

    /// Fetch every value change for `sr` in `[0, end+1)`, replicating the
    /// growing-buffer doubling loop in `_fetchAllChanges`. Returns the change
    /// count (>= 0). A wild read inside wellen faults here before returning.
    fn fetch_all_changes(h: *const WellenHandle, sr: u32, end_time: u64) -> i64 {
        let query_end = if end_time == 0 { 1 } else { end_time + 1 };
        let mut max_count: i64 = 1024;
        let mut value_buf_len: u32 = (max_count as u32) * 20;

        loop {
            let mut times = vec![0u64; max_count as usize];
            let mut offsets = vec![0u32; max_count as usize];
            let mut val_buf = vec![0u8; value_buf_len as usize];

            let count = wellen_signal_changes(
                h,
                sr,
                0,
                query_end,
                times.as_mut_ptr(),
                val_buf.as_mut_ptr(),
                value_buf_len,
                offsets.as_mut_ptr(),
                max_count,
            );

            if count == -2 {
                max_count *= 2;
                value_buf_len = value_buf_len.saturating_mul(2);
                continue;
            }
            assert!(
                count >= 0,
                "wellen_signal_changes errored ({count}) for ref {sr}"
            );
            return count;
        }
    }

    /// One full "Add all in scope" pass over an open handle: load every signal
    /// and fetch all of its changes. Returns total changes observed.
    fn add_all_in_scope(h: *mut WellenHandle) -> u64 {
        let refs = collect_signal_refs(h);
        assert!(!refs.is_empty(), "no signal refs found in {FIXTURE}");
        let end_time = wellen_time_end(h);
        let mut total = 0u64;
        for sr in refs {
            assert_eq!(wellen_load_signal(h, sr), 0, "load failed for ref {sr}");
            total += fetch_all_changes(h, sr, end_time) as u64;
        }
        total
    }

    /// Single bounded pass — the regression test. Loads every signal in the
    /// captured RISC-V trace and fetches all changes; must not crash.
    #[test]
    fn captured_riscv_add_all_in_scope_does_not_crash() {
        let Some(h) = open_fixture() else {
            return; // fixture not present on this machine
        };
        let total = add_all_in_scope(h);
        assert!(
            total > 0,
            "expected at least one value change across all signals"
        );
        wellen_close(h);
    }

    /// Stress loop — re-opens the file and replays the whole sequence N times
    /// to provoke the intermittent fault. Ignored by default; run under ASan to
    /// capture the offending wellen frame. Override iteration count with
    /// `WELLEN_REPRO_ITERS`.
    #[test]
    #[ignore = "stress/ASan repro — run explicitly with --ignored"]
    fn captured_riscv_add_all_in_scope_stress() {
        if !std::path::Path::new(FIXTURE).exists() {
            return;
        }
        let iters: u32 = std::env::var("WELLEN_REPRO_ITERS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(200);

        for i in 0..iters {
            let Some(h) = open_fixture() else { return };
            let total = add_all_in_scope(h);
            assert!(total > 0, "iteration {i}: no changes observed");
            wellen_close(h);
        }
    }

    /// Concurrent stress — `WELLEN_REPRO_THREADS` (default 8) threads, each
    /// owning its OWN handle, all replaying "Add all in scope" in parallel for
    /// `WELLEN_REPRO_ITERS` (default 100) iterations. This mirrors the
    /// real-world trigger the single-threaded loop can't reach: multiple
    /// wellen handles (two open files, the diff/comparison view, or a Pro
    /// override provider running beside the open-core one) hammering the
    /// library's shared global state — including rayon's global pool used by
    /// `load_signals` — at the same time. Ignored by default; run under ASan
    /// once a nightly toolchain is installed.
    #[test]
    #[ignore = "concurrent stress/ASan repro — run explicitly with --ignored"]
    fn captured_riscv_add_all_in_scope_concurrent() {
        if !std::path::Path::new(FIXTURE).exists() {
            return;
        }
        let threads: u32 = std::env::var("WELLEN_REPRO_THREADS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(8);
        let iters: u32 = std::env::var("WELLEN_REPRO_ITERS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(100);

        let handles: Vec<_> = (0..threads)
            .map(|t| {
                std::thread::spawn(move || {
                    for i in 0..iters {
                        // *mut WellenHandle is not Send — create it inside the
                        // thread so each thread drives an independent handle.
                        let Some(h) = open_fixture() else { return };
                        let total = add_all_in_scope(h);
                        assert!(total > 0, "thread {t} iter {i}: no changes");
                        wellen_close(h);
                    }
                })
            })
            .collect();

        for h in handles {
            h.join().expect("a stress thread panicked or crashed");
        }
    }
}
