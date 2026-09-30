//! Rust port of the WaveCrux 1-Wire decoder demonstrator plugin.
//!
//! Same wire-level behavior as the C reference under
//! `examples/decoder-plugin-demo/`, written in idiomatic Rust against
//! the same C ABI exposed by `include/wavecrux_decoder.h`. The
//! two ports produce binary artifacts that are interchangeable from
//! the WaveCrux loader's perspective — pick whichever language you
//! prefer for your own plugin.
//!
//! Build:
//!   cargo build --release
//!
//! The resulting `target/release/libwavecrux_onewire.{so,dylib}` (or
//! `wavecrux_onewire.dll` on Windows) drops directly into the
//! WaveCrux plugin directory.

use std::ffi::{c_char, c_int, c_void};
use std::os::raw::c_uchar;
use std::ptr;

// ── ABI types and constants (mirroring wavecrux_decoder.h) ────────────────

/// (MAJOR << 16) | MINOR. The host's loader rejects mismatching MAJOR.
const ABI_VERSION: u32 = (1 << 16) | 0;

#[repr(i32)]
enum WcRc {
    Ok = 0,
    Err = 1,
    NeedMoreSlots = 2,
}

#[repr(C)]
pub struct WcSample {
    pub timestamp_fs: u64,
    pub bits_ptr: *const c_uchar,
    pub bit_width: u32,
    pub _reserved0: u32,
}

#[repr(C)]
pub struct WcTransaction {
    pub start_fs: u64,
    pub end_fs: u64,
    pub label: *const c_char,
    pub fields_json: *const c_char,
    pub is_error: u32,
    pub _reserved0: u32,
}

type WcDecoderHandle = *mut c_void;

#[repr(C)]
pub struct WcDecoderDef {
    pub id: *const c_char,
    pub display_name: *const c_char,
    pub manifest_json: *const c_char,
    pub create: extern "C" fn(*const c_char) -> WcDecoderHandle,
    pub feed: extern "C" fn(
        WcDecoderHandle,
        *const WcSample,
        *mut WcTransaction,
        *mut usize,
    ) -> i32,
    pub flush: extern "C" fn(
        WcDecoderHandle,
        *mut WcTransaction,
        *mut usize,
    ) -> i32,
    pub destroy: extern "C" fn(WcDecoderHandle),
    pub _reserved0: *mut c_void,
    pub _reserved1: u64,
}

// ── manifest and labels ────────────────────────────────────────────────────
//
// Use `\0`-terminated &'static [u8] slices and convert to `*const c_char`
// at the FFI boundary. Lifetime: `'static` matches the "borrowed by the
// loader for the lifetime of the shared library" rule from the header.

const MANIFEST_JSON: &[u8] = b"{\
\"signals\":[\
{\"name\":\"dq\",\"description\":\"1-Wire data line (DQ, open-drain)\",\"bit_width\":1}\
],\
\"parameters\":[],\
\"description\":\"Maxim / Dallas 1-Wire bus decoder. Observes a single DQ line and emits RESET, PRESENCE, and BYTE transactions.\",\
\"category\":\"userPlugin\"\
}\0";

const ID_STR: &[u8] = b"examples.onewire\0";
const DISPLAY_NAME_STR: &[u8] = b"1-Wire (demo plugin)\0";

const RESET_LABEL: &[u8] = b"RESET\0";
const RESET_FIELDS: &[u8] = b"{\"kind\":\"reset\"}\0";
const PRESENCE_LABEL: &[u8] = b"PRESENCE\0";
const PRESENCE_FIELDS: &[u8] = b"{\"kind\":\"presence\",\"valid\":\"true\"}\0";

// ── timing thresholds (femtoseconds) ──────────────────────────────────────

const fn us_to_fs(us: u64) -> u64 {
    us * 1_000_000_000
}

const RESET_LOW_MIN_FS: u64 = us_to_fs(400);
const PRESENCE_MIN_FS: u64 = us_to_fs(30);
const PRESENCE_MAX_FS: u64 = us_to_fs(240);
const BIT_ONE_MAX_FS: u64 = us_to_fs(15);
const BIT_ZERO_MIN_FS: u64 = us_to_fs(30);

// ── decoder state ──────────────────────────────────────────────────────────

const LABEL_MAX: usize = 64;
const FIELDS_MAX: usize = 192;
const MAX_PENDING: usize = 16;

#[derive(Clone, Copy)]
enum TxKind {
    Reset,
    Presence,
    Byte(u8),
}

#[derive(Clone, Copy)]
struct PendingTx {
    start_fs: u64,
    end_fs: u64,
    kind: TxKind,
    is_error: bool,
}

struct OneWireState {
    last_level: i8, // -1 uninitialised, 0 / 1 otherwise
    last_fall_fs: u64,
    last_was_reset: bool,
    byte_accum: u8,
    byte_bits: u8,
    byte_start_fs: u64,
    pending: [PendingTx; MAX_PENDING],
    pending_count: usize,
    label_buf: [[u8; LABEL_MAX]; MAX_PENDING],
    fields_buf: [[u8; FIELDS_MAX]; MAX_PENDING],
    buf_cursor: usize,
}

impl OneWireState {
    fn new() -> Self {
        Self {
            last_level: -1,
            last_fall_fs: 0,
            last_was_reset: false,
            byte_accum: 0,
            byte_bits: 0,
            byte_start_fs: 0,
            pending: [PendingTx {
                start_fs: 0,
                end_fs: 0,
                kind: TxKind::Reset,
                is_error: false,
            }; MAX_PENDING],
            pending_count: 0,
            label_buf: [[0u8; LABEL_MAX]; MAX_PENDING],
            fields_buf: [[0u8; FIELDS_MAX]; MAX_PENDING],
            buf_cursor: 0,
        }
    }

    fn enqueue(&mut self, tx: PendingTx) {
        if self.pending_count >= MAX_PENDING {
            return; // drop on overflow
        }
        self.pending[self.pending_count] = tx;
        self.pending_count += 1;
    }

    /// Write a NUL-terminated copy of `src` into `dst`, truncating if
    /// necessary. Returns a `*const c_char` pointing into `dst`.
    fn write_cstr(dst: &mut [u8], src: &[u8]) -> *const c_char {
        let n = src.len().min(dst.len() - 1);
        dst[..n].copy_from_slice(&src[..n]);
        dst[n] = 0;
        dst.as_ptr() as *const c_char
    }

    fn format_pending(&mut self, tx: PendingTx, out: &mut WcTransaction) {
        let slot = self.buf_cursor;
        self.buf_cursor = (self.buf_cursor + 1) % MAX_PENDING;
        let (label_src, fields_src);
        let mut byte_label = [0u8; LABEL_MAX];
        let mut byte_fields = [0u8; FIELDS_MAX];
        match tx.kind {
            TxKind::Reset => {
                label_src = RESET_LABEL;
                fields_src = RESET_FIELDS;
            }
            TxKind::Presence => {
                label_src = PRESENCE_LABEL;
                fields_src = PRESENCE_FIELDS;
            }
            TxKind::Byte(value) => {
                let label = format!("BYTE 0x{:02X}\0", value);
                let fields = format!(
                    "{{\"value\":\"0x{:02X}\",\"bits\":\"8\"}}\0",
                    value
                );
                let lb = label.as_bytes();
                let fb = fields.as_bytes();
                let nl = lb.len().min(LABEL_MAX);
                let nf = fb.len().min(FIELDS_MAX);
                byte_label[..nl].copy_from_slice(&lb[..nl]);
                byte_fields[..nf].copy_from_slice(&fb[..nf]);
                label_src = &byte_label;
                fields_src = &byte_fields;
            }
        }
        out.start_fs = tx.start_fs;
        out.end_fs = tx.end_fs;
        out.label = Self::write_cstr(&mut self.label_buf[slot], label_src);
        out.fields_json =
            Self::write_cstr(&mut self.fields_buf[slot], fields_src);
        out.is_error = if tx.is_error { 1 } else { 0 };
        out._reserved0 = 0;
    }
}

// ── helpers ────────────────────────────────────────────────────────────────

fn extract_level(sample: &WcSample) -> i8 {
    if sample.bit_width == 0 || sample.bits_ptr.is_null() {
        return 1; // assume idle
    }
    // Safety: caller guarantees `bits_ptr` points to at least
    // ceil(2 * bit_width / 8) bytes for the lifetime of this call
    // (the loader allocates the buffer).
    let b = unsafe { *sample.bits_ptr };
    let unknown = (b >> 1) & 1;
    if unknown != 0 {
        return -1;
    }
    (b & 1) as i8
}

// ── lifecycle callbacks ────────────────────────────────────────────────────

extern "C" fn ow_create(_config_json: *const c_char) -> WcDecoderHandle {
    let state = Box::new(OneWireState::new());
    Box::into_raw(state) as WcDecoderHandle
}

extern "C" fn ow_feed(
    handle: WcDecoderHandle,
    sample: *const WcSample,
    out_transactions: *mut WcTransaction,
    inout_count: *mut usize,
) -> i32 {
    if handle.is_null() || sample.is_null() || inout_count.is_null() {
        if !inout_count.is_null() {
            unsafe { *inout_count = 0 };
        }
        return WcRc::Err as i32;
    }
    let st: &mut OneWireState = unsafe { &mut *(handle as *mut OneWireState) };
    let s: &WcSample = unsafe { &*sample };

    let level = extract_level(s);
    if level >= 0 && level != st.last_level {
        if st.last_level == -1 {
            // First feed call.
            if level == 0 {
                st.last_fall_fs = s.timestamp_fs;
            }
        } else if st.last_level == 1 && level == 0 {
            st.last_fall_fs = s.timestamp_fs;
        } else if st.last_level == 0 && level == 1 {
            let dur = s.timestamp_fs.saturating_sub(st.last_fall_fs);
            let mut tx = PendingTx {
                start_fs: st.last_fall_fs,
                end_fs: s.timestamp_fs,
                kind: TxKind::Reset,
                is_error: false,
            };
            if dur >= RESET_LOW_MIN_FS {
                tx.kind = TxKind::Reset;
                st.enqueue(tx);
                st.last_was_reset = true;
                st.byte_accum = 0;
                st.byte_bits = 0;
            } else if st.last_was_reset
                && dur >= PRESENCE_MIN_FS
                && dur <= PRESENCE_MAX_FS
            {
                tx.kind = TxKind::Presence;
                st.enqueue(tx);
                st.last_was_reset = false;
            } else {
                let bit: u8 = if dur < BIT_ONE_MAX_FS {
                    1
                } else if dur >= BIT_ZERO_MIN_FS {
                    0
                } else {
                    tx.is_error = true;
                    0
                };
                if st.byte_bits == 0 {
                    st.byte_start_fs = st.last_fall_fs;
                    st.byte_accum = 0;
                }
                st.byte_accum |= (bit & 1) << st.byte_bits;
                st.byte_bits += 1;
                st.last_was_reset = false;
                if st.byte_bits == 8 {
                    let byte_tx = PendingTx {
                        start_fs: st.byte_start_fs,
                        end_fs: s.timestamp_fs,
                        kind: TxKind::Byte(st.byte_accum),
                        is_error: tx.is_error,
                    };
                    st.enqueue(byte_tx);
                    st.byte_accum = 0;
                    st.byte_bits = 0;
                }
            }
        }
        st.last_level = level;
    }

    drain(st, out_transactions, inout_count)
}

extern "C" fn ow_flush(
    handle: WcDecoderHandle,
    out_transactions: *mut WcTransaction,
    inout_count: *mut usize,
) -> i32 {
    if handle.is_null() || inout_count.is_null() {
        if !inout_count.is_null() {
            unsafe { *inout_count = 0 };
        }
        return WcRc::Err as i32;
    }
    let st: &mut OneWireState = unsafe { &mut *(handle as *mut OneWireState) };
    drain(st, out_transactions, inout_count)
}

fn drain(
    st: &mut OneWireState,
    out_transactions: *mut WcTransaction,
    inout_count: *mut usize,
) -> i32 {
    let cap = unsafe { *inout_count };
    if cap == 0 && st.pending_count > 0 {
        return WcRc::NeedMoreSlots as i32;
    }
    let mut emitted = 0usize;
    while emitted < cap && emitted < st.pending_count {
        let tx = st.pending[emitted];
        let out = unsafe { &mut *out_transactions.add(emitted) };
        st.format_pending(tx, out);
        emitted += 1;
    }
    if emitted > 0 && st.pending_count > emitted {
        for i in emitted..st.pending_count {
            st.pending[i - emitted] = st.pending[i];
        }
    }
    st.pending_count -= emitted;
    unsafe { *inout_count = emitted };
    if st.pending_count > 0 {
        WcRc::NeedMoreSlots as i32
    } else {
        WcRc::Ok as i32
    }
}

extern "C" fn ow_destroy(handle: WcDecoderHandle) {
    if handle.is_null() {
        return;
    }
    // Safety: handle was created by `Box::into_raw` in `ow_create`.
    unsafe {
        drop(Box::from_raw(handle as *mut OneWireState));
    }
}

// ── ABI entry points ───────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn wavecrux_decoder_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn wavecrux_decoder_register(
    out_defs: *mut WcDecoderDef,
    inout_count: *mut usize,
) -> i32 {
    if inout_count.is_null() {
        return WcRc::Err as i32;
    }
    let cap = unsafe { *inout_count };
    if out_defs.is_null() || cap == 0 {
        unsafe { *inout_count = 1 };
        return WcRc::NeedMoreSlots as i32;
    }
    let def = WcDecoderDef {
        id: ID_STR.as_ptr() as *const c_char,
        display_name: DISPLAY_NAME_STR.as_ptr() as *const c_char,
        manifest_json: MANIFEST_JSON.as_ptr() as *const c_char,
        create: ow_create,
        feed: ow_feed,
        flush: ow_flush,
        destroy: ow_destroy,
        _reserved0: ptr::null_mut(),
        _reserved1: 0,
    };
    unsafe {
        *out_defs = def;
        *inout_count = 1;
    }
    let _ = c_int::default(); // suppress unused-import lint
    WcRc::Ok as i32
}
