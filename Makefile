.PHONY: web web-release web-profile bootstrap native analyze test clean gen

# ── Web builds ────────────────────────────────────────────────────────────────
# CanvasKit is required for CustomPainter performance (waveform canvas) and is
# the default renderer for `flutter build web`. The old `--web-renderer
# canvaskit` flag was removed in Flutter 3.44.x, so it is no longer passed
# (passing it fails the build). The HTML renderer is not supported for wavecrux.

web:
	flutter build web

web-release:
	flutter build web --release

web-profile:
	flutter build web --profile

# ── Setup ─────────────────────────────────────────────────────────────────────
# Everything a fresh clone lacks before `flutter analyze` and `flutter test`
# pass. None of it is committed:
#
#   native     the wellen FFI library, which every test that opens a waveform
#              loads (without it those suites skip, naming this step)
#   gen        the Riverpod `*.g.dart` parts, without which nothing compiles
#   wavecrux_ctl's packages, because the root analyzer reads that tool's
#              analysis_options.yaml and must resolve its `include:`
#   the web fixture bundle, which an integration test imports
#
# Every step is a quick no-op once its output is current, so `analyze` and
# `test` run it each time instead of trusting that it was done.

bootstrap: native gen
	dart pub get --directory tool/wavecrux_ctl
	dart run tool/generate_web_fixture_bundle.dart

native:
	cd native/wellen_ffi && cargo build --release

# ── Code generation ───────────────────────────────────────────────────────────

gen:
	flutter pub get
	dart run build_runner build --delete-conflicting-outputs

# ── Quality gates ─────────────────────────────────────────────────────────────

analyze: bootstrap
	flutter analyze --fatal-infos --fatal-warnings

test: bootstrap
	flutter test

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	flutter clean
	cd native/wellen_ffi && cargo clean
