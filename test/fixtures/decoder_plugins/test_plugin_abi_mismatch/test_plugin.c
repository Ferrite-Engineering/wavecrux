// Variant of the test plugin that reports a bumped ABI MAJOR version.
// The loader must reject this plugin with status `abiMismatch` and
// proceed to load every other plugin in the same directory.

#include "../../../../include/wavecrux_decoder.h"

#include <stdint.h>
#include <stdlib.h>

static const char kManifestJson[] =
    "{\"signals\":[],\"parameters\":[]}";

uint32_t wavecrux_decoder_abi_version(void) {
    // Pretend to speak ABI 99.0 — incompatible with whatever the host
    // actually requires. The loader must not invoke `register` once it
    // sees the mismatch.
    return ((uint32_t)99 << 16) | (uint32_t)0;
}

int32_t wavecrux_decoder_register(WcDecoderDef* out_defs,
                                  size_t* inout_count) {
    (void)out_defs;
    if (inout_count != NULL) *inout_count = 0;
    // Should never be reached because the loader gates on the version
    // mismatch above.
    return WC_DECODER_ERR;
}

// Reference the manifest so it is not stripped by the linker —
// otherwise some toolchains drop unused .rodata sections.
const char* _wavecrux_test_keep = kManifestJson;
