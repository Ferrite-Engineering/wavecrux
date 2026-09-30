// wellen_ffi.h — C-ABI header for the wellen_ffi Rust crate.
//
// Consumed by Dart's ffigen to auto-generate Dart bindings.
// All strings returned by pointer are valid for the lifetime of the handle.
// All functions are thread-safe with respect to different handles; do NOT
// share a single handle across threads.

#ifndef WELLEN_FFI_H
#define WELLEN_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── opaque handle ──────────────────────────────────────────────────────────

typedef struct WellenHandle WellenHandle;

// ── scope type constants ───────────────────────────────────────────────────

#define WELLEN_SCOPE_MODULE        0
#define WELLEN_SCOPE_TASK          1
#define WELLEN_SCOPE_FUNCTION      2
#define WELLEN_SCOPE_BEGIN         3
#define WELLEN_SCOPE_FORK          4
#define WELLEN_SCOPE_GENERATE      5
#define WELLEN_SCOPE_STRUCT        6
#define WELLEN_SCOPE_UNION         7
#define WELLEN_SCOPE_CLASS         8
#define WELLEN_SCOPE_INTERFACE     9
#define WELLEN_SCOPE_PACKAGE       10
#define WELLEN_SCOPE_PROGRAM       11
#define WELLEN_SCOPE_VHDL_ARCH     20
#define WELLEN_SCOPE_VHDL_PROC     21
#define WELLEN_SCOPE_VHDL_FUNC     22
#define WELLEN_SCOPE_VHDL_RECORD   23
#define WELLEN_SCOPE_VHDL_PROCESS  24
#define WELLEN_SCOPE_VHDL_BLOCK    25
#define WELLEN_SCOPE_VHDL_FOR_GEN  26
#define WELLEN_SCOPE_VHDL_IF_GEN   27
#define WELLEN_SCOPE_VHDL_GEN      28
#define WELLEN_SCOPE_VHDL_PKG      29
#define WELLEN_SCOPE_GHW_GENERIC   30
#define WELLEN_SCOPE_VHDL_ARRAY    31

// ── variable type constants ────────────────────────────────────────────────

#define WELLEN_VAR_EVENT           0
#define WELLEN_VAR_INTEGER         1
#define WELLEN_VAR_PARAMETER       2
#define WELLEN_VAR_REAL            3
#define WELLEN_VAR_REG             4
#define WELLEN_VAR_SUPPLY0         5
#define WELLEN_VAR_SUPPLY1         6
#define WELLEN_VAR_TIME            7
#define WELLEN_VAR_TRI             8
#define WELLEN_VAR_TRIAND          9
#define WELLEN_VAR_TRIOR           10
#define WELLEN_VAR_TRIREG          11
#define WELLEN_VAR_TRI0            12
#define WELLEN_VAR_TRI1            13
#define WELLEN_VAR_WAND            14
#define WELLEN_VAR_WIRE            15
#define WELLEN_VAR_WOR             16
#define WELLEN_VAR_STRING          17
#define WELLEN_VAR_PORT            18
#define WELLEN_VAR_SPARSE_ARRAY    19
#define WELLEN_VAR_REAL_TIME       20
#define WELLEN_VAR_BIT             30
#define WELLEN_VAR_LOGIC           31
#define WELLEN_VAR_INT             32
#define WELLEN_VAR_SHORT_INT       33
#define WELLEN_VAR_LONG_INT        34
#define WELLEN_VAR_BYTE            35
#define WELLEN_VAR_ENUM            36
#define WELLEN_VAR_SHORT_REAL      37
#define WELLEN_VAR_BOOLEAN         40
#define WELLEN_VAR_BIT_VECTOR      41
#define WELLEN_VAR_STD_LOGIC       42
#define WELLEN_VAR_STD_LOGIC_VEC   43
#define WELLEN_VAR_STD_ULOGIC      44
#define WELLEN_VAR_STD_ULOGIC_VEC  45
#define WELLEN_VAR_REAL_PARAMETER  46

// ── direction constants ────────────────────────────────────────────────────

#define WELLEN_DIR_UNKNOWN         0
#define WELLEN_DIR_IMPLICIT        1
#define WELLEN_DIR_INPUT           2
#define WELLEN_DIR_OUTPUT          3
#define WELLEN_DIR_INOUT           4
#define WELLEN_DIR_BUFFER          5
#define WELLEN_DIR_LINKAGE         6

// ── file format constants ──────────────────────────────────────────────────

#define WELLEN_FORMAT_UNKNOWN      0
#define WELLEN_FORMAT_VCD          1
#define WELLEN_FORMAT_FST          2
#define WELLEN_FORMAT_GHW          3

// ── lifecycle ──────────────────────────────────────────────────────────────

/// Open a VCD, FST, or GHW waveform file.
/// Returns a non-null handle on success, or NULL on failure.
/// The returned handle must be freed with wellen_close().
WellenHandle* wellen_open(const char* path);

/// Free a handle returned by wellen_open().
void wellen_close(WellenHandle* handle);

/// Return the last error message (empty string if none).
/// The returned pointer is valid until the next call on this handle.
const char* wellen_last_error(const WellenHandle* handle);

// ── metadata ───────────────────────────────────────────────────────────────

/// Fill *factor_out and *unit_exp_out with the timescale.
/// unit_exp_out is the SI exponent (e.g. -9 for nanoseconds, -12 for picoseconds).
/// Returns 1 if a timescale is present, 0 if not.
int32_t wellen_get_timescale(WellenHandle* handle,
                             uint32_t*     factor_out,
                             int32_t*      unit_exp_out);

/// Return the last time value in the time table (simulation end, in ticks).
uint64_t wellen_time_end(const WellenHandle* handle);

/// Return a null-terminated string with the simulation date.
/// Pointer is valid for the lifetime of the handle.
const char* wellen_date(const WellenHandle* handle);

/// Return a null-terminated string with the simulator version.
/// Pointer is valid for the lifetime of the handle.
const char* wellen_version(const WellenHandle* handle);

/// Return the file format of the opened waveform (WELLEN_FORMAT_* constant).
/// Returns WELLEN_FORMAT_UNKNOWN (0) if the format could not be determined
/// from the file extension or the handle is NULL.
int32_t wellen_file_format(const WellenHandle* handle);

/// Return the total number of value changes across all signals loaded so far
/// via wellen_load_signal(). The count accumulates as more signals are loaded.
/// Returns 0 if no signals have been loaded yet, or the handle is NULL.
uint64_t wellen_total_transition_count(const WellenHandle* handle);

/// Return the number of value changes for a specific signal_ref.
/// The signal must first be loaded via wellen_load_signal(); returns 0 if
/// the signal is not loaded or the handle is NULL.
uint64_t wellen_signal_transition_count(const WellenHandle* handle,
                                        uint32_t            signal_ref);

/// Return an approximate memory usage in bytes for the waveform data held by
/// this handle. This is an estimate, not an exact allocation count:
///   time_table entries × 8 bytes
///   + scope metadata × 200 bytes + variable metadata × 100 bytes
///   + loaded signal changes × 16 bytes (estimated storage per change)
/// Returns 0 if the handle is NULL.
uint64_t wellen_memory_usage_bytes(const WellenHandle* handle);

// ── hierarchy counts ───────────────────────────────────────────────────────

/// Total number of scopes in the hierarchy (all levels).
uint64_t wellen_num_scopes(const WellenHandle* handle);

/// Total number of variables in the hierarchy (all levels).
uint64_t wellen_num_vars(const WellenHandle* handle);

// ── root-level items ───────────────────────────────────────────────────────

/// Write up to `max` top-level scope indices into `out`.
/// Returns the number of indices written, or -1 on error.
int64_t wellen_root_scopes(const WellenHandle* handle, uint64_t* out, uint64_t max);

/// Write up to `max` top-level variable indices into `out`.
/// Returns the number of indices written, or -1 on error.
int64_t wellen_root_vars(const WellenHandle* handle, uint64_t* out, uint64_t max);

// ── scope properties ───────────────────────────────────────────────────────

/// Return the name of scope `scope_idx` as a null-terminated string.
/// Pointer is valid for the lifetime of the handle. Returns NULL if out of range.
const char* wellen_scope_name(const WellenHandle* handle, uint64_t scope_idx);

/// Return the scope type (WELLEN_SCOPE_* constant), or -1 if out of range.
int32_t wellen_scope_type(const WellenHandle* handle, uint64_t scope_idx);

/// Write up to `max` child scope indices of `scope_idx` into `out`.
/// Returns the count written, or -1 on error.
int64_t wellen_scope_child_scopes(const WellenHandle* handle,
                                  uint64_t            scope_idx,
                                  uint64_t*           out,
                                  uint64_t            max);

/// Write up to `max` child variable indices of `scope_idx` into `out`.
/// Returns the count written, or -1 on error.
int64_t wellen_scope_child_vars(const WellenHandle* handle,
                                uint64_t            scope_idx,
                                uint64_t*           out,
                                uint64_t            max);

// ── variable properties ────────────────────────────────────────────────────

/// Return the name of variable `var_idx` as a null-terminated string.
/// Pointer is valid for the lifetime of the handle. Returns NULL if out of range.
const char* wellen_var_name(const WellenHandle* handle, uint64_t var_idx);

/// Return the variable type (WELLEN_VAR_* constant), or -1 if out of range.
int32_t wellen_var_type(const WellenHandle* handle, uint64_t var_idx);

/// Return the variable direction (WELLEN_DIR_* constant), or -1 if out of range.
int32_t wellen_var_direction(const WellenHandle* handle, uint64_t var_idx);

/// Return the bit width of variable `var_idx` (0 if not a bit-vector or unavailable).
uint32_t wellen_var_length(const WellenHandle* handle, uint64_t var_idx);

/// Return the signal reference (opaque u32) for variable `var_idx`.
/// Pass this value to wellen_load_signal / wellen_value_at / wellen_signal_changes.
/// Returns UINT32_MAX on error.
uint32_t wellen_var_signal_ref(const WellenHandle* handle, uint64_t var_idx);

// ── signal loading ─────────────────────────────────────────────────────────

/// Load signal data for `signal_ref` (lazy — call before querying values).
/// Returns 0 on success, -1 on error.
int32_t wellen_load_signal(WellenHandle* handle, uint32_t signal_ref);

/// Unload a previously loaded signal to free memory.
/// Returns 0 on success, -1 on error.
int32_t wellen_unload_signal(WellenHandle* handle, uint32_t signal_ref);

// ── value queries ──────────────────────────────────────────────────────────

/// Write the signal value at simulation tick `time` into `value_buf` as a
/// null-terminated bit string (e.g. "0", "1", "10x1z", "3.14").
///
/// Returns bytes written (excluding null), -1 if no value available at/before
/// `time` or signal not loaded, -2 if buffer too small.
int32_t wellen_value_at(const WellenHandle* handle,
                        uint32_t            signal_ref,
                        uint64_t            time,
                        uint8_t*            value_buf,
                        uint32_t            buf_len);

/// Collect all value changes in the half-open interval [start_time, end_time).
///
/// out_times      — uint64 array, receives the tick of each change
/// out_value_buf  — flat byte buffer for null-terminated value strings
/// value_buf_len  — total capacity of out_value_buf
/// out_offsets    — uint32 array, byte offset into out_value_buf per change
/// max_count      — capacity of out_times and out_offsets
///
/// Returns the number of changes written, -1 if signal not loaded,
/// or -2 if any output buffer is too small.
int64_t wellen_signal_changes(const WellenHandle* handle,
                              uint32_t            signal_ref,
                              uint64_t            start_time,
                              uint64_t            end_time,
                              uint64_t*           out_times,
                              uint8_t*            out_value_buf,
                              uint32_t            value_buf_len,
                              uint32_t*           out_offsets,
                              int64_t             max_count);

/// Find the next value change strictly after `after_time`.
///
/// On success: writes change time to *out_time, value string to value_buf,
///             and returns 1.
/// Returns 0 if there is no next transition.
/// Returns -1 if the signal is not loaded or an error occurred.
/// Returns -2 if value_buf is too small.
int32_t wellen_next_transition(const WellenHandle* handle,
                               uint32_t            signal_ref,
                               uint64_t            after_time,
                               uint64_t*           out_time,
                               uint8_t*            value_buf,
                               uint32_t            buf_len);

/// Find the last value change strictly before `before_time`.
///
/// On success: writes change time to *out_time, value string to value_buf,
///             and returns 1.
/// Returns 0 if there is no previous transition.
/// Returns -1 if the signal is not loaded or an error occurred.
/// Returns -2 if value_buf is too small.
int32_t wellen_prev_transition(const WellenHandle* handle,
                               uint32_t            signal_ref,
                               uint64_t            before_time,
                               uint64_t*           out_time,
                               uint8_t*            value_buf,
                               uint32_t            buf_len);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // WELLEN_FFI_H
