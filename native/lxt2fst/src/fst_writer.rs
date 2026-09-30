// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// FST writer module.
//
// This crate depends on the `fst-writer` crate (BSD-3-Clause,
// same author as the `fst-reader` that wellen uses) rather than hand-
// roll an in-crate FST writer. Rationale is in `native/lxt2fst/README.md`
// §"Dependency choices".
//
// This module wraps `fst-writer` behind a small façade so the rest of
// the crate can write FST without coupling to the upstream API surface.
// If we ever need to swap to an in-crate writer (e.g., the dep drifts
// or the wasm bundle blows the 400 KiB budget under a future upgrade),
// only this file changes.
//
// The FST can land in a file (desktop/mobile, via the C ABI) or in memory
// (the web build, where wasm32 has no filesystem). Both go through the same
// serializer; the in-memory path relies on the vendored fst-writer's
// `FstHeaderWriter::new` (see native/vendor/fst-writer/Cargo.toml).

use std::io::{Seek, Write};
use std::path::Path;

/// Where [`FstWriter::finish`] puts the serialized FST.
pub enum FstOutput<'a> {
    /// A file, created (or truncated) only once the whole trace has been
    /// decoded — a conversion that fails early leaves nothing on disk.
    File(&'a Path),
    /// An in-memory buffer, replaced with the complete FST file body.
    Memory(&'a mut Vec<u8>),
}

/// What kind of FST signal a given facility maps to. Derived from
/// LXT2 geometry by `lxt2::convert_lxt2_to_fst`.
#[derive(Debug, Clone)]
pub enum FstSignalKind {
    /// Standard bit-vector wire / reg. `width = 1` is a scalar.
    Wire { width: u32 },
    /// Real-valued or string-valued (LXT2 flags=2). The FST format
    /// distinguishes these via `FstVarType::Real` / `FstVarType::String`
    /// in the hierarchy header; the value-change pipeline carries the
    /// raw payload bytes either way.
    VariableLength,
}

/// A single signal definition handed to the writer. The caller assigns
/// the handle (currently we use the LXT2 facility index 1:1, which is
/// guaranteed unique and stable across the file).
#[derive(Debug, Clone)]
pub struct FstSignalDef {
    pub handle: u32,
    /// Scope chain, root-first. E.g. ["top", "cpu", "alu"] for
    /// `top.cpu.alu.result`.
    pub scopes: Vec<String>,
    /// Leaf signal name (no scope prefix).
    pub leaf_name: String,
    pub kind: FstSignalKind,
}

/// Façade over the underlying FST writer. The concrete fst-writer API
/// types live behind `sink` and are not exported.
pub struct FstWriter {
    timescale_exp: i8,
    sink: Sink,
}

enum Sink {
    /// Buffers the hierarchy and value changes until `finish()` serializes
    /// them. Buffering lets us write a syntactically-valid FST even when the
    /// value-change decoder covers only part of a trace (the file still
    /// parses with wellen and shows the hierarchy), and it defers creating
    /// the output until the decode has succeeded.
    Buffered {
        defs: Vec<FstSignalDef>,
        events: Vec<TimedChange>,
    },
}

#[derive(Debug, Clone)]
struct TimedChange {
    handle: u32,
    time: u64,
    value: String,
}

impl FstWriter {
    /// Create a writer; the destination is chosen at [`FstWriter::finish`].
    /// `timescale_exp` is the signed base-10 exponent (e.g. -9 for ns).
    pub fn create(timescale_exp: i8) -> std::io::Result<Self> {
        Ok(Self {
            timescale_exp,
            sink: Sink::Buffered {
                defs: Vec::new(),
                events: Vec::new(),
            },
        })
    }

    /// Declare the full signal hierarchy. Must be called exactly once,
    /// before any `write_value_change` calls.
    pub fn write_hierarchy(&mut self, defs: &[FstSignalDef]) -> std::io::Result<()> {
        match &mut self.sink {
            Sink::Buffered { defs: d, .. } => {
                d.clear();
                d.extend_from_slice(defs);
                Ok(())
            }
        }
    }

    /// Record a value change for `handle` at `time`. `value` is the
    /// VCD-style ASCII representation:
    ///   * Bit-vectors: a string of '0'/'1'/'x'/'z' (no leading 'b').
    ///   * Reals: ASCII decimal (`"1.8"`, `"nan"`, …).
    ///   * Strings: the raw string body.
    pub fn write_value_change(
        &mut self,
        handle: u32,
        time: u64,
        value: &str,
    ) -> std::io::Result<()> {
        match &mut self.sink {
            Sink::Buffered { events, .. } => {
                events.push(TimedChange {
                    handle,
                    time,
                    value: value.to_string(),
                });
                Ok(())
            }
        }
    }

    /// Serialize the buffered hierarchy and events as a valid FST into
    /// `out`. The hierarchy is always written; the value-change region
    /// depends on what the legacy decoder provided.
    pub fn finish(self, out: FstOutput<'_>) -> std::io::Result<()> {
        let Sink::Buffered { defs, events } = self.sink;
        match out {
            FstOutput::File(path) => {
                let mut file = std::io::BufWriter::new(std::fs::File::create(path)?);
                write_with_fst_writer(&mut file, self.timescale_exp, &defs, &events)?;
                // An explicit flush surfaces a failed final write (disk full,
                // revoked sandbox access); dropping the BufWriter would
                // swallow it.
                file.flush()
            }
            FstOutput::Memory(buf) => {
                let mut cursor = std::io::Cursor::new(Vec::new());
                write_with_fst_writer(&mut cursor, self.timescale_exp, &defs, &events)?;
                *buf = cursor.into_inner();
                Ok(())
            }
        }
    }
}

/// Concrete adapter to the `fst-writer` crate. Isolated so callers don't
/// see upstream types. `out` must be positioned at the start of the stream.
fn write_with_fst_writer<W: Write + Seek>(
    out: W,
    timescale_exp: i8,
    defs: &[FstSignalDef],
    events: &[TimedChange],
) -> std::io::Result<()> {
    use fst_writer::{
        FstHeaderWriter, FstInfo, FstScopeType, FstSignalType, FstVarDirection, FstVarType,
    };

    let info = FstInfo {
        start_time: events.iter().map(|e| e.time).min().unwrap_or(0),
        timescale_exponent: timescale_exp,
        version: "lxt2fst 0.1.0".to_string(),
        date: String::new(),
        file_type: fst_writer::FstFileType::Verilog,
    };

    let mut hier = FstHeaderWriter::new(out, &info).map_err(io_err)?;

    // Sort defs so signals in the same scope are emitted contiguously —
    // FST's scope-encoding is a streaming structure (down_scope /
    // up_scope), not a random-access tree.
    let mut ordered = defs.to_vec();
    ordered.sort_by(|a, b| a.scopes.cmp(&b.scopes).then(a.leaf_name.cmp(&b.leaf_name)));

    let mut current: Vec<String> = Vec::new();
    let mut handle_to_id: std::collections::HashMap<u32, fst_writer::FstSignalId> =
        std::collections::HashMap::new();
    // Handles backed by an FST `real` signal — their value changes are
    // written as 8-byte little-endian f64, not as a bit-string.
    let mut real_handles: std::collections::HashSet<u32> = std::collections::HashSet::new();

    for def in &ordered {
        // Walk the scope path: close (up_scope) any scope we're leaving,
        // then open (scope) any scope we're entering.
        let common = current
            .iter()
            .zip(def.scopes.iter())
            .take_while(|(a, b)| a == b)
            .count();
        while current.len() > common {
            hier.up_scope().map_err(io_err)?;
            current.pop();
        }
        for s in &def.scopes[common..] {
            // fst-writer 0.3 takes (name, component, scope_type). We use
            // empty `component` (no VHDL component instance) for now.
            hier.scope(s.as_str(), "", FstScopeType::Module)
                .map_err(io_err)?;
            current.push(s.clone());
        }

        let (signal_type, var_type) = match &def.kind {
            FstSignalKind::Wire { width } => (FstSignalType::bit_vec(*width), FstVarType::Wire),
            // Variable-length facilities (LXT2 flags=2) are stored by
            // `vcd2lxt2` as 8-byte reals — even VCD `$var string`
            // facilities are emitted as reals (their text collapses to a
            // `nan` real in the LXT2 file). So we declare them as FST
            // reals and write each value change as a little-endian f64.
            FstSignalKind::VariableLength => {
                real_handles.insert(def.handle);
                (FstSignalType::real(), FstVarType::Real)
            }
        };
        let sig = hier
            .var(
                def.leaf_name.as_str(),
                signal_type,
                var_type,
                FstVarDirection::Implicit,
                None,
            )
            .map_err(io_err)?;
        handle_to_id.insert(def.handle, sig);
    }

    // Close any remaining scopes.
    while !current.is_empty() {
        hier.up_scope().map_err(io_err)?;
        current.pop();
    }

    let mut body = hier.finish().map_err(io_err)?;

    // Emit value changes in time order. fst-writer requires monotonic
    // timestamps; we sort defensively even though our LXT2 reader emits
    // already-ordered events (since LXT2's time table is monotonic).
    let mut sorted = events.to_vec();
    sorted.sort_by_key(|e| e.time);

    let mut current_time = u64::MAX;
    for ev in &sorted {
        if ev.time != current_time {
            body.time_change(ev.time).map_err(io_err)?;
            current_time = ev.time;
        }
        if let Some(sig) = handle_to_id.get(&ev.handle) {
            if real_handles.contains(&ev.handle) {
                // Real facility: parse the decoded text to f64 and write
                // the native 8-byte representation. A non-numeric payload
                // (e.g. a `vcd2lxt2`-mangled string) becomes NaN, matching
                // what the LXT2 file actually carries.
                let f: f64 = ev.value.trim().parse().unwrap_or(f64::NAN);
                body.signal_change(*sig, &f.to_le_bytes()).map_err(io_err)?;
            } else {
                body.signal_change(*sig, ev.value.as_bytes())
                    .map_err(io_err)?;
            }
        }
    }

    body.finish().map_err(io_err)?;
    Ok(())
}

fn io_err<E: std::fmt::Display>(e: E) -> std::io::Error {
    std::io::Error::other(format!("fst-writer: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn two_signal_writer() -> FstWriter {
        let mut w = FstWriter::create(-9).unwrap();
        let defs = vec![
            FstSignalDef {
                handle: 0,
                scopes: vec!["top".to_string()],
                leaf_name: "clk".to_string(),
                kind: FstSignalKind::Wire { width: 1 },
            },
            FstSignalDef {
                handle: 1,
                scopes: vec!["top".to_string()],
                leaf_name: "count".to_string(),
                kind: FstSignalKind::Wire { width: 8 },
            },
        ];
        w.write_hierarchy(&defs).unwrap();
        w.write_value_change(0, 0, "0").unwrap();
        w.write_value_change(1, 0, "00000000").unwrap();
        w.write_value_change(0, 10, "1").unwrap();
        w.write_value_change(1, 10, "00000001").unwrap();
        w
    }

    #[test]
    fn write_simple_two_signal_fst() {
        let tmp = tempfile_path("lxt2fst_writer_smoke.fst");
        two_signal_writer().finish(FstOutput::File(&tmp)).unwrap();

        let wf = wellen::simple::read(tmp.to_str().unwrap()).expect("wellen reads our FST");
        let h = wf.hierarchy();
        assert!(h.all_scopes().any(|s| s.name(h) == "top"));
        assert!(h.all_vars().any(|v| v.name(h) == "clk"));
        assert!(h.all_vars().any(|v| v.name(h) == "count"));
    }

    #[test]
    fn memory_output_is_byte_identical_to_file_output() {
        let tmp = tempfile_path("lxt2fst_writer_memory_vs_file.fst");
        two_signal_writer().finish(FstOutput::File(&tmp)).unwrap();
        let on_disk = std::fs::read(&tmp).unwrap();

        let mut in_memory = Vec::new();
        two_signal_writer()
            .finish(FstOutput::Memory(&mut in_memory))
            .unwrap();

        assert!(!in_memory.is_empty());
        assert_eq!(in_memory, on_disk);
    }

    fn tempfile_path(name: &str) -> std::path::PathBuf {
        let p = std::env::temp_dir().join(name);
        let _ = std::fs::remove_file(&p);
        p
    }
}
