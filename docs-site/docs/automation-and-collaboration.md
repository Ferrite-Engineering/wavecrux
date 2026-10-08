# Automation & collaboration

This page covers the ways to drive WaveCrux from other tools and to review waveforms together with other people. Three of these capabilities are free and part of Open Core — the WCP remote-control API, interactive VCD streaming, and CXP cross-probing between WaveCrux and the other tools in your flow. The fourth, live collaborative viewing, is split from WaveCrux 1.1: **joining a session is free in every edition**, and **hosting one is an Enterprise feature**. (In 1.0.x, both need Enterprise.)

## WCP — remote control { #wcp }

WCP is a remote-control API for WaveCrux: the Waveform Control Protocol, a JSON-over-TCP control surface that lets an external program drive the application. Through it, another tool can open files, add signals, move the cursor, and perform similar operations — the same actions you would otherwise take by hand. WCP is part of Open Core and is free.

The point of WCP is integration. Use it from a continuous-integration job to open a build artifact and place the cursor at a failing event; from an editor extension to jump WaveCrux to the signal under your text cursor; or from a simulator to push the viewer to a point of interest the moment a check fires.

!!! tip "Scripted simulate-and-inspect"

    WCP pairs naturally with interactive VCD, below: a script can launch a simulation feeding its trace into WaveCrux live, then issue WCP calls to navigate to whatever the run produces.

### Connecting { #wcp-connect }

The WCP server is **off by default**. Turn it on in **Settings → Remote Control → Enable Remote Control**; the same section sets the **Port** (default `54321`) and shows the server's **Status** and connected clients. The server runs in the desktop and mobile apps, not in the browser build, and listens only on `127.0.0.1`.

Connect, and the server immediately sends a `greeting` frame announcing its protocol version (integer `0`, serialized as the string `"0"`) and the list of commands it supports, so a client can feature-detect before sending anything.

Each message is a JSON object terminated by a single null byte (`\x00`) — that byte is the frame delimiter. You send commands; the server replies and may also broadcast events.

#### Two envelopes { #wcp-envelopes }

WaveCrux speaks two wire dialects over the same socket, detected per message, so one connection may even mix them:

- **Spec envelope (default).** The upstream Waveform Control Protocol shape (as implemented by the Surfer project) and the default for third-party WCP clients. Commands are *id-less*, with parameters as top-level fields; replies are correlated by order (each command gets exactly one response/error frame, in request order, enforced by a per-connection serial dispatch queue).
- **Legacy id dialect.** WaveCrux's original envelope, used by the `wavecrux_ctl` command-line client in the open-core source. Commands carry a mandatory integer `id` and nest their parameters under `data`; replies echo the `id`. A `command` frame that carries an integer `id` selects this dialect; an id-less frame selects the spec envelope.

Broadcast events follow whichever envelope the connection most recently latched (legacy until a spec-envelope command is seen).

| Frame | Spec envelope (default) | Legacy id dialect |
|---|---|---|
| Command (client → server) | `{"type":"command","command":"<name>",…params}` | `{"type":"command","id":<int>,"command":"<name>","data":{…}}` |
| Response (success) | `{"type":"response","command":"<name>",…fields}` — payload-less acks echo `"ack"` | `{"type":"response","id":<int>,"data":{…}}` — `id` echoes the command |
| Error | `{"type":"error","error":"<name>","arguments":[…],"message":"…"}` | `{"type":"error","id":<int>,"code":<int>,"message":"…"}` |
| Event (server → client) | `{"type":"event","event":"<name>",…fields}` | `{"type":"event","event":"<name>","data":{…}}` — e.g. `waveforms_loaded` |

Legacy-dialect error `code` values: `1` parse error, `2` unknown command, `3` invalid argument, `4` internal error, `5` precondition not met (for example, no file loaded), `6` item not found. Spec-envelope errors name the failure in the `error` field instead.

All times are integer tick counts in the loaded trace's timescale. Commands act on the active pane's active tab; use `wavecrux.setActiveTab` to retarget first when several tabs are open.

### Base commands { #wcp-base-commands }

These follow the shared Waveform Control Protocol vocabulary, so a client written against the common WCP surface drives WaveCrux without modification. The deprecated spec commands `add_variables` and `add_scope` are accepted as aliases of `add_items`.

| Command | Parameters | What it does |
|---|---|---|
| `load` | `source` (file path) | Opens a waveform file in the active tab; broadcasts `waveforms_loaded`. |
| `reload` | — | Re-reads the current file; broadcasts `waveforms_loaded`. |
| `clear` | — | Removes all displayed signals. |
| `add_items` | `items[]` (or `paths[]` / `item_path`); `recursive` (opt) | Adds signals (or a scope's signals — its whole subtree when recursive). Returns each item's stable integer `id`; all-or-nothing if any entry fails to resolve. |
| `remove_items` | `ids[]` | Removes signals by the IDs returned from `add_items`. |
| `get_item_list` | — | Lists every displayed signal and marker with IDs. |
| `get_item_info` | `ids[]` | Returns name and path for specific items. |
| `set_cursor` | `timestamp` | Places the primary cursor at a tick time. |
| `set_viewport_range` | `start`, `end` | Pans and zooms to show exactly that range. |
| `set_viewport_to` | `timestamp` | Centers the viewport on a tick time. |
| `zoom_to_fit` | — | Zooms to fit the whole trace. |
| `set_item_color` | `id`, `color` (`#RRGGBB[AA]`) | Sets a signal's waveform color. |
| `focus_item` | `id` | Selects a signal. |
| `add_markers` | `markers[]` (`time`; `name` a–z, optional) | Places named markers (a missing name takes the first free letter); returns their item IDs. |
| `shutdown` | — | Stops the WCP server and closes connections. |

### WaveCrux extension commands { #wcp-extension-commands }

These are WaveCrux-specific, namespaced under `wavecrux.` They add read-back and multi-tab control that the base vocabulary does not cover.

| Command | Parameters | What it does |
|---|---|---|
| `wavecrux.getValueAt` | `signal_path`, `time` | Returns a signal's formatted value at a tick time. |
| `wavecrux.getHierarchy` | — | Returns the full scope/signal tree (name, path, type, bit width) so a client can discover signals without parsing the file. |
| `wavecrux.getState` | — | Snapshots the open file, cursor positions, zoom, pan offset, and displayed-signal list. |
| `wavecrux.setActiveTab` | `tab_id`; `pane_id` (opt) | Activates a workspace tab so later commands target it; optionally asserts the tab lives in a given pane. |

!!! note "A first round-trip"

    Open a file, drop a signal in, and park the cursor on it (legacy id dialect):

    ```json
    {"type":"command","id":1,"command":"load","data":{"source":"/tmp/run.fst"}}
    {"type":"command","id":2,"command":"add_items","data":{"item_path":"top.cpu.state"}}
    {"type":"command","id":3,"command":"set_cursor","data":{"timestamp":12000}}
    ```

    Each frame is followed by a `\x00` byte. The `add_items` response carries the new item's `id`, which you reuse for `set_item_color` or `focus_item`.

## Interactive VCD { #interactive-vcd }

On desktop, WaveCrux can read a VCD from standard input or from a named pipe while a simulation is still running. You do not have to wait for the run to finish and write a complete file: once the header's `$enddefinitions` arrives the hierarchy appears, and as the simulator emits value changes the canvas updates, so you can navigate the data received so far while more keeps arriving. Interactive VCD is part of Open Core and is free.

Start WaveCrux from a terminal with one of:

- `--stdin` (or `--interactive`) — read the VCD from standard input, e.g. `my_sim | wavecrux --stdin`.
- `--pipe <path>` — read the VCD from the named pipe at `<path>`.

Use the executable for your platform — see [Files & sessions → command-line flags](files-and-sessions.md#recovery-desktop). While a stream is live, **File → Stop Streaming** ends it.

This is what makes the scripted simulate-and-inspect loop possible. Point your simulator's VCD output at the pipe WaveCrux is reading, drive the viewer with WCP as the run progresses, and you have a closed loop between the simulation and the display with no intermediate file to manage.

## CXP — cross-probing { #cxp }

CXP is the cross-tool peer protocol of the EDACrux suite: it lets WaveCrux exchange selections and deep links with the other tools in your flow — NetCrux, LintCrux, SimCrux, and editor integrations — so selecting a net in one tool can take another to the matching signal, time, or line. WaveCrux runs a CXP server that is **on by default**; the protocol is part of Open Core and free, and its specification is public at [edacrux.app/cxp](https://edacrux.app/cxp).

### The Cross-Probe Panel { #cxp-cross-probe }

CXP surfaces in the app as a dockable **Cross-Probe Panel** — open it with **View → Show Cross-Probe Panel**, the toolbar's Cross-Probe button, or ++cmd+shift+x++ / ++ctrl+shift+x++ (tablet and desktop). The panel lists **Connected Peers**, shows **Recent Events** in and out, and flags **Unreachable peers** it found but couldn't reach. With a signal selected, **Send selection to this peer** pushes it across so that tool jumps to the matching net.

The server and its behavior live under **Settings → CXP Cross-Probe** — **Enable CXP server**, **CXP port** (default `54322`, distinct from the WCP port), and **CXP Status** — along with two options that are on by default:

- **Broadcast selection automatically.** As you select signals, WaveCrux announces the selection to connected peers so they follow along live. Turn it off to share only explicit sends.
- **Request attention on cross-probe.** When a peer cross-probes you, WaveCrux bounces the dock (or flashes the taskbar) so you notice — it never steals focus.

## Collaborative viewing { #collaborative-viewing }

Collaborative viewing provides live shared waveform sessions in **Presenter Mode**. One participant is the **presenter**; everyone else's view follows the presenter's automatically — same zoom, same scroll, same place in the trace — with no per-person opt-in. Each participant still has their own live copy of the waveform open, and everyone appears as a **named, colored cursor** on the canvas, so you can tell who is pointing at what. Control of the session passes by an explicit hand-off, so any teammate can take a turn driving. **From WaveCrux 1.1, joining a session is free; hosting one is an Enterprise feature.** A guest without a licence is a full participant: they follow the presenter, drop pins and pings, ask to present, and write notes that travel with the session. Only **Share Session** <span class="tier tier-enterprise">Enterprise</span> carries the Enterprise badge. There are two ways in, and both open the same dialogs: **File ▸ Share Session…** and **File ▸ Join Session…** (also in the command palette), and the **Collaborate** chip at the right of the status bar, which offers **Share Session…** and **Join Session…** when no session is live and shows the session — who is in the room, who is presenting, and how to leave — while one is. The desktop app offers collaboration; the browser and mobile builds do not.

### Why this instead of screen-sharing? { #collab-why }

You could share a waveform over a Zoom or Teams screen-share — so why use this? Because a waveform is close to the worst case for screen-share video: dense, thin, high-contrast traces and tiny value labels are exactly what video compression smears, and it gets worse the more you zoom. Presenter Mode never sends video. Each participant **renders the real waveform locally**, at native crispness on their own display — the colleague on a 4K monitor sees 4K, and the presenter's laptop never becomes the bottleneck. Three things follow from that, and they are the reasons to reach for this over a screen-share:

- **It's full-fidelity.** No compression artifacts, no blur on closely-spaced edges, no mush when the playhead animates a Stage widget. Everyone reads the signal, not a re-encoded picture of it.
- **It's interactive, not a movie.** Because each viewer holds the real data, you can glance at a value the presenter skipped, hover a different signal, or drop a marker — then snap back. On a screen-share you can only watch and ask the driver to scroll.
- **Your waveform never leaves your machine.** Cursors, viewports, markers and the notes people write during the review cross the network; the waveform itself never does (see [what travels over the network](#collab-privacy)). Over the internet that traffic is end-to-end encrypted, so the relay routes your session without being able to read it. On a local network nothing leaves the building at all, so it works in isolated and IP-sensitive labs where a cloud screen-share isn't allowed.

!!! note "It complements a call — it doesn't replace it"

    Presenter Mode carries no voice or video. In practice you run it alongside whatever voice call your team already uses — it upgrades the *visual* channel of a waveform review, it isn't a meeting tool. And because every participant needs WaveCrux and the same capture open, it shines for a design or verification *team* reviewing together; for a one-off "show an outsider this glitch," an ordinary screen-share is still the lower-friction choice.

### Starting and joining a session { #collab-start }

A session runs either on your **local network** — **LAN (local network)** — or over the **internet** — **Internet (relay)**; you pick the mode in the Share and Join dialogs, and **Settings → Collaboration → Default mode** sets which one they start on. The host chooses **Share Session**; everyone else chooses **Join Session**. Anyone can open **Settings ▸ Collaboration** to set the name others see and, if your organization runs its own relay, the relay server URL. From 1.1 that page is not tied to a licence tier.

- **Local network — automatic (mDNS).** When the host shares on the local network, WaveCrux advertises the session over mDNS (Bonjour / DNS-SD). In the Join dialog, leave **Discover automatically** switched on and click **Join with mDNS** — the host is found on the network with no address to type in.
- **Local network — manual IP (fallback).** Some networks block mDNS — certain corporate VLANs, machines on different subnets, or strict firewalls. If automatic discovery doesn't find the host, switch **Discover automatically** off, type the **Host address**, and click **Join with IP**. The host's local-network address(es) are listed on the host's own Share screen for exactly this purpose. WaveCrux remembers your last host address and your choice of mode for next time.
- **Internet (relay).** The host switches to the Internet option, shares, and receives a **session invite** in two parts. The first is a room code the relay routes on; the second is the key that encrypts the session, which never reaches the relay. Participants choose the Internet option, paste the *whole* invite, and join from anywhere (see [what travels over the network](#collab-privacy), below). A partial invite will not connect — a room code on its own is rejected before you try.

!!! tip "The host lets people in"

    Joining is a request, not an entitlement. When someone joins, the host sees *“&lt;name&gt; wants to join”* with **Approve** and **Deny**; until the host approves, the joiner is connected but is not a member and receives none of the session. An unanswered request expires, and the joiner is told which of the two happened rather than being shown a generic connection error. On a local network, **Settings → Collaboration → Admit local network joiners automatically** skips the prompt — it is off by default, applies to the local network only, and resets to off each time WaveCrux starts.

!!! note "Local-network sessions are not encrypted"

    Internet sessions are end-to-end encrypted because the invite carries a secret the relay never sees. A local-network session has no invite to carry one — being able to join with no configuration at all is the point of that mode — so any key both ends could derive would be one that anyone else on the segment could derive too. We would rather say this plainly than ship encryption that reads as protection in a review and provides none.

    What protects a local-network session is **the host approving each joiner**, and the fact that it never leaves your network. If that is not enough for your threat model, use the internet mode — even between two machines in the same room.

!!! tip "Getting the invite back to bring someone in later"

    For an internet session the invite stays available the whole time: click the **session chip** in the status bar to copy it, send it by **Email** or **Message**, or show a **QR code** a phone can scan rather than typing it. The invite grants access for the life of the session and cannot be revoked for one participant — to cut access off, end the session and start a new one.

!!! note "Open the same waveform first"

    Everyone should open the *same* file before joining — cursors and markers line up by *time*, so two people on different captures would see a cursor land at the same time on different values. WaveCrux compares a fingerprint of each participant's file and shows a **Different waveform** warning in the status bar if they don't match; only the fingerprint is exchanged, never the file itself. On macOS the first local-network session asks for *Local Network* permission — allow it so mDNS can find peers (manual IP still works if you decline). When you're done, a host can **File → Export Session Recording…** — a timestamped log of who looked at what — for an audit trail.

### Who's driving, and how control changes hands { #collab-presenter }

Every session has exactly one **presenter** at a time, and everyone else follows them automatically. The participant who shares the session starts out as the presenter; the rest of the room syncs to their view the moment they join. There is nothing to switch on to start following — following is the default.

- **Hand the session to someone (assign).** The presenter — or the session host — opens the presenter controls from the **session chip** in the status bar (or **File → Hand Off Presenter…**) and picks *Hand off to &lt;name&gt;*. That person becomes the presenter and the whole room's view shifts to theirs, announced with a *Presenting: &lt;name&gt;* indicator.
- **Ask to drive (request control).** Any participant can choose **Request control**. The current presenter sees *“&lt;name&gt; wants to present”* with approve / deny; on approval, control hands over the same way. So control moves both ways — pushed by the presenter, or pulled by a request — but always explicitly. It is never grabbed out from under someone. A host who would rather not field requests can turn off **Settings → Collaboration → Allow participants to request control**.
- **Glance away, then snap back.** Pan, zoom, or scrub at any time — unlike a hard lock, this doesn't drop you out of the session or stop the presenter. Your view simply detaches locally and a *Resume following* button appears; click it to jump back to exactly where the presenter is now. This is the quick "let me check one thing" without losing your place.
- **If the presenter leaves.** The session never stalls without a driver: if the presenter disconnects, the host takes the presenter role back automatically; if the host themselves drops, the longest-present remaining participant is promoted.

When the presenter plays the Stage [playback transport](stage.md#playback), the room's playheads advance in step with theirs, so a signal-bound Stage widget animates the same way on every screen. A colleague's cursor only paints while it falls inside your visible time range; while you're all following the presenter you're in the same region, but if you detach to look elsewhere you may not see other cursors until your views overlap again.

### Following the presenter's full view { #collab-view }

Following isn't only about matching where the presenter is looking — you also see *what they've set up*. As you follow, the presenter's working view is mirrored to you: the signals they've added and how they're arranged, the [protocol decoders](protocol-decoders.md) they've run, the [value translators](translators.md) they've applied, the [Stage](stage.md) dashboard they've assembled and what each widget is bound to, and the FSM view they've opened. Add a decoder or drop in a Stage widget mid-session and it appears for everyone — "let me show you my setup" just works.

- **It's layered on top of your own work, never destructive.** The presenter's view is an overlay; your own signal arrangement, decoders, and Stage setup are left untouched underneath. Detach to look around — or leave the session — and your workspace is exactly as you left it.
- **Still only descriptions cross the wire.** The presenter's view travels as a short recipe — "decode these signals as AXI4," "arrange the signals this way," "bind this gauge to that signal" — that each machine rebuilds against its own copy of the file. A decoder runs *locally* on your data; the decoded transactions are never transmitted. The design-stays-local guarantee covers the whole view, not just the cursor.
- **It degrades gracefully.** If the presenter references a signal your capture doesn't have — or a Pro decoder or Stage widget your build doesn't include — that piece is left out and a **View partially unavailable** notice names what is missing, alongside the **Different waveform** warning when the files differ.
- **Layout adapts to your screen.** You get the presenter's choice of *which* panels are open — Stage, FSM, the value column — laid out for your own window size, not a pixel-for-pixel mirror of theirs. On a hand-off, the room re-syncs to the new presenter's setup.

### Pointing without presenting { #collab-pointing }

Sometimes you want to say "look at *this* edge" without taking over the session. Any participant — presenter or not — can drop a pointer that everyone sees, anchored to a specific signal and time so it stays glued to that transition as the view pans and zooms (**File → Drop Ping** / **Drop Pin**, or the command palette):

- **Ping** — a quick laser-pointer flash that fades on its own; for "here, now."
- **Pin** — a marker that stays until you remove it; for "leave that up while we discuss it." Only the person who placed a pin can delete it.

If a pointer lands outside your current view, an arrow at the edge of the canvas shows which way to look; a follower can also ask the presenter to bring it into view, and the presenter sees *“&lt;name&gt; asks you to scroll here”* with **Scroll there** — so nothing gets lost off-canvas.

### Writing on the waveform together { #collab-annotations }

Pins and pings are transient. When the point is worth keeping, write an [annotation](annotations.md) — and in a session, the notes people write reach everyone in the room. The host carries them, so somebody who joins twenty minutes late receives the whole conversation rather than only what happens after they arrive.

While a colleague is composing, a chip appears on the canvas at the time and signal they are writing about — *“Priya is writing a note…”* — so two people don't independently annotate the same edge. It carries no text, only the fact and the place.

- **Attribution is not the sender's to choose.** Every note is stamped from the session, so a participant cannot add one under somebody else's name, edit one they did not write, or delete one they neither wrote nor host. Because a note has exactly one author, two people can never be editing the same one.
- **The host can remove anything** — it is their meeting. The author is told when their note is removed rather than watching it silently disappear.
- **Only notes written during the session travel.** Annotations already on your canvas when the session started stay yours and stay local.

When the session ends, WaveCrux asks whether to keep what was written — all of it, only your own, or none. Anything you keep becomes a named layer you can hide or delete as a unit, so a meeting's output neither becomes permanent clutter nor silently vanishes. See [Notes from a review, kept as a group](annotations.md#layers).

### Review minutes { #collab-minutes }

The host's **File ▸ Export Review Minutes…** (Enterprise, like Export Session Recording; from 1.1 guests can join and take part but do not export) turns the session's annotations into a document you can paste into a ticket: Markdown or CSV, time-ordered, each entry carrying its author, the wall-clock time it was raised, the signal path, and the time in the waveform's own timescale. A raw tick count means nothing in a bug tracker, so the timescale comes from the trace rather than from the session.

Minutes are what the meeting *concluded*. A note edited during the review appears once saying what it ended up saying, keeping the timestamp of when the point was first raised — a typo fixed ten minutes later did not raise it again — and a note deleted during the meeting does not appear at all. If you need the raw event log instead, that is the **session recording**, which keeps everything.

!!! note "Deploying this in an organization?"

    [Administration](administration.md#collaboration) states the security model and, more importantly, its limits — no per-participant identity, no revocation, no forward secrecy, and no encryption on local-network sessions. That is the section to send to a security reviewer.

### What travels over the network { #collab-privacy }

Collaborative viewing shares *where people are looking*, not the waveform itself. Every participant opens the same file on their own machine; the session then keeps a small amount of presence data in sync between them — cursor positions, the visible time range, shared marker and pointer (pin / ping) positions, who the current presenter is and control hand-offs, playback (play / pause) state, and a description of the presenter's view — the on-screen signals and their order, the decoders and translators in use, the Stage dashboard and its bindings, and which panels are open — plus participant display names, join/leave events, and a fingerprint of each participant's file. That view description is a recipe each machine rebuilds against its own copy of the file: a decoder reruns locally and its decoded output is never sent. The waveform data itself — your signals, their values, your design — never leaves your computer and never passes through the relay.

A session also carries **the annotations people write during it** — balloons, arrows and range bands, and their text. That is user-authored content rather than presence data, so it is worth naming separately: notes you write in a session go to the other participants. Notes that were already on your canvas when the session started do not, and never will.

!!! tip "Your design data stays local"

    The relay is a stateless message router. It connects the participants in a room and forwards messages between them; a room exists only in memory while someone is in it, there are no accounts, and nothing is persisted.

    Over the internet, a session is **end-to-end encrypted**. The invite you share is two parts — a room code and a secret — and only the room code reaches the relay. The secret never leaves the participants' machines, so the relay *cannot* read what it routes, including the annotations people write during a review. A compromise or a legal demand against the relay yields ciphertext.

    What it still sees, and we would rather say so than let you find out: room codes, IP addresses, connection times, and the size and timing of messages. It can tell that five people collaborated for forty minutes. Traffic analysis is not something encryption fixes, and we do not claim it does.

!!! note "Relay location & latency"

    Today, internet sessions are carried by a single relay hosted in the United States (`wss://relay.wavecrux.app`). Because only small presence messages cross it — at human pace, not a stream — latency is rarely noticeable, though participants far from the US may see a slightly longer delay before a remote cursor catches up. Local-network sessions never touch the relay at all: participants connect to one another directly.

    The relay address is **Settings → Collaboration → Relay server URL**, so a team that would rather keep internet sessions inside its own network can point every client at a relay it runs (changes apply to your next session). **We do not ship a packaged relay image today** — if self-hosting is a requirement for your deployment, [tell us](mailto:support@ferriteengineering.com) and we will work through it with you rather than leave you to reverse-engineer the protocol.

!!! info "Hosting is Enterprise; joining is free (from 1.1)"

    Starting a session (**Share Session**) needs an Enterprise license key; the <span class="tier tier-enterprise">Enterprise</span> badge marks it. **Joining** a session needs no licence at all — a contractor, a customer or a professor invited into a review can take part with the free app. If the presenter's view uses a Pro decoder you do not have, that part of the view shows a "requires WaveCrux Pro" chip instead of unlocking: joining gives you the session, not the host's tier. See [Tiers & licensing](licensing.md) for the details.

!!! note "Related"

    For how WaveCrux treats interactive VCD as an input format alongside the files it opens, see [Files & sessions](files-and-sessions.md). For how the Enterprise tier is licensed and what it includes beyond collaboration, see [Tiers & licensing](licensing.md).
