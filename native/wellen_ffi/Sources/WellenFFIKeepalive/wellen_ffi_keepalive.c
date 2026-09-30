// wellen_ffi_keepalive.c — keep `_wellen_*` symbols out of the linker's dead
// strip on iOS / iPadOS.
//
// Why this file exists
// --------------------
// The Rust-built `libwellen_ffi.a` (shipped in `WellenFFI.xcframework`) exports
// the `_wellen_*` C ABI used by Dart through ffigen. On iOS the Dart side loads
// these symbols at runtime via `DynamicLibrary.process()` + `dlsym` — there is
// no Swift/ObjC code in Runner.app that references them at compile time.
//
// Apple's linker (`ld64`) consequently strips every `_wellen_*` symbol from the
// final Runner binary's dynamic symbol table during link, because nothing
// reaches the symbols from the entry-point graph. `dlsym` then returns NULL,
// `WellenFfi(...)` throws on the first ffigen lookup, and the user sees
// "Failed to load waveform / Retry with backup parser".
//
// The standard fix is `-force_load <path>` on the static archive. It works in
// pure-Xcode setups but fights CocoaPods' xcframework dependency tracker — the
// [CP] Copy XCFrameworks phase declares its output as `WellenFFI.framework`
// (a directory), not `libwellen_ffi.a`, so Xcode's "Build input file cannot be
// found" check rejects the linker phase before the build even runs.
//
// Instead we emit a single retained array of function pointers from this
// translation unit. The `&` operator forces the compiler to emit relocations
// against each `_wellen_*` symbol, and `__attribute__((used, retain))` tells
// the compiler / linker to keep this object file's symbols regardless of any
// dead-strip pass. The relocations cause the linker to pull the referenced
// `_wellen_*` definitions out of `libwellen_ffi.a` and into the final binary,
// where `dlsym` can find them at runtime.
//
// This file is compiled as the `WellenFFIKeepalive` SwiftPM target declared
// in `Package.swift`, which both Runner projects (open-core and Pro) consume
// as the `WellenFFI` local-package product.
//
// The same library also carries the LXT/LXT2 → FST converter: the Rust
// `wellen_ffi` crate links `lxt2fst`, so the archive exports `_lxt2fst_*` too
// and Dart's `Lxt2FstConverter` looks them up through the same
// `DynamicLibrary.process()`. They need the same protection.
//
// Keep this list in sync with `wellen_ffi.h` and
// `native/lxt2fst/include/lxt2fst.h` — test/static/wellen_ffi_bundles_lxt2fst_test.dart
// fails when a header function is missing here. A new entry point without a
// line below is stripped on iOS and its Dart binding fails at runtime.
//
// This file protects the symbols at LINK time only. Archive (App Store /
// TestFlight) builds additionally run `strip` on the Runner executable as a
// post-processing step, which under Xcode's default Strip Style ("All
// Symbols" for executables) deletes the dlsym export trie wholesale. The
// Runner target therefore sets STRIP_STYLE = "non-global" (Release + Profile
// configs) in ios/Runner.xcodeproj — without it, every `wellen_*` lookup
// fails on physical devices in release builds even though this keepalive
// linked the symbols in. Debug builds never hit this because Xcode's
// debug-dylib mechanism puts the app code in Runner.debug.dylib, which is
// not stripped. Guarded by test/static/ios_runner_strip_style_test.dart.

#include <stdint.h>

// Forward declarations of the wellen C ABI. We don't need the real
// signatures — taking the address of the function only requires the symbol
// name to be declared as `extern`. A real signature mismatch would matter
// only if we *called* these functions, which we never do.
extern void wellen_open(void);
extern void wellen_close(void);
extern void wellen_last_error(void);
extern void wellen_last_open_error(void);
extern void wellen_get_timescale(void);
extern void wellen_time_end(void);
extern void wellen_date(void);
extern void wellen_version(void);
extern void wellen_file_format(void);
extern void wellen_total_transition_count(void);
extern void wellen_signal_transition_count(void);
extern void wellen_memory_usage_bytes(void);
extern void wellen_num_scopes(void);
extern void wellen_num_vars(void);
extern void wellen_root_scopes(void);
extern void wellen_root_vars(void);
extern void wellen_scope_name(void);
extern void wellen_scope_type(void);
extern void wellen_scope_child_scopes(void);
extern void wellen_scope_child_vars(void);
extern void wellen_var_name(void);
extern void wellen_var_type(void);
extern void wellen_var_direction(void);
extern void wellen_var_length(void);
extern void wellen_var_signal_ref(void);
extern void wellen_load_signal(void);
extern void wellen_unload_signal(void);
extern void wellen_value_at(void);
extern void wellen_signal_changes(void);
extern void wellen_next_transition(void);
extern void wellen_prev_transition(void);
extern void lxt2fst_abi_version(void);
extern void lxt2fst_detect_format(void);
extern void lxt2fst_convert(void);
extern void lxt2fst_last_error_message(void);

// `used` + `retain` keep this array (and therefore the relocations against
// each function) alive through every linker dead-strip pass. `volatile` keeps
// the compiler from optimising the array away in LTO. `extern "C"` is
// implicit because this is a .c file.
__attribute__((used, retain, visibility("default")))
static const void* const volatile _wellen_ffi_keepalive[] = {
    (const void*)&wellen_open,
    (const void*)&wellen_close,
    (const void*)&wellen_last_error,
    (const void*)&wellen_last_open_error,
    (const void*)&wellen_get_timescale,
    (const void*)&wellen_time_end,
    (const void*)&wellen_date,
    (const void*)&wellen_version,
    (const void*)&wellen_file_format,
    (const void*)&wellen_total_transition_count,
    (const void*)&wellen_signal_transition_count,
    (const void*)&wellen_memory_usage_bytes,
    (const void*)&wellen_num_scopes,
    (const void*)&wellen_num_vars,
    (const void*)&wellen_root_scopes,
    (const void*)&wellen_root_vars,
    (const void*)&wellen_scope_name,
    (const void*)&wellen_scope_type,
    (const void*)&wellen_scope_child_scopes,
    (const void*)&wellen_scope_child_vars,
    (const void*)&wellen_var_name,
    (const void*)&wellen_var_type,
    (const void*)&wellen_var_direction,
    (const void*)&wellen_var_length,
    (const void*)&wellen_var_signal_ref,
    (const void*)&wellen_load_signal,
    (const void*)&wellen_unload_signal,
    (const void*)&wellen_value_at,
    (const void*)&wellen_signal_changes,
    (const void*)&wellen_next_transition,
    (const void*)&wellen_prev_transition,
    (const void*)&lxt2fst_abi_version,
    (const void*)&lxt2fst_detect_format,
    (const void*)&lxt2fst_convert,
    (const void*)&lxt2fst_last_error_message,
};
