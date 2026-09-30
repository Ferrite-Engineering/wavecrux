// Variant of the test plugin that returns a malformed JSON manifest.
// The loader must surface this with status `manifestInvalid` and not
// register anything from the plugin.

#include "../../../../include/wavecrux_decoder.h"

#include <stdint.h>
#include <stdlib.h>

static const char kBadManifestJson[] = "{ this is not valid JSON";

static WcDecoderHandle cm_create(const char* config_json) {
    (void)config_json;
    return (WcDecoderHandle)0x1;  // Non-NULL sentinel; never invoked.
}
static int32_t cm_feed(WcDecoderHandle handle,
                       const WcSample* sample,
                       WcTransaction* out_transactions,
                       size_t* inout_count) {
    (void)handle;
    (void)sample;
    (void)out_transactions;
    if (inout_count != NULL) *inout_count = 0;
    return WC_DECODER_ERR;
}
static int32_t cm_flush(WcDecoderHandle handle,
                        WcTransaction* out_transactions,
                        size_t* inout_count) {
    (void)handle;
    (void)out_transactions;
    if (inout_count != NULL) *inout_count = 0;
    return WC_DECODER_OK;
}
static void cm_destroy(WcDecoderHandle handle) { (void)handle; }

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
    out_defs[0].id            = "test_corrupt_manifest";
    out_defs[0].display_name  = "Test Corrupt Manifest";
    out_defs[0].manifest_json = kBadManifestJson;
    out_defs[0].create        = cm_create;
    out_defs[0].feed          = cm_feed;
    out_defs[0].flush         = cm_flush;
    out_defs[0].destroy       = cm_destroy;
    *inout_count = 1;
    return WC_DECODER_OK;
}
