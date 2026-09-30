// Minimal "passthrough" decoder plugin used by the loader unit tests.
// Emits exactly one transaction per `feed` call carrying the
// originating sample's timestamp. Per-instance state is a single int
// counter so we can also assert that `create` / `destroy` lifecycle
// runs as expected.
//
// Build (Linux/macOS):  see ../build_test_plugins.sh
// Build (Windows):      see ../build_test_plugins.bat

#include "../../../../include/wavecrux_decoder.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static const char kManifestJson[] =
    "{"
    "\"signals\":["
    "{\"name\":\"data\",\"description\":\"Test data line\",\"bit_width\":1}"
    "],"
    "\"parameters\":[],"
    "\"description\":\"Loader fixture decoder used by FfiDecoderLoader unit tests.\","
    "\"category\":\"userPlugin\""
    "}";

typedef struct PassthroughState {
    int feed_count;
} PassthroughState;

static WcDecoderHandle pt_create(const char* config_json) {
    (void)config_json;
    PassthroughState* st =
        (PassthroughState*)calloc(1, sizeof(PassthroughState));
    return (WcDecoderHandle)st;
}

static int32_t pt_feed(WcDecoderHandle handle,
                       const WcSample* sample,
                       WcTransaction* out_transactions,
                       size_t* inout_count) {
    PassthroughState* st = (PassthroughState*)handle;
    if (handle == NULL || sample == NULL || inout_count == NULL) {
        if (inout_count != NULL) *inout_count = 0;
        return WC_DECODER_ERR;
    }
    if (*inout_count == 0) {
        return WC_DECODER_NEED_MORE_SLOTS;
    }
    st->feed_count += 1;
    out_transactions[0].start_fs    = sample->timestamp_fs;
    out_transactions[0].end_fs      = sample->timestamp_fs;
    out_transactions[0].label       = "passthrough";
    out_transactions[0].fields_json = "{\"feeds\":\"1\"}";
    out_transactions[0].is_error    = 0;
    *inout_count = 1;
    return WC_DECODER_OK;
}

static int32_t pt_flush(WcDecoderHandle handle,
                        WcTransaction* out_transactions,
                        size_t* inout_count) {
    (void)handle;
    (void)out_transactions;
    if (inout_count != NULL) *inout_count = 0;
    return WC_DECODER_OK;
}

static void pt_destroy(WcDecoderHandle handle) {
    if (handle != NULL) free(handle);
}

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
    out_defs[0].id            = "test_passthrough";
    out_defs[0].display_name  = "Test Passthrough";
    out_defs[0].manifest_json = kManifestJson;
    out_defs[0].create        = pt_create;
    out_defs[0].feed          = pt_feed;
    out_defs[0].flush         = pt_flush;
    out_defs[0].destroy       = pt_destroy;
    *inout_count = 1;
    return WC_DECODER_OK;
}
