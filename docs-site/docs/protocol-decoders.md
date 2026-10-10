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
| <span id="pcie_tlp"></span>PCIe TLP | Transaction Layer Packets (memory, I/O, configuration, completion and message TLPs) on a streaming interface, 32 bits per beat. From 1.1, 64, 128 and 256-bit beats, request and completion pairing, PCIe Base Spec rule checks, bus statistics, and presets for Xilinx and Intel PCIe cores. See [PCIe TLP analysis](#pcie-tlp-analysis). |
| <span id="jtag"></span>JTAG | IEEE 1149.1 TAP state machine over TCK/TMS/TDI/TDO, one transaction per IR or DR scan, with the standard opcodes and IDCODE fields. |
| <span id="mdio"></span>MDIO | Clause 22 and Clause 45 Ethernet PHY register access. |
| <span id="axi_stream"></span>AXI-Stream | Standalone TVALID/TREADY/TLAST packets with TKEEP, TSTRB, TUSER, TDEST and TID, without an upper framing protocol. |
| <span id="avalon_mm"></span>Avalon-MM | Intel/Altera memory-mapped — bursts, wait states, pipelined read responses, and byte enables. |
| <span id="avalon_st"></span>Avalon-ST | Intel/Altera streaming — SOP/EOP framing, `empty`, channel multiplexing, and error signaling. |
| <span id="ethernet_axis"></span><span id="ethernet_mii"></span><span id="ethernet_rmii"></span><span id="ethernet_gmii"></span>Ethernet front-ends (AXIS, MII, RMII, GMII) | Frame-layer decode at each physical-layer encoding. |

## PCIe TLP analysis <span class="tier tier-pro">Pro</span> { #pcie-tlp-analysis }

From 1.1, the PCIe TLP decoder does more than name each packet. Bind both directions of the link and it pairs every completion with the request it answers, measures the latency between them, and checks the traffic against the PCI Express Base Specification. Three presets read the user interface of a Xilinx or Intel PCIe core directly, and a **Bus Statistics** tab sums the decode up. Everything in this section applies to the generic decoder and to its presets alike.

### The generic interface { #pcie-tlp-generic }

The **PCIe TLP** decoder reads a stream of 32-bit DWs: `tlp_valid`, `tlp_sop`, `tlp_eop` and `tlp_data`, sampled on the rising edge of `clk`, with optional `tlp_ready` and `rst_n` (active low). DW 0 of a beat sits in `tlp_data[31:0]`, each DW carries TLP byte 0 in its bits [31:24], and a TLP starts in DW 0 of the beat where `tlp_sop` is high.

From 1.1, **Data Width (bits)** takes 32, 64, 128 or 256 (1, 2, 4 or 8 DWs per beat). On a wide bus, bind `tlp_keep` (the byte enables of the last beat, bit 0 = byte 0) to mark which DWs of that beat are valid; left unbound, the last beat is trimmed to the length the TLP header announces.

To decode the opposite direction as well, bind `peer_valid`, `peer_sop`, `peer_eop` and `peer_data`, with optional `peer_ready` and `peer_keep`. Every TLP then carries a `direction` field, `tlp` or `peer`, and completions are paired with requests as described in [Requests and completions](#pcie-tlp-pairing).

### Vendor presets { #pcie-tlp-presets }

From 1.1, three presets read a vendor PCIe core's own user interface, with no adapter to a one-DW-per-beat stream. Each one binds by the core's own port names, so auto-bind finds them in a design that instantiates the core. Choose them in the **Add Protocol Decoder** picker like any other decoder.

| Preset | What it reads |
|---|---|
| <span id="pcie_tlp_xilinx_7series"></span>PCIe TLP (Xilinx 7 Series AXIS) | The AXI4-Stream interface of the AMD/Xilinx 7 Series Integrated Block for PCI Express (PG054): receive on `m_axis_rx_*`, transmit on `s_axis_tx_*`, 64 or 128 bits, on `user_clk_out` with the active-high `user_reset_out`. The 128-bit receive interface is framed by `rx_is_sof` and `rx_is_eof` in `m_axis_rx_tuser`, including a TLP that starts in the same beat the previous one ends in. The BAR hit is read from `m_axis_rx_tuser` and reported in a `bar_hit` field. Bind the transmit side to pair completions with requests. |
| <span id="pcie_tlp_xilinx_ultrascale"></span>PCIe TLP (Xilinx UltraScale CQ/CC/RQ/RC) | The four descriptor interfaces of the AMD/Xilinx UltraScale (PG156) and UltraScale+ (PG213) PCI Express cores: completer request `m_axis_cq_*`, completer completion `s_axis_cc_*`, requester request `s_axis_rq_*` and requester completion `m_axis_rc_*`, 64, 128 or 256 bits, on `user_clk` with the active-high `user_reset`. Bind any of the four. Each descriptor is rebuilt into its TLP header, so the packet is named, paired and checked like any other, and the `direction` field names its interface (`CQ`, `CC`, `RQ` or `RC`). CC completions pair with CQ requests, and RC completions with RQ requests, when both interfaces of a pair are bound. The CQ BAR and target function, RC descriptor error codes, and packets the source discontinued through `tuser` are reported too. |
| <span id="pcie_tlp_intel_avalon_st"></span>PCIe TLP (Intel Avalon-ST) | The Avalon-ST interface for PCI Express of the Intel Arria 10 and Cyclone 10 GX Hard IP (683647): receive on `rx_st_*`, transmit on `tx_st_*`, 64, 128 or 256 bits, on `pld_clk` with the active-high `reset_status`. The qword-alignment pad is removed, payload bytes are put back in TLP order, `rx_st_empty` and `tx_st_empty` trim the last beat, and the BAR hit is read from `rx_st_bar` into a `bar_hit` field. Bind the transmit side to pair completions with requests. |

Each preset's **Data Width (bits)** parameter defaults to **Auto (from the data bus)**, which reads the width from the bound data signal; choose a width to set it yourself. The UltraScale preset also has **Payload Alignment**, **Dword-aligned** (the default) or **Address-aligned**. It is a core setting the waveform does not show, so set it to match how the core was generated.

!!! note "Not decoded yet"

    Two packing modes are not decoded: UltraScale 256-bit requester completion straddle (two completions in one beat, with `m_axis_rc_tlast` tied low), and Avalon-ST with two TLPs in one beat (`rx_st_sop[1]` / `rx_st_eop[1]`). The Avalon-ST preset flags the second case once rather than decoding it.

### Requests and completions { #pcie-tlp-pairing }

With both directions bound, every completion is paired with the non-posted request it answers, by Requester ID and tag:

- The completion carries an `answers` field naming the request, and its label shows the address or register it answers, plus the value for a single-DW read.
- Request and completion both carry a `latency` field, from the start of the request to the start of its first completion.
- The request carries a `completion` field with its outcome: `SC`, the unsuccessful status (`UR`, `CA` or `CRS`), `timeout`, `tag reused`, or `pending` when the capture ends before the completion arrives.

These are flagged as errors on the packet concerned:

- A completion timeout (PCIe Base Spec §2.8). **Completion Timeout (ns)** sets the limit; the default, 50,000 ns, is the low end of the range the specification allows, so a short simulation still reports a stuck request.
- An unexpected completion, with no outstanding request to answer (§2.3.2).
- A tag reused while a request with that tag is still outstanding (§2.2.6.2).
- A byte count or lower address that does not match the request, including across split completions (§2.2.9, §2.3.1.1).
- A successful completion to a read that carries no data, and a completion to a write that carries data (§2.2.9).

Configuration requests name the register they address, such as `Device ID` or `BAR0`, in a `register_name` field and in the label, and report the value in register order in a `value` field. The decoder learns each function's header layout from Header Type reads and its capability list from Capabilities Pointer reads, so registers inside the PCI Express Capability read as `Device Control` or `Link Status`. **Configuration Header** overrides the learned layout: **Learn from Header Type reads** (the default), **Type 0 (endpoint)**, or **Type 1 (bridge, switch, root port)**.

**Labels** sets how much each transaction label says. **Full (Requester ID, tag, status)**, the default, appends the Requester ID and tag and shows a successful completion's status; **Compact (one-endpoint link)** drops them, which reads better on a link with a single endpoint. An unsuccessful completion status is always shown.

Every TLP also carries its name (`MRd32`, `CplD` and so on) in a `tlp` field, so the transaction table has a column to sort and filter by packet type.

### Base Spec rule checks { #pcie-tlp-rules }

From 1.1, each TLP is checked against the transaction rules of the PCI Express Base Specification, and a violation is flagged with the section it breaks:

- A memory request that crosses a 4 KB boundary (§2.2.7).
- A payload larger than Max_Payload_Size (§2.2.2).
- A memory read that asks for more than Max_Read_Request_Size (§7.5.3.4).
- First and Last DW Byte Enables that break the byte enable rules (§2.2.5).
- A 64-bit address header used for an address below 4 GB (§2.2.4.1).

**Max_Payload_Size** and **Max_Read_Request_Size** default to **Auto (from the trace)**: the values the trace writes to Device Control. Finding Device Control needs the PCI Express Capability, which the decoder learns from configuration reads and their completions, so Auto needs both directions bound; until it has learned a value, Auto skips the check. Choose a size from 128 to 4096 bytes to set the limit yourself.

**Check Read-After-Write Ordering** flags a memory read whose completion data differs from an earlier posted write to the same address on the same link direction: the read passed the write (§2.4.1). It is off by default, because registers with side effects, such as write-1-to-clear or read-only bits, read back differently by design. It is a best-effort check from one link.

### Bus statistics and JSON export { #pcie-tlp-statistics }

From 1.1, the transaction table's **More export options** menu has **Show statistics for** *decoder* for each PCIe TLP decoder. It opens the **Bus Statistics** tab in the bottom dock on that decoder. Choose the **Decoder** at the top of the tab, and the range to measure: **Whole trace**, **Visible range**, or **Between cursors** (place the primary and secondary cursors first). The tab shows:

- **Transactions by type**: a count per TLP type, with the total and how many are flagged.
- **Payload throughput**: payload bytes and the rate over the range, for each link direction.
- **Latency**: the number of answered requests, the minimum, mean and maximum latency, and a histogram. Latency needs requests paired with their completions, so bind both directions.
- **Outstanding requests**: how many requests were waiting for a completion at once, with the peak.

The same menu has **Export** *decoder* **as JSON…** for every decoder, not only PCIe TLP. It writes the decoder's rows as the table currently shows them, with the same filter and order as **Export CSV**: each row's times, label and error, with its decoded fields as a nested object, so a script can read a field without knowing the decoder's column set. Times are in ticks, and the file states the timescale.

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
