# Translators

A translator reinterprets a signal's value into something you can read — a radix, a symbolic name, a disassembled instruction, or a packed bus broken out into named, individually-formatted child rows. Translators are bound per signal, persist with the session, and run identically on desktop, mobile, and the web build. This page covers the built-in formats, structured decomposition, authoring your own, and the curated Pro translator pack.

!!! note "Translator vs. decoder"

    A **translator** answers "what does this value mean, right here" — it works on one signal's value and re-renders it. A [protocol decoder](protocol-decoders.md) answers "what protocol event happened over this time window" — it correlates several signals and walks a state machine across the sample stream to produce transactions. Reach for a translator to read a bus field or an instruction word; reach for a decoder to follow SPI, AXI, or USB traffic.

!!! info "Unlocked in the beta, licensed from 1.0"

    The Pro translator pack is unlocked for everyone through the 0.8.x public beta; from 1.0 it needs a Pro license key. Everything without a badge — the built-in display formats, struct/bitfield decomposition, RISC-V disassembly, and the translators you author yourself — is Open Core and stays free in both. See [Tiers & licensing](licensing.md) for details.

## How translators work { #how-translators-work }

Every signal has a translator bound to it. By default that is the built-in translator, which provides the display formats; you bind a different one from the signal's context menu in the value column, and the choice persists with the session.

A translator can return more than a flat string. When it decomposes a value into named parts, each part renders as an **expandable child row** beneath the parent signal, aligned to the same timeline so every field shares the wave's transitions. A translator can also report per-value validity and a color hint — for example a pixel translator that paints a swatch of the decoded color.

### How to apply a translator { #apply }

1. **Open the value's context menu.**

    Right-click the signal's value in the value column (long-press on touch). The top of the menu lists the built-in **Display Format** choices, with **Configure…** for fixed-point and **Edit enum labels…** for named enums.

2. **Pick a translator.**

    Choose **Custom translator…** to open the list of translators you can bind: the Pro pack presets, the RISC-V instruction translator, and the custom translators you have authored. The value column re-renders immediately and the choice persists with the session. **Clear custom translator** returns the signal to its display format.

3. **Expand the child rows.**

    If the translator decomposes the value into named fields, the value row shows an expand chevron at its right edge. Click it to reveal each field as its own timeline-aligned child row, and click it again to collapse them.

## Open Core translators { #open-core-translators }

These translators are part of the free Open Core viewer — no badge, no license. The built-in display formats are the default on every signal; the struct/bitfield translators you author cover structured decomposition; and the RISC-V instruction format reads an instruction word as its disassembly. Each is detailed in its own section below.

| Translator | What it renders |
|---|---|
| [Built-in display formats](#formats) | Hexadecimal, unsigned and signed decimal, binary, octal, ASCII, IEEE 754 single and double, Gray code, fixed-point (Q), signed-magnitude, and named enumerations — the default translator bound to every signal. |
| [Struct & bitfield decomposition](#structured) | Slice a packed bus into named fields, each rendered as its own formatted child row. |
| [Custom translators](#custom) | Author your own bit-field translators in **Settings → Extensions → Custom Translators** and bind them per signal — no code, runs on every platform. |
| [RISC-V instruction format](#riscv) | Render an instruction-word signal as its disassembly inline, with mnemonic and operand subfields. |

## Built-in display formats { #formats }

The built-in translator covers the radixes and symbolic forms you reach for most. They are documented in full, with the complete table, under [Working with signals → Display formats](working-with-signals.md#formats).

## Struct & bitfield decomposition { #structured }

Wide control and status words rarely mean anything as a single hex blob. A struct/bitfield translator slices a bus into named fields and renders each as its own child row under the parent signal — individually formatted, and aligned to the same timeline so you can read a field's value at any cursor position. The parent row shows a compact summary such as `{valid=1, len=8}`.

- Each field is a name and an inclusive bit range (high bit to low bit), with its own display format.
- A field whose range does not fit the signal shows `X`; if no field fits at all, the signal simply falls back to its plain display format.
- Expand or collapse the parent to show or hide the field rows without removing the signal from the trace.
- The translator format also allows a field to be a struct of its own, expanding as a tree — the Pro AMBA presets use this; the Settings editor authors one level of fields.

## Custom translators { #custom }

You are not limited to the built-in set. Open **Settings → Extensions → Custom Translators** and choose **Add Translator**: give it a **Name**, then **Add Field** for each subfield with its **Field name**, **High bit**, **Low bit** and format — **Hexadecimal**, **Unsigned Decimal**, **Signed Decimal**, **Binary**, or **Named enum** with its own label table. Save it, then bind it to any signal through **Custom translator…** in the value column. There is no code to write and nothing to rebuild, and a translator you author works the same on the web build as it does on desktop and mobile.

!!! tip

    A custom translator is the fastest way to make a project-specific encoding readable — a status register, a descriptor layout, or a packed command word that no decoder covers. Define it once and it travels with the signal binding in your session.

## RISC-V instruction format { #riscv }

The RISC-V instruction translator renders any instruction-word signal as its disassembly — `addi x1, x0, 5` — inline at every value, with the mnemonic and operands as subfields. It covers RV32I and RV64I with the M, A, F, D and C extensions from the bundled instruction tables, plus any tables you add (see [Authoring custom decoders → ISA encoding tables](authoring-custom-decoders.md#isa-tables)). Values containing `x` or `z`, or that match no instruction, fall back to hex.

It is distinct from the [RISC-V instruction-stream decoder](protocol-decoders.md), which decodes a fetch port over time and lists the program as transactions: the translator formats *any* signal carrying an instruction word, wherever it appears in your design. Both are free in Open Core and share the same disassembler and tables.

## Pro translator pack <span class="tier tier-pro">Pro</span> { #pro-pack }

The Pro pack adds curated translators for common hardware encodings, offered as presets in the **Custom translator…** dialog. All are declarative — each renders as named child rows (and, for pixels, a color swatch).

| Translator | What it renders |
|---|---|
| AMBA control-word expanders | AXI4 `AxBURST` / `AxSIZE` / `AxCACHE` / `AxPROT` / `AxLOCK` and AHB `HTRANS` / `HBURST` / `HSIZE` broken out into named, individually-decoded fields. Pairs with the AXI4 (Pro) and AHB-Lite decoders. |
| Extended & ML floats | bfloat16, IEEE half (FP16), and FP8 (E4M3 / E5M2) decoded to readable values — the formats accelerator datapaths carry, distinct from the built-in IEEE 754 single and double. |
| Pixel & framebuffer formats | RGB565, RGB888, and ARGB8888 split into per-channel subfields plus a live color swatch. Pairs with the Stage framebuffer and OLED widgets. |

The Pro translator pack is included in the Education tier as well as Pro and Enterprise. See [Tiers & licensing](licensing.md) for the full breakdown.

## GTKWave translate filters { #gtkwave }

For compatibility with existing GTKWave libraries, WaveCrux reads GTKWave `.txt` translate filter files directly, and supports filter processes that pipe values through an external program. These import unchanged and are the legacy on-ramp into the translator system; see [Working with signals → GTKWave translate filters and filter processes](working-with-signals.md#filters) for details.

!!! note "Related"

    For the full display-format reference, see [Working with signals](working-with-signals.md). For decoding protocols across several signals into transactions, see [Protocol decoders](protocol-decoders.md).
