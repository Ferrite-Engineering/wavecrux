// lxt2fst_loader.js — bridges the lxt2fst wasm-bindgen ES module to
// globalThis so Flutter's `dart:js_interop` can convert LXT/LXT2 files.
//
// The wasm-bindgen build (`dart run tool/build_lxt2fst_wasm.dart`, which runs
// `wasm-pack build --target web`) emits `web/wasm/lxt2fst.js` plus
// `lxt2fst_bg.wasm`. Dart cannot import an ES module at runtime, so this
// script publishes a small loader object on `globalThis.waveCruxLxt2Fst`,
// the shape `lib/services/waveform/lxt2fst_converter_web.dart` binds:
//
//   ensureReady()               → Promise resolving to null on success, or
//                                 to the load error
//   convert(bytes, progress?)   → Uint8Array of FST bytes; throws on failure
//   abiVersion()                → number
//
// Lazy on purpose. Unlike `wellen_wasm_loader.js`, nothing is fetched at page
// load: the module and its wasm are imported on the first `ensureReady()`,
// i.e. the first time someone opens an LXT/LXT2 file, so every other visitor
// pays nothing for the converter.
//
// Loaded via `<script type="module" src="wasm/lxt2fst_loader.js">` from
// `web/index.html` (and the Pro overlay's copy, synced by its
// `tool/sync_web_wasm.dart`).

let converter = null;
let readyPromise = null;
let readyError = null;

function ensureReady() {
  if (readyPromise) return readyPromise;
  readyPromise = (async () => {
    try {
      const module = await import('./lxt2fst.js');
      // Explicit URL so the fetch resolves next to this script even when the
      // page is served from a base href other than `/`.
      const wasmUrl = new URL('./lxt2fst_bg.wasm', import.meta.url);
      await module.default({ module_or_path: wasmUrl });
      converter = module;
      return null;
    } catch (err) {
      readyError = err;
      return err;
    }
  })();
  return readyPromise;
}

function loaded() {
  if (converter) return converter;
  if (readyError) {
    throw new Error('lxt2fst wasm failed to load: ' + readyError);
  }
  throw new Error('lxt2fst wasm is not loaded; await ensureReady() first');
}

function convert(bytes, progress) {
  // wasm-bindgen copies `bytes` into linear memory and returns a fresh
  // Uint8Array; a Rust-side conversion error surfaces as a thrown string.
  return loaded().lxt2fstConvert(bytes, progress ?? undefined);
}

function abiVersion() {
  return loaded().lxt2fstAbiVersion();
}

globalThis.waveCruxLxt2Fst = {
  ensureReady,
  convert,
  abiVersion,
};
