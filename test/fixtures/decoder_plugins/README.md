# Decoder plugin loader test fixtures

Tiny native plugins used by [`test/services/decoders/ffi/ffi_decoder_loader_test.dart`](../../../test/services/decoders/ffi/ffi_decoder_loader_test.dart) to exercise every load-status path in `FfiDecoderLoader`.

| Variant | Purpose |
|---|---|
| `test_plugin/` | Baseline good plugin. Loads, registers a single `test_passthrough` decoder, and emits one transaction per `feed`. |
| `test_plugin_abi_mismatch/` | Reports ABI MAJOR=99. Loader must reject with `abiMismatch`. |
| `test_plugin_missing_symbol/` | Omits `wavecrux_decoder_register`. Loader must report `missingSymbol`. |
| `test_plugin_corrupt_manifest/` | Returns malformed JSON from `register`. Loader must report `manifestInvalid`. |
| `test_plugin_named/` | Exports the optional ABI 1.1 plugin name and description. |
| `test_plugin_config/` | Refuses a `create` configuration that does not carry its `decoder_id`, and echoes the configuration back from `flush`. |
| `test_plugin_width/` | Ties its `data` and `datak` widths to the `data_width` parameter (`width_param` / `width_scale`) and reports the sample width the host packed. |
| `test_plugin_lifecycle/` | Counts `create` and `destroy` per instance; its `fail` parameter makes `create`, `feed` or `flush` fail. The host must destroy every instance exactly once. |

## Building

The Dart test setup invokes [`build_test_plugins.sh`](build_test_plugins.sh) (Linux/macOS) or [`build_test_plugins.bat`](build_test_plugins.bat) (Windows) via `Process.run`. Tests are skipped when no C toolchain is available — there is no fallback path that mocks the FFI surface.

To build manually:

```bash
bash test/fixtures/decoder_plugins/build_test_plugins.sh
```

This produces, for each variant directory:

* Linux: `lib<name>.so`
* macOS: `lib<name>.dylib`
* Windows: `<name>.dll`

The shared libraries are intentionally **not committed** to the repo — they are rebuilt on demand by the test runner. The C source files and `CMakeLists.txt` files **are** committed.

## Regenerating after editing the C ABI

If `include/wavecrux_decoder.h` changes in a backward-incompatible way (MAJOR bump), the variants here continue to compile but their behaviour with respect to the loader needs review:

1. Update each variant's source to match the new ABI surface.
2. Re-run `build_test_plugins.sh` and `flutter test test/services/decoders/ffi/ffi_decoder_loader_test.dart`.
3. Update the loader's `WAVECRUX_DECODER_ABI_MAJOR` constant in lock-step.
