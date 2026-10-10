# Protocol decoders

A protocol decoder turns raw signal transitions into structured transactions — bytes, frames, packets, and bus cycles — overlaid on the waveform and listed in a sortable table. WaveCrux ships decoders for the buses you actually trace, binds them to your signals automatically, and flags protocol violations where they happen. This page covers how decoders work and the full catalog across Open Core, Pro, and Enterprise.

!!! info "What the tier badges cover"

    The Pro and Enterprise decoders need a matching license key; the decoder picker shows a tier badge on each one. The unbadged Open Core decoders are free. See [Tiers & licensing](licensing.md) for details.

## How decoders work { #how-decoders-work }

Add a decoder from the toolbar or **Tools → Add Protocol Decoder**, or press ++cmd+shift+d++ / ++ctrl+shift+d++, to open the **Add Protocol Decoder** picker. The picker lists every available decoder with the signals it requires and accepts, and shows a tier badge on the Pro and Enterprise entries.

When you choose a decoder, WaveCrux **auto-binds** it to your waveform, working from the strongest evidence to the weakest: a group of signals that share a scope and a name prefix and cover the decoder's roles (`m_axi_awvalid`, `m_axi_awready`, …); then any signal whose leaf name matches a role; then well-known aliases (`aclk` for `clk`, `sdo` for `mosi`); then a close fuzzy match on the name. Any binding it proposes can be overridden, so a decoder still works when your signal names don't follow a common convention.

Each decoder exposes its own configurable parameters — for example baud rate, clock polarity and phase, address width, or word size — so you can match the decoder to the exact configuration of the bus you captured.

Decoded transactions render two ways. A **transaction lane** draws the decoded fields directly on the waveform, aligned to the signals they came from. A sortable **transaction table** docks at the bottom of the window — toggle it with ++cmd+shift+t++ / ++ctrl+shift+t++ — with a decoder filter, a search box, and **Export CSV**. Click any transaction in the table to jump the cursor to its time, or move to it with the arrow keys and press ++enter++ — the full key set is in [Keyboard & mouse reference → In the transaction table](keyboard-mouse.md#transaction-table-keys).

Protocol violations and errors are flagged visually where they occur — for example a CRC error, a UART framing error, a USB `NAK`, or an AXI `SLVERR` response — so a bad transaction stands out instead of hiding in the decode.

1. **Open the decoder picker.**

    Press ++cmd+shift+d++ / ++ctrl+shift+d++ and choose the protocol you captured.

2. **Check the auto-bindings.**

    Choosing a decoder opens its configuration dialog. Review the proposed signals in the **Signal Bindings** section and override anything it got wrong; **Auto-bind signals** runs the guess again.

    From 1.1, a signal the waveform declares under several names (an alias, such as the copies Verilator traces for `assign TxData = src_data;`) is listed under every one of those names, and auto-bind can match any of them. They are one signal, so whichever name you pick decodes the same data.

3. **Set the parameters.**

    In the same dialog, the **Parameters** section matches the decoder to the hardware — set baud rate, clock polarity and phase, address width, or word size — then choose **Add Decoder**. To change the bindings or parameters later, right-click the decoder's lane (long-press on touch) and choose **Configure…**; **Remove Decoder** takes it off.

4. **Read the transactions.**

    Open the transaction table with ++cmd+shift+t++ / ++ctrl+shift+t++ and click a row to jump the cursor there. Protocol violations are flagged inline.

For a worked example from raw wires to a readable table, follow the cookbook recipe [Decode a bus from raw signals](cookbook-decode-a-bus.md).

!!! tip

    Let auto-binding run first, then check the bindings it was unsure about. A fuzzy name match is the most common reason a decode looks wrong — point the decoder at the right signal in **Signal Bindings**.

## Open Core decoders { #open-core-decoders }

These decoders are part of the free Open Core viewer — no badge, no license — on every platform, including the browser. They cover the embedded serial buses and the common SoC interconnect fabrics.

| Decoder | What it decodes |
|---|---|
| <span id="spi"></span>SPI | Serial Peripheral Interface with configurable clock polarity (CPOL) and phase (CPHA), bit order, word size and chip-select polarity. |
| <span id="spi_flash"></span>SPI Flash | JEDEC SPI NOR flash commands, stacked on an SPI decoder, with vendor presets. |
| <span id="i2c"></span>I²C | 7-bit or 10-bit addressing, ACK/NACK, and repeated start. |
| <span id="uart"></span>UART | Configurable bit timing (baud rate, clocks per bit, or auto-detect), data bits (5–9), parity, stop bits and bit order; TX, RX or both. See [UART bit timing](#uart-timing). |
| <span id="axi4_lite"></span>AXI4-Lite | Single-beat reads and writes across the five channels. From 1.1, several writes and reads can be outstanding at once and each response completes the oldest one, as the protocol allows; a write or read still waiting for its response at the end of the trace is listed with the response `no response`. |
| <span id="apb"></span>APB | AMBA APB3 / APB4 read and write cycles. |
| <span id="ahb_lite"></span>AHB-Lite | Two-phase pipelined transfers with every HBURST variant (single, incrementing and wrapping bursts). |
| <span id="wishbone"></span>Wishbone | Wishbone B3 (classic, with registered-feedback bursts) and B4 (pipelined) reads and writes. |
| <span id="riscv"></span>RISC-V Instruction Trace | Disassembles an instruction-fetch trace — RV32I / RV64I, with the M, A, F, D and C extensions selectable in its configuration — into mnemonics and operands, read as text with the cursor synchronized. Its tables are TOML files in the `instruction-decoder` format that Surfer also reads, and you can add your own — see [ISA encoding tables](authoring-custom-decoders.md#isa-tables). |

## Pseudo-instructions <span class="tier tier-pro">Pro</span> { #pseudo-instructions }

An encoding table can tell you that `0x00b50513` is `addi a0, a1, 0`. It cannot tell you that every assembler, every debugger and every engineer calls that `mv a0, a1` — because that is not a property of the encoding. It is a convention layered on top of it, and there is no field in a decoder table that could hold it.

WaveCrux Pro ships a curated pseudo-instruction set for RISC-V, transcribed from Table 25 of the Unprivileged ISA manual. The same fetch trace reads differently:

| Open Core renders | Pro renders |
|---|---|
| `addi a0, a1, 0` | `mv a0, a1` |
| `addi x0, x0, 0` | `nop` |
| `jalr x0, ra, 0` | `ret` |
| `addi a0, x0, 42` | `li a0, 42` |
| `bne a5, x0, -12` | `bnez a5, -12` |
| `sub a0, x0, a1` | `neg a0, a1` |
| `xori a0, a1, -1` | `not a0, a1` |

Nothing about the decode changes and Open Core's rendering is not wrong — it is exactly what the encoding says. What changes is that a scrolling instruction trace reads the way the source was written instead of the way it was assembled.

!!! note "Why this is curated rather than configurable"

    Because precedence is the hard part, not the list. `addi rd, x0, 0` is simultaneously a valid `li`, a valid `mv` and a valid `nop`, and only the specification says which one an assembler prints. Getting that ordering right across a whole instruction set is judgement work, and it is checked here against spec-derived test vectors — instruction words built from the field layouts in the manual rather than from our own decoder's output, so a rule cannot be self-consistently wrong.

**RISC-V's encoding tables themselves stay in Open Core**, and so does the ability to point WaveCrux at your own TOML table for any instruction set you like. Only the curated convention layer is Pro.

## Beyond RISC-V: the ISA pack <span class="tier tier-pro">Pro</span> { #isa-pack }

An FPGA engineer debugging a MicroBlaze fetch bus today reads hex. Vendor tooling shows you a waveform; it does not show you the instruction stream as instructions.

WaveCrux Pro ships curated encoding tables for soft cores that actually get simulated:

| ISA | Instructions | Why it is in the pack |
|---|---|---|
| <span id="microblaze"></span>MicroBlaze | 137 | Xilinx's soft core, in an enormous number of FPGA designs and simulated constantly. |
| <span id="lm32"></span>LatticeMico32 | 57 | Open ISA, still deployed, and the open-source ecosystem around it has no waveform disassembler at all. |

!!! note "What you are actually buying"

    Not "it parses" — **"it is verified, and someone is accountable for it."** These tables are not transcribed from a manual by hand. They are *derived from and checked against GNU binutils*, the reference toolchain these architectures already use, then verified across tens of thousands of instruction words — comparing not just the mnemonic but every operand, register for register.

    That distinction is not academic. A table that names each instruction correctly but reads the wrong register field produces disassembly that looks entirely normal and is wrong, and nothing in a waveform will tell you. It is the specific failure this method exists to make impossible.

A handful of instructions in each ISA are **deliberately absent rather than approximated** — the control-register accesses (MicroBlaze `mfs` / `mts`, LatticeMico32 `rcsr` / `wcsr`), where an approximate decode would name the *wrong* register, and MicroBlaze's FSL stream family. Leaving an instruction undecoded is honest; decoding it wrongly is not.

Each pack is a **decoder you pick like any other** — *MicroBlaze Instruction Trace* and *LatticeMico32 Instruction Trace* appear in the decoder list alongside RISC-V, SPI and the rest. The signal bindings are deliberately identical to the RISC-V decoder's: a fetch clock, a 32-bit instruction word, and optionally a valid strobe and a PC. An instruction fetch has the same shape whatever the core is, and having learned to bind one instruction trace you should not have to learn a second vocabulary for the next.

!!! note "The free half is not a teaser"

    Bring-your-own-ISA stays in Open Core. Point WaveCrux at a TOML encoding table and the RISC-V Instruction Trace decoder picks it up — custom instructions for your own core, or a replacement for a bundled set — with the loader, the schema and the diagnostics all free. RISC-V's tables stay free too. What is Pro is the curated content inside that ecosystem: tables we have verified, keep current, and are accountable for.

## UART bit timing { #uart-timing }

UART is asynchronous — there is no clock on the wire, so the decoder has to be told how long a bit lasts. Which unit is natural depends on where the trace came from, so WaveCrux offers three under **Bit Timing**.

| Mode | Use it when |
|---|---|
| Baud rate | The default. Right for a captured trace with a real time base — a logic-analyzer capture at 9600 or 115200. |
| Clocks per bit | Right for an HDL simulation. Bind your design's clock to the optional `clk` signal and enter **Clocks per Bit** — the same `CLKS_PER_BIT` constant the RTL uses. WaveCrux measures the clock period from the trace itself. |
| Auto-detect from the line | When you do not know either. WaveCrux infers the bit period from the gaps between edges on the data line. A heuristic — accurate on simulation output, less reliable on a captured trace with real jitter. |

!!! note

    **Why this matters more than it looks.** A testbench written as `always #5 clk` with `CLKS_PER_BIT = 8` is running at 12.5 Mbaud. Left at the 9600 default, the decoder finds nothing at all — and a bit period that is wrong by a smaller margin is worse, because it decodes confident, plausible-looking wrong bytes rather than staying silent. If a UART decode looks subtly wrong, check the bit timing first.

## Pro decoders <span class="tier tier-pro">Pro</span> { #pro-decoders }

The Pro catalog adds the full-spec bus protocols and the high-speed and networking decoders used in verification and protocol bring-up. Pro and Enterprise decoders are available in the desktop and mobile apps; the browser build does not include them.

| Decoder | What it decodes |
|---|---|
| <span id="axi4_full"></span>AXI4 Full | The full AXI4 spec — bursts, exclusive access, and ID-tagged transactions. |
| <span id="can"></span>CAN / CAN-FD | CAN 2.0A/B and ISO or non-ISO CAN-FD — data, remote, error and overload frames, payloads up to 64 bytes with CRC-17 / CRC-21, and all five ISO 11898-1 error classes. |
| <span id="usb2"></span>USB 2.0 | Low-Speed (1.5 Mb/s) and Full-Speed (12 Mb/s) tokens, data and handshakes, with CRC validation. |
| <span id="pcie_tlp"></span>PCIe TLP | Transaction Layer Packets on a 32-bit AXI-Stream-style interface — memory, I/O, configuration, completion and message TLPs. |
| <span id="jtag"></span>JTAG | IEEE 1149.1 TAP state machine over TCK/TMS/TDI/TDO, one transaction per IR or DR scan, with the standard opcodes and IDCODE fields. |
| <span id="mdio"></span>MDIO | Clause 22 and Clause 45 Ethernet PHY register access. |
| <span id="axi_stream"></span>AXI-Stream | Standalone TVALID/TREADY/TLAST packets with TKEEP, TSTRB, TUSER, TDEST and TID, without an upper framing protocol. |
| <span id="avalon_mm"></span>Avalon-MM | Intel/Altera memory-mapped — bursts, wait states, pipelined read responses, and byte enables. |
| <span id="avalon_st"></span>Avalon-ST | Intel/Altera streaming — SOP/EOP framing, `empty`, channel multiplexing, and error signaling. |
| <span id="ethernet_axis"></span><span id="ethernet_mii"></span><span id="ethernet_rmii"></span><span id="ethernet_gmii"></span>Ethernet front-ends (AXIS, MII, RMII, GMII) | Frame-layer decode at each physical-layer encoding. |

## Enterprise decoders <span class="tier tier-enterprise">Enterprise</span> { #enterprise-decoders }

Enterprise extends the Ethernet front-ends to gigabit DDR signaling and adds offline frame synthesis from packet captures.

| Decoder or tool | What it does |
|---|---|
| <span id="ethernet_rgmii"></span>Ethernet (RGMII) | Reduced GMII at 10/100/1000 Mbit with DDR sampling and a configurable clock-to-data phase delay (TX delay, RX delay, none, or auto-detect). Bind one instance per direction. |
| **Tools → Convert PCAP to VCD…** | Reads a libpcap `.pcap` file and synthesizes a VCD of its Ethernet frames at a chosen physical-layer encoding (MII, RMII, GMII, RGMII or AXIS). |

## Export and extensibility { #export-and-extensibility }

Decoders are not a closed set. You can take a decode back out to other tools, drop in your own decoders, and pull in the wider open-source decoder ecosystem.

- **Ethernet PCAP export <span class="tier tier-pro">Pro</span>** — from the transaction table's export menu, write an active Ethernet decoder's transactions as a libpcap `.pcap` file to open in Wireshark or `tcpdump`.
- <span id="plugins"></span>**User-contributed decoders** — the decoder plugin interface is open and stable. Drop a native decoder plugin into a plugin directory (**Settings → Extensions → Decoder Plugins**) and it appears in the picker alongside the built-in decoders. This is free, on every tier, in the desktop apps. See [Authoring custom decoders](authoring-custom-decoders.md) for the full C ABI, the build-and-install walkthrough, and the C and Rust reference implementations. Ready-made open-source plugins, starting with PCIe PIPE and Data Link Layer decoders, are published in [wavecrux-decoders](https://github.com/Ferrite-Engineering/wavecrux-decoders).
- **Sigrok bridge** — the optional bridge adds 130+ libsigrokdecode community decoders. See [Sigrok bridge](sigrok-bridge.md) for installation and use.

!!! note "Related"

    For deeper analysis built on decoded data, see [Analysis & debug](analysis.md). To reach far beyond the built-in catalog, see the [Sigrok bridge](sigrok-bridge.md).
