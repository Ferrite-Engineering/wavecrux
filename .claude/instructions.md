# WaveCrux Localization Guidelines

**Suite scope:** This file is the canonical CJK house style for the entire Crux suite (WaveCrux, NetCrux, LintCrux, SimCrux — core and Pro overlays). Sibling repos carry adapted copies (`.claude/instructions.md` + `assets/l10n/glossary.json`) that keep the Core Principles, Placeholder Rules, Formatting Rules, Language-Specific Rules, and Prohibited Patterns verbatim, swap in an app-specific glossary, and must not contradict the Suite-Wide Terms table below. Suite-wide terms render identically in every app.

## Core Principles

1. **Precision over politeness** – Users are EDA professionals. Technical accuracy trumps marketing fluff.
2. **Conciseness** – UI space is limited. Keep buttons short; tooltips can be longer.
3. **Consistency** – Same English term → same translation everywhere in a given language.
4. **Preserve placeholders** – Never break ICU MessageFormat syntax.

## Glossary (Mandatory Mappings)

| English | zh-CN | ja | ko |
|---------|-------|-----|-----|
| waveform | 波形 | 波形 | 파형 |
| signal | 信号 | 信号 | 신호 |
| transition (edge change) | 跳变 | トランジション | 트랜지션 |
| conversion (format) | 转换 | 変換 | 변환 |
| group (signal group) | 组 | グループ | 그룹 |
| comment (annotation) | 注释 | コメント | 주석 |
| lane (signal row) | 信号行 | 信号行 | 신호 행 |
| decoder | 解码器 | デコーダー | 디코더 |
| glitch | 毛刺 | グリッチ | 글리치 |
| glitch point | 毛刺点 | グリッチ箇所 | 글리치 지점 |
| toggle rate | 翻转率 | トグルレート | 토글 레이트 |
| stuck at reset | 复位卡住 | リセットから復帰せず | 리셋 후 멈춤 |
| process filter | 外部命令过滤 | プロセスフィルタ | 프로세스 필터 |
| translate filter | 翻译过滤器 | 翻訳フィルタ | 번역 필터 |
| scope (hierarchy) | 作用域 | スコープ | 스코프 |
| scope (time range) | 范围 | 範囲 | 범위 |
| panel (UI container) | 面板 | パネル | 패널 |
| pane (split window) | 窗格 | ペイン | 창 |
| cursor | 光标 | カーソル | 커서 |
| marker | 标记 | マーカー | 마커 |
| hierarchy depth | 层次深度 | 階層の深さ | 계층 깊이 |
| timescale | 时间刻度 | タイムスケール | 타임스케일 |

## Suite-Wide Terms (identical in every Crux app)

These concepts appear in more than one Crux app (CXP, shared chrome, settings). Every app — core and Pro overlay — must use exactly these renderings. App-local glossaries may add terms but may never override this table.

| English | zh-CN | ja | ko |
|---------|-------|-----|-----|
| cross-probe / cross-probing | 交叉探测 | クロスプローブ | 교차 프로브 |
| Remote Control (settings section) | 远程控制 | リモートコントロール | 원격 제어 |
| waiver / waive | 豁免 | ウェイバー | 면제 |
| workspace | 工作区 | ワークスペース | 워크스페이스 |
| preset | 预设 | プリセット | 프리셋 |
| editor | 编辑器 | エディター | 에디터 |
| viewer | 查看器 | ビューアー | 뷰어 |
| open-core (edition name) | 开放核心版 | オープンコア | 오픈 코어 |
| command palette | 命令面板 | コマンドパレット | 명령 팔레트 |
| panel | 面板 | パネル | 패널 |
| pane | 窗格 | ペイン | 창 |
| custom (adjective) | 自定义 | カスタム | 사용자 정의 (never 사용자 지정) |
| clock (noun) | 时钟 | クロック | 클럭 (never 클록) |

Note: 开放核心版, never 开源核心版 — "open-core" names the edition, not a licence: the core is open source, but the Pro and Enterprise editions built on it are not.

## Acronyms (Never Translate)

VCD, FST, GHW, LXT, LXT2, FSDB, PCAP, CSV, JSON, XML, YAML, HTML, SVG, PNG, RGB, LED, LCD, OLED, FSM, RTL, API, SDK, ABI, CLI, GUI, WASM, TCP, UDP, HTTP, JSON-RPC, CXP, WCP

**Protocol/Interface names (never translate):**
SPI, I2C, I²C, UART, AXI, AXI4, AXI4-Lite, APB, AHB, AHB-Lite, Wishbone, JTAG, MDIO, CAN, CAN-FD, USB, PCIe, Ethernet, MII, RMII, GMII, RGMII, AXIS, RISC-V, RV32, RV64, Cocotb, GTKWave, Synopsys

**Tools/commands (never translate):**
fsdb2vcd, vcd2fst, xml2stems, vermin, dlopen, LoadLibrary, make, cmake

**Product / brand names (never translate):**
WaveCrux, NetCrux, LintCrux, SimCrux, EDACrux, Ferrite Engineering, Stage, Stage Pro, Rive, Yosys, Verible, Verilator, svlint, GHDL, Icarus Verilog, FuseSoC, Vivado, Quartus

"Stage" is the WaveCrux Stage brand and stays in Latin script everywhere (never 舞台 / ステージ / 스테이지). Legacy translated occurrences are defects to sweep.

## Placeholder Rules (ICU MessageFormat)

All plural placeholders MUST include both `=1` and `other` cases:

Correct:
"{count, plural, =1{1 signal} other{{count} signals}}"

Incorrect (missing =1 case):
"{count, plural, other{{count} signals}}"

For Chinese, Japanese, Korean (no grammatical number), use:

zh-CN:
"{count, plural, =1{1个信号} other{{count}个信号}}"

ja:
"{count, plural, =1{1 信号} other{{count} 信号}}"

ko:
"{count, plural, =1{1개 신호} other{{count}개 신호}}"

## Formatting Rules

### Ellipsis (…)
- All languages: No space before … (U+2026)
- Use single character …, not three dots

### Units
- Use localized unit symbols where standard: ms, ns, μs, MB, GB, Hz, kHz, MHz, GHz, FPS
- For frequency: {freq} Hz, {freq} MHz (keep space before unit in all languages)

### Symbols
- Δ (delta) → keep as Δ
- f (frequency) → keep as f (lowercase)
- × (multiply) → use ×, not x or *

## Language-Specific Rules

### Chinese (zh-CN)
- Use Simplified Chinese only
- 跳变 = signal edge transition; 转换 = format conversion
- 注释 = comment (never 评论)
- 显示 = show/display; 隐藏 = hide
- 无法 = cannot/failed; 失败 = failed
- Prefer 4-character phrases where natural (节省空间)

### Japanese (ja)
- **signal = 信号, never シグナル** (resolves the old kanji-vs-katakana ambiguity; the glossary previously said シグナル, actual usage was majority 信号, and 信号 is what JP EDA documentation uses). Sweep legacy シグナル occurrences.
- **Long-vowel (ー) forms for -er/-or katakana loanwords** (generalizing the デコーダー rule): デコーダー、インスペクター、エディター、ビューアー (not ビューワー)、サーバー、フォルダー、ドライバー、ワイヤー、シミュレーター. Short forms are defects.
- Use デコーダー consistently (not デコーダ)
- 表示中の = "visible" (e.g., 表示中のトランジション)
- 履歴 = "recent files history" (shorter than 最近のファイル)
- できません = polite negative; 失敗 = failure
- Never use あなた; use passive or drop subject
- Use kanji for common terms, katakana for technical imports

### Korean (ko)
- Use 10진수 (with Arabic numeral) for decimal
- 토글 레이트 > 토글 속도 for "toggle rate"
- 글리치 지점 > 글리치 포인트 for "glitch points"
- No space before … (U+2026) – fix all instances
- Use subject-drop where natural
- Use native Korean words over Sino-Korean when shorter

## Prohibited Patterns (All Languages)

- Never translate version numbers (v0.1.0 stays as-is)
- Never translate placeholder variable names ({count}, {filename}, {reason})
- Never translate help/documentation URLs (docs.wavecrux.app)
- Never translate license names (MIT, BSD-3-Clause)
- Never translate company names (Ferrite Engineering)
- Never translate brand/trademark disclaimers except for localization (keep original company names)

## Button Label Length Targets

| Language | Max chars for primary button | Max chars for tooltip |
|----------|------------------------------|----------------------|
| zh-CN | 8 | unlimited |
| ja | 10 | unlimited |
| ko | 8 | unlimited |

Example shortening:
- "Generate & Open in New Tab" → zh: "生成并打开", ja: "生成して開く", ko: "생성 후 열기"
- "Remove from recent files" → zh: "移除", ja: "削除", ko: "제거" (tooltip explains)

## Quality Checklist

Before outputting any ARB translation:
- [ ] All plural placeholders have `=1` case
- [ ] Acronyms are untouched
- [ ] URLs unchanged
- [ ] No English leftover (except acronyms)
- [ ] Consistent with glossary
- [ ] Button labels reasonably short