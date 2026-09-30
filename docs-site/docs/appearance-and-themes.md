# Appearance & themes

WaveCrux ships a set of built-in color themes — light and dark — that recolor the whole app and the waveform canvas in one click. The active theme *is* the light/dark control: there is no separate light/dark/system switch. You can fine-tune individual colors, and you can author and share your own theme as a small JSON file.

## Choosing a theme { #choosing }

Open **Settings** (++cmd+comma++ / ++ctrl+comma++) and select the **Appearance** category. Above the theme controls sit **Language**, **Waveform Font Size** (8–24), and **Boost Legibility for XR / Large Displays**, which thickens traces and raises the minimum text size for XR glasses and far-away screens. The **Presets** section below shows a grid of theme cards; each card previews its color swatches. Tap a card to apply it — the canvas, panels, toolbar, and status bar all recolor immediately, and the choice persists across launches.

| Built-in preset | Brightness | Notes |
|---|---|---|
| Crux Dark | Dark | The default. The suite's engineering-tool look, tuned for long debugging sessions. |
| Crux Light | Light | The light counterpart — good for bright rooms, projectors, and printed screenshots. |
| Solarized Dark | Dark | The familiar Solarized palette applied to the app chrome. |
| High Contrast Dark | Dark | Maximum contrast for accessibility and high-glare environments. |
| Oscilloscope | Dark | A phosphor-green-on-black look reminiscent of a bench oscilloscope. |
| OLED XR | Dark | True black with saturated accents and tempered whites, tuned for Micro-OLED XR / AR glasses. |

## Light, dark, and the toggle { #light-dark }

Brightness is a property of the theme. Picking a *light* preset switches the entire app to light; picking any *dark* preset switches it to dark. There is no separate light/dark/system selector — the preset you choose is the single brightness control.

To flip quickly, press ++cmd+shift+k++ / ++ctrl+shift+k++ (also available as **View → Toggle Theme**). From any dark theme it switches to Crux Light, and from any light theme back to Crux Dark.

!!! note

    Earlier builds had a light/dark/system segmented control in Settings. It was removed: once the presets shipped, the preset already determined brightness, so the separate switch was redundant — and it no longer drove the app's colors. The preset picker and the ++cmd+shift+k++ toggle now move the same single lever.

## Fine-tuning colors { #overrides }

Below the presets, the **Color overrides** section lets you adjust individual colors on top of the active preset, grouped into **Canvas** and **Application chrome**. Tap a token's swatch to open a color picker (hex, RGB or HSV); your change repaints live and is saved with your settings. A per-token **Reset to default** drops the override and returns that color to the preset's value.

Overrides belong to the preset you made them on: choosing a different preset — from the grid or with the theme toggle — starts that preset clean and discards the overrides.

## Creating a custom theme { #custom }

A complete theme is a small JSON file with the `.crux-theme.json` extension — a **theme pack**. Use the **Theme packs** section of Settings → Appearance to:

- **Import theme pack…** — pick a `.crux-theme.json` file. It is validated, copied into WaveCrux's themes folder, and appears under **Installed packs**.
- **Activate** an installed pack so its colors take effect.
- **Export current theme…** — save the active theme, including your color overrides, to a `.crux-theme.json` file. The fastest way to start a custom theme is to export a built-in preset and edit it.
- **Uninstall** a pack you no longer want.

An activated pack stays active and is reapplied at the next launch, before the window appears. If it has been uninstalled since, WaveCrux opens on Crux Dark instead. Color changes you make while a pack is active last for the session only; to keep them, export the theme and import it as a pack.

!!! tip

    The simplest authoring workflow: pick the built-in preset closest to what you want, apply any overrides, export it, open the exported file in any text editor, change the colors you care about, and re-import.

## The .crux-theme.json schema { #json }

A theme pack is a JSON object with a small fixed header and a nested `tokens` map. Colors are hex strings — `#RRGGBB` or `#RRGGBBAA` (the optional last byte is alpha).

```json
{
  "schemaVersion": 1,
  "id": "my-theme",
  "displayName": "My Theme",
  "brightness": "dark",
  "tokens": {
    "canvas": {
      "background": "#101418",
      "cursor.primary": "#FFD54A",
      "signal.x.fill": "#FF4D4D"
    },
    "chrome": {
      "scaffold.background": "#0B0E11",
      "toolbar.background": "#141A20"
    }
  }
}
```

| Key | Type | Meaning |
|---|---|---|
| `schemaVersion` | integer | Format version. Must be `1`; any other value is rejected so a newer pack is never rendered wrongly. |
| `id` | string | Stable identifier for the theme. It becomes the installed filename (`<id>.crux-theme.json`), so it may not contain a path separator, `..`, a `:`, control characters, or leading/trailing spaces, and may not start with `.` or `~`. |
| `displayName` | string | The human-readable name shown in the installed-packs list. Must not be empty. |
| `brightness` | string | Either `"light"` or `"dark"`. Sets the app's brightness and the default used for any canvas token you omit. |
| `tokens` | object | A two-level map: `category → token → color`. See the token reference below. |

## Token reference { #tokens }

`tokens` is grouped into two categories. Every token is optional: a canvas token you omit uses its light or dark default, and a chrome token you omit keeps the standard look of the app.

**`canvas`** — everything drawn in the waveform area:

| Token | Colors |
|---|---|
| `background` | Canvas background |
| `lane.backgroundOdd`, `lane.backgroundEven` | Alternating lane backgrounds |
| `lane.divider` | Line between lanes |
| `group.header` | Signal-group header background |
| `signal.x.fill`, `signal.x.hatch` | Unknown (X) state fill and hatching |
| `signal.z.line` | High-impedance (Z) line |
| `cursor.primary`, `cursor.secondary` | The two cursors — their lines on the canvas and their triangles on the time ruler |
| `cursor.delta` | Shaded band between the two cursors. Off (fully transparent) in every built-in theme |
| `marker.line` | A line through the canvas at each named marker. Off (fully transparent) in every built-in theme |
| `marker.flag`, `marker.flagText` | A named marker's triangle and letter on the time ruler |
| `ruler.background`, `ruler.tick`, `ruler.label` | The time ruler's background, minor ticks and time labels |
| `ruler.cursorTime` | The time between the two cursors, shown on the ruler |
| `ruler.tickMajor` | Signal-group headers, comment rows and the empty-canvas message |
| `selection` | Drag-zoom selection |

A trace and a bus's value labels are drawn in the signal's own color, which you set per signal, so no theme token overrides them.

`cursor.delta` and `marker.line` need a color with some opacity to show: use the 8-digit `#RRGGBBAA` form, for example `#FFEE5833` for a faint yellow band. The color picker's sliders keep a color's opacity, so start from the hex field.

**`chrome`** — the application surfaces around the canvas:

| Token | Colors |
|---|---|
| `scaffold.background` | Window background |
| `panel.background`, `panel.header.background`, `panel.header.foreground` | Panels and their headers |
| `toolbar.background`, `toolbar.icon`, `toolbar.iconActive` | The toolbar |
| `statusBar.background`, `statusBar.foreground` | The status bar |
| `splitter`, `splitter.hover` | Panel splitters |
| `tabBar.background`, `tabBar.selected`, `tabBar.label` | Tab bars |

!!! note "Strict validation"

    Imports are checked before anything is installed. A file that is not valid JSON, has the wrong `schemaVersion`, an unsafe `id`, an empty `displayName`, an unknown `brightness`, or any color that is not `#RRGGBB` / `#RRGGBBAA` is rejected as a whole, and the reason is shown in a message. Nothing is half-imported.

!!! tip

    Themes are portable, plain-text files — commit them to your project repo or drop them in a team chat so everyone debugs against the same palette.

!!! note "Next"

    For the rest of the layout and where Settings lives, see [The interface](interface.md). For the full keyboard reference, including the theme toggle, see [Keyboard & mouse reference](keyboard-mouse.md).
