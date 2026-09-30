# Administration <span class="tier tier-enterprise">Enterprise</span>

Everything WaveCrux reads from your organization's signed `.crux-policy.json`, plus the decoder-plugin allowlist and the limits of collaborative viewing. This page is for the person deploying WaveCrux across a fleet — the rest of these docs are for the engineer at the keyboard, and you may never open the application at all.

!!! note "The file itself is documented once, for the whole suite"

    One policy file configures all four EDACrux products. Where it goes on each platform, how you sign it, discovery order, precedence and the full key table live in [the policy file reference](https://edacrux.app/policy-reference); the rollout procedure is [Deployment](https://edacrux.app/deployment). This page covers only what WaveCrux's own keys do.

!!! info "Unlocked in the beta, licensed from 1.0"

    Through the 0.8.x public beta every tier is unlocked and no licences are issued, so there is nothing to deploy *against* yet — but the file already parses, lints and signs, so you can write and validate one today. From 1.0 the keys divide: a key that **grants** a capability (`signalGroups`, `decoderSettings`, `themePacks`, `sessionTemplates`) is honoured only on a seat holding an Enterprise licence, while the keys that can only **withhold** something — the `approvedPlugins` allowlist and the two server switches — are honoured at every tier, so a security control never waits on a licence check.

## WaveCrux's policy keys { #keys }

All of these live under `products.wavecrux`. Each takes either a bare value (a **default** the engineer may change) or `{"value": …, "locked": true}` (a **lock** they may not).

| Key | What it does | State |
|---|---|---|
| `signalGroups` | Org-standard signal groupings, by glob pattern. | In force |
| `decoderSettings` | Default protocol-decoder parameters. | In force |
| `themePacks` | A theme pack on your own share. | In force |
| `sessionTemplates` | A session file used as the starting point for new sessions. | In force |
| `approvedPlugins` | The decoder-plugin allowlist, by SHA-256. | In force |
| `wcpServer` | Whether the WCP remote-control server may run on this seat. [Below.](#servers) | In force |
| `cxpServer` | Whether the CXP peer server may run on this seat. [Below.](#servers) | In force |

**Seven keys, all of them in force.** WaveCrux has no reserved keys today. If there is a control you need, [tell us which](mailto:support@ferriteengineering.com).

!!! warning "Three rows of this table were wrong until 2026-09-19"

    `wcpServer` and `cxpServer` were listed as **Reserved — nothing reads it**. They are **enforced**, and have been since the read landed: `org_server_policy.dart:50-66`, consumed by the two servers themselves (`remote_control_notifier.dart:917`, `cxp_server_provider.dart:393`) and by the two Settings switches that render them (`settings_screen.dart:627`, `:760`). An administrator who read this page concluded a working security control was inert. It is not.

    `defaultColorScheme` was listed as Reserved and is **out of the schema** — no WaveCrux release ever registered it; it was superseded by `suite.theme` before one could. `crux-policy lint` now reports it as *"unknown to this version of the CLI … check the spelling"*, so a file carrying it fails your own linter. **Delete it.** `suite.theme` is itself unhonoured — see [the policy file reference](https://edacrux.app/policy-reference#suite-keys) — and `themePacks` above is the shipped mechanism.

## The two listening servers { #servers }

Both `wcpServer` and `cxpServer` open a socket on the engineer's machine, and both are the kind of thing an organization decides centrally rather than asking each engineer to. Each takes a bool.

```json
"products": {
  "wavecrux": {
    "wcpServer": { "value": false, "locked": true },
    "cxpServer": { "value": false, "locked": true }
  }
}
```

Precedence is the suite's, with no local variation:

```
1. a LOCKED policy value    the organization decided, and said so
2. the engineer's setting   the Remote Control / CXP switch in Settings
3. an unlocked default      the organization's starting point
4. off                      the compiled-in default for both
```

**A locked value outranks the Settings switch** — that is what locking is for here, and the switch renders read-only with its source named. **The built-in is `off` for both**, deliberately: neither server has ever started itself on a fresh install, and a policy file that fails to parse must not be the thing that opens a port. An unlocked `true` is a starting point for seats nobody has touched, not a command to turn the server on everywhere.

### What a locked value looks like to the engineer { #what-locking-looks-like }

Not a mysteriously greyed control. A locked decoder parameter renders read-only **with its source named** — “Fixed by your organization's policy file.” — beside it. That distinction is worth knowing before you lock anything, because a greyed control with no explanation becomes a support ticket, and one that explains itself does not.

**An unlocked value is a starting point, not an override.** It replaces WaveCrux's own built-in default for anyone who has not chosen; anyone who *has* chosen keeps their choice. If you want your value to win over an engineer's existing setting, you want `locked`. Deploying an unlocked default expecting it to reset everyone would silently do nothing, which is the single most common way to misread this file.

## Signal groups { #signal-groups }

A team looking at the same SoC every day groups the same signals every day — the AXI write channel, the reset tree, the DFT chain. Left to itself, each engineer rebuilds those groups by hand on every new capture and two engineers' groupings drift apart, which is not the state a design review wants to start from.

```
"products": {
  "wavecrux": {
    "signalGroups": [
      { "name": "AXI write", "patterns": ["top.**.axi_aw*", "top.**.axi_w*"] },
      { "name": "Reset tree", "patterns": ["top.**.*rst*"], "collapsed": true }
    ]
  }
}
```

**Patterns, not signal lists.** A literal list of paths is a standard that fits one design and one hierarchy; `top.**.axi_aw*` fits the family. The vocabulary is two wildcards and no more:

- `*` — matches within one path segment
- `**` — matches across segments

A regular expression would be more powerful and would put a language nobody can review into a signed file — and a mistyped one silently matches nothing, which produces a group that appears empty for reasons no engineer can see.

`collapsed` is worth using. The reset tree is a group you want to *exist* and rarely want to *look at*; a standard grouping that expands forty signals nobody asked for gets ignored within a day.

**It offers, it does not impose.** The groups are applied as signals are added, and the engineer may then move, rename, ungroup or delete them exactly as if they had made them. Under a **locked** key they are re-applied on each add rather than frozen in place — locking says *these groups exist*, not *this pane may not be rearranged*.

One malformed group is dropped and the rest still apply, so a typo in the fifth entry does not cost you the other four. Run `crux-policy lint` to see which was dropped and why.

## Decoder settings { #decoder-settings }

Verification teams standardise on things a decoder cannot guess — the bus's clock polarity, the UART's baud, whether the I²C address is 7-bit or 8-bit. Get them wrong and you get a decode that is confidently meaningless.

```
"decoderSettings": {
  "uart": { "baud": 115200 },
  "i2c":  { "addressBits": 7 },
  "spi":  { "cpol": 0, "cpha": 1 }
}
```

The shape is `{"<decoderId>": {"<parameter>": value}}`. Precedence has one case that is not simply “a default”, and it is the reason to think before locking:

- **Unlocked** — your value replaces the decoder's built-in default, so a freshly added decoder starts right. Anything the engineer has already set for that instance wins.
- **Locked** — your value wins outright, including over a value the engineer set earlier and over one restored from a saved session. A lock that yielded to a saved session would be a lock in name only.

A decoder id whose value is not an object is dropped rather than failing the whole key — one malformed entry must not cost you the other nine.

## Theme packs and session templates { #theme-packs }

Both name a file on **your own share**, and a share is a path you already have: an NFS mount, a mapped drive, a synced folder, a git checkout. **There is no download, no URL and no cache** — each of those would be something we run, or something that fails differently on an airgapped machine.

```
"themePacks": {
  "value": { "path": "/mnt/eng-share/edacrux/house.crux-theme.json",
             "sha256": "3b1f0c…" },
  "locked": true
},
"sessionTemplates": "/mnt/eng-share/edacrux/standard-review.wavecrux"
```

A bare path string works too — it is what you write first, and refusing it would make the simplest case the one that needs the manual. Both keys are plural because an organization may want to *offer* several later; today the first entry of a list is used, so a one-element list behaves exactly as you would expect.

- **Theme pack.** WaveCrux already installs, activates and exports theme packs. What this adds is the organization *supplying* one, so a house colour scheme is applied at launch instead of being emailed round as a file half the team forgets to import. Unlocked, it is applied as the starting point and the engineer may pick anything else afterwards.
- **Session template.** An ordinary `.wavecrux` session file, used as the starting point for a **new** session — so a team's standard signal arrangement, cursors and panel layout are what an engineer starts from rather than what they rebuild. **A template never touches an open session, and never overrides a session opened from a file.** Somebody who double-clicked a `.wavecrux` wants that session, and applying a template over it would be the feature destroying the thing the engineer asked for.

**Locked**, the pack is applied at every launch and Settings ▸ Appearance becomes read-only: the presets, color overrides and theme packs stay visible under a note that the organization's policy file sets the theme, and **Toggle Theme** shows the same note instead of switching.

### Pinning by content hash { #pinning }

`sha256` is optional, and its absence is not laxity: a theme pack you edit monthly should not need a policy-file commit and a re-sign each time. When it *is* present the file must match, and a mismatch is a refusal rather than a warning — a pinned resource that silently loaded something else would be worse than one that did not load at all.

**This is a different decision from the plugin allowlist below, and the two look similar.** The allowlist decides whether to *execute code*, so it refuses what it cannot verify. This decides whether to apply a *preference*, so an unpinned resource is a legitimate configuration rather than a hole.

## The decoder-plugin allowlist { #plugins }

This is a security control rather than an Enterprise nicety, so it is worth stating what it replaced. Before it, WaveCrux's FFI decoder loader performed **no signature check and no allowlist**: it opened a native library from a path and registered whatever the manifest declared. For an organization whose whole posture is “design IP does not leave the building”, “any shared library on the path is loaded into the tool that reads our RTL” is a question somebody eventually asks.

```
"approvedPlugins": [
  "sha256:9f2c1d4e…",
  "4a77b0c9…"
]
```

Lower-case hex SHA-256 over the plugin file's bytes. A `sha256:` prefix is accepted, because that is how most other tools print one. Compute a digest with whatever you already use:

```
shasum -a 256 libwavecrux_axi.dylib      # macOS
sha256sum libwavecrux_axi.so             # Linux
certutil -hashfile wavecrux_axi.dll SHA256   # Windows
```

!!! tip "Deploying a policy file does not break your existing plugins"

    **With no `approvedPlugins` key there is no allowlist, and every plugin loads exactly as it always has** — including the Sigrok bridge, which is a shipped, supported integration. An allowlist constrains only once you have written one.

    Refusing everything by default would have broken every existing user the first time they updated, and a list that *appeared* is not a list anybody chose. So the absence of the key is load-bearing, and you can deploy a policy file for telemetry or licensing without thinking about plugins at all.

Three rules follow, and the second and third are the ones that catch people:

- **An absent key means no constraint.** As above.
- **An empty list is not an absent key.** `"approvedPlugins": []` says *no plugins are approved*, and it is honoured. Refusing to honour it would make the strictest posture the one thing the key cannot express — so if you want to turn FFI decoder plugins off fleet-wide, that is how.
- **A malformed value degrades to absent, never to empty.** A typo must not silently become the strictest possible policy and stop every plugin in the fleet. That is the loudest possible wrong answer to a mistake, so it is the one behaviour ruled out.

**A plugin file that cannot be read is refused, not admitted.** An unreadable plugin is one this process cannot hash, and admitting what it cannot verify would make the allowlist advisory. The refusal names the reason, so a permissions problem does not present as a policy one.

### Hashing is not signing { #hashing-not-signing }

A digest answers “is this the exact binary the organization approved?” and nothing else. It cannot answer “who built it” — a hash has no author. What it buys is the property that actually matters here: you vet a binary once, record its digest, and a substituted or modified file stops loading.

**Ed25519 plugin signing and a `wavecrux-sign` CLI are not built**, and are not on this page as “coming soon”. They need a customer who has their own plugin build pipeline, and building a signing story blind builds the wrong one. If you have that pipeline, [that is the conversation to start](mailto:support@ferriteengineering.com).

### What the audit log records { #plugin-audit }

Two events, and they are deliberately separate:

- `plugin.load.attempted` — every candidate the loader considers, allowed or not. Payload: the plugin's file name, its SHA-256, and whether it was refused.
- `plugin.load.refused` — the refusal on its own, which is the security-relevant half and the one to alert on.

**Neither carries the plugin's path.** A path is a filesystem path and carries a username, in a file your log shipper reads; the digest identifies the binary better anyway and is exactly what you compare against your own list.

## Audit events WaveCrux records { #audit }

Turned on with `suite.audit.path`, suite-wide. The full envelope, the format, rotation and failure behaviour are in [the audit log reference](https://edacrux.app/audit-log) — this is just WaveCrux's vocabulary.

| Kind | When | Payload |
|---|---|---|
| `session.saved` | After a session write succeeds — never before, because a line for a save that did not happen is the one an investigation would trust. | `file`, `trigger` — **`file` is the base name, never the directory** |
| `decoder.activated` | A decoder is activated on a signal. | `decoder`, `userSupplied` |
| `stage.widget.loaded` | A user-supplied Stage widget bundle loads. | `widget`, `userSupplied` |
| `plugin.load.attempted` | Every candidate decoder plugin. | `plugin`, `sha256`, `refused` |
| `pro.feature.activated` | A licensed feature is used. | `feature`, `tier`, `requiredTier`, `betaPeriod` |
| `license.tier.changed` | The effective tier transitions. | `from`, `to` |

Autosaves are recorded at `debug` severity, so they appear only under `"verbosity": "verbose"`. Everything else appears at the default `normal`.

!!! note "`session.saved` carries `file`, not `path` — check your log-shipper query"

    The payload key is **`file`** and its value is the **base name** (`soc_debug.wavecrux`), not the full path. This page said `path` until 2026-09-19, so a query written against it matches nothing. The suite's rule is that no audit payload carries a filesystem path — a session is saved wherever the engineer likes, a home directory or a customer's share, and this file is forwarded off the machine by your log shipper. The name is what an investigation needs; the directory is what it must not export.

The decoder-plugin loader also records the suite-wide `plugin.load.refused` (payload `plugin`, `sha256`, `reason`) for every refusal — see [What the audit log records](#plugin-audit). WaveCrux also records the suite-wide `policy.loaded` when it honours your policy file, and reports `policy.rejected` to the **process log** when it refuses one — see [the audit log reference](https://edacrux.app/audit-log#refusals) for why a refusal cannot go into a file the refused document configures.

**Emission is unconditional; the sink is what you gate.** Every emitter above runs on every installation at every tier. What your policy file decides is whether there is anywhere for the events to go — so turning auditing on is a configuration change, not a different build.

## Collaborative viewing: what a security review will ask { #collaboration }

[Presenter Mode](automation-and-collaboration.md#collaborative-viewing) is documented for the engineer elsewhere. This section is the part an Enterprise security review asks about, including the limits — finding them listed is better than finding them absent.

**The security model in one sentence:** the invite carries key material the relay never sees, so a peer without it produces frames whose authentication tag fails, is dropped, and never enters the roster. Authentication falls out of encryption — there are no accounts, no identity service and no directory, and nothing of ours to run in that path beyond a stateless message router.

```
ABC123-Zm9vYmFyYmF6cXV4MTIzNDU2
└room┘ └───── secret, never transmitted ─────┘
```

The room code goes in the relay URL. The secret stays between the clients. A breach of the relay, or a legal demand against it, yields ciphertext.

### What it does not protect against { #collab-limits }

- **Metadata and traffic analysis.** The relay still sees room codes, IP addresses, connection times, and message sizes and rates. It can tell that five people collaborated for forty minutes. Encryption does not fix that and we do not claim it does.
- **The malicious invitee.** Anyone holding the invite is fully trusted. **There is no per-participant identity and no revocation.**
- **No forward secrecy, and no rekey on membership change.** Someone who was in the room keeps a key that works for the session's lifetime and can rejoin. Proper rekeying needs pairwise channels the protocol does not have, and it was deliberately not built in v1. The operating rule instead: **the invite is the credential for the life of the session — to revoke access, end the session and start a new one.**
- **Local-network sessions are not encrypted.** LAN is peer-to-peer with zero-config discovery, so there is no out-of-band invite to carry key material and no meaningful secret to derive one from — encrypting under a key anyone on the segment could reconstruct would be theatre. The meaningful LAN control is **host approval on join**, and a LAN session never touches the relay at all.

NetCrux's collaborative schematic sessions reuse this design exactly, so [the same limits apply there](https://docs.netcrux.app/administration#collaboration) and are stated in the same terms.

## Managed installs and updates { #packaging }

**A managed install does not update itself.** If you deployed by MSI, `.deb` or `.rpm`, WaveCrux will not offer an in-app update and will not nag — the version is your deployment tooling's business, which is the point of packaging it that way. That behaviour outranks every policy key, including `suite.updateChannel`, because it describes how the application was installed rather than what you configured.

For installs that do update themselves, pinning, channel selection and an on-prem manifest mirror are suite-wide keys: [the reference has them](https://edacrux.app/policy-reference#suite-keys), and [Deployment](https://edacrux.app/deployment#updates) has the two behaviours worth knowing before you write one.

!!! tip "See also"

    [Policy file reference](https://edacrux.app/policy-reference) · [Audit log](https://edacrux.app/audit-log) · [Deployment](https://edacrux.app/deployment) · [The end-to-end administrator workflow](https://edacrux.app/for/devops-engineers) · [Tiers & licensing](licensing.md)
