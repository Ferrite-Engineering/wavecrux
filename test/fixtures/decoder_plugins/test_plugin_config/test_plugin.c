// Loader fixture that pins the instance configuration the host hands to
// `create`. Plugins that host several decoders behind one entry point
// (the Sigrok bridge shim is one) pick the decoder from `decoder_id`, so
// `create` refuses a configuration that does not name this decoder.
// `flush` echoes the configuration back as the transaction's
// `fields_json`, letting the Dart test assert every top-level key.
// The manifest declares `enum_labels` in both accepted shapes: an
// object keyed by value, and an array in `enum_values` order.
//
// Build (Linux/macOS):  see ../build_test_plugins.sh
// Build (Windows):      see ../build_test_plugins.bat

#include "../../../../include/wavecrux_decoder.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static const char kDecoderId[] = "test_config_contract";

static const char kManifestJson[] =
    "{"
    "\"signals\":["
    "{\"name\":\"data\",\"description\":\"Test data line\",\"bit_width\":1}"
    "],"
    "\"parameters\":["
    "{\"name\":\"baudrate\",\"kind\":\"integer\",\"default\":9600},"
    "{\"name\":\"parity\",\"kind\":\"enum\",\"default\":\"n\","
    "\"enum_values\":[\"n\",\"e\"],"
    "\"enum_labels\":{\"n\":\"None\",\"e\":\"Even\"}},"
    "{\"name\":\"direction\",\"kind\":\"enum\",\"default\":\"tx\","
    "\"enum_values\":[\"tx\",\"rx\"],"
    "\"enum_labels\":[\"Downstream\",\"Upstream\"]}"
    "],"
    "\"description\":\"Loader fixture that echoes its instance configuration.\","
    "\"category\":\"userPlugin\""
    "}";

typedef struct ConfigState {
    char* config_json;
    int flushed;
} ConfigState;

static WcDecoderHandle cfg_create(const char* config_json) {
    if (config_json == NULL) return NULL;
    if (strstr(config_json, "\"decoder_id\":\"test_config_contract\"") == NULL) {
        return NULL;
    }
    ConfigState* st = (ConfigState*)calloc(1, sizeof(ConfigState));
    if (st == NULL) return NULL;
    size_t len = strlen(config_json);
    st->config_json = (char*)malloc(len + 1);
    if (st->config_json == NULL) {
        free(st);
        return NULL;
    }
    memcpy(st->config_json, config_json, len + 1);
    return (WcDecoderHandle)st;
}

static int32_t cfg_feed(WcDecoderHandle handle,
                        const WcSample* sample,
                        WcTransaction* out_transactions,
                        size_t* inout_count) {
    (void)sample;
    (void)out_transactions;
    if (handle == NULL || inout_count == NULL) {
        if (inout_count != NULL) *inout_count = 0;
        return WC_DECODER_ERR;
    }
    *inout_count = 0;
    return WC_DECODER_OK;
}

static int32_t cfg_flush(WcDecoderHandle handle,
                         WcTransaction* out_transactions,
                         size_t* inout_count) {
    ConfigState* st = (ConfigState*)handle;
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
    out_transactions[0].start_fs    = 0;
    out_transactions[0].end_fs      = 0;
    out_transactions[0].label       = kDecoderId;
    out_transactions[0].fields_json = st->config_json;
    out_transactions[0].is_error    = 0;
    *inout_count = 1;
    return WC_DECODER_OK;
}

static void cfg_destroy(WcDecoderHandle handle) {
    ConfigState* st = (ConfigState*)handle;
    if (st == NULL) return;
    free(st->config_json);
    free(st);
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
    out_defs[0].id            = kDecoderId;
    out_defs[0].display_name  = "Test Config Contract";
    out_defs[0].manifest_json = kManifestJson;
    out_defs[0].create        = cfg_create;
    out_defs[0].feed          = cfg_feed;
    out_defs[0].flush         = cfg_flush;
    out_defs[0].destroy       = cfg_destroy;
    *inout_count = 1;
    return WC_DECODER_OK;
}
