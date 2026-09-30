# WaveCrux — Open Core Manual Verification Checklist

> **Purpose.** Pre-release sign-off list filtered to **only those items that require human verification**.
>
> Every feature here either inherently depends on human judgement (UX feel, visual polish, cross-OS share-sheet behavior, accessibility-tool interaction, performance perception) OR exercises a process / cross-tool / cross-device flow that the automated suite cannot cover.
>
> **Excluded:** every item that is, or will be, protected by an automated `flutter_test` widget test or `integration_test/` test — see `VERIFICATION_CHECKLIST.md` for the full list and `integration_test/PENDING.md` for the automation backlog.
>
> **Workflow.** Tick each box as it's verified. Print or copy this file per release. Capture a `baseline_report_<release>.txt` from Diagnostics → Copy Report at the start of every cycle.

---

## Release metadata

- Version: ____________________
- Build SHA: ____________________
- Verified by: ____________________
- Date: ____________________
- Platform(s) tested: ____________________

---

## 1. Pre-flight

- [ ] Debug or profile build with diagnostics panel always available, OR release build with diagnostics opt-in enabled in Settings → Advanced
- [ ] All fixtures present under `verification/fixtures/` (one-time per release)
- [ ] Baseline diagnostics report captured: `baseline_report_<release>.txt`

---

## 2. Open Core protocol decoders

### Wishbone

- [ ] Per-instance configuration round-trips through session save/load (revision, addr_width, data_width, granularity, endianness, check_alignment)

### AHB-Lite

- [ ] Per-instance configuration round-trips through session save/load (addr_width, data_width, check_alignment, wait_state_threshold)
- [ ] Wait-state warning (violation 8) fires when `wait_state_threshold` is set below the actual stall length
- [ ] Awareness note: address-phase signal stability during wait state (IHI 0033 §3.4) is intentionally NOT detected by this decoder — relies on simulator assertions

### RISC-V instruction trace

- [ ] "Instruction Trace" category appears in the decoder picker; CJK locale sweep (en / zh_CN / zh / ja / ko) all render
- [ ] Surfer `instruction-decoder` `.toml` file (drop-in from <https://github.com/ics-jku/instruction-decoder>) loads and decodes equivalently (cross-tool compatibility — VERIFICATION_GUIDE.md §5.9.8)
- [ ] **Optional**: authentic Verilator-generated trace decodes consistently with a picorv32 source program (recipe in VERIFICATION_GUIDE.md §5.9.9; not required for sign-off)

### SPI flash command decoder

- [ ] Stacked decoder entry appears in picker only when SPI decoder is already active (VERIFICATION_GUIDE.md §5.10.9)
- [ ] No PRO tier badge on the SPI flash decoder picker row — this is Open Core (VERIFICATION_GUIDE.md §5.10.8)

---

## 3. Cocotb log correlation

- [ ] Stress log (10 k+ entries): UI does not freeze during load and filter operations under sustained load (HYBRID — parse correctness is automated; UI freeze under load is the manual portion)

---

## 4. Flutter Web

- [ ] Renders acceptably with ~50 signals (perceptual — performance feel on real Chrome / Safari / Firefox)

---

## 5. User-contributed decoder plugin loader

- [ ] Build the 1-Wire demonstrator (`make` in `examples/decoder-plugin-demo/`); copy the artifact into the per-user plugin directory; restart WaveCrux
- [ ] Decoder picker shows `1-Wire (demo plugin)` under the User-Contributed group (registry-level coverage is automated; visible-in-picker is the manual portion)
- [ ] Rust companion port at `examples/decoder-plugin-demo-rust/` builds via `cargo build --release` and produces a byte-equivalent decoder (developer-time check)

---

## 6. Display formats and translate filters

- [ ] 256-bit and 1024-bit signals render in reasonable time (HYBRID — value correctness up to 1024-bit is automated; perceptual render time is the manual portion)
- [ ] Named enum import from `.txt` filter file populates editor rows (VERIFICATION_GUIDE.md §17.14 step 8)
- [ ] Named enum export writes `.txt` file with correct `<value>  <label>` format (VERIFICATION_GUIDE.md §17.14 step 9)

---

## 7. Performance

- [ ] Desktop: 1000 signals @ 60 fps avg (HYBRID — parser/render numbers automated; perceptual 60 fps is the manual portion)
- [ ] Tablet: 500 signals @ 60 fps avg
- [ ] Phone: 100 signals smooth

---

## 8. SigRok bridge plugin (downloadable, opt-in)

> Skip this section if the bridge is not installed. The bridge is a downloadable, opt-in plugin distributed via GitHub Releases on `wavecrux/wavecrux-sigrok-bridge`. See VERIFICATION_GUIDE.md §22.5.4.1 for the full walkthrough.

- [ ] Bridge installed: shim binary in per-user plugin directory; subprocess on PATH or sibling
- [ ] Subprocess kill mid-session: WaveCrux does not crash, error transaction surfaces, next activation respawns the subprocess
- [ ] ABI mismatch path: bridge built against a future MAJOR shows `abiMismatch` row, no decoders appear in picker
- [ ] X/Z policy default (`glitch`): indeterminate bits produce a glitch annotation, no libsigrokdecode-side garbage
- [ ] X/Z policy override (`coerce_last`) per-instance: behaves correctly for a fixture with a brief reset-time X-storm

---

## 9. About Box

- [ ] Dialog opens from platform menu bar (macOS: WaveCrux → About; Windows / Linux: Help → About)
- [ ] "Copy Version Info" clipboard contents are structured plain text in the expected format (button-enabled state is automated; clipboard content format is the manual portion)
- [ ] "Visit Website" and "Report Issue" buttons open the correct browser URLs

---

## 10. Color Theming & Customization

- [ ] Theme-not-found fallback: `wavecrux-dark` activated, snackbar shown to user
- [ ] Import valid `.wavecrux-theme.json`: preset added to grid, tokens visibly apply
- [ ] Signal palette swatch tap → color picker opens; pick a color → palette updates and canvas re-assigns immediately
- [ ] Signal palette drag-to-reorder → canvas uses the new palette order
- [ ] Signal palette Reset → reverts to the active preset's original palette
- [ ] Quick override `canvas.background` → canvas re-paints immediately
- [ ] Quick override persists across app restart
- [ ] Quick override does not bleed into other presets
- [ ] Chrome-only theme pack (no `canvas` key) → canvas uses preset defaults, chrome updates

---

## 11. Multi-Tab Workspace

- [ ] Open file → opens in a new tab (or replaces the Welcome tab if it is the only tab)
- [ ] Tab switching preserves per-tab cursor, zoom, and signal arrangement
- [ ] Tab context menu: Duplicate Tab, Move to New Window (disabled), Reveal in Finder/Explorer, Close Tab, Close Other Tabs, Close Tabs to the Right
- [ ] "Move to New Window" is visible but disabled (`kMultiWindowAvailable = false`); tooltip explains
- [ ] Keyboard shortcuts work: close tab (Cmd/Ctrl+W), next/prev tab (Ctrl+Tab / Ctrl+Shift+Tab), jump to tab 1–9 (there is no new-tab shortcut)
- [ ] All tab keyboard shortcuts appear in the command palette under the File category
- [ ] Startup restoration disabled in Settings → relaunch starts with a single Welcome tab
- [ ] Session save/load is per-tab: Cmd+S saves only the active tab
- [ ] Panel context switches on tab change: waveform canvas, value column, signal tree, transaction view all reflect the new tab's state
- [ ] Waveform diff panel: switching tabs while diff is open updates to the active tab's waveform
- [ ] Diagnostics panel: switching tabs updates File Info, Memory, and Signal Health to the active tab's file
- [ ] Status bar (cursor time, filename, zoom) updates immediately on tab switch

---

## 12. Workspace Model & Split-Pane

- [ ] WCP `wcp.load`, `set_cursor`, etc. target the active pane's active tab
- [ ] WCP `wavecrux.setActiveTab` extension accepts the optional `paneId` parameter

---

## 13. Final report

- [ ] Diagnostics report archived for each major fixture under release version (process artifact)
- [ ] Open issues filed for any failures
- [ ] Sign-off captured (name + date below)

---

**Sign-off:** ____________________  **Date:** ____________________
