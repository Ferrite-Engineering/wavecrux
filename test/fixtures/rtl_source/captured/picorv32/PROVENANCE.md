# PROVENANCE — picorv32 (captured RTL)

A real, third-party RTL design used to exercise the in-app stems generator
(`lib/services/rtl_source/stems_generator.dart`) against production Verilog with
a genuine multi-module instantiation hierarchy — not a hand-authored toy.

| Field | Value |
|---|---|
| **Source project** | PicoRV32 — a size-optimized RV32I/RV32IC RISC-V CPU core |
| **Upstream** | https://github.com/YosysHQ/picorv32 |
| **File** | `picorv32.v` (the entire core, verbatim) |
| **Commit SHA** | `de92ce54e8a3f24f2adc6b5d04de35e4edb873e5` |
| **License** | **ISC** (allow-listed) — © 2015 Claire Xenia Wolf |
| **Capture method** | Direct verbatim download of the raw file at the pinned commit (`curl https://raw.githubusercontent.com/YosysHQ/picorv32/<sha>/picorv32.v`). No edits. |
| **Size** | 3,049 lines / ~95 KB |

## Why this design

`picorv32.v` declares 8 modules and contains real cross-module instantiation:
`picorv32_axi` instantiates both `picorv32_axi_adapter` (instance `axi_adapter`)
and the `picorv32` core (instance `picorv32_core`). It exercises ANSI ports,
parameterized instantiations (`#(...)`), `generate` blocks, and large port lists
— a realistic stress test for the best-effort declaration parser.

## Hand-verified anchors (against the pinned SHA)

These line numbers were verified by hand and are asserted (by token match, so
they survive minor reformatting) in
`test/services/rtl_source/picorv32_captured_test.dart`:

| Hierarchy path | Source line | Line contains |
|---|---|---|
| `picorv32_axi` (scope) | 2517 | `module picorv32_axi` |
| `picorv32_axi.trap` (var) | 2545 | `output trap` |
| `picorv32_axi.picorv32_core` (scope) | 62 | `module picorv32` |
| `picorv32_axi.picorv32_core.trap` (var) | 91 | `trap` |
| `picorv32_axi.axi_adapter` (scope) | 2731 | `module picorv32_axi_adapter` |

`picorv32_axi` and `picorv32_wb` are both un-instantiated, so auto-top detection
reports them as ambiguous candidates (the generator refuses to guess and the
test passes `topModule: 'picorv32_axi'`).

## License note

ISC is on the WaveCrux captured-fixture allow-list (MIT, BSD-2, BSD-3,
Apache-2.0, ISC, CC0, public-domain). The full ISC text is preserved in the
header of the vendored `picorv32.v`.
