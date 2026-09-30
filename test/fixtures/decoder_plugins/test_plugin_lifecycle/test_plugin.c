// Loader fixture that counts decoder-instance lifecycles, so a test can
// assert the host destroys every instance `create` returned exactly once,
// whichever way the decode ends. The ABI forbids touching a handle after
// `destroy`, so a second `destroy` is a double free in any plugin that
// frees its state there.
//
// The `fail` parameter picks the step that fails:
//   "create" — `create` returns NULL;
//   "feed"   — `feed` returns WC_DECODER_ERR;
//   "flush"  — `flush` returns WC_DECODER_ERR;
//   absent   — nothing fails.
//
// Instances live in static storage and `destroy` never frees, so a double
// destroy is counted rather than crashing the test process. The counters
// are exported for the test to read through its own `DynamicLibrary`.
//
// Build (Linux/macOS):  see ../build_test_plugins.sh
// Build (Windows):      see ../build_test_plugins.bat

#include "../../../../include/wavecrux_decoder.h"

#include <stdint.h>
#include <string.h>

static const char kDecoderId[] = "test_lifecycle";

static const char kManifestJson[] =
    "{"
    "\"signals\":["
    "{\"name\":\"data\",\"description\":\"Test data line\",\"bit_width\":1}"
    "],"
    "\"parameters\":["
    "{\"name\":\"fail\",\"kind\":\"string\",\"default\":\"\"}"
    "],"
    "\"description\":\"Loader fixture that counts instance lifecycles.\","
    "\"category\":\"userPlugin\""
    "}";

#define kMaxInstances 64

typedef struct LifecycleState {
    int fail_feed;
    int fail_flush;
    int destroys;
} LifecycleState;

static LifecycleState g_instances[kMaxInstances];
static int32_t g_created = 0;
static int32_t g_destroyed = 0;
static int32_t g_destroyed_twice = 0;
static int32_t g_destroyed_unknown = 0;

static int in_pool(WcDecoderHandle handle) {
    const LifecycleState* st = (const LifecycleState*)handle;
    return st >= &g_instances[0] && st < &g_instances[g_created];
}

static WcDecoderHandle lc_create(const char* config_json) {
    if (config_json == NULL) return NULL;
    if (strstr(config_json, "\"fail\":\"create\"") != NULL) return NULL;
    if (g_created >= kMaxInstances) return NULL;
    LifecycleState* st = &g_instances[g_created++];
    st->fail_feed = strstr(config_json, "\"fail\":\"feed\"") != NULL;
    st->fail_flush = strstr(config_json, "\"fail\":\"flush\"") != NULL;
    st->destroys = 0;
    return (WcDecoderHandle)st;
}

static int32_t lc_feed(WcDecoderHandle handle,
                       const WcSample* sample,
                       WcTransaction* out_transactions,
                       size_t* inout_count) {
    (void)sample;
    (void)out_transactions;
    if (inout_count != NULL) *inout_count = 0;
    if (handle == NULL || !in_pool(handle)) return WC_DECODER_ERR;
    LifecycleState* st = (LifecycleState*)handle;
    return st->fail_feed ? WC_DECODER_ERR : WC_DECODER_OK;
}

static int32_t lc_flush(WcDecoderHandle handle,
                        WcTransaction* out_transactions,
                        size_t* inout_count) {
    (void)out_transactions;
    if (inout_count != NULL) *inout_count = 0;
    if (handle == NULL || !in_pool(handle)) return WC_DECODER_ERR;
    LifecycleState* st = (LifecycleState*)handle;
    return st->fail_flush ? WC_DECODER_ERR : WC_DECODER_OK;
}

static void lc_destroy(WcDecoderHandle handle) {
    g_destroyed++;
    if (handle == NULL || !in_pool(handle)) {
        g_destroyed_unknown++;
        return;
    }
    LifecycleState* st = (LifecycleState*)handle;
    if (st->destroys++ > 0) g_destroyed_twice++;
}

// Instances `create` returned (NULL returns are not counted).
int32_t wcx_test_lifecycle_created(void) { return g_created; }

// Calls to `destroy`, including repeats.
int32_t wcx_test_lifecycle_destroyed(void) { return g_destroyed; }

// `destroy` calls on an instance already destroyed.
int32_t wcx_test_lifecycle_destroyed_twice(void) { return g_destroyed_twice; }

// `destroy` calls on a handle `create` never returned.
int32_t wcx_test_lifecycle_destroyed_unknown(void) {
    return g_destroyed_unknown;
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
    out_defs[0].display_name  = "Test Lifecycle";
    out_defs[0].manifest_json = kManifestJson;
    out_defs[0].create        = lc_create;
    out_defs[0].feed          = lc_feed;
    out_defs[0].flush         = lc_flush;
    out_defs[0].destroy       = lc_destroy;
    *inout_count = 1;
    return WC_DECODER_OK;
}
