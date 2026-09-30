// Variant of the test plugin that omits `wavecrux_decoder_register`.
// `dlopen` succeeds but the loader's symbol lookup must report the
// missing entry point and skip this plugin.

#include "../../../../include/wavecrux_decoder.h"

#include <stdint.h>

uint32_t wavecrux_decoder_abi_version(void) {
    return WAVECRUX_DECODER_ABI_VERSION;
}

// `wavecrux_decoder_register` is intentionally not defined.
