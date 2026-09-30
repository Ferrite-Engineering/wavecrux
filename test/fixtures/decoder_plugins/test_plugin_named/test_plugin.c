// Loader fixture exercising the optional ABI 1.1 self-identification
// entry points. It registers a single decoder but also exports
// `wavecrux_decoder_plugin_name` / `wavecrux_decoder_plugin_description`,
// so the loader must surface the plugin-reported name on the
// DecoderPluginInfo instead of falling back to the first decoder's
// display name (which `test_plugin` exercises).
//
// Build (Linux/macOS):  see ../build_test_plugins.sh
// Build (Windows):      see ../build_test_plugins.bat

#include "../../../../include/wavecrux_decoder.h"

#include <stdint.h>
#include <stdlib.h>

static const char kManifestJson[] =
    "{"
    "\"signals\":["
    "{\"name\":\"data\",\"description\":\"Test data line\",\"bit_width\":1}"
    "],"
    "\"parameters\":[],"
    "\"description\":\"Named-plugin fixture decoder.\","
    "\"category\":\"userPlugin\""
    "}";

static WcDecoderHandle nd_create(const char* config_json) {
    (void)config_json;
    return (WcDecoderHandle)calloc(1, sizeof(int));
}

static int32_t nd_feed(WcDecoderHandle handle,
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

static int32_t nd_flush(WcDecoderHandle handle,
                        WcTransaction* out_transactions,
                        size_t* inout_count) {
    (void)handle;
    (void)out_transactions;
    if (inout_count != NULL) *inout_count = 0;
    return WC_DECODER_OK;
}

static void nd_destroy(WcDecoderHandle handle) {
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
    out_defs[0].id            = "named.demo";
    out_defs[0].display_name  = "Named Demo";
    out_defs[0].manifest_json = kManifestJson;
    out_defs[0].create        = nd_create;
    out_defs[0].feed          = nd_feed;
    out_defs[0].flush         = nd_flush;
    out_defs[0].destroy       = nd_destroy;
    *inout_count = 1;
    return WC_DECODER_OK;
}

// Optional ABI 1.1 self-identification.
const char* wavecrux_decoder_plugin_name(void) {
    return "Example Plugin Suite";
}

const char* wavecrux_decoder_plugin_description(void) {
    return "Fixture plugin exercising ABI 1.1 self-identification.";
}
