# WaveCrux for coding agents

WaveCrux reads simulation waveforms (VCD, FST, GHW and the other formats the
app opens) and answers questions about them from the command line or over the
Model Context Protocol. This file is for an agent, and for the person who
configures one: when to call WaveCrux, how to read what it returns, and how to
cite it so a person can check the answer.

## Starting the server

```
wavecrux mcp --root <project directory>
```

The server speaks MCP over stdin and stdout. Every path a tool receives must be
inside `--root` (the working directory when omitted); a path outside it, a
symbolic link that leads outside it, or a network path is refused and never
opened. The server writes nothing and makes no network call of its own.

Each tool is also a command, with the same inputs as flags and the same output
with `--json`:

```
wavecrux info dump.vcd --json
wavecrux search dump.vcd fifo --json
wavecrux values dump.vcd --signal top.u_fifo.count --at 1500ns --json
wavecrux transitions dump.vcd --signal top.u_fifo.full --from 0 --to 20us --json
```

A tool's text is byte for byte what the command writes, so a script and an
agent read the same document.

## When to call it

- **A waveform exists and re-running the simulation is slow or impossible.**
  Read the dump instead of adding prints and simulating again.
- **The question is about what a signal did in time:** when it changed, what
  it held at an instant, what it held at each clock edge, whether it was ever
  `x` or `z`.
- **The source cannot answer it,** because the behaviour depends on
  stimulus, timing or a model you cannot read.

Start with `info` (the timescale, the time range and the top of the
hierarchy), then `search` to find the full path of each signal you need.
Signal names in the other tools are full hierarchical paths, as `search`
returns them.

## The four tools

| Tool | Returns | Limits |
|---|---|---|
| `info` | Format, timescale, first and last tick, signal and scope counts, the top two levels of scopes | 50 scopes |
| `search` | Signals whose name matches a substring, or a glob with `glob: true`: full path, width, type, direction | `limit`: default 50, at most 500 |
| `values` | The value of each signal at one time (`at`), or at each rising edge of `clock` in `[from, to)` | 32 signals; `limit` clock edges: default 200, at most 5000 |
| `transitions` | Every recorded change of each signal in `[from, to)`, and its value at `from` | 32 signals; `limit` changes per signal: default 200, at most 10000 |

Use `transitions` rather than sampling with `values` when you need to know
what happened between two times: it returns every change, including a pulse
shorter than any sampling step.

## Times

Every time in a document is a whole number of **ticks** of the file's
timescale (`info` gives it, for example `1ns` with `seconds_per_tick`
`1e-9`). An input time is either a tick count (`1500`) or a time with a unit
(`1500ns`, `1.5us`, `2ms`), converted with the file's timescale. A time that
falls between two ticks, or a unit on a file with no timescale, is refused
rather than rounded.

Windows are half-open: `from` is included, `to` is not, so a change at
exactly `to` is not in the answer.

A value at a tick is the value recorded at that tick, after every change at
it. At a clock edge, a register clocked by that edge already shows its new
value; for the value it sampled, ask for the tick before.

## Reading a document

Every answer is one JSON object with eight members, always present, in this
order:

| Member | Meaning |
|---|---|
| `schema_version` | `1` |
| `tool` | `{"name": "wavecrux", "version": ...}` |
| `command` | The command or tool that ran |
| `outcome` | `completed` when there is an answer; otherwise `usage_error`, `input_error` or `engine_error` |
| `engines` | `[{"name": "wellen", ...}]` once the file was handed to the reader |
| `design` | Always `null` for WaveCrux |
| `body` | The answer, or `null` when there is none |
| `diagnostics` | Errors that say why there is no answer, and warnings that qualify one |

**The `outcome` is the authority.** Read `body` only when `outcome` is
`completed`. On anything else, read the `error` diagnostics: their `message`
says what went wrong and `fix`, when present, what to do. The tool result's
`isError` is true exactly when there is no answer.

| Outcome | Exit code | Typical cause |
|---|---|---|
| `completed` | 0 | An answer; check the warnings |
| `usage_error` | 64 | A bad or missing input, a path outside the root, a time between ticks |
| `input_error` | 65 | No such file, a file the reader refused, no signal by any name given |
| `engine_error` | 3 | The reader hung or failed |

**Warnings qualify an answer.** A signal name that is not in the file is a
`signal.not_found` warning, and the other signals are still answered. Do not
treat a missing signal as a value.

**Truncated lists say so.** Each list that can grow carries `returned`,
`truncated` and a way on: `transitions` gives `next_from` per signal and
`values` gives `next_from` for clock edges. Ask again with `from` set to
`next_from` to continue. A `transitions.same_tick_split` warning means several
changes share the last tick returned and the limit fell among them; ask again
with a higher `limit` to see them all.

The schemas of every body are in this repository under `spec/mcp/schemas/`,
with a golden document for every outcome each tool can produce under
`spec/mcp/goldens/`.

## Citing

Every signal in `values` and `transitions` carries a `location`:

```json
{
  "file": "/work/sim/dump.vcd",
  "signal": "top.u_fifo.full",
  "time": {"at": 1500, "unit": "tick"},
  "link": "wavecrux://open?file=%2Fwork%2Fsim%2Fdump.vcd&signal=top.u_fifo.full&t=1500"
}
```

**Cite every finding with its `link`.** It opens WaveCrux at that file, adds
the signal and puts the cursor on that tick, so the person reviewing your
answer can check it in one click. Copy links from the answer; do not build
them. One link is given per signal, at the start of the window; to point at a
change inside the same answer, you may replace the number after `t=` with any
tick that answer contains, and nothing else.

`info` returns a place (`file` and `time`, no signal and no link). A warning
about a missing signal carries a place too.

Report what the document says. A value is the waveform's, as recorded by the
simulator; WaveCrux adds no interpretation of its own.
