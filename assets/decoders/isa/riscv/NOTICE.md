# RISC-V instruction-decoder TOML files

The TOML schema used by the files in this directory is that of the
**`instruction-decoder` Rust crate**, originated by Johannes Kepler University
(JKU) Linz and published at <https://github.com/ics-jku/instruction-decoder>
under the MIT license:

> Copyright (c) 2024 Johannes Kepler University Linz
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to
> deal in the Software without restriction, …

The schema (six top-level keys: `set`, `width`, `[formats]`, `[types]`,
`[mappings]`, plus per-format `[…]` and `[….repr]`/`[….instructions.<name>]`
sections) is the contract that makes WaveCrux's RISC-V decoder cross-tool
compatible with Surfer (which consumes the same crate). A `.toml` file
written for the JKU loader loads in WaveCrux unmodified, and vice versa.

The subtle part of that contract, and the part worth writing down: a slice's
`top`/`bot` are positions **within the decoded part's value**, not within the
instruction word. Slices tile the word MSB-first in declaration order, each
consuming `top - bot + 1` bits from a running cursor, and the extracted bits
are shifted left by `bot` and OR'd into the part. That indirection is what
lets a scattered immediate — RISC-V's B-type, J-type and every compressed
branch — be described declaratively, and it is why the implicit `imm[0] = 0`
on branch and jump offsets needs no scaling field: no slice claims value bit
0, so it stays zero. Reading `top`/`bot` as instruction-word indices instead
parses without error and decodes to plausible garbage, so the compatibility
claim above is pinned by a test (`instruction_disassembler_test.dart`,
"Cross-tool compatibility with the JKU loader") rather than left to review.

The TOML *files* in this directory are hand-authored against that schema for
the WaveCrux launch coverage (RV32I, RV64I, M, A, F, D, C). They are not
verbatim copies of the JKU files.

**You can add your own tables without rebuilding.** On desktop builds,
**Settings → Extensions → ISA encoding tables → Add directory…** (or the
`WAVECRUX_ISA_PATH` environment variable) names directories whose `*.toml`
tables load alongside these. They are composed into the RISC-V Instruction
Trace decoder at launch — restart after adding a directory — and a file with
the same name as a bundled set replaces it. Upstream's own files decode
correctly, which is what the compatibility test above establishes, so they can
be loaded the same way. `docs/ISA_TABLE_AUTHORING.md` is the format and loading
reference.

Schema attribution is reproduced in the project's top-level `NOTICES` file.
