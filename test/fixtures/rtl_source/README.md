# RTL source fixtures

Sample HDL designs that exercise the in-app RTL stems **generator**
(`lib/services/rtl_source/stems_generator.dart`) and the source-annotation
load/view path. Used by `test/services/rtl_source/stems_generation_e2e_test.dart`
and `test/services/rtl_source/*_test.dart`.

## Provenance

All files here are **clean-room, hand-authored** for WaveCrux's test suite — not
captured from any external project. They carry no third-party license
obligations and may be modified freely. They are intentionally small and written
in the common synthesizable subset so line-number mappings are deterministic.

- `cpu/` — Verilog: `top` instantiates `regfile` (`u_regfile`) and `alu`
  (`u_alu`); covers ANSI ports, internal nets, multi-file hierarchy, and an
  unparented memory (`mem`).
- `vhdl/` — VHDL: `counter` entity + architecture; covers entity ports and
  architecture signals across the entity/architecture split.

## Captured (`captured/`)

Real third-party RTL, vendored verbatim at a pinned commit with a
`PROVENANCE.md` (source, SHA, license, hand-verified anchors). License
allow-list matches the protocol-decoder corpus (MIT, BSD-2/3, Apache-2.0, ISC,
CC0, public-domain).

- `captured/picorv32/` — **PicoRV32** RISC-V core (ISC). Exercises the generator
  on production Verilog: 8 modules, multi-line parameterized instantiations
  (`picorv32_axi` → `picorv32_core` via a many-line `#(...)`), `generate` blocks,
  and large port lists. Driven by `stems_generation_e2e`-style assertions in
  `test/services/rtl_source/picorv32_captured_test.dart`.

These live under `rtl_source/captured/`, not `fixtures/protocol/`, so the
protocol-decoder static guards (`captured_fixture_companion_test`,
`captured_fixture_licenses_test`) don't apply; provenance/licensing is enforced
by review + the per-fixture `PROVENANCE.md`.
