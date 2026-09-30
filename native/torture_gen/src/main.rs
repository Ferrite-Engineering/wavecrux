// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

//! WaveCrux torture-file generator.
//!
//! Emits a synthetic waveform (VCD or FST) with a controllable signal count,
//! transition density, and hierarchy shape — for performance/scale benchmarks
//! and parser fuzzing. Replaces the slow Dart generator (this is disk-bound,
//! ~100x faster), so multi-GB captures are practical.
//!
//! Output content is byte-stable for a given (--seed, --signals, --transitions,
//! --depth, --branching): the perf baseline uses a fixed seed so numbers are
//! comparable. `--random` picks a fresh seed each run (and prints it, so a
//! fuzz failure is reproducible) for robustness/variety coverage.
//!
//! Examples:
//!   torture_gen --signals 2000 --target-size-mb 700 --format fst --out big.fst
//!   torture_gen --random --target-size-mb 50 --out fuzz.vcd
//!   torture_gen --help

use std::io::{BufWriter, Write};
use std::time::Instant;

use clap::{Parser, ValueEnum};
use fst_writer::{
    open_fst, FstFileType, FstInfo, FstScopeType, FstSignalId, FstSignalType, FstVarDirection,
    FstVarType,
};
use rand::seq::SliceRandom;
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;

/// VCD bytes/transition is ~12 (empirically); used to map --target-size-mb to a
/// transition count. FST is more compact, so a target produces a smaller FST.
const VCD_BYTES_PER_TRANSITION: f64 = 12.0;

#[derive(Copy, Clone, PartialEq, Eq, ValueEnum)]
enum Format {
    Vcd,
    Fst,
}

#[derive(Parser)]
#[command(
    name = "torture_gen",
    about = "Synthetic VCD/FST waveform generator for WaveCrux perf + fuzz."
)]
struct Args {
    /// Number of signals (variables).
    #[arg(long, default_value_t = 1000)]
    signals: usize,
    /// Total value changes across all signals. Overrides --target-size-mb.
    #[arg(long)]
    transitions: Option<u64>,
    /// Approximate output size in MB (VCD-calibrated). Ignored if --transitions
    /// is given.
    #[arg(long)]
    target_size_mb: Option<f64>,
    /// Scope-tree depth.
    #[arg(long, default_value_t = 3)]
    depth: usize,
    /// Scope children per node.
    #[arg(long, default_value_t = 3)]
    branching: usize,
    /// PRNG seed for byte-stable output (perf baseline uses a fixed seed).
    #[arg(long, default_value_t = 42)]
    seed: u64,
    /// Pick a fresh random seed (printed) instead of --seed — for fuzz/variety.
    #[arg(long, default_value_t = false)]
    random: bool,
    /// Output format.
    #[arg(long, value_enum, default_value_t = Format::Vcd)]
    format: Format,
    /// Output path.
    #[arg(long, default_value = "build/perf/fixtures/synth.vcd")]
    out: String,
    /// Timescale as a power of ten (e.g. -9 = 1 ns, -12 = 1 ps).
    #[arg(long, default_value_t = -9)]
    timescale_exp: i8,
    /// Quantize event times to multiples of this many ticks (e.g. with
    /// --timescale-exp -12 and --tick-quantum 50, events land on a 50 ps
    /// grid). Default 1 (no quantization).
    #[arg(long, default_value_t = 1)]
    tick_quantum: u64,
    /// Stretch the time axis so the dump spans (approximately) this many
    /// ticks. Default: derived from the hottest signal (legacy behavior).
    #[arg(long)]
    span_ticks: Option<u64>,
}

fn timescale_vcd(exp: i8) -> String {
    match exp {
        0 => "1 s".into(),
        -3 => "1 ms".into(),
        -6 => "1 us".into(),
        -9 => "1 ns".into(),
        -12 => "1 ps".into(),
        -15 => "1 fs".into(),
        e => panic!("unsupported timescale exponent {e} (use a multiple of 3)"),
    }
}

const ID_CHARS: &[u8] =
    b"!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

struct Variable {
    width: u32,
    name: String,
    scope_idx: usize,
    vcd_id: String,
}

struct Scope {
    name: String,
    children: Vec<usize>,
}

fn vcd_id(i: usize) -> String {
    let n = ID_CHARS.len();
    if i < n {
        return (ID_CHARS[i] as char).to_string();
    }
    let mut buf = Vec::new();
    let mut i = i;
    loop {
        buf.push(ID_CHARS[i % n]);
        let next = i / n;
        if next == 0 {
            break;
        }
        i = next - 1;
    }
    String::from_utf8(buf).unwrap()
}

/// Pre-order scope tree of the requested depth/branching. Returns (scopes,
/// leaf_indices).
fn build_scopes(depth: usize, branching: usize) -> (Vec<Scope>, Vec<usize>) {
    let mut scopes = vec![Scope {
        name: "tb".to_string(),
        children: vec![],
    }];
    fn grow(scopes: &mut Vec<Scope>, parent: usize, remaining: usize, branching: usize) {
        if remaining == 0 {
            return;
        }
        for i in 0..branching {
            let idx = scopes.len();
            scopes.push(Scope {
                name: format!("blk{i}"),
                children: vec![],
            });
            scopes[parent].children.push(idx);
            grow(scopes, idx, remaining - 1, branching);
        }
    }
    grow(&mut scopes, 0, depth, branching);
    let leaves: Vec<usize> = (0..scopes.len())
        .filter(|&i| scopes[i].children.is_empty())
        .collect();
    (scopes, leaves)
}

/// Power-law-ish: 5% of signals carry 50% of transitions (busy clocks + a quiet
/// long tail). Returns per-signal transition counts.
fn distribute_transitions(total: u64, signals: usize, rng: &mut ChaCha8Rng) -> Vec<u64> {
    let hot_count = ((signals as f64 * 0.05).round() as usize).max(1);
    let hot_share = (total as f64 * 0.5).round() as u64;
    let cold_share = total.saturating_sub(hot_share);
    let cold_each = (cold_share / (signals.saturating_sub(hot_count).max(1)) as u64).max(1);

    let mut indices: Vec<usize> = (0..signals).collect();
    indices.shuffle(rng);
    let mut is_hot = vec![false; signals];
    for &i in indices.iter().take(hot_count) {
        is_hot[i] = true;
    }

    let mut counts = vec![0u64; signals];
    let per_hot = (hot_share / hot_count as u64).max(1);
    let mut assigned: i128 = 0;
    for i in 0..signals {
        counts[i] = if is_hot[i] { per_hot } else { cold_each };
        assigned += counts[i] as i128;
    }
    let drift = total as i128 - assigned;
    if let Some(&first_hot) = indices.first() {
        counts[first_hot] = (counts[first_hot] as i128 + drift).max(0) as u64;
    }
    counts
}

fn mask_for(width: u32) -> u64 {
    if width >= 64 {
        u64::MAX
    } else {
        (1u64 << width) - 1
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    let seed = if args.random {
        let s = rand::rngs::OsRng.gen::<u64>();
        eprintln!("torture_gen: --random seed = {s} (rerun with --seed {s} to reproduce)");
        s
    } else {
        args.seed
    };

    let transitions = match (args.transitions, args.target_size_mb) {
        (Some(t), _) => t,
        (None, Some(mb)) => (mb * 1024.0 * 1024.0 / VCD_BYTES_PER_TRANSITION) as u64,
        (None, None) => 500_000,
    };

    let start = Instant::now();
    let mut rng = ChaCha8Rng::seed_from_u64(seed);

    let (scopes, leaves) = build_scopes(args.depth, args.branching);

    // Width mix: 60% scalar, 25% 8-bit, 10% 32-bit, 5% 64-bit.
    let mut variables = Vec::with_capacity(args.signals);
    for i in 0..args.signals {
        let roll: f64 = rng.gen();
        let width = if roll < 0.60 {
            1
        } else if roll < 0.85 {
            8
        } else if roll < 0.95 {
            32
        } else {
            64
        };
        variables.push(Variable {
            width,
            name: format!("sig_{i}"),
            scope_idx: leaves[i % leaves.len()],
            vcd_id: vcd_id(i),
        });
    }

    let per_signal = distribute_transitions(transitions, args.signals, &mut rng);
    let seeds: Vec<u64> = (0..args.signals).map(|_| rng.gen()).collect();

    let out = std::path::Path::new(&args.out);
    if let Some(p) = out.parent() {
        std::fs::create_dir_all(p)?;
    }

    // Internal event grid: span/quantum grid points stretched across the
    // requested span (events land on multiples of --tick-quantum).
    let grid_max = args.span_ticks.map(|s| (s / args.tick_quantum).max(1));

    match args.format {
        Format::Vcd => write_vcd(&args, &scopes, &variables, &per_signal, &seeds, grid_max)?,
        Format::Fst => write_fst(&args, &scopes, &variables, &per_signal, &seeds, grid_max)?,
    }

    let size = std::fs::metadata(out)?.len();
    println!(
        "{}: {:.1} MB, {} signals, {} transitions, depth={} branching={}, format={}, seed={}, wrote in {} ms",
        args.out,
        size as f64 / (1024.0 * 1024.0),
        args.signals,
        transitions,
        args.depth,
        args.branching,
        match args.format { Format::Vcd => "vcd", Format::Fst => "fst" },
        seed,
        start.elapsed().as_millis(),
    );
    Ok(())
}

/// Drives the time-ordered event stream (min-heap merge of per-signal
/// cadences), invoking `emit(time, idx, value, width)` per change. Shared by
/// both writers so VCD and FST of the same params carry identical content.
fn drive_events<F: FnMut(u64, usize, u64, u32) -> std::io::Result<()>>(
    variables: &[Variable],
    per_signal: &[u64],
    seeds: &[u64],
    grid_max: Option<u64>,
    quantum: u64,
    mut emit: F,
) -> std::io::Result<()> {
    use std::cmp::Reverse;
    use std::collections::BinaryHeap;

    let hottest = per_signal.iter().copied().max().unwrap_or(0);
    let time_max = grid_max.unwrap_or_else(|| hottest.saturating_mul(2)).max(1);

    let mut step = vec![1u64; variables.len()];
    let mut remaining = vec![0u64; variables.len()];
    for i in 0..variables.len() {
        let n = per_signal[i];
        if n == 0 {
            continue;
        }
        step[i] = (time_max / n).max(1);
        remaining[i] = n;
    }

    let mut cur = vec![0u64; variables.len()];
    let mut heap: BinaryHeap<Reverse<(u64, usize)>> = BinaryHeap::new();
    for i in 0..variables.len() {
        if remaining[i] > 0 {
            heap.push(Reverse((0, i)));
        }
    }

    while let Some(Reverse((t, idx))) = heap.pop() {
        let v = &variables[idx];
        let value = if v.width == 1 {
            cur[idx] ^= 1;
            cur[idx]
        } else {
            let mask = mask_for(v.width);
            let next = (cur[idx]
                .wrapping_mul(6364136223846793005)
                .wrapping_add(seeds[idx])
                | 1)
                & mask;
            cur[idx] = next;
            next
        };
        emit(t.saturating_mul(quantum), idx, value, v.width)?;
        remaining[idx] -= 1;
        if remaining[idx] > 0 {
            heap.push(Reverse((t + step[idx], idx)));
        }
    }
    Ok(())
}

fn write_vcd(
    args: &Args,
    scopes: &[Scope],
    variables: &[Variable],
    per_signal: &[u64],
    seeds: &[u64],
    grid_max: Option<u64>,
) -> std::io::Result<()> {
    let f = std::fs::File::create(&args.out)?;
    let mut w = BufWriter::with_capacity(1 << 20, f);

    writeln!(w, "$date\n  2026-01-01 00:00:00\n$end")?;
    writeln!(w, "$version\n  wavecrux torture_gen\n$end")?;
    writeln!(w, "$timescale {} $end", timescale_vcd(args.timescale_exp))?;

    let mut vars_in_scope: Vec<Vec<usize>> = vec![vec![]; scopes.len()];
    for (vi, v) in variables.iter().enumerate() {
        vars_in_scope[v.scope_idx].push(vi);
    }
    emit_vcd_scope(&mut w, 0, scopes, variables, &vars_in_scope)?;
    writeln!(w, "$enddefinitions $end")?;
    writeln!(w, "$dumpvars")?;
    for v in variables {
        if v.width == 1 {
            writeln!(w, "0{}", v.vcd_id)?;
        } else {
            writeln!(w, "b0 {}", v.vcd_id)?;
        }
    }
    writeln!(w, "$end")?;

    let mut last_time: i128 = -1;
    drive_events(variables, per_signal, seeds, grid_max, args.tick_quantum, |t, idx, value, width| {
        if t as i128 != last_time {
            writeln!(w, "#{t}")?;
            last_time = t as i128;
        }
        let v = &variables[idx];
        if width == 1 {
            writeln!(w, "{value}{}", v.vcd_id)
        } else {
            writeln!(w, "b{value:b} {}", v.vcd_id)
        }
    })?;
    w.flush()
}

fn emit_vcd_scope<W: Write>(
    w: &mut W,
    scope_idx: usize,
    scopes: &[Scope],
    variables: &[Variable],
    vars_in_scope: &[Vec<usize>],
) -> std::io::Result<()> {
    writeln!(w, "$scope module {} $end", scopes[scope_idx].name)?;
    for &vi in &vars_in_scope[scope_idx] {
        let v = &variables[vi];
        if v.width > 1 {
            writeln!(
                w,
                "$var wire {} {} {} [{}:0] $end",
                v.width,
                v.vcd_id,
                v.name,
                v.width - 1
            )?;
        } else {
            writeln!(w, "$var wire 1 {} {} $end", v.vcd_id, v.name)?;
        }
    }
    for &c in &scopes[scope_idx].children {
        emit_vcd_scope(w, c, scopes, variables, vars_in_scope)?;
    }
    writeln!(w, "$upscope $end")
}

fn write_fst(
    args: &Args,
    scopes: &[Scope],
    variables: &[Variable],
    per_signal: &[u64],
    seeds: &[u64],
    grid_max: Option<u64>,
) -> Result<(), Box<dyn std::error::Error>> {
    let info = FstInfo {
        start_time: 0,
        timescale_exponent: args.timescale_exp,
        version: "wavecrux torture_gen".to_string(),
        date: "2026-01-01".to_string(),
        file_type: FstFileType::Verilog,
    };
    let mut hdr = open_fst(&args.out, &info)?;

    let mut vars_in_scope: Vec<Vec<usize>> = vec![vec![]; scopes.len()];
    for (vi, v) in variables.iter().enumerate() {
        vars_in_scope[v.scope_idx].push(vi);
    }
    let mut fst_ids: Vec<Option<FstSignalId>> = vec![None; variables.len()];
    emit_fst_scope(&mut hdr, 0, scopes, variables, &vars_in_scope, &mut fst_ids)?;
    let mut body = hdr.finish()?;
    let fst_ids: Vec<FstSignalId> = fst_ids.into_iter().map(|o| o.unwrap()).collect();

    body.time_change(0)?;
    for (i, v) in variables.iter().enumerate() {
        let zero = vec![b'0'; v.width as usize];
        body.signal_change(fst_ids[i], &zero)?;
    }

    let mut last_time: i128 = 0;
    drive_events(variables, per_signal, seeds, grid_max, args.tick_quantum, |t, idx, value, width| {
        if t as i128 != last_time {
            body.time_change(t).map_err(to_io)?;
            last_time = t as i128;
        }
        let s = format!("{value:0width$b}", width = width as usize);
        body.signal_change(fst_ids[idx], s.as_bytes()).map_err(to_io)
    })?;
    body.finish()?;
    Ok(())
}

fn to_io<E: std::fmt::Display>(e: E) -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::Other, e.to_string())
}

fn emit_fst_scope<W: Write + std::io::Seek>(
    hdr: &mut fst_writer::FstHeaderWriter<W>,
    scope_idx: usize,
    scopes: &[Scope],
    variables: &[Variable],
    vars_in_scope: &[Vec<usize>],
    fst_ids: &mut [Option<FstSignalId>],
) -> Result<(), Box<dyn std::error::Error>> {
    hdr.scope(&scopes[scope_idx].name, "", FstScopeType::Module)?;
    for &vi in &vars_in_scope[scope_idx] {
        let v = &variables[vi];
        let id = hdr.var(
            &v.name,
            FstSignalType::bit_vec(v.width),
            FstVarType::Wire,
            FstVarDirection::Implicit,
            None,
        )?;
        fst_ids[vi] = Some(id);
    }
    for &c in &scopes[scope_idx].children {
        emit_fst_scope(hdr, c, scopes, variables, vars_in_scope, fst_ids)?;
    }
    hdr.up_scope()?;
    Ok(())
}
