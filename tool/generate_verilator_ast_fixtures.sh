#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Regenerates the committed Verilator AST fixtures under
# test/fixtures/rtl_source/verilator_ast/ (see the README there).
#
# Requires `verilator` (fixtures last generated with Verilator 5.048) and
# `python3` on PATH. Run from anywhere:
#
#   tool/generate_verilator_ast_fixtures.sh
#
# For each design it runs `verilator --json-only` and rewrites the meta
# files-table paths to repo-relative form so the committed fixtures are
# machine-independent (Verilator emits absolute paths). Tool-internal
# entries (e.g. <verilated_std>) get their realpath collapsed to the stable
# filename for the same reason.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/test/fixtures/rtl_source/verilator_ast"

generate() {
  local name="$1" top="$2"
  shift 2
  local out_dir="$FIXTURE_DIR/$name"
  local mdir
  mdir="$(mktemp -d)"
  verilator --json-only -Wno-fatal --Mdir "$mdir" --top-module "$top" "$@" \
    > /dev/null
  mkdir -p "$out_dir"
  cp "$mdir/V$top.tree.json" "$out_dir/"
  REPO_ROOT="$REPO_ROOT" python3 - "$mdir/V$top.tree.meta.json" \
    "$out_dir/V$top.tree.meta.json" << 'PY'
import json
import os
import sys

src, dst = sys.argv[1], sys.argv[2]
repo = os.environ['REPO_ROOT']
with open(src) as f:
    meta = json.load(f)
for entry in meta.get('files', {}).values():
    for key in ('filename', 'realpath'):
        path = entry.get(key)
        if not isinstance(path, str):
            continue
        if path.startswith(repo + '/'):
            entry[key] = path[len(repo) + 1:]
        elif key == 'realpath' and os.path.isabs(path):
            # Verilator-internal file outside the repo: keep the stable
            # placeholder name (e.g. "<verilated_std>") instead of a
            # machine-local install path.
            entry[key] = entry.get('filename', path)
with open(dst, 'w') as f:
    json.dump(meta, f, indent=1)
    f.write('\n')
PY
  rm -rf "$mdir"
  echo "regenerated $name (top: $top)"
}

generate cpu top "$REPO_ROOT"/test/fixtures/rtl_source/cpu/*.v
generate genloop top "$FIXTURE_DIR/genloop.v"
