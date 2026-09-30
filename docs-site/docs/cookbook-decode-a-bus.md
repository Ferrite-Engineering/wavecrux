# Decode a bus from raw signals

You captured a few wires — a clock and a couple of data lines — and you want to read the traffic as bytes and transactions instead of counting edges by hand. This recipe attaches a protocol decoder, points it at the right signals, and turns the trace into a readable transaction table. The example uses SPI; I²C, UART, and the rest follow the same shape.

Goal
:   Decode raw bus wires into structured transactions overlaid on the waveform and listed in a table.

Time
:   About 5 minutes

Tier
:   Open Core for SPI / I²C / UART / AXI4-Lite and the other built-in decoders. Full-spec buses (AXI4 full, USB 2.0, PCIe TLP) are <span class="tier tier-pro">Pro</span>.

You will use
:   The [decoder picker](protocol-decoders.md#how-decoders-work), the decoder configuration dialog, and the transaction table.

## Before you start { #before }

Know where the bus signals live in the hierarchy. For SPI that is a clock (`SCK`), one or both data lines (`MOSI`, `MISO`), and a chip-select (`CS`); for I²C it is `SDA` and `SCL`; for UART it is a single `TX` or `RX` line. You do not have to add the signals to the canvas first — auto-binding searches the whole loaded waveform — but having them on screen makes the bindings easy to eyeball.

## Steps { #steps }

1. **Open the decoder picker.**

    Press ++cmd+shift+d++ / ++ctrl+shift+d++ (**Tools → Add Protocol Decoder**), or add a decoder from the toolbar. The picker lists every available decoder; Pro and Enterprise entries carry a tier badge.

2. **Choose the protocol.**

    Pick the bus you captured — **SPI** here. WaveCrux opens the decoder's configuration dialog and **auto-binds** it to your signals, from the strongest evidence to the weakest: a family of signals sharing a scope and name prefix, then a matching leaf name, then a well-known alias, then a close fuzzy match.

3. **Check and fix the bindings.**

    Review the proposed bindings in **Signal Bindings** — clock, data, select. Auto-binding is usually right, so check the ones that look doubtful. A fuzzy name match is the single most common reason a decode looks wrong: point the role at the correct signal from its drop-down.

    !!! tip "Naming off the beaten path?"

        Decoders work even when your signal names don't follow convention — every proposed binding can be overridden by hand, so a `spi_clk_int` maps to the clock role just fine.

4. **Set the protocol options.**

    The **Parameters** section holds the settings that define the bus. For SPI, set CPOL, CPHA, bit order and word size; for UART, the bit timing, data bits, parity, and stop bits; for AXI4-Lite or APB, the address and data widths. Match these to how the hardware was actually configured, then choose **Add Decoder**.

5. **Read the decode.**

    Decoded fields render as a **transaction lane** on the waveform, aligned to the signals they came from. Open the sortable **transaction table** with ++cmd+shift+t++ / ++ctrl+shift+t++ and click any row to jump the cursor to that transaction's time.

6. **Spot the violations.**

    Protocol errors are flagged where they happen — a UART framing error, an I²C NACK, a CRC failure, a USB `NAK`, an AXI `SLVERR`. A bad transaction stands out in the lane and the table instead of hiding inside the decode, so scan for the flags first.

!!! note "Going further"

    Need the full-spec buses — AXI4 full bursts, USB 2.0 packets, PCIe TLPs, CAN-FD, JTAG, MDIO, or the Ethernet front-ends? Those are <span class="tier tier-pro">Pro</span> decoders in the desktop and mobile apps and attach exactly the same way. You can also bind the same UART line to the <span class="tier tier-pro">Pro</span> [Stage UART Terminal](stage.md#protocol-communication) to watch the text scroll as you scrub.

## Where to go next { #next }

[Protocol decoders](protocol-decoders.md) has the full catalog and the details of auto-binding. Need a protocol WaveCrux does not ship? [Write your own decoder plugin](authoring-custom-decoders.md), or see the [Sigrok bridge](sigrok-bridge.md) for the libsigrokdecode protocols.
