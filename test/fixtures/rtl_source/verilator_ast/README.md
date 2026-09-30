# Verilator AST fixtures (`--json-only` dumps)

Committed Verilator AST dumps used by
`test/services/rtl_source/verilator_ast_stems_importer_test.dart` to test the
conversion of `verilator --json-only` output into the `StemsFile` model.

| Directory  | Sources                                       | What it exercises                                            |
|------------|-----------------------------------------------|--------------------------------------------------------------|
| `cpu/`     | `test/fixtures/rtl_source/cpu/*.v` (existing) | Multi-module instance hierarchy (`top.u_regfile`, `top.u_alu`) |
| `genloop/` | `genloop.v` (this directory)                  | Unrolled generate-for scopes (`gen_blink[0]`…`gen_blink[3]`), `genvar` filtering |

Each directory holds the two files Verilator emits: `V<top>.tree.json` (the
AST) and `V<top>.tree.meta.json` (file table + pointer table).

## Regenerating

```bash
tool/generate_verilator_ast_fixtures.sh
```

Requires `verilator` and `python3` on PATH. Fixtures were last generated with
**Verilator 5.048**. The script rewrites the meta files-table paths to
repo-relative form (Verilator emits absolute paths) so the committed fixtures
are machine-independent; tool-internal entries such as `<verilated_std>` keep
their placeholder names.

The JSON schema is Verilator-internal with **no stability contract** — it
tracks compiler internals and may change between Verilator releases. If a
regeneration with a newer Verilator changes the shape (node types, `loc`
format, `modp` pointer encoding), the importer
(`lib/services/rtl_source/verilator_ast_stems_importer.dart`) and its tests must
be revisited against the premises that file documents.
