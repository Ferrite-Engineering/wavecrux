// wellen_wasm_loader.js — bridges the wasm-bindgen ES module to globalThis
// so Flutter's `dart:js_interop` can call it.
//
// The wasm-bindgen build (`wasm-pack build --target web`) emits an ES module
// in `web/wasm/wellen_wasm.js` plus the `.wasm` binary. ES modules cannot be
// dynamically imported from Dart's `dart:js_interop`, but they can be
// imported from another script and re-published on `globalThis`. This file
// does exactly that — it imports the wasm-bindgen output, kicks off the wasm
// instantiation, and exposes a small loader object that the Dart wrapper in
// `lib/services/waveform/wellen_wasm_provider_web.dart` consumes.
//
// Loaded via `<script type="module" src="wasm/wellen_wasm_loader.js">` from
// `web/index.html`. Once executed, `globalThis.waveCruxWellen` holds the
// loader. The Dart side calls `ensureReady()` (returns a Promise) before any
// other method; it resolves to `null` on success and to an error otherwise.

import init, * as wellenWasm from './wellen_wasm.js';

let readyPromise = null;
let readyError = null;

function ensureReady() {
  if (readyPromise) return readyPromise;
  readyPromise = (async () => {
    try {
      // The wasm-bindgen `init()` accepts either a URL/Request to the .wasm
      // file or no arguments (which falls back to relative resolution).
      // Passing the explicit URL avoids surprises when the page lives at a
      // base href other than `/`.
      const wasmUrl = new URL('./wellen_wasm_bg.wasm', import.meta.url);
      await init({ module_or_path: wasmUrl });
      return null;
    } catch (err) {
      readyError = err;
      return err;
    }
  })();
  return readyPromise;
}

function createWaveform(filename, bytes) {
  if (readyError) {
    throw new Error('wellen_wasm failed to load: ' + readyError);
  }
  // bytes is a Uint8Array passed straight from Dart; wasm-bindgen copies into
  // wasm linear memory inside the constructor.
  return new wellenWasm.WellenWasm(filename, bytes);
}

function abiVersion() {
  if (readyError) {
    throw new Error('wellen_wasm failed to load: ' + readyError);
  }
  return wellenWasm.abiVersion();
}

globalThis.waveCruxWellen = {
  ensureReady,
  createWaveform,
  abiVersion,
};
