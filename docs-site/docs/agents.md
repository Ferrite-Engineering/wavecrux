# WaveCrux for coding agents

WaveCrux reads simulation waveforms (VCD, FST, GHW and the other formats the
app opens) and answers questions about them over the Model Context Protocol
(MCP), so a coding agent can look at what a signal did without you pasting a
dump into the conversation. Every answer is also a command, with the same
output.

## What the server offers

The server is started with `wavecrux mcp --root <project directory>`. It speaks
MCP over standard input and output, runs on your machine, writes nothing and
makes no network call of its own. Every path a tool receives must be inside
`--root` (the working directory when omitted); a path outside it, a symbolic
link that leads outside it, or a network path is refused and never opened.

| Tool | What it returns |
|---|---|
| `info` | The format, timescale, time range, signal and scope counts, and the top of the hierarchy |
| `search` | Signals whose name matches a substring or a glob: full path, width, type, direction |
| `values` | The value of each signal at one time, or at each rising edge of a clock in a window |
| `transitions` | Every recorded change of each signal in a window, and its value at the start |

WaveCrux Pro adds a fifth, `advise`: the Debug Advisor's rule-based findings at
one time (X propagation, clock-domain crossing, stuck-at and setup/hold
proximity), each with a confidence and a link. A finding is a heuristic, not a
verdict; check it in the waveform before reporting it as fact. The Pro binary is
`wavecrux_pro`, started the same way, and `advise` needs a licence that admits
Pro, read from `--license-file`, then the `WAVECRUX_LICENSE_FILE` environment
variable, then the organisation's `.crux-policy.json`. Without one it answers
with a licence error and reads nothing. The four other tools answer at every
tier.

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

## Register it with your agent

The `wavecrux` command must be on the `PATH` of the program that starts the
server. The instructions below were checked against each host's own
documentation on 2026-11-24; hosts change, so check theirs if a step differs.
To use Pro, replace `wavecrux` with `wavecrux_pro`.

=== "Claude Code"

    Add the server for the current project:

    ```
    claude mcp add --transport stdio wavecrux -- wavecrux mcp --root /path/to/project
    ```

    Everything after `--` is the command that starts the server. By default the
    entry is private to you and the project. To share it with your team, add
    `--scope project`, which writes `.mcp.json` in the project root:

    ```json
    {
      "mcpServers": {
        "wavecrux": {
          "command": "wavecrux",
          "args": ["mcp", "--root", "${CLAUDE_PROJECT_DIR:-.}"]
        }
      }
    }
    ```

    Claude Code asks each person to approve a project server the first time.
    Run `claude mcp list`, or `/mcp` inside Claude Code, to see that it
    connected.

=== "VS Code"

    With the EDACrux WaveCrux extension installed, there is nothing to
    configure. The extension registers the server with the editor for each
    workspace folder you open, with that folder as `--root`, and the editor asks
    you before it first runs. It needs a folder open in a trusted workspace.
    It finds `wavecrux_pro` or `wavecrux` through the `edacrux.wave.executable`
    setting, then your `PATH`. Turn registration off with the
    `edacrux.wave.mcp.enabled` setting.

    Without the extension, add the server to `.vscode/mcp.json` in the
    workspace (VS Code's own file uses `servers`, not `mcpServers`):

    ```json
    {
      "servers": {
        "wavecrux": {
          "type": "stdio",
          "command": "wavecrux",
          "args": ["mcp", "--root", "${workspaceFolder}"]
        }
      }
    }
    ```

    Or run **MCP: Add Server** from the Command Palette and choose a command
    (stdio) server.

=== "Cursor"

    Create `.cursor/mcp.json` in the project (or `mcp.json` in `.cursor` in your
    home folder for every project):

    ```json
    {
      "mcpServers": {
        "wavecrux": {
          "type": "stdio",
          "command": "wavecrux",
          "args": ["mcp", "--root", "${workspaceFolder}"]
        }
      }
    }
    ```

    Then open **Customize** in the sidebar and confirm the server is enabled.
    If it does not connect, open the Output panel and choose "MCP Logs".

An editor that does not offer the registration API gets the same snippet from
the **Copy WaveCrux MCP Server Configuration** command in the Command Palette.

## When an agent should call it

- A waveform exists and re-running the simulation is slow or impossible: read
  the dump instead of adding prints and simulating again.
- The question is about what a signal did in time: when it changed, what it held
  at an instant or at each clock edge, whether it was ever `x` or `z`.
- The source cannot answer it, because the behaviour depends on stimulus,
  timing or a model the agent cannot read.

The agent should start with `info`, then `search` to find the full path of each
signal, then `values` or `transitions`. Use `transitions` to see what happened
between two times: it returns every change, including a pulse shorter than any
sampling step.

## Read the outcome first

Every answer is one JSON document. Its `outcome` is the authority: read the
`body` only when it is `completed`; on anything else, the error diagnostics say
what went wrong and what to do. Warnings qualify an answer (a signal not in the
file is a warning, not a value), and a truncated list says so and gives
`next_from` to continue. Times are whole ticks of the file's timescale, or a
number with a unit; windows include `from` and exclude `to`.

## Cite with the link

Every signal in `values` and `transitions` carries a `location` with a `link`:

```
wavecrux://open?file=%2Fwork%2Fsim%2Fdump.vcd&signal=top.u_fifo.full&t=1500
```

Tell the agent to cite every finding with its link. The link opens WaveCrux at
that file, adds the signal and puts the cursor on that tick, so you can check
the answer in one click. The agent should copy links from the answer rather than
build them. The forms are described on the
[agent link convention](https://edacrux.app/agent-links) page.

An answer is the waveform's, as the simulator recorded it. WaveCrux adds no
interpretation of its own.
