# AI assistant *(experimental)*

The WaveCrux AI assistant reads your signals with you. Ask it to **explain a region**, **find a condition in plain English**, or **hypothesise why your design hung** — and every answer it gives points at a real moment in your capture that you can click to jump to and check. It is **bring-your-own-key**: WaveCrux runs no model of its own, so you choose the provider, you hold the key, and your tokens are yours. The single-shot [Explain Selection](#explain) carries no tier badge; the agentic [AI Waveform Assistant](#advisor) is Pro.

!!! warning "Experimental"

    The AI assistant is an **experimental** feature. It is off by default — you turn it on in **Settings → AI Assistant** — and it may change or be removed. AI behaviour depends on a third-party model you supply, so treat its output as a fast, well-grounded lead to verify, never as a signed-off result.

## AI, done right { #philosophy }

A chat box bolted onto a waveform viewer is easy to build and worth very little. A waveform is millions of transitions — you cannot paste it into a model and expect a useful answer, and a tool that confidently invents signal behaviour is worse than no tool at all for an engineer who has to be *right*. WaveCrux takes a different position, built on three rules.

- **The viewer owns the context, not a prompt box.** WaveCrux already holds the parsed signal hierarchy, the decoded protocol transactions, and the deterministic analysis engines. The assistant is given precise, structured access to that — so it reasons about *your* capture, not a vague description of it.
- **Ground everything; invent nothing.** The assistant answers by calling deterministic tools — signal search, transition lookup, transaction queries, and in Pro the [Debug Advisor](analysis.md#debug-advisor) rule engine with its [X-trace](analysis.md#x-trace) causal chain. Every claim it makes is meant to carry a citation to a real time (and signal) in the trace, and [clicking it jumps the cursor there](#citations). WaveCrux re-checks every citation against the loaded trace instead of trusting the model.
- **You bring the model.** WaveCrux hosts no AI and ships no key. You connect your own account — a hosted provider or a model running on your own machine — so cost, choice of model, and where your data goes all stay in your hands. See [Your key, your data](#privacy).

The result is an assistant that behaves like a sharp colleague leaning over your shoulder: it knows where to look, it shows its work, and you can verify every claim with one click.

## Connect your model (BYO-key) { #setup }

The assistant needs a model to talk to. WaveCrux supports the major hosted providers and a local model running on your own machine, so you can pick on cost, capability, or data-handling policy.

1. **Open the AI settings.**

    Go to **Settings → AI Assistant**. Switch on **Enable experimental AI features** — this is off by default, and turning it on is what makes the AI surfaces appear in the app.

2. **Choose a provider and paste your key.**

    Pick a **Provider** — **Anthropic**, **OpenAI**, **Google**, or **Local (Ollama)** — and paste your **API key** (a local Ollama endpoint needs no key). For a self-hosted or proxied endpoint, set the optional **Endpoint** URL. Your key is stored in your device's secure storage — never in the plain settings file.

3. **You're connected.**

    Until a model is configured, the AI surfaces report *"No model configured"* and point you at the provider and key. Once a key is in place, the [Explain Selection](#explain) action and the [AI Waveform Assistant](#advisor) panel become usable.

!!! tip

    Prefer a model that supports **tool use / function calling** for the AI Waveform Assistant — that is how WaveCrux lets the model search signals and query transactions on your behalf. A local Ollama model keeps every byte on your own machine; see [Your key, your data](#privacy) for the trade-offs.

!!! note "Builds from source"

    The provider clients ship in the downloadable WaveCrux app. A build compiled from the open-core source has no model client, so its AI surfaces always report that no model is configured.

## Explain Selection { #explain }

**Explain Selection** is the simplest way in, and it carries no tier badge. Select signals and a time window, and WaveCrux assembles a compact, structured summary of that region — each signal's value at the start of the window, its transitions inside it, any decoded transactions in range, and an X-origin trace for any signal that is unknown — sends it to your model in a **single call** with no tools, and renders the explanation in the **Explain Selection** panel with every reference clickable.

1. **Select a region.**

    Select the signals you care about (for example ++cmd++ / ++ctrl++ + click their names), then set the window by placing the primary and secondary cursors at its two ends. Without a secondary cursor the whole loaded time range is used. The more focused the selection, the sharper the answer.

2. **Run Explain Selection.**

    Choose **Tools → Explain Selection**, or open the command palette (++cmd+shift+p++ / ++ctrl+shift+p++) and search for it. The action is enabled once a file is loaded, signals are selected and a model is configured. The result opens in the **Explain Selection** panel.

3. **Read it, then verify it.**

    The explanation describes what the signals are doing in plain language. Its citations are links — click one to [jump the cursor to that exact evidence](#citations) and confirm it with your own eyes.

!!! note

    Explain Selection is a single question and a single answer — there is no back-and-forth and no multi-step searching. It is perfect for getting your bearings in an unfamiliar block or a piece of third-party IP. When you need the assistant to go hunting across the whole capture, reach for the [AI Waveform Assistant](#advisor).

## AI Waveform Assistant <span class="tier tier-pro">Pro</span> { #advisor }

The **AI Waveform Assistant** is the agentic assistant. Instead of one shot, it works in a loop — calling WaveCrux's own tools to search signals, read transitions in a window, list and query decoded transactions, jump the cursor, drop markers, and run the [Debug Advisor](analysis.md#debug-advisor) with its [X-trace](analysis.md#x-trace) causal chain — until it can answer your question with evidence in hand. You watch each step it takes, so it is never a black box. Open it from **Tools → AI Waveform Assistant** or the command palette.

It is built for three jobs:

### Find it in plain English

Describe the condition instead of building a query. Ask *"find the first place `reset` deasserts but the FIFO isn't empty"* and the assistant locates the matching signals, reads their transitions, and jumps the cursor or drops markers at what it finds.

### Explain a region, with drill-down

Like Explain Selection, but conversational — the panel's **Explain selection** quick action starts it. Ask a follow-up — *"why is `wready` low for so long here?"* — and the assistant pulls in the decoded handshake transactions, the relevant clock, and the surrounding transitions to answer, then lets you keep digging.

### Hypothesise a root cause

Point it at a symptom — the **Why did it hang here?** quick action, or a question such as *"why did the design hang around `1.2 ms`?"* — and the assistant runs the Debug Advisor's X-propagation, clock-domain-crossing, stuck-at, and setup/hold detectors, follows the X-trace causal chain, and proposes evidence-backed hypotheses. Each one cites the signals and timestamps it is built on.

1. **Ask your question.**

    Type it into the panel (*Ask about the waveform…*) in plain language. Reference signals by name; it resolves them against your capture.

2. **Watch it work.**

    Under **Steps**, the assistant shows each tool call as it runs and how many citations it produced, so you can see exactly how it reached its conclusion. A long investigation stops at a step limit and shows what it found so far.

3. **Follow the evidence.**

    Click any citation in the answer to jump there. **Pin this finding** keeps it under **Pinned findings** — pinned findings and the conversation are saved with your session, so they are still there when you reopen the capture tomorrow. **New conversation** starts over.

!!! note "Leads, not proofs"

    Its hypotheses are leads, not proofs — exactly like the [Debug Advisor](analysis.md#debug-advisor) findings they are built on. Their value is that they arrive with the signals and the timestamp already in hand, so confirming or dismissing one takes seconds. If a pinned finding refers to a signal or decoder that is no longer in a reloaded capture, it is dropped quietly rather than breaking the session.

## Grounded answers you can click { #citations }

Grounding is the whole point. The assistant is instructed to back every claim with a citation to a coordinate in your capture — a time, or a signal at a time — taken from the data WaveCrux handed it. In the answer those citations are live links:

- **Every citation is clickable.** Click one and the primary cursor jumps to the cited time, and the canvas pans so you land on the evidence.
- **If a citation can't be resolved** — a signal or time that doesn't exist in the trace — WaveCrux marks it *"could not locate"* rather than silently jumping somewhere wrong. A wrong jump would be worse than none.

!!! note "Why this matters"

    An assistant you can't check is an assistant you can't trust with a tape-out. Because every WaveCrux answer lands you on the exact cycle it is talking about, you stay in control: the AI does the looking, you do the deciding.

## Your key, your data { #privacy }

WaveCrux does not run, host, or proxy any AI model, and it ships no API key. When you use the assistant, WaveCrux talks **only** to the provider endpoint you configured, using **your** key.

- **Your key stays local.** It is held in your device's secure storage and sent only to the provider you chose.
- **You decide where your design goes.** To answer a question, WaveCrux sends the relevant slice of signal context to your chosen model. Pick a hosted provider for convenience, or run a local model with **Ollama** so that none of your capture leaves your machine.
- **Conversations are yours.** The AI Waveform Assistant transcript and pinned findings are saved inside your local session file, alongside the rest of your workspace — not on any WaveCrux server.

## Tiers & availability { #tiers }

- **Explain Selection** — single-shot, grounded explanation of a selected region. No tier badge. Bring your own key.
- <span class="tier tier-pro">Pro</span> **AI Waveform Assistant** — the agentic assistant: natural-language navigation, conversational explain-with-drill-down, and root-cause hypotheses over WaveCrux's deterministic engines.
- *(experimental)* Both are experimental and off by default until you enable them in **Settings → AI Assistant**.

!!! info "Unlocked in the beta, licensed from 1.0"

    The AI Waveform Assistant is a Pro feature. Through the 0.8.x public beta every tier is unlocked for everyone, so you can use it today as soon as you connect your own provider key; from 1.0 it needs a Pro license key as well. Explain Selection is Open Core in either build and needs only your provider key. See [Tiers & licensing](licensing.md) for the full picture.
