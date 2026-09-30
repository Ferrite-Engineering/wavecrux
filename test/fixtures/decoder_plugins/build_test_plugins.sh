#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build all decoder-plugin loader test fixtures.
#
# Usage:
#   bash test/fixtures/decoder_plugins/build_test_plugins.sh
#
# Compiles every variant directory under test/fixtures/decoder_plugins
# into the platform-appropriate shared library, leaving the artifact in
# the same directory the source lives in. The Dart test setUpAll() in
# ffi_decoder_loader_test.dart invokes this script via Process.run and
# skips the test if it exits non-zero (e.g. no C toolchain installed).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCLUDE_DIR="$(cd "${HERE}/../../../include" && pwd)"

uname_s="$(uname -s)"
case "${uname_s}" in
    Darwin)
        EXT="dylib"
        SHARED_FLAGS="-dynamiclib"
        ;;
    Linux)
        EXT="so"
        SHARED_FLAGS="-shared -fPIC"
        ;;
    *)
        echo "build_test_plugins.sh: unsupported uname=${uname_s}" >&2
        exit 1
        ;;
esac

CC="${CC:-cc}"
if ! command -v "${CC}" >/dev/null 2>&1; then
    echo "build_test_plugins.sh: no C compiler at \$CC=${CC}; skipping" >&2
    exit 1
fi

build_one() {
    local subdir="$1"
    local libname="$2"
    local src="${HERE}/${subdir}/test_plugin.c"
    local out="${HERE}/${subdir}/lib${libname}.${EXT}"
    "${CC}" ${SHARED_FLAGS} -O0 -g -I"${INCLUDE_DIR}" \
        -o "${out}" "${src}"
    echo "built ${out}"
}

build_one "test_plugin"                 "test_passthrough"
build_one "test_plugin_abi_mismatch"    "test_abi_mismatch"
build_one "test_plugin_missing_symbol"  "test_missing_symbol"
build_one "test_plugin_corrupt_manifest" "test_corrupt_manifest"
build_one "test_plugin_named"            "test_named"
build_one "test_plugin_config"           "test_config"
build_one "test_plugin_lifecycle"        "test_lifecycle"

echo "all decoder-plugin test fixtures built"
