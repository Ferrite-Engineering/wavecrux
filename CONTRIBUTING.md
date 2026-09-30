# Contributing to WaveCrux

Thanks for your interest in contributing to WaveCrux. This document describes
how to file issues, submit pull requests, run the project's quality gates,
and certify the origin of your contributions.

WaveCrux open core is licensed under the [Apache License 2.0](LICENSE). All
contributions you submit to this repository are accepted under that same
licence, and require a signed Contributor License Agreement — see
[Contributor License Agreement](#contributor-license-agreement-cla) below.

## Filing issues

Open issues at the project's GitHub issue tracker. A useful issue includes:

- A short, descriptive title.
- The version of WaveCrux you are using (or a Git commit SHA).
- The platform (Linux/macOS/Windows/iOS/Android/Web) and version.
- Steps to reproduce the problem, ideally with a minimal waveform file or
  test case attached.
- The expected behavior and the actual behavior you observed.
- Logs or stack traces, if any.

For correctness or rendering bugs in the waveform engine, attaching the
output of the **Diagnostics → Copy Report** action is the fastest way to
get the maintainers what they need (see
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) §8.8).

For security issues, please do **not** file a public issue. Contact the
maintainers privately via the email address listed in the project's
GitHub profile or organization page.

## Submitting pull requests

1. **Fork** the repository and create a topic branch off `main`. Branch
   names follow `feature/short-description` or `fix/short-description` per
   the project's git conventions.
2. **Make your changes** following the coding conventions documented in
   [`CLAUDE.md`](CLAUDE.md) (the engineering manual for AI-assisted
   contributors and human reviewers alike) and
   [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). The most load-bearing
   rules:
   - **No hardcoded user-facing strings** — every string goes through the
     localization system. ARB files in all four locales (`en`, `zh_CN`,
     `ja`, `ko`) must stay in sync.
   - **Tests are mandatory** — every new or modified file in `lib/` has a
     corresponding test in `test/` mirroring the directory layout. Widget
     tests include a locale sweep across `en`, `zh_CN`, `ja`, `ko`.
   - **Mobile UI standards** — read sizes from `MobileMetrics`, follow
     touch-target / long-press / chrome-overflow rules in
     `docs/ARCHITECTURE.md` §3.1.8.
   - **Open-core extension point first** — Pro features that need a hook
     in this repo land the extension-point interface here first; never
     fork code from this repo into the closed-source overlay.
3. **Run the quality gates locally** before pushing (see
   [Quality gates](#quality-gates) below).
4. **Sign the CLA** if you have not already — one time per
   contributor, not per pull request (see
   [Contributor License Agreement](#contributor-license-agreement-cla)
   below). It gates the merge, not the review, so open the pull
   request whenever you are ready.
5. **Open a pull request** against `main`. Use the [Conventional Commits](https://www.conventionalcommits.org/)
   prefix in both the commit subject and the PR title (`feat:`, `fix:`,
   `refactor:`, `docs:`, `test:`, `chore:`).

PRs should be focused — one logical change per PR. Reviewers will ask you
to split mixed PRs.

## Quality gates

### Setting up a fresh clone

A fresh clone is missing four things the gates depend on, none of which is
committed. You need the Flutter version pinned in CI and a stable Rust
toolchain (see the README's **Prerequisites**). Then:

```bash
git clone --recurse-submodules https://github.com/Ferrite-Engineering/wavecrux.git
cd wavecrux
make bootstrap
```

`make bootstrap` runs these, which you can also run by hand:

```bash
# The wellen FFI library. Every test that opens a waveform loads it.
cd native/wellen_ffi && cargo build --release && cd ../..

# Packages, then Riverpod codegen. The generated *.g.dart files are not
# committed, so nothing compiles until this has run.
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Two inputs `flutter analyze` reads: the packages of the bundled
# wavecrux_ctl tool, and the fixture bundle an integration test imports.
dart pub get --directory tool/wavecrux_ctl
dart run tool/generate_web_fixture_bundle.dart
```

Run it again after pulling changes to the Rust crate, to Riverpod providers,
or to the test fixtures. Each step is quick when its output is already
current.

If the library is not built, the suites that need it are reported as
**skipped**, each with the reason
`cd native/wellen_ffi && cargo build --release`, and the rest of the suite
still runs. A skip means a missing build step, not a broken test. CI builds
the library first and treats a missing one as a failure.

### Before every pull request

Every PR must pass these locally before review:

```bash
# Linting: zero-warning policy. Treat any warning or info as a blocker.
flutter analyze --fatal-infos --fatal-warnings

# Formatting, over the files the repository tracks.
git ls-files -z '*.dart' | xargs -0 dart format --output=none --set-exit-if-changed

# Full test suite. Must be green, and no skip may name the native library.
flutter test

# Rust native library, for changes under native/wellen_ffi/
cd native/wellen_ffi && cargo check
cd native/wellen_ffi && cargo test
```

`make analyze` and `make test` run `make bootstrap` first, so they work on a
fresh clone as they are.

CI runs the same gates on every PR; failures block merge.

## Coding conventions

The complete style and architecture guide lives in two places:

- [`CLAUDE.md`](CLAUDE.md) — the day-to-day engineering manual, optimized
  for both human contributors and AI-assisted authoring. Covers Dart
  style, widget architecture, Riverpod conventions, mobile UI standards,
  testing requirements, localization rules, and the project's git
  workflow.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the deep architectural
  reference: layer responsibilities, the `WaveformDataSource` abstraction,
  the FFI architecture, the design system, the test fixture and
  validation strategy, the diagnostics panel design, and the open-core
  extension-point seams that the closed-source overlay plugs into.

Read both before submitting non-trivial changes.

## Contributing a decoder plugin

WaveCrux exposes a stable C ABI for community-contributed protocol decoders.
A decoder plugin is a native shared library (`.so` / `.dylib` / `.dll`) that
WaveCrux discovers at startup, loads via `dart:ffi`, and registers into the
built-in `DecoderRegistry` alongside the open-core decoders. Plugins can be
written in any language that emits a stable C ABI — C, C++, Rust, Zig.

The full binding contract — struct layouts, lifecycle callbacks, threading
model, memory ownership — lives in
[`include/wavecrux_decoder.h`](include/wavecrux_decoder.h). Read the header
before you start; this section documents only the version contract.

### ABI version contract

The header defines two independent version components:

```c
#define WAVECRUX_DECODER_ABI_MAJOR 1
#define WAVECRUX_DECODER_ABI_MINOR 0
```

These are combined into a single `uint32_t` via
`WAVECRUX_DECODER_ABI_VERSION`, which every plugin must publish from its
`wavecrux_decoder_abi_version()` entry point.

**MAJOR** version. Incompatible changes — struct field reordering or
removal, callback signature changes, semantic changes that break existing
plugins. The loader rejects any plugin whose MAJOR component does not
match the host's MAJOR. MAJOR bumps are rare and accompanied by a written
migration guide that walks plugin authors through the changes.

**MINOR** version. Backward-compatible additions — new trailing fields on
existing structs, new optional callbacks, new optional manifest keys. The
loader and plugins on either side of a MINOR boundary are required to
interoperate without recompilation:

* **Older plugin, newer host.** The host reads only the prefix of each
  struct that the plugin's MINOR understood. Trailing fields the host
  added in a later MINOR are filled with zero / NULL on the host side.
  Any new optional callback the host knows how to call must therefore
  tolerate a NULL function pointer.
* **Newer plugin, older host.** The host reads only the fields its own
  MINOR knows about; trailing fields the plugin populates from a newer
  MINOR are silently ignored. Features the host doesn't yet understand
  are inert.

The trailing-field rule means: when adding a field to `WcDecoderDef`,
`WcSample`, or `WcTransaction`, append it to the end of the struct, give
it a default-zero meaning, and bump only the MINOR component. Reordering
or removing existing fields requires a MAJOR bump.

### Plugin authoring tutorial

A complete reference plugin lives at
[`examples/decoder-plugin-demo/`](examples/decoder-plugin-demo/) — a
working 1-Wire (Maxim/Dallas) bus decoder with end-to-end build
instructions, a hand-crafted fixture VCD, a canonical
`onewire_basic.expected_transactions.json` companion, and a README
that walks the author through every step from "git clone" to
"1-Wire decoder appears in WaveCrux's decoder picker". A companion
Rust port at
[`examples/decoder-plugin-demo-rust/`](examples/decoder-plugin-demo-rust/)
shows the same plugin written in idiomatic Rust against the same C
ABI.

Clone or copy the demonstrator directory, change the protocol logic
to fit your own bus, rename the manifest's decoder id, and you have
a complete WaveCrux plugin. The demonstrator README walks through
the modal customisation path (manifest, timing thresholds, feed
loop, transaction labels) and includes a troubleshooting section
covering every load-status the loader reports in
`Settings → Decoders → Plugins`.

The integration test in
`test/services/decoders/ffi/onewire_demo_integration_test.dart`
loads the demonstrator end-to-end and asserts decoder output matches
the committed expected-transactions JSON byte-for-byte. Treat that
test as the canonical regression check when you contribute a new
fixture or extend the C ABI.

## Contributor License Agreement (CLA)

WaveCrux requires a signed **Contributor License Agreement** before your
first contribution can be merged. It is a one-time step per contributor, not
per pull request.

The CLA does two things. It confirms you have the right to submit what you
are submitting — that you wrote it, or are permitted to contribute it — and
it grants Ferrite Engineering the licence to distribute your contribution.
**That includes distributing it under commercial licences**, in the paid
editions built on this open core, not only under the Apache 2.0 terms this
repository ships under. That is the difference between this and a Developer
Certificate of Origin, and it is the reason we ask for a signature rather
than a sign-off line. You keep the copyright in your contribution and may
use it however else you like.

It is modelled on the Apache Software Foundation's CLAs, so if you have
signed one of those the shape will be familiar. It is a single form covering
both individual and entity contributors — there is no separate corporate
version. Read it at [`CLA.md`](CLA.md).

### How to sign

Read [`CLA.md`](CLA.md), then write to
[support@ferriteengineering.com](mailto:support@ferriteengineering.com)
with `CLA` in the subject line and we will send you the signing
instructions. If you are contributing as part of your employment, say so
and name the employer: work done on company time usually belongs to the
company, and the CLA's employer clause asks you to confirm you have their
permission to contribute it.

We intend to move this into the pull request itself, so that accepting is a
click rather than an email. Until that is in place, it is email.

Open the pull request whenever you like — the CLA only gates the merge, and
nobody wants you to do the work twice. We will tell you if it is outstanding.

The name you sign under must be your real legal name. A pull request author
and a signatory who cannot be matched to each other is one we cannot merge.

### Licence of submitted code

Your contribution is distributed under the **Apache License 2.0**, the same
licence as the rest of this repository. You retain copyright; the CLA grants
the rights needed to use, modify and redistribute the work.

## Questions

If anything about contributing is unclear, open an issue with the
`question` label or start a discussion on the project's GitHub
Discussions page.
