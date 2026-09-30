// onewire_decoder.c — Reference 1-Wire (Maxim/Dallas) decoder plugin.
//
// This is the canonical demonstrator for the WaveCrux user-contributed
// decoder plugin C ABI. It implements a passive observer that watches a
// single open-drain `dq` signal and decodes:
//
//   1. RESET pulses (DQ low for ≥ 400 µs)
//   2. PRESENCE pulses (DQ low 30–240 µs immediately following a RESET
//      release — the slave's "I am here" acknowledgement)
//   3. Bit slots (DQ low for < 15 µs → bit 1; DQ low for ≥ 30 µs and
//      < 240 µs → bit 0). Bit slots are accumulated in groups of eight
//      and emitted as BYTE transactions, LSB-first per the 1-Wire
//      specification.
//
// The decoder does not interpret the byte stream above the
// physical / framing layer — it does not know that 0x33 is the
// READ_ROM command or that a particular byte is a CRC. Higher-level
// interpretation is left to upstream tooling (or a richer plugin).
//
// Why 1-Wire as the canonical demo:
//   * Single signal — minimal manifest noise.
//   * Bounded transactions — every transaction has a clear start / end.
//   * Well-documented in the Maxim DS18B20 datasheet and the
//     "1-Wire Communication Through Software" application note.
//   * Not in WaveCrux's built-in decoder set, so the demonstrator is
//     immediately useful even after this prompt lands.
//
// Build:
//   make                    # Linux / macOS
//   cmake -S . -B build && cmake --build build   # cross-platform
//
// See README.md for the end-to-end walkthrough from "git clone" to
// "1-Wire decoder appears in WaveCrux's decoder picker".

#include "wavecrux_decoder.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── manifest ──────────────────────────────────────────────────────────────
//
// One required signal: `dq`, 1 bit. No configurable parameters.
// `category: userPlugin` flags this for the user-contributed group in
// the decoder picker.

static const char kManifestJson[] =
    "{"
    "\"signals\":["
    "{\"name\":\"dq\","
    "\"description\":\"1-Wire data line (DQ, open-drain)\","
    "\"bit_width\":1}"
    "],"
    "\"parameters\":[],"
    "\"description\":\"Maxim / Dallas 1-Wire bus decoder. Observes a "
    "single DQ line and emits RESET, PRESENCE, and BYTE transactions.\","
    "\"category\":\"userPlugin\""
    "}";

// ── timing thresholds (femtoseconds) ──────────────────────────────────────
//
// All timestamps the loader passes are in fs. The 1-Wire spec uses µs
// as its native unit; we convert with the constants below. The
// thresholds are deliberately loose enough to absorb test-fixture
// rounding without overlapping into the next category.

#define US_TO_FS(us) ((uint64_t)(us) * 1000ULL * 1000ULL * 1000ULL)

#define RESET_LOW_MIN_FS    US_TO_FS(400)   // ≥ 400 µs low → RESET
#define PRESENCE_MIN_FS     US_TO_FS(30)    // ≥ 30 µs low → presence (after reset)
#define PRESENCE_MAX_FS     US_TO_FS(240)   // ≤ 240 µs low → still presence
#define BIT_ONE_MAX_FS      US_TO_FS(15)    // < 15 µs low → bit 1
#define BIT_ZERO_MIN_FS     US_TO_FS(30)    // ≥ 30 µs low → bit 0

// ── transaction emission scratch space ────────────────────────────────────
//
// `feed` may emit at most one transaction per call (a falling-then-
// rising edge resolves into a single decoded event). We size the
// per-instance string buffers to fit the longest transaction label and
// fields-JSON we generate.

#define LABEL_MAX 64
#define FIELDS_MAX 192
#define MAX_PENDING 16

typedef enum {
    TX_RESET,
    TX_PRESENCE,
    TX_BYTE,
} TxKind;

typedef struct PendingTx {
    uint64_t start_fs;
    uint64_t end_fs;
    TxKind   kind;
    uint8_t  byte_value;
    int      is_error;
} PendingTx;

typedef struct OneWireState {
    // Last seen level (0 / 1). -1 = uninitialised; the first feed call
    // captures the current level without producing any transition
    // event.
    int last_level;
    // Timestamp of the most recent 1 → 0 transition. Set on every
    // falling edge so we can compute the next 0 → 1 pulse duration.
    uint64_t last_fall_fs;
    // Transition we just classified — used to suppress the post-RESET
    // gap from being mistaken for a stray bit slot.
    int last_was_reset;
    // Bit accumulator: value (LSB-first) and how many bits we've
    // received since the last RESET (or since byte boundary).
    uint8_t  byte_accum;
    int      byte_bits;
    uint64_t byte_start_fs;

    // Per-instance scratch storage for label and fields_json strings
    // referenced by the most-recently-emitted transactions. These
    // remain valid until the next feed / flush call on the same
    // handle, per the ABI contract in wavecrux_decoder.h.
    char     label_buf[MAX_PENDING][LABEL_MAX];
    char     fields_buf[MAX_PENDING][FIELDS_MAX];
    int      buf_cursor;

    // Pending queue — the decoder may finish a byte (8 bits) on the
    // same `feed` call that finishes the bit slot, so the host can
    // receive multiple transactions at once. The queue rotates
    // through `MAX_PENDING` entries.
    PendingTx pending[MAX_PENDING];
    int      pending_count;
} OneWireState;

// ── helpers ───────────────────────────────────────────────────────────────

static int extract_level(const WcSample* s) {
    if (s->bit_width == 0 || s->bits_ptr == NULL) return 1;  // assume idle
    // 4-state encoding: bit 0 = level, bit 1 = unknown flag. Treat X/Z
    // as "level unchanged" — caller sees previous level on subsequent
    // edge-detection logic.
    uint8_t b = s->bits_ptr[0];
    int unknown = (b >> 1) & 1;
    if (unknown) return -1;
    return (int)(b & 1);
}

static void enqueue(OneWireState* st, PendingTx tx) {
    if (st->pending_count >= MAX_PENDING) return;  // drop on overflow
    st->pending[st->pending_count++] = tx;
}

static void format_byte(OneWireState* st,
                        WcTransaction* out,
                        const PendingTx* tx) {
    int slot = st->buf_cursor;
    st->buf_cursor = (st->buf_cursor + 1) % MAX_PENDING;
    snprintf(st->label_buf[slot], LABEL_MAX,
             "BYTE 0x%02X", tx->byte_value);
    snprintf(st->fields_buf[slot], FIELDS_MAX,
             "{\"value\":\"0x%02X\",\"bits\":\"8\"}",
             tx->byte_value);
    out->start_fs    = tx->start_fs;
    out->end_fs      = tx->end_fs;
    out->label       = st->label_buf[slot];
    out->fields_json = st->fields_buf[slot];
    out->is_error    = (uint32_t)(tx->is_error ? 1 : 0);
}

static void format_simple(OneWireState* st,
                          WcTransaction* out,
                          const PendingTx* tx,
                          const char* label,
                          const char* fields) {
    int slot = st->buf_cursor;
    st->buf_cursor = (st->buf_cursor + 1) % MAX_PENDING;
    snprintf(st->label_buf[slot], LABEL_MAX, "%s", label);
    snprintf(st->fields_buf[slot], FIELDS_MAX, "%s", fields);
    out->start_fs    = tx->start_fs;
    out->end_fs      = tx->end_fs;
    out->label       = st->label_buf[slot];
    out->fields_json = st->fields_buf[slot];
    out->is_error    = (uint32_t)(tx->is_error ? 1 : 0);
}

static void format_pending(OneWireState* st,
                           WcTransaction* out,
                           const PendingTx* tx) {
    switch (tx->kind) {
        case TX_RESET:
            format_simple(st, out, tx, "RESET",
                          "{\"kind\":\"reset\"}");
            break;
        case TX_PRESENCE:
            format_simple(st, out, tx, "PRESENCE",
                          "{\"kind\":\"presence\",\"valid\":\"true\"}");
            break;
        case TX_BYTE:
            format_byte(st, out, tx);
            break;
    }
}

// ── lifecycle callbacks ───────────────────────────────────────────────────

static WcDecoderHandle ow_create(const char* config_json) {
    (void)config_json;
    OneWireState* st = (OneWireState*)calloc(1, sizeof(OneWireState));
    if (st == NULL) return NULL;
    st->last_level = -1;
    return (WcDecoderHandle)st;
}

static int32_t ow_feed(WcDecoderHandle handle,
                       const WcSample* sample,
                       WcTransaction* out_transactions,
                       size_t* inout_count) {
    if (handle == NULL || sample == NULL || inout_count == NULL) {
        if (inout_count != NULL) *inout_count = 0;
        return WC_DECODER_ERR;
    }
    OneWireState* st = (OneWireState*)handle;

    int level = extract_level(sample);
    if (level >= 0 && level != st->last_level) {
        if (st->last_level == -1) {
            // First feed call — capture level without classifying. If
            // the line is already low we have to record this as the
            // fall time so the next rising edge can compute the pulse
            // duration correctly.
            if (level == 0) {
                st->last_fall_fs = sample->timestamp_fs;
            }
        } else if (st->last_level == 1 && level == 0) {
            // 1 → 0 falling edge.
            st->last_fall_fs = sample->timestamp_fs;
        } else if (st->last_level == 0 && level == 1) {
            // 0 → 1 rising edge: classify the low pulse.
            uint64_t dur = sample->timestamp_fs - st->last_fall_fs;
            PendingTx tx = {
                .start_fs = st->last_fall_fs,
                .end_fs   = sample->timestamp_fs,
                .kind     = TX_RESET,
                .is_error = 0,
            };
            if (dur >= RESET_LOW_MIN_FS) {
                tx.kind = TX_RESET;
                enqueue(st, tx);
                st->last_was_reset = 1;
                st->byte_accum = 0;
                st->byte_bits = 0;
            } else if (st->last_was_reset
                       && dur >= PRESENCE_MIN_FS
                       && dur <= PRESENCE_MAX_FS) {
                tx.kind = TX_PRESENCE;
                enqueue(st, tx);
                st->last_was_reset = 0;
            } else {
                // Bit slot. Short low → 1, long low → 0.
                int bit;
                if (dur < BIT_ONE_MAX_FS) {
                    bit = 1;
                } else if (dur >= BIT_ZERO_MIN_FS) {
                    bit = 0;
                } else {
                    // Ambiguous — treat as 0 with error flag.
                    bit = 0;
                    tx.is_error = 1;
                }
                if (st->byte_bits == 0) {
                    st->byte_start_fs = st->last_fall_fs;
                    st->byte_accum = 0;
                }
                st->byte_accum |= (uint8_t)((bit & 1) << st->byte_bits);
                st->byte_bits += 1;
                st->last_was_reset = 0;
                if (st->byte_bits == 8) {
                    PendingTx byte_tx = {
                        .start_fs = st->byte_start_fs,
                        .end_fs   = sample->timestamp_fs,
                        .kind     = TX_BYTE,
                        .byte_value = st->byte_accum,
                        .is_error = tx.is_error,
                    };
                    enqueue(st, byte_tx);
                    st->byte_accum = 0;
                    st->byte_bits = 0;
                }
            }
        }
        st->last_level = level;
    }

    // Drain pending into the host's buffer.
    size_t cap = *inout_count;
    if (cap == 0 && st->pending_count > 0) {
        return WC_DECODER_NEED_MORE_SLOTS;
    }
    size_t emitted = 0;
    while (emitted < cap && emitted < (size_t)st->pending_count) {
        format_pending(st, &out_transactions[emitted],
                       &st->pending[emitted]);
        emitted++;
    }
    // Compact remaining queue entries to the front.
    if (emitted > 0 && (size_t)st->pending_count > emitted) {
        for (size_t i = emitted; i < (size_t)st->pending_count; i++) {
            st->pending[i - emitted] = st->pending[i];
        }
    }
    st->pending_count -= (int)emitted;
    *inout_count = emitted;
    return st->pending_count > 0 ? WC_DECODER_NEED_MORE_SLOTS : WC_DECODER_OK;
}

static int32_t ow_flush(WcDecoderHandle handle,
                        WcTransaction* out_transactions,
                        size_t* inout_count) {
    if (handle == NULL || inout_count == NULL) {
        if (inout_count != NULL) *inout_count = 0;
        return WC_DECODER_ERR;
    }
    OneWireState* st = (OneWireState*)handle;
    size_t cap = *inout_count;
    if (cap == 0 && st->pending_count > 0) {
        return WC_DECODER_NEED_MORE_SLOTS;
    }
    size_t emitted = 0;
    while (emitted < cap && emitted < (size_t)st->pending_count) {
        format_pending(st, &out_transactions[emitted],
                       &st->pending[emitted]);
        emitted++;
    }
    if (emitted > 0 && (size_t)st->pending_count > emitted) {
        for (size_t i = emitted; i < (size_t)st->pending_count; i++) {
            st->pending[i - emitted] = st->pending[i];
        }
    }
    st->pending_count -= (int)emitted;
    *inout_count = emitted;
    return st->pending_count > 0 ? WC_DECODER_NEED_MORE_SLOTS : WC_DECODER_OK;
}

static void ow_destroy(WcDecoderHandle handle) {
    if (handle != NULL) free(handle);
}

// ── ABI entry points ──────────────────────────────────────────────────────

uint32_t wavecrux_decoder_abi_version(void) {
    return WAVECRUX_DECODER_ABI_VERSION;
}

int32_t wavecrux_decoder_register(WcDecoderDef* out_defs,
                                  size_t* inout_count) {
    if (inout_count == NULL) return WC_DECODER_ERR;
    if (out_defs == NULL || *inout_count == 0) {
        *inout_count = 1;
        return WC_DECODER_NEED_MORE_SLOTS;
    }
    out_defs[0].id            = "examples.onewire";
    out_defs[0].display_name  = "1-Wire (demo plugin)";
    out_defs[0].manifest_json = kManifestJson;
    out_defs[0].create        = ow_create;
    out_defs[0].feed          = ow_feed;
    out_defs[0].flush         = ow_flush;
    out_defs[0].destroy       = ow_destroy;
    *inout_count = 1;
    return WC_DECODER_OK;
}
