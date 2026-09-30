/* @ts-self-types="./wellen_wasm.d.ts" */

export class WellenWasm {
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        WellenWasmFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_wellenwasm_free(ptr, 0);
    }
    /**
     * Return the simulation date string (from the file header), or empty if
     * absent.
     * @returns {string}
     */
    date() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_date(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Return file format identifier (1 = VCD, 2 = FST, 3 = GHW, 0 = unknown).
     * @returns {number}
     */
    fileFormat() {
        const ret = wasm.wellenwasm_fileFormat(this.__wbg_ptr);
        return ret;
    }
    /**
     * Load signal data for `signal_ref`. Returns the change count (also
     * cached internally). Returns 0 on error. Return value is `f64` because
     * JS Numbers fit ~53 bits of integer precision — more than enough for any
     * transition count we ship.
     * @param {number} signal_ref
     * @returns {number}
     */
    loadSignal(signal_ref) {
        const ret = wasm.wellenwasm_loadSignal(this.__wbg_ptr, signal_ref);
        return ret;
    }
    /**
     * Approximate memory usage in bytes — same formula as the FFI crate.
     * @returns {number}
     */
    memoryUsageBytes() {
        const ret = wasm.wellenwasm_memoryUsageBytes(this.__wbg_ptr);
        return ret;
    }
    /**
     * Open a waveform from a byte buffer.
     *
     * `filename` is the user-visible filename (used for extension-based
     * format detection); the file contents come from `bytes`. Returns a
     * `WellenWasm` handle that must be `.free()`d by the JS caller.
     * @param {string} filename
     * @param {Uint8Array} bytes
     */
    constructor(filename, bytes) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(filename, wasm.__wbindgen_export3, wasm.__wbindgen_export4);
            const len0 = WASM_VECTOR_LEN;
            const ptr1 = passArray8ToWasm0(bytes, wasm.__wbindgen_export3);
            const len1 = WASM_VECTOR_LEN;
            wasm.wellenwasm_new(retptr, ptr0, len0, ptr1, len1);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            this.__wbg_ptr = r0;
            WellenWasmFinalization.register(this, this.__wbg_ptr, this);
            return this;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Find the next value change strictly after `after_time`.
     * Returns `{ time, value }` (time as JS Number) or `null` if none.
     * @param {number} signal_ref
     * @param {number} after_time
     * @returns {any}
     */
    nextTransition(signal_ref, after_time) {
        const ret = wasm.wellenwasm_nextTransition(this.__wbg_ptr, signal_ref, after_time);
        return takeObject(ret);
    }
    /**
     * Total number of scopes in the hierarchy.
     * @returns {number}
     */
    numScopes() {
        const ret = wasm.wellenwasm_numScopes(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Total number of variables in the hierarchy.
     * @returns {number}
     */
    numVars() {
        const ret = wasm.wellenwasm_numVars(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Find the last value change strictly before `before_time`.
     * Returns `{ time, value }` (time as JS Number) or `null` if none.
     * @param {number} signal_ref
     * @param {number} before_time
     * @returns {any}
     */
    prevTransition(signal_ref, before_time) {
        const ret = wasm.wellenwasm_prevTransition(this.__wbg_ptr, signal_ref, before_time);
        return takeObject(ret);
    }
    /**
     * Return indices of all top-level scopes as a Uint32Array (packed via
     * transmute to u32 — scope indices in wellen always fit).
     * @returns {Uint32Array}
     */
    rootScopes() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_rootScopes(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayU32FromWasm0(r0, r1).slice();
            wasm.__wbindgen_export(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Return indices of all top-level variables.
     * @returns {Uint32Array}
     */
    rootVars() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_rootVars(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayU32FromWasm0(r0, r1).slice();
            wasm.__wbindgen_export(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Return the child scope indices of `scope_idx`.
     * @param {number} scope_idx
     * @returns {Uint32Array}
     */
    scopeChildScopes(scope_idx) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_scopeChildScopes(retptr, this.__wbg_ptr, scope_idx);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayU32FromWasm0(r0, r1).slice();
            wasm.__wbindgen_export(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Return the child variable indices of `scope_idx`.
     * @param {number} scope_idx
     * @returns {Uint32Array}
     */
    scopeChildVars(scope_idx) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_scopeChildVars(retptr, this.__wbg_ptr, scope_idx);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayU32FromWasm0(r0, r1).slice();
            wasm.__wbindgen_export(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Return the name of the scope at `scope_idx`, or empty if out of range.
     * @param {number} scope_idx
     * @returns {string}
     */
    scopeName(scope_idx) {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_scopeName(retptr, this.__wbg_ptr, scope_idx);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Return the scope type identifier (see `scope_type_to_int` for mapping).
     * Returns -1 if scope_idx is out of range.
     * @param {number} scope_idx
     * @returns {number}
     */
    scopeType(scope_idx) {
        const ret = wasm.wellenwasm_scopeType(this.__wbg_ptr, scope_idx);
        return ret;
    }
    /**
     * Return all value changes for `signal_ref` in `[start_time, end_time)`
     * as a JS object: `{ times: Float64Array, values: string[] }`. The two
     * arrays are the same length; index i in `times` corresponds to the same
     * transition as index i in `values`. Times are encoded as `f64` (JS
     * Number) — simulation times fit in 53 bits.
     * @param {number} signal_ref
     * @param {number} start_time
     * @param {number} end_time
     * @returns {any}
     */
    signalChanges(signal_ref, start_time, end_time) {
        const ret = wasm.wellenwasm_signalChanges(this.__wbg_ptr, signal_ref, start_time, end_time);
        return takeObject(ret);
    }
    /**
     * Transition count for a single signal. Returns 0 if not loaded.
     * @param {number} signal_ref
     * @returns {number}
     */
    signalTransitionCount(signal_ref) {
        const ret = wasm.wellenwasm_signalTransitionCount(this.__wbg_ptr, signal_ref);
        return ret;
    }
    /**
     * Return the last time in the time table (simulation end time in ticks).
     *
     * Returned as `f64` rather than `u64` so the JS-side caller gets a plain
     * Number — simulation times fit in 53 bits comfortably and avoiding the
     * BigInt round-trip simplifies the Dart-side js_interop bindings.
     * @returns {number}
     */
    timeEnd() {
        const ret = wasm.wellenwasm_timeEnd(this.__wbg_ptr);
        return ret;
    }
    /**
     * Return the timescale factor (1 if no timescale), and the unit exponent
     * as a power of 10 (e.g. -9 for nanoseconds). The factor is encoded in
     * the high 32 bits of the returned u64; the unit-exponent (i32 cast to
     * u32) is encoded in the low 32 bits. Returns `0` (factor=0,
     * unitExp=i32::MIN treated as "no timescale") when the file declared
     * none.
     * @returns {any}
     */
    timescale() {
        const ret = wasm.wellenwasm_timescale(this.__wbg_ptr);
        return takeObject(ret);
    }
    /**
     * Total transitions across all loaded signals. Returned as `f64` so the
     * JS-side caller gets a plain Number — counts fit in 53 bits even for
     * very large captures.
     * @returns {number}
     */
    totalTransitionCount() {
        const ret = wasm.wellenwasm_totalTransitionCount(this.__wbg_ptr);
        return ret;
    }
    /**
     * Unload a previously loaded signal.
     * @param {number} signal_ref
     */
    unloadSignal(signal_ref) {
        wasm.wellenwasm_unloadSignal(this.__wbg_ptr, signal_ref);
    }
    /**
     * Return the signal value at the given simulation tick, as a string.
     * Returns empty string if the signal is not loaded or has no value at/before `time`.
     * `time` is `f64` (JS Number) — simulation times fit in 53 bits.
     * @param {number} signal_ref
     * @param {number} time
     * @returns {string}
     */
    valueAt(signal_ref, time) {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_valueAt(retptr, this.__wbg_ptr, signal_ref, time);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Return the variable direction identifier. Returns -1 on error.
     * @param {number} var_idx
     * @returns {number}
     */
    varDirection(var_idx) {
        const ret = wasm.wellenwasm_varDirection(this.__wbg_ptr, var_idx);
        return ret;
    }
    /**
     * Return the bit-width of the variable (0 if unavailable / not a bit vec).
     * @param {number} var_idx
     * @returns {number}
     */
    varLength(var_idx) {
        const ret = wasm.wellenwasm_varLength(this.__wbg_ptr, var_idx);
        return ret >>> 0;
    }
    /**
     * Return the variable name at `var_idx`, or empty if out of range.
     * @param {number} var_idx
     * @returns {string}
     */
    varName(var_idx) {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_varName(retptr, this.__wbg_ptr, var_idx);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Return the signal-ref (opaque u32) used for load_signal and value queries.
     * Returns u32::MAX on error.
     * @param {number} var_idx
     * @returns {number}
     */
    varSignalRef(var_idx) {
        const ret = wasm.wellenwasm_varSignalRef(this.__wbg_ptr, var_idx);
        return ret >>> 0;
    }
    /**
     * Return the variable type identifier. Returns -1 on error.
     * @param {number} var_idx
     * @returns {number}
     */
    varType(var_idx) {
        const ret = wasm.wellenwasm_varType(this.__wbg_ptr, var_idx);
        return ret;
    }
    /**
     * Return the simulator version string, or empty if absent.
     * @returns {string}
     */
    version() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wellenwasm_version(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) WellenWasm.prototype[Symbol.dispose] = WellenWasm.prototype.free;

/**
 * The wellen_wasm ABI version. JS callers should reject mismatches.
 * @returns {number}
 */
export function abiVersion() {
    const ret = wasm.abiVersion();
    return ret >>> 0;
}

export function init() {
    wasm.init();
}
function __wbg_get_imports() {
    const import0 = {
        __proto__: null,
        __wbg_Error_bce6d499ff0a4aff: function(arg0, arg1) {
            const ret = Error(getStringFromWasm0(arg0, arg1));
            return addHeapObject(ret);
        },
        __wbg___wbindgen_throw_9c31b086c2b26051: function(arg0, arg1) {
            throw new Error(getStringFromWasm0(arg0, arg1));
        },
        __wbg_error_a6fa202b58aa1cd3: function(arg0, arg1) {
            let deferred0_0;
            let deferred0_1;
            try {
                deferred0_0 = arg0;
                deferred0_1 = arg1;
                console.error(getStringFromWasm0(arg0, arg1));
            } finally {
                wasm.__wbindgen_export(deferred0_0, deferred0_1, 1);
            }
        },
        __wbg_new_02d162bc6cf02f60: function() {
            const ret = new Object();
            return addHeapObject(ret);
        },
        __wbg_new_227d7c05414eb861: function() {
            const ret = new Error();
            return addHeapObject(ret);
        },
        __wbg_new_from_slice_02962bf7778cf945: function(arg0, arg1) {
            const ret = new Float64Array(getArrayF64FromWasm0(arg0, arg1));
            return addHeapObject(ret);
        },
        __wbg_new_with_length_c2a8f9ac6aaaac03: function(arg0) {
            const ret = new Array(arg0 >>> 0);
            return addHeapObject(ret);
        },
        __wbg_set_78ea6a19f4818587: function(arg0, arg1, arg2) {
            getObject(arg0)[arg1 >>> 0] = takeObject(arg2);
        },
        __wbg_set_a0e911be3da02782: function() { return handleError(function (arg0, arg1, arg2) {
            const ret = Reflect.set(getObject(arg0), getObject(arg1), getObject(arg2));
            return ret;
        }, arguments); },
        __wbg_stack_3b0d974bbf31e44f: function(arg0, arg1) {
            const ret = getObject(arg1).stack;
            const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export3, wasm.__wbindgen_export4);
            const len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        },
        __wbindgen_cast_0000000000000001: function(arg0) {
            // Cast intrinsic for `F64 -> Externref`.
            const ret = arg0;
            return addHeapObject(ret);
        },
        __wbindgen_cast_0000000000000002: function(arg0, arg1) {
            // Cast intrinsic for `Ref(String) -> Externref`.
            const ret = getStringFromWasm0(arg0, arg1);
            return addHeapObject(ret);
        },
        __wbindgen_object_drop_ref: function(arg0) {
            takeObject(arg0);
        },
    };
    return {
        __proto__: null,
        "./wellen_wasm_bg.js": import0,
    };
}

const WellenWasmFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_wellenwasm_free(ptr, 1));

function addHeapObject(obj) {
    if (heap_next === heap.length) heap.push(heap.length + 1);
    const idx = heap_next;
    heap_next = heap[idx];

    heap[idx] = obj;
    return idx;
}

function dropObject(idx) {
    if (idx < 1028) return;
    heap[idx] = heap_next;
    heap_next = idx;
}

function getArrayF64FromWasm0(ptr, len) {
    ptr = ptr >>> 0;
    return getFloat64ArrayMemory0().subarray(ptr / 8, ptr / 8 + len);
}

function getArrayU32FromWasm0(ptr, len) {
    ptr = ptr >>> 0;
    return getUint32ArrayMemory0().subarray(ptr / 4, ptr / 4 + len);
}

let cachedDataViewMemory0 = null;
function getDataViewMemory0() {
    if (cachedDataViewMemory0 === null || cachedDataViewMemory0.buffer.detached === true || (cachedDataViewMemory0.buffer.detached === undefined && cachedDataViewMemory0.buffer !== wasm.memory.buffer)) {
        cachedDataViewMemory0 = new DataView(wasm.memory.buffer);
    }
    return cachedDataViewMemory0;
}

let cachedFloat64ArrayMemory0 = null;
function getFloat64ArrayMemory0() {
    if (cachedFloat64ArrayMemory0 === null || cachedFloat64ArrayMemory0.byteLength === 0) {
        cachedFloat64ArrayMemory0 = new Float64Array(wasm.memory.buffer);
    }
    return cachedFloat64ArrayMemory0;
}

function getStringFromWasm0(ptr, len) {
    return decodeText(ptr >>> 0, len);
}

let cachedUint32ArrayMemory0 = null;
function getUint32ArrayMemory0() {
    if (cachedUint32ArrayMemory0 === null || cachedUint32ArrayMemory0.byteLength === 0) {
        cachedUint32ArrayMemory0 = new Uint32Array(wasm.memory.buffer);
    }
    return cachedUint32ArrayMemory0;
}

let cachedUint8ArrayMemory0 = null;
function getUint8ArrayMemory0() {
    if (cachedUint8ArrayMemory0 === null || cachedUint8ArrayMemory0.byteLength === 0) {
        cachedUint8ArrayMemory0 = new Uint8Array(wasm.memory.buffer);
    }
    return cachedUint8ArrayMemory0;
}

function getObject(idx) { return heap[idx]; }

function handleError(f, args) {
    try {
        return f.apply(this, args);
    } catch (e) {
        wasm.__wbindgen_export2(addHeapObject(e));
    }
}

let heap = new Array(1024).fill(undefined);
heap.push(undefined, null, true, false);

let heap_next = heap.length;

function passArray8ToWasm0(arg, malloc) {
    const ptr = malloc(arg.length * 1, 1) >>> 0;
    getUint8ArrayMemory0().set(arg, ptr / 1);
    WASM_VECTOR_LEN = arg.length;
    return ptr;
}

function passStringToWasm0(arg, malloc, realloc) {
    if (realloc === undefined) {
        const buf = cachedTextEncoder.encode(arg);
        const ptr = malloc(buf.length, 1) >>> 0;
        getUint8ArrayMemory0().subarray(ptr, ptr + buf.length).set(buf);
        WASM_VECTOR_LEN = buf.length;
        return ptr;
    }

    let len = arg.length;
    let ptr = malloc(len, 1) >>> 0;

    const mem = getUint8ArrayMemory0();

    let offset = 0;

    for (; offset < len; offset++) {
        const code = arg.charCodeAt(offset);
        if (code > 0x7F) break;
        mem[ptr + offset] = code;
    }
    if (offset !== len) {
        if (offset !== 0) {
            arg = arg.slice(offset);
        }
        ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
        const view = getUint8ArrayMemory0().subarray(ptr + offset, ptr + len);
        const ret = cachedTextEncoder.encodeInto(arg, view);

        offset += ret.written;
        ptr = realloc(ptr, len, offset, 1) >>> 0;
    }

    WASM_VECTOR_LEN = offset;
    return ptr;
}

function takeObject(idx) {
    const ret = getObject(idx);
    dropObject(idx);
    return ret;
}

let cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
cachedTextDecoder.decode();
const MAX_SAFARI_DECODE_BYTES = 2146435072;
let numBytesDecoded = 0;
function decodeText(ptr, len) {
    numBytesDecoded += len;
    if (numBytesDecoded >= MAX_SAFARI_DECODE_BYTES) {
        cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
        cachedTextDecoder.decode();
        numBytesDecoded = len;
    }
    return cachedTextDecoder.decode(getUint8ArrayMemory0().subarray(ptr, ptr + len));
}

const cachedTextEncoder = new TextEncoder();

if (!('encodeInto' in cachedTextEncoder)) {
    cachedTextEncoder.encodeInto = function (arg, view) {
        const buf = cachedTextEncoder.encode(arg);
        view.set(buf);
        return {
            read: arg.length,
            written: buf.length
        };
    };
}

let WASM_VECTOR_LEN = 0;

let wasmModule, wasmInstance, wasm;
function __wbg_finalize_init(instance, module) {
    wasmInstance = instance;
    wasm = instance.exports;
    wasmModule = module;
    cachedDataViewMemory0 = null;
    cachedFloat64ArrayMemory0 = null;
    cachedUint32ArrayMemory0 = null;
    cachedUint8ArrayMemory0 = null;
    wasm.__wbindgen_start();
    return wasm;
}

async function __wbg_load(module, imports) {
    if (typeof Response === 'function' && module instanceof Response) {
        if (typeof WebAssembly.instantiateStreaming === 'function') {
            try {
                return await WebAssembly.instantiateStreaming(module, imports);
            } catch (e) {
                const validResponse = module.ok && expectedResponseType(module.type);

                if (validResponse && module.headers.get('Content-Type') !== 'application/wasm') {
                    console.warn("`WebAssembly.instantiateStreaming` failed because your server does not serve Wasm with `application/wasm` MIME type. Falling back to `WebAssembly.instantiate` which is slower. Original error:\n", e);

                } else { throw e; }
            }
        }

        const bytes = await module.arrayBuffer();
        return await WebAssembly.instantiate(bytes, imports);
    } else {
        const instance = await WebAssembly.instantiate(module, imports);

        if (instance instanceof WebAssembly.Instance) {
            return { instance, module };
        } else {
            return instance;
        }
    }

    function expectedResponseType(type) {
        switch (type) {
            case 'basic': case 'cors': case 'default': return true;
        }
        return false;
    }
}

function initSync(module) {
    if (wasm !== undefined) return wasm;


    if (module !== undefined) {
        if (Object.getPrototypeOf(module) === Object.prototype) {
            ({module} = module)
        } else {
            console.warn('using deprecated parameters for `initSync()`; pass a single object instead')
        }
    }

    const imports = __wbg_get_imports();
    if (!(module instanceof WebAssembly.Module)) {
        module = new WebAssembly.Module(module);
    }
    const instance = new WebAssembly.Instance(module, imports);
    return __wbg_finalize_init(instance, module);
}

async function __wbg_init(module_or_path) {
    if (wasm !== undefined) return wasm;


    if (module_or_path !== undefined) {
        if (Object.getPrototypeOf(module_or_path) === Object.prototype) {
            ({module_or_path} = module_or_path)
        } else {
            console.warn('using deprecated parameters for the initialization function; pass a single object instead')
        }
    }

    if (module_or_path === undefined) {
        module_or_path = new URL('wellen_wasm_bg.wasm', import.meta.url);
    }
    const imports = __wbg_get_imports();

    if (typeof module_or_path === 'string' || (typeof Request === 'function' && module_or_path instanceof Request) || (typeof URL === 'function' && module_or_path instanceof URL)) {
        module_or_path = fetch(module_or_path);
    }

    const { instance, module } = await __wbg_load(await module_or_path, imports);

    return __wbg_finalize_init(instance, module);
}

export { initSync, __wbg_init as default };
