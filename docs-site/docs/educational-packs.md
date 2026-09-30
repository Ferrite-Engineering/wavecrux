# Educational packs

A WaveCrux educational pack is a ready-to-teach lab for a digital-design course. Each pack bundles everything an instructor needs to run a session and everything a student needs to follow along — the design, the stimulus, the waveform to read, and the words around it. The packs are licensed `CC-BY-4.0`, and they run on the free Open Core viewer, so no license is required to use them in a classroom.

## What's in a pack { #whats-in-a-pack }

Every pack is self-contained. At minimum it carries:

- **HDL source and a testbench** — the design under study and the stimulus that drives it.
- **Pre-generated `VCD`/`FST` fixtures** — so students can open a waveform on the first day without installing a simulator.
- **A session template** — a starting layout with the right signals already arranged.
- **A student handout** — the lab worksheet that walks through the exercise.
- **Instructor notes** — teaching guidance, expected answers, and discussion prompts.

Depending on the pack, it may also include **decoder bindings**, **translate filters**, and **Stage panel configurations** so the relevant feature is wired up and ready the moment the session opens.

Each pack carries a forward-compatible manifest file, `pack.yaml`, listing its learning objectives, level, duration and contents. The packs are published in the public `edacrux-edu-packs` repository and listed on the [EDACrux education site](https://edacrux.app/edu).

## Using a pack { #using-a-pack }

A pack is just files, so there is no special importer to run. Once you have one, open its **session template** — the `.wavecrux` file in the pack's `fixtures/` folder — in WaveCrux with **File → Open File** (++cmd+o++ / ++ctrl+o++). The waveform loads with the right signals, groups, display formats, decoder bindings, and any Stage layout already arranged, so the lab is ready the moment it opens. To start from a blank slate instead, open the pack's raw `VCD`/`FST` fixture and build the view yourself by following the handout.

## They run on Open Core { #open-core }

!!! note "No license needed"

    Educational packs run entirely on the free Open Core viewer. Every feature a pack uses — signal browsing, cursors, markers, translate filters, FSM visualization, the Stage SDK and board widgets, and the Open Core protocol decoders — is free. The Education *tier* is a separate thing: it unlocks Pro features for coursework (see [Tiers & licensing](licensing.md)). The packs themselves do not require it.

## The catalog { #the-catalog }

Twelve packs ship today, spanning a first-day introduction to advanced verification workflows. Levels are a rough guide to course placement, not a hard prerequisite chain.

| Pack | Level | Focus |
|---|---|---|
| `counter-lab` | Intro | Your first lab — open a VCD, add signals, navigate transitions |
| `mux-and-adder` | Intro | Hierarchical navigation, signal search, multi-lane formats |
| `traffic-light-fsm` | Intro | A three-state FSM with translate filters and the FSM visualizer |
| `shift-register-patterns` | Intro | Transition counting and period measurement |
| `uart-lab` | Intermediate | A UART transmitter with the decoder and transaction table |
| `spi-lab` | Intermediate | SPI mode 0 with the decoder; reasoning about CPOL/CPHA |
| `memory-controller` | Intermediate | A Wishbone B4 master/slave with the decoder |
| `axi4-lite-peripheral` | Advanced | AXI4-Lite five-channel decode with an intentional protocol violation |
| `single-cycle-cpu` | Intermediate | A tiny RV32I CPU trace with the RISC-V decoder |
| `debug-hunt` | Intermediate | Find an intentional bug using waveform diff |
| `stage-showcase-basys3` | Intermediate | Bind a Basys 3 design to the Stage board widget |
| `cocotb-driven-testbench` | Advanced | Cocotb log correlation with waveform events |

!!! tip "For instructors"

    The [Education page](https://wavecrux.app/education) covers the program as a whole, and [Tiers & licensing](licensing.md) explains the Education tier — every Pro feature, free for verified students and faculty — if your course also wants the Pro decoders and the curated Stage pack.
