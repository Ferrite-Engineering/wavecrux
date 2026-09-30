// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// wasm-bindgen surface for the web build.
//
// Mirrors the wellen_wasm pattern: free functions with the same
// convert-on-open semantics as the C-ABI, arranged so the Flutter Web
// file-picker / drag-and-drop flow can drive them via dart:js_interop. The
// hand-written `web/wasm/lxt2fst_loader.js` imports this module lazily and
// republishes it as `globalThis.waveCruxLxt2Fst`. The conversion is
// single-shot and synchronous (web has no Workers: threads would need
// SharedArrayBuffer, which requires cross-origin-isolation deployment headers
// the web build does without), and entirely in memory: wasm32-unknown-unknown
// has no filesystem.

use wasm_bindgen::prelude::*;

use crate::detect_format;

/// Convenience global installed at module load. Identical strategy to
/// `wellen_wasm`'s panic hook — turns Rust panics into useful browser
/// console messages instead of an opaque "unreachable executed" abort.
#[wasm_bindgen(start)]
pub fn _start() {
    console_error_panic_hook::set_once();
}

/// Convert an in-memory LXT/LXT2 buffer (e.g. from `File.arrayBuffer()`)
/// to FST bytes. The returned Uint8Array is the FST file body, which the
/// caller hands straight to the wellen-wasm loader. Nothing is cached: a
/// second open of the same file converts again.
///
/// `progress` is an optional JS function `(done: number, total: number)
/// => void`. The Rust side throttles to at most one call per 1% of
/// progress or 50 ms.
#[wasm_bindgen(js_name = lxt2fstConvert)]
pub fn js_convert(input: &[u8], progress: Option<js_sys::Function>) -> Result<Vec<u8>, JsValue> {
    let mut cb: Option<Box<dyn FnMut(u64, u64)>> = progress.map(|p| {
        let f: Box<dyn FnMut(u64, u64)> = Box::new(move |d: u64, t: u64| {
            let _ = p.call2(
                &JsValue::NULL,
                &JsValue::from_f64(d as f64),
                &JsValue::from_f64(t as f64),
            );
        });
        f
    });
    let cb_ref: Option<&mut dyn FnMut(u64, u64)> = match cb.as_mut() {
        Some(b) => Some(b.as_mut()),
        None => None,
    };

    crate::convert_bytes(input, cb_ref).map_err(|e| JsValue::from_str(&format!("{e}")))
}

/// JS-side magic-byte detection mirroring `lxt2fst_detect_format`.
/// Returns 0 / 1 / 2 — see the `LXT2FST_FORMAT_*` constants in
/// lxt2fst.h.
#[wasm_bindgen(js_name = lxt2fstDetectFormat)]
pub fn js_detect_format(head: &[u8]) -> u32 {
    detect_format(head) as u32
}

/// Returns the ABI version. The Dart-Web loader checks this against an
/// expected constant to reject mismatched modules at load time.
#[wasm_bindgen(js_name = lxt2fstAbiVersion)]
pub fn js_abi_version() -> u32 {
    crate::ABI_VERSION
}
