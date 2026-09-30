// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// lxt2fst.h — C-ABI header for the lxt2fst Rust crate.
//
// Consumed by Dart's ffigen to auto-generate Dart bindings.
// Hand-maintained in lockstep with `extern "C"` exports in src/lib.rs.
// Mirrors the structural style of wellen_ffi.h.
//
// The crate is single-shot: there is no opaque handle. A caller invokes
// `lxt2fst_convert(...)` to convert a `.lxt` or `.lxt2` file into an `.fst`
// file at the requested output path, and receives a structured error code
// plus an optional progress callback.

#ifndef LXT2FST_H
#define LXT2FST_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── error codes ───────────────────────────────────────────────────────────
//
// Returned by lxt2fst_convert. Negative values are reserved for future
// expansion; positive non-zero values indicate specific failure modes.

#define LXT2FST_OK                 0  // conversion succeeded
#define LXT2FST_ERR_FILE_NOT_FOUND 1  // input path could not be opened
#define LXT2FST_ERR_MAGIC_MISMATCH 2  // file is not LXT or LXT2
#define LXT2FST_ERR_TRUNCATED      3  // unexpected EOF while parsing
#define LXT2FST_ERR_WRITE_FAILED   4  // output path could not be written
#define LXT2FST_ERR_OOM            5  // memory allocation failed
#define LXT2FST_ERR_UNSUPPORTED    6  // a recognized but unimplemented form
                                       // (e.g., real/string value-change
                                       // granule decoding under active
                                       // reverse-engineering; see README)
#define LXT2FST_ERR_INTERNAL       7  // panic-safety net tripped
#define LXT2FST_ERR_INVALID_ARG    8  // null path or invalid UTF-8

// ── format magic-byte detection ───────────────────────────────────────────
//
// Cheap probe used by the Dart open-from-path routing: read the first 2
// bytes of the file and pass to this function. Returns one of the
// LXT2FST_FORMAT_* values. No I/O performed inside the call.

#define LXT2FST_FORMAT_UNKNOWN 0
#define LXT2FST_FORMAT_LXT     1  // LXT classic (2003 streaming, magic 0x0138)
#define LXT2FST_FORMAT_LXT2    2  // LXT2 (2005 block-indexed, magic 0x1380)

int32_t lxt2fst_detect_format(const uint8_t* head_bytes, uintptr_t len);

// ── progress callback ─────────────────────────────────────────────────────
//
// Invoked at most every 50 ms OR every 1% of progress, whichever comes
// first. (done, total) units depend on format:
//   * LXT2  — (blocks_done, total_blocks) read from the block index
//   * LXT   — (bytes_consumed, total_size) from the file size
//
// The callback receives the opaque `user_data` pointer that the caller
// passed to lxt2fst_convert. May be NULL, in which case progress
// reporting is disabled. The callback MUST NOT throw / longjmp / panic
// across the FFI boundary; do only lightweight reporting work inside it.

typedef void (*lxt2fst_progress_fn)(uint64_t done,
                                    uint64_t total,
                                    void* user_data);

// ── main conversion entry point ───────────────────────────────────────────
//
// `in_path`  — NUL-terminated absolute filesystem path to the .lxt/.lxt2
//              file to convert (UTF-8 on all platforms).
// `out_path` — NUL-terminated absolute filesystem path to the .fst file
//              to create. Overwritten if it exists. On failure, any
//              partial output is removed by the caller (the converter
//              does not always do this transparently on cancel-from-panic).
// `progress` — optional callback (see above). NULL to disable.
// `user_data`— opaque pointer forwarded to `progress`. NULL is allowed.
//
// Returns one of the LXT2FST_* codes. On non-OK return, callers may pass
// `out_path` to lxt2fst_last_error_message() to retrieve a human-readable
// description for diagnostics (the string is a static borrowed pointer
// valid until the next conversion call).

int32_t lxt2fst_convert(const char* in_path,
                        const char* out_path,
                        lxt2fst_progress_fn progress,
                        void* user_data);

// Returns a NUL-terminated, static-lifetime English message describing
// the most recent conversion's error. Returns "" if the most recent
// conversion succeeded or if no conversion has been performed.
//
// The pointer is valid until the next call to lxt2fst_convert on the
// same thread. Not thread-safe across simultaneous conversions on
// different threads (this matches wellen_ffi's per-handle convention —
// here the "handle" is per-thread because the API is single-shot).

const char* lxt2fst_last_error_message(void);

// ── ABI version ───────────────────────────────────────────────────────────
//
// Incremented whenever an exported symbol changes shape or semantics.
// The Dart side reads this on load and refuses mismatched libraries.

uint32_t lxt2fst_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif // LXT2FST_H
