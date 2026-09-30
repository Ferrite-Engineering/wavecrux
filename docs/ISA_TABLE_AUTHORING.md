# Authoring an ISA encoding table

WaveCrux decodes an instruction stream from **TOML encoding tables**. The RISC-V
tables ship bundled; you can add your own. The disassembler itself contains no
architecture knowledge — describing an instruction set is authoring a table,
not writing code.

Your tables are composed into the **RISC-V Instruction Trace** decoder, after
the bundled RISC-V sets it always loads (RV32I, plus whichever extensions its
configuration enables). The intended use is extending a RISC-V core — custom
instructions in the `custom-0`…`custom-3` opcode space, for example — or
replacing one of the bundled sets. A table for an unrelated architecture still
decodes *alongside* RV32I: your table wins every encoding the two share, but
any word it does not match can still decode as RISC-V.

This document is the format reference. It lives in the product repo because a
stale copy would misdescribe the loader that reads it.

---

## 1. Where WaveCrux looks

**Settings → Extensions → ISA encoding tables → Add directory…** (the section
sits below Decoder Plugins).

Every `*.toml` directly inside a configured directory is loaded. Subdirectories
are not scanned, and symbolic links are not followed. Paths must be
**absolute**: a relative path means something different depending on how the
app was launched, so relative entries are dropped with a log line rather than
guessed at. A directory that does not exist is skipped silently.

`WAVECRUX_ISA_PATH` names additional directories, path-list separated (`:` on
Unix, `;` on Windows). It exists so a CI job or a shared team checkout can
supply tables without every engineer configuring the same path by hand. Its
directories are scanned **before** the configured list, so if two directories
hold a file with the same name, the one scanned later wins — the configured
directory, not the environment variable.

Tables are composed **at launch**. After adding a directory, restart WaveCrux.
The Settings panel reports whether a table *parses* immediately — that is the
loop you want while authoring — but the running decoder picks it up on the next
start.

> **Desktop builds only.** The panel is not shown on iOS, Android, or the web
> build. The web build (app.wavecrux.app) has no filesystem, so only the
> bundled tables load there.

### Name collisions

A table is keyed by its **file name** (case-sensitive), not by the `set` label
inside it. Two files declaring `set = "MYCORE"` are two sets, and a file named
`RV32I.toml` replaces the bundled RV32I on purpose — silently preferring ours
would be indistinguishable from the file never loading. A replacement takes
the bundled set's place in the composition order.

A table with a new name is composed **after** the bundled RISC-V sets. The
disassembler resolves an encoding matched by more than one set by *last match
wins*, so a table describing a custom instruction that overlaps a base encoding
takes precedence. That overlap is usually the reason the table exists.

---

## 2. A complete minimal table

```toml
set   = "MYCORE"       # recorded as the `isa` field of each decoded instruction
width = 32             # instruction word width in bits — see §4

[formats]
names = ["r_type"]
# [name, bitwidth, type, radix?]
parts = [
  ["opcode", 7,  "",    ""],
  ["rd",     5,  "reg", ""],
  ["imm",    20, "i32", "hexadecimal"],
]

[types]
names = ["r"]
[[types.r]]
name = "imm"
top  = 19
bot  = 0
[[types.r]]
name = "rd"
top  = 4
bot  = 0
[[types.r]]
name = "opcode"
top  = 6
bot  = 0

[mappings]
names = ["reg"]
reg = ["zero", "ra", "sp", "gp"]     # index is the raw field value

[r_type]
type = "r"

[r_type.repr]
default = "custom %rd%, %imm%"
myinsn  = "$name$ %rd%, %imm%"

[r_type.instructions.myinsn]
mask  = 127      # bits that must match
match = 11       # the value they must match
```

The word `0x0001208B` (`imm = 0x12`, `rd = 1`, opcode `0x0B`) renders as
`myinsn ra, 0x12`.

---

## 3. The part that trips everyone

**`top` and `bot` are positions inside the decoded part's value, not inside the
instruction word.**

Slices tile the word MSB-first from a running cursor, in declaration order. Each
slice consumes `top - bot + 1` bits from the word and places them at bit `bot`
of that part's value.

Two consequences:

- **Declaration order is the word layout.** The first slice takes the most
  significant bits.
- **A scattered immediate is expressible** — several slices naming the same part
  at different value positions. RISC-V's B-type and J-type work exactly this
  way, and their implicit `imm[0] = 0` needs no special field: no slice claims
  value bit 0, so it stays zero.

Getting this backwards produces a table that decodes without error and reports
wrong operands. It is the single most likely mistake, and it is why the loader
enforces the next rule.

### Slices must account for every bit

Every type's slice widths must sum to `width`. A gap silently mis-reads every
field after it, so the loader rejects the table rather than decoding it:

```
mycore.toml: types.r covers 25 bits, not 32 — slices tile the word MSB-first
and must account for every bit. Add a slice for the gap, or widen an existing
one.
```

Pad with a slice for the unused bits rather than leaving a hole.

---

## 4. Field reference

### `width`

The loader accepts 1..64, but the instruction-trace decoder fetches **32-bit**
words and the disassembler only consults sets whose `width` equals 32. A table
with any other width loads without error and never decodes anything. 16-bit
compressed encodings go in the low half of a 32-bit word, as the bundled
`RV32C-lower.toml` does.

### `parts` — `[name, bitwidth, type, radix?]`

`bitwidth` must be an integer but is not otherwise used: a part's width comes
from its slices (`max(top) + 1`). `type` is either a builtin or **the name of a
mapping table**. Builtin names are case-sensitive:

| Builtin | Meaning |
|---|---|
| `""` | not decoded — use it for fields such as the opcode, and leave it out of `repr` |
| `boolean` | `true` / `false` |
| `char` | printable ASCII, else the number in the part's radix |
| `i8` `i16` `i32` `i64` | signed, sign-extended from the part's own width (the suffix is not used) |
| `u8` `u16` `u32` `u64` | unsigned |
| `isize` `usize` | aliases for `i64` / `u64` |
| `f32` `f64` | accepted, but rendered as an unsigned integer in the part's radix — there is no floating-point formatting |
| `VInt` | integer of the part's width; signed unless the instruction sets `unsigned = true` |

Anything else names a mapping. **A typo therefore looks like a mapping
reference**, which is why the loader checks that the mapping exists:

```
mycore.toml: part "rd" has type "regsiter", which is neither a builtin type
nor a declared mapping. Declared mappings: reg. Builtin types: boolean, char,
i8, …
```

`radix` accepts `decimal`/`dec`/`d`/`10`, `hexadecimal`/`hex`/`h`/`x`/`0x`/`16`,
`octal`/`oct`/`o`/`0o`/`8`, `binary`/`bin`/`b`/`0b`/`2`, or `""` for decimal
(case-insensitive). An unrecognised spelling is an error, not a fallback — a
silent default to decimal would render every immediate in the wrong base with
nothing to notice.

### `[[types.<name>]]` slices

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | which part this slice feeds |
| `top` | yes | inclusive MSB position **within the part's value** |
| `bot` | yes | inclusive LSB position within the part's value |
| `extend_top` | no | integer, default 0. When the part's sign bit is set, this many bits above it are also set in the *unsigned* reading. Signed types are always fully sign-extended, so it has no effect on them. |

### `[mappings]`

List form — the index is the raw value:

```toml
names = ["reg"]
reg = ["zero", "ra", "sp"]
```

Table form — sparse; keys parse as integers (`0x` accepted):

```toml
names = ["csr"]
[mappings.csr]
"0x300" = "mstatus"
"0x305" = "mtvec"
```

In both forms, a value with no entry renders as a number in the part's radix.

### `[<format>.repr]`

`default` is the fallback rendering; a key matching an instruction name
overrides it. With no `repr` at all, the mnemonic is rendered alone.

| Placeholder | Expands to |
|---|---|
| `$name$` | the instruction's name (its key under `instructions`) |
| `%part%` | the decoded part, through its type, radix, or mapping |

Anything else is copied through literally — including `{part}`, so a template
written in brace syntax loads without error and prints its braces. A `$` or
`%` with no closing partner is an error when that instruction is rendered.

### `[<format>.instructions.<name>]`

| Key | Meaning |
|---|---|
| `mask` | bits that must match (integer) |
| `match` | the value those bits must equal (integer) |
| `unsigned` | optional; `true` makes `VInt` parts unsigned. No effect on other types. |

---

## 5. Checking your work

1. **Settings → Extensions → ISA encoding tables** reports how many of your
   tables loaded and lists any file that failed, with the offending key path.
2. Open a trace with your fetch bus, add the **RISC-V Instruction Trace**
   decoder, and read the stream.
3. Compare against your assembler. If mnemonics look right but operands do not,
   re-read §3 — that is the signature of an inverted `top`/`bot`.

The failure this format is prone to is not a crash. It is a decode that looks
entirely normal and is wrong, which no waveform will tell you about. Check a
handful of instructions whose encoding you know by hand before trusting a table
on a real debug session.

---

## 6. Prior art

The schema is the JKU
[`instruction-decoder`](https://github.com/ics-jku/instruction-decoder) format
(MIT). A table authored for
that project loads in WaveCrux unmodified, provided it passes the stricter
checks above: a known radix, resolvable mapping types, and slices that cover
the word. A WaveCrux table loads there. The `top`/`bot` compatibility is pinned
by a test written in upstream's conventions rather than asserted in a notice
file. See `assets/decoders/isa/riscv/NOTICE.md`.
