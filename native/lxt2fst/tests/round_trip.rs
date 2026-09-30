// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Round-trip integration tests for the lxt2fst converter.
//
// These tests run the public `convert(...)` API against every committed
// legacy fixture under `wavecrux/test/fixtures/legacy/` and assert:
//
//   1. Structural conversion succeeds (or surfaces a clean error for
//      the LXT-classic stub).
//   2. The generated FST is parseable by wellen.
//   3. The hierarchy in the converted FST matches the names embedded
//      in the source LXT2.
//
// Value-equivalence tests live under `#[ignore]` with explicit `reason:`
// strings until the per-facility value-change granule decoder lands;
// running them today would fail-not-because-of-the-bridge but because
// the converter is documented as emitting initial-only values. See
// `native/lxt2fst/README.md` §Status.

use std::path::PathBuf;

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../test/fixtures/legacy")
        .join(name)
}

fn tmp_fst(name: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("lxt2fst_roundtrip_{name}.fst"));
    let _ = std::fs::remove_file(&p);
    p
}

#[test]
fn simple_counter_lxt2_structural_round_trip() {
    let src = fixture("simple_counter.lxt2");
    let dst = tmp_fst("simple_counter");

    let mut progress_calls: Vec<(u64, u64)> = Vec::new();
    let mut cb = |d, t| progress_calls.push((d, t));
    lxt2fst::convert(&src, &dst, Some(&mut cb)).expect("conversion succeeds");

    // Progress must end at (N, N).
    let last = *progress_calls.last().expect("at least one tick");
    assert_eq!(last.0, last.1, "progress finishes at total");

    // wellen must read the FST back. We assert the hierarchy contents
    // since the value-change decoder is intentionally incomplete.
    let wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let names: Vec<String> = h.all_vars().map(|v| v.name(h).to_string()).collect();
    assert!(
        names.contains(&"clk".to_string()),
        "clk missing in {names:?}"
    );
    assert!(
        names.contains(&"count".to_string()),
        "count missing in {names:?}"
    );
}

#[test]
fn multi_scope_lxt2_hierarchy_preserved() {
    let src = fixture("multi_scope.lxt2");
    let dst = tmp_fst("multi_scope");
    lxt2fst::convert(&src, &dst, None).expect("conversion succeeds");

    let wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let scope_names: Vec<String> = h.all_scopes().map(|s| s.name(h).to_string()).collect();
    assert!(
        scope_names.contains(&"top".to_string()),
        "top missing in {scope_names:?}"
    );
    // multi_scope nests top.cpu.alu, top.cpu.regfile.
    assert!(
        scope_names.contains(&"cpu".to_string()),
        "cpu missing in {scope_names:?}"
    );
    assert!(
        scope_names.contains(&"alu".to_string()),
        "alu missing in {scope_names:?}"
    );
    assert!(
        scope_names.contains(&"regfile".to_string()),
        "regfile missing in {scope_names:?}"
    );
}

#[test]
fn large_sample_lxt2_walks_all_blocks_with_progress() {
    let src = fixture("large_sample.lxt2");
    let dst = tmp_fst("large_sample");
    let mut ticks: Vec<(u64, u64)> = Vec::new();
    let mut cb = |d, t| ticks.push((d, t));
    lxt2fst::convert(&src, &dst, Some(&mut cb)).expect("conversion succeeds");

    // Progress must monotonically increase and reach (total, total).
    assert!(ticks.len() >= 2, "expected multiple progress ticks");
    let mut last = 0u64;
    for (d, _t) in &ticks {
        assert!(*d >= last, "progress non-monotonic: {ticks:?}");
        last = *d;
    }
    let (final_d, final_t) = ticks.last().copied().unwrap();
    assert_eq!(final_d, final_t, "progress finishes at total");
    assert_eq!(final_t, 5, "large_sample has 5 blocks");
}

#[test]
fn vector_signals_lxt2_recognizes_real_and_vector_geometry() {
    let src = fixture("vector_signals.lxt2");
    let dst = tmp_fst("vector_signals");
    lxt2fst::convert(&src, &dst, None).expect("conversion succeeds");

    let wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let names: Vec<String> = h.all_vars().map(|v| v.name(h).to_string()).collect();
    assert!(names.contains(&"bus32".to_string()), "bus32 missing");
    assert!(names.contains(&"bus64".to_string()), "bus64 missing");
    assert!(names.contains(&"voltage".to_string()), "voltage missing");
}

#[test]
fn string_values_lxt2_emits_string_facilities_as_variable_length() {
    let src = fixture("string_values.lxt2");
    let dst = tmp_fst("string_values");
    lxt2fst::convert(&src, &dst, None).expect("conversion succeeds");

    let wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let names: Vec<String> = h.all_vars().map(|v| v.name(h).to_string()).collect();
    assert!(names.contains(&"state".to_string()), "state missing");
    assert!(names.contains(&"msg".to_string()), "msg missing");
    assert!(names.contains(&"code".to_string()), "code missing");
}

#[test]
fn lxt_classic_structural_round_trip() {
    let src = fixture("simple_counter.lxt");
    let dst = tmp_fst("simple_counter_classic");

    let mut progress_calls: Vec<(u64, u64)> = Vec::new();
    let mut cb = |d, t| progress_calls.push((d, t));
    // The LXT-classic decoder now mirrors the LXT2 path: it decodes the
    // file structure and emits an FST carrying the full hierarchy plus
    // initial values. Per-facility value-change granules remain the
    // shared follow-up (see the ignored test below).
    lxt2fst::convert(&src, &dst, Some(&mut cb)).expect("conversion succeeds");

    // Progress must end at (N, N).
    let last = *progress_calls.last().expect("at least one tick");
    assert_eq!(last.0, last.1, "progress finishes at total");

    // wellen must read the FST back. We assert the hierarchy contents
    // since the value-change decoder is intentionally incomplete.
    let wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let names: Vec<String> = h.all_vars().map(|v| v.name(h).to_string()).collect();
    assert!(
        names.contains(&"clk".to_string()),
        "clk missing in {names:?}"
    );
    assert!(
        names.contains(&"count".to_string()),
        "count missing in {names:?}"
    );
    let scope_names: Vec<String> = h.all_scopes().map(|s| s.name(h).to_string()).collect();
    assert!(
        scope_names.contains(&"top".to_string()),
        "top scope missing in {scope_names:?}"
    );
}

/// The web build converts through `convert_bytes` (no filesystem on wasm32);
/// desktop and mobile go through the path-based `convert`. Both must produce
/// the same FST, so every value-equivalence test below covers the web path
/// too.
#[test]
fn convert_bytes_matches_path_conversion_for_every_fixture() {
    for name in [
        "simple_counter.lxt2",
        "simple_counter.lxt",
        "multi_scope.lxt2",
        "vector_signals.lxt2",
        "string_values.lxt2",
        "large_sample.lxt2",
    ] {
        let src = fixture(name);
        let dst = tmp_fst(&format!("bytes_vs_path_{name}"));
        lxt2fst::convert(&src, &dst, None).expect("path conversion succeeds");
        let on_disk = std::fs::read(&dst).unwrap();

        let input = std::fs::read(&src).unwrap();
        let mut ticks: Vec<(u64, u64)> = Vec::new();
        let mut cb = |d, t| ticks.push((d, t));
        let in_memory =
            lxt2fst::convert_bytes(&input, Some(&mut cb)).expect("byte conversion succeeds");

        assert_eq!(in_memory, on_disk, "{name}: FST bytes differ");
        let (done, total) = *ticks.last().expect("at least one tick");
        assert_eq!(done, total, "{name}: progress finishes at total");
    }
}

#[test]
fn convert_bytes_rejects_non_legacy_input_without_output() {
    assert_eq!(
        lxt2fst::convert_bytes(b"$timescale 1ns $end", None),
        Err(lxt2fst::error::ConvertError::MagicMismatch)
    );
}

#[test]
fn magic_byte_probe_routes_correctly() {
    let lxt2 = std::fs::read(fixture("simple_counter.lxt2")).unwrap();
    assert_eq!(
        lxt2fst::detect_format(&lxt2[..4]),
        lxt2fst::LegacyFormat::Lxt2
    );

    let lxt = std::fs::read(fixture("simple_counter.lxt")).unwrap();
    assert_eq!(
        lxt2fst::detect_format(&lxt[..4]),
        lxt2fst::LegacyFormat::Lxt
    );

    let junk = [0xCA, 0xFE, 0xBA, 0xBE];
    assert_eq!(
        lxt2fst::detect_format(&junk),
        lxt2fst::LegacyFormat::Unknown
    );

    // Truncated probe is Unknown, not a panic.
    assert_eq!(
        lxt2fst::detect_format(&[0x13]),
        lxt2fst::LegacyFormat::Unknown
    );
    assert_eq!(lxt2fst::detect_format(&[]), lxt2fst::LegacyFormat::Unknown);
}

/// Read a signal's value changes as `(time, bit-string)` pairs.
fn read_changes(wf: &wellen::simple::Waveform, name: &str) -> Vec<(u64, String)> {
    let h = wf.hierarchy();
    let var = h
        .all_vars()
        .find(|v| v.name(h) == name)
        .unwrap_or_else(|| panic!("var {name} not found"));
    let sig = wf.get_signal(var.signal_ref()).expect("signal loaded");
    let tt = wf.time_table();
    sig.iter_changes()
        .map(|(idx, v)| {
            (
                tt[idx as usize],
                v.to_bit_string().expect("bit-vector value"),
            )
        })
        .collect()
}

#[test]
fn simple_counter_lxt2_value_equivalence() {
    let src = fixture("simple_counter.lxt2");
    let dst = tmp_fst("simple_counter_values");
    lxt2fst::convert(&src, &dst, None).expect("conversion succeeds");

    let mut wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let refs: Vec<_> = h
        .all_vars()
        .filter(|v| v.name(h) == "clk" || v.name(h) == "count")
        .map(|v| v.signal_ref())
        .collect();
    wf.load_signals(&refs);

    // clk toggles 0/1 every 10 ns over t=0..490 (50 changes).
    let clk = read_changes(&wf, "clk");
    assert_eq!(clk.len(), 50, "clk change count");
    for (i, (t, val)) in clk.iter().enumerate() {
        assert_eq!(*t, i as u64 * 10);
        assert_eq!(val, if i % 2 == 0 { "0" } else { "1" }, "clk@{t}");
    }

    // count increments 0x00..0x31 over the same window (8-bit, 50 changes).
    let count = read_changes(&wf, "count");
    assert_eq!(count.len(), 50, "count change count");
    for (i, (t, val)) in count.iter().enumerate() {
        assert_eq!(*t, i as u64 * 10);
        assert_eq!(val, &format!("{i:08b}"), "count@{t}");
    }
}

#[test]
fn multi_scope_lxt2_value_equivalence() {
    let src = fixture("multi_scope.lxt2");
    let dst = tmp_fst("multi_scope_values");
    lxt2fst::convert(&src, &dst, None).expect("conversion succeeds");

    let mut wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let refs: Vec<_> = h.all_vars().map(|v| v.signal_ref()).collect();
    wf.load_signals(&refs);

    // 16-bit ALU result: 0x0000 @0, 0x00FF @30, 0x1234 @50, 0xFFFF @90.
    let result = read_changes(&wf, "result");
    assert_eq!(
        result,
        vec![
            (0, "0000000000000000".to_string()),
            (30, "0000000011111111".to_string()),
            (50, "0001001000110100".to_string()),
            (90, "1111111111111111".to_string()),
        ]
    );
    // 32-bit regfile r0: 0 @0, 0xDEADBEEF @40, 0x1 @70.
    let r0 = read_changes(&wf, "r0");
    assert_eq!(
        r0,
        vec![
            (0, "00000000000000000000000000000000".to_string()),
            (40, "11011110101011011011111011101111".to_string()),
            (70, "00000000000000000000000000000001".to_string()),
        ]
    );
}

#[test]
fn vector_signals_lxt2_value_equivalence() {
    let src = fixture("vector_signals.lxt2");
    let dst = tmp_fst("vector_signals_values");
    lxt2fst::convert(&src, &dst, None).expect("conversion succeeds");

    let mut wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let refs: Vec<_> = h.all_vars().map(|v| v.signal_ref()).collect();
    wf.load_signals(&refs);

    // 32-bit bus with x/z states preserved per bit.
    let xz32 = read_changes(&wf, "xz32");
    assert_eq!(xz32[0], (0, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx".to_string()));
    assert_eq!(
        xz32[1],
        (10, "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz".to_string())
    );
    assert_eq!(
        xz32[2],
        (20, "x0x0x0x0x0x0x0x0x0x0x0x0x0x0x0x0".to_string())
    );

    // Real-valued facility: voltage = 1.8, 3.3, -1.2, 0.0 (read as f64).
    let h = wf.hierarchy();
    let voltage_ref = h
        .all_vars()
        .find(|v| v.name(h) == "voltage")
        .unwrap()
        .signal_ref();
    let sig = wf.get_signal(voltage_ref).expect("voltage loaded");
    let tt = wf.time_table();
    let reals: Vec<(u64, f64)> = sig
        .iter_changes()
        .filter_map(|(idx, v)| match v {
            wellen::SignalValueRef::Real(r) => Some((tt[idx as usize], r)),
            _ => None,
        })
        .collect();
    let expected = [(0u64, 1.8f64), (20, 3.3), (40, -1.2), (60, 0.0)];
    assert_eq!(reals.len(), expected.len(), "voltage change count");
    for ((t, got), (et, want)) in reals.iter().zip(expected.iter()) {
        assert_eq!(t, et);
        assert!((got - want).abs() < 1e-9, "voltage@{t}: {got} vs {want}");
    }
}

#[test]
fn lxt_classic_value_equivalence_post_decoder() {
    // The LXT-classic *streaming* value-change decoder (`lxt_value_decode`,
    // differentially fuzz-validated against `vcd2lxt`) now emits the real
    // per-facility transitions. This asserts byte-equality of transitions
    // against the same ground truth as the LXT2 path
    // (`simple_counter_lxt2_value_equivalence`): clk toggles 0/1 every 10 ns
    // over t=0..490, count increments 0x00..0x31.
    let src = fixture("simple_counter.lxt");
    let dst = tmp_fst("simple_counter_classic_values");
    lxt2fst::convert(&src, &dst, None).expect("conversion succeeds");

    let mut wf = wellen::simple::read(dst.to_str().unwrap()).expect("wellen reads converted FST");
    let h = wf.hierarchy();
    let refs: Vec<_> = h
        .all_vars()
        .filter(|v| v.name(h) == "clk" || v.name(h) == "count")
        .map(|v| v.signal_ref())
        .collect();
    wf.load_signals(&refs);

    let clk = read_changes(&wf, "clk");
    assert_eq!(clk.len(), 50, "clk change count");
    for (i, (t, val)) in clk.iter().enumerate() {
        assert_eq!(*t, i as u64 * 10);
        assert_eq!(val, if i % 2 == 0 { "0" } else { "1" }, "clk@{t}");
    }

    let count = read_changes(&wf, "count");
    assert_eq!(count.len(), 50, "count change count");
    for (i, (t, val)) in count.iter().enumerate() {
        assert_eq!(*t, i as u64 * 10);
        assert_eq!(val, &format!("{i:08b}"), "count@{t}");
    }
}
