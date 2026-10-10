// Loader fixture for parameter-driven signal widths (ABI 1.2 manifest keys
// `width_param` / `width_scale`). The manifest ties `data` to the
// `data_width` parameter and `datak` to one bit per byte of it, the shape a
// PIPE decoder with 8- to 64-bit data needs. `flush` reports the
// `WcSample.bit_width` the host packed, as the label "bits=<n>".
//
// Build (Linux/macOS):  see ../build_test_plugins.sh
// Build (Windows):      see ../build_test_plugins.bat

#include "../../../../include/wavecrux_decoder.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static const char kDecoderId[] = "test_width_param";

static const char kManifestJson[] =
    "{"
    "\"signals\":["
    "{\"name\":\"data\",\"bit_width\":64,"
    "\"width_param\":\"data_width\",\"width_scale\":1},"
    "{\"name\":\"datak\",\"bit_width\":8,"
    "\"width_param\":\"data_width\",\"width_scale\":0.125}"
    "],"
    "\"parameters\":["
    "{\"name\":\"data_width\",\"kind\":\"integer\",\"default\":64}"
    "],"
    "\"description\":\"Loader fixture with parameter-driven signal widths.\""
    "}";

typedef struct WidthState {
    uint32_t last_bit_width;
    int flushed;
    char label[32];
} WidthState;

static WcDecoderHandle w_create(const char* config_json) {
    (void)config_json;
    return (WcDecoderHandle)calloc(1, sizeof(WidthState));
}

static int32_t w_feed(WcDecoderHandle handle,
                      const WcSample* sample,
                      WcTransaction* out_transactions,
                      size_t* inout_count) {
    (void)out_transactions;
    WidthState* st = (WidthState*)handle;
    if (st == NULL || sample == NULL || inout_count == NULL) {
        if (inout_count != NULL) *inout_count = 0;
        return WC_DECODER_ERR;
    }
    st->last_bit_width = sample->bit_width;
    *inout_count = 0;
    return WC_DECODER_OK;
}

static int32_t w_flush(WcDecoderHandle handle,
                       WcTransaction* out_transactions,
                       size_t* inout_count) {
    WidthState* st = (WidthState*)handle;
    if (st == NULL || inout_count == NULL) {
        if (inout_count != NULL) *inout_count = 0;
        return WC_DECODER_ERR;
    }
    if (st->flushed) {
        *inout_count = 0;
        return WC_DECODER_OK;
    }
    if (*inout_count == 0) {
        *inout_count = 1;
        return WC_DECODER_NEED_MORE_SLOTS;
    }
    st->flushed = 1;
    snprintf(st->label, sizeof st->label, "bits=%u",
             (unsigned)st->last_bit_width);
    out_transactions[0].start_fs    = 0;
    out_transactions[0].end_fs      = 0;
    out_transactions[0].label       = st->label;
    out_transactions[0].fields_json = "{}";
    out_transactions[0].is_error    = 0;
    *inout_count = 1;
    return WC_DECODER_OK;
}

static void w_destroy(WcDecoderHandle handle) { free(handle); }

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
    out_defs[0].id            = kDecoderId;
    out_defs[0].display_name  = "Test Width Param";
    out_defs[0].manifest_json = kManifestJson;
    out_defs[0].create        = w_create;
    out_defs[0].feed          = w_feed;
    out_defs[0].flush         = w_flush;
    out_defs[0].destroy       = w_destroy;
    *inout_count = 1;
    return WC_DECODER_OK;
}
