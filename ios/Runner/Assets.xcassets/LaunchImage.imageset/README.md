# Launch Screen Assets

**Do not hand-edit these PNGs.** They are generated from the master app icon
(`assets/images/wavecrux_icon_1024.png`) by:

```bash
swift tool/generate_ios_launch_images.swift   # run from the repo root
```

Re-run it whenever the app icon changes, so the launch mark and the home-screen
icon cannot drift apart.

The generator renders the icon at 160 pt (160/320/480 px for 1x/2x/3x) clipped
to the iOS icon corner radius, and `Base.lproj/LaunchScreen.storyboard` centres
it on `#101830` — the mean of the icon artwork's four corner pixels.

This replaced Flutter's stock placeholder: a 1×1 transparent PNG on a hardcoded
white background, which produced a full-brightness white flash on every cold
start (worst on a dark-mode OLED phone) and made `flutter build ipa` warn
"Launch image is set to the default placeholder icon". See the generator's
header comment for the full rationale.
