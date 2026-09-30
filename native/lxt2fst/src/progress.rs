// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Throttled progress reporter for the conversion path.
//
// Progress fires at most every 50 ms OR every 1% of
// progress, whichever comes first. This both keeps the FFI/UI thread from
// being flooded by callbacks (a converted 50 MB LXT2 can emit hundreds of
// thousands of granule decode steps) and gives a fast-moving progress bar
// for small files where 1% would lag.
//
// On wasm we cannot use std::time::Instant — `Instant::now()` panics under
// wasm32-unknown-unknown unless `instant`/`js-sys` provides a shim. We
// degrade gracefully there to the 1% gate only.

#[cfg(not(target_arch = "wasm32"))]
use std::time::{Duration, Instant};

/// Wraps a caller-provided `(done, total)` callback with the 50 ms / 1%
/// throttling rule.
///
/// `total` may legitimately change as the conversion progresses (e.g., the
/// LXT2 reader discovers the true block count from the block index after
/// it walks the file once); the reporter recomputes the "next %" threshold
/// from the latest `total` whenever it fires.
pub struct ProgressReporter<'a> {
    inner: Option<&'a mut dyn FnMut(u64, u64)>,
    last_done: u64,
    last_total: u64,
    last_percent: u32,
    #[cfg(not(target_arch = "wasm32"))]
    last_fire: Option<Instant>,
    /// Forces the next `report()` to fire regardless of throttle. Used to
    /// guarantee the final (N, N) callback is always delivered.
    force_next: bool,
}

impl<'a> ProgressReporter<'a> {
    pub fn new(inner: Option<&'a mut dyn FnMut(u64, u64)>) -> Self {
        Self {
            inner,
            last_done: 0,
            last_total: 0,
            last_percent: u32::MAX, // ensures the 0% / first call fires
            #[cfg(not(target_arch = "wasm32"))]
            last_fire: None,
            force_next: true,
        }
    }

    /// Report a progress tick. The actual callback is invoked only if at
    /// least one throttle gate has elapsed: 50 ms OR 1% of `total`.
    pub fn report(&mut self, done: u64, total: u64) {
        if self.inner.is_none() {
            self.last_done = done;
            self.last_total = total;
            return;
        }

        let percent = (done.min(total) * 100).checked_div(total).unwrap_or(0) as u32;

        let percent_advanced = self.last_percent == u32::MAX
            || (percent != self.last_percent
                && percent.saturating_sub(self.last_percent.min(percent)) >= 1)
            || self.last_total != total;

        #[cfg(not(target_arch = "wasm32"))]
        let time_elapsed = match self.last_fire {
            None => true,
            Some(t) => t.elapsed() >= Duration::from_millis(50),
        };
        #[cfg(target_arch = "wasm32")]
        let time_elapsed = false; // 1% gate only on wasm

        if self.force_next || percent_advanced || time_elapsed {
            if let Some(cb) = self.inner.as_mut() {
                cb(done, total);
            }
            self.last_done = done;
            self.last_total = total;
            self.last_percent = percent;
            self.force_next = false;
            #[cfg(not(target_arch = "wasm32"))]
            {
                self.last_fire = Some(Instant::now());
            }
        }
    }

    /// Force-fire the final (done, total) call, even if throttled. The
    /// converter calls this at end-of-stream so the UI always sees 100%.
    pub fn finish(&mut self, done: u64, total: u64) {
        if let Some(cb) = self.inner.as_mut() {
            cb(done, total);
        }
        self.last_done = done;
        self.last_total = total;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_report_always_fires() {
        let mut calls: Vec<(u64, u64)> = Vec::new();
        let mut cb = |d, t| calls.push((d, t));
        let mut r = ProgressReporter::new(Some(&mut cb));
        r.report(0, 100);
        assert_eq!(calls, vec![(0, 100)]);
    }

    #[test]
    fn percent_gate_throttles_sub_percent_steps() {
        let mut calls: Vec<(u64, u64)> = Vec::new();
        let mut cb = |d, t| calls.push((d, t));
        let mut r = ProgressReporter::new(Some(&mut cb));
        r.report(0, 10000);
        // 0..99 are all sub-1% steps; only the first should fire.
        for d in 0..100 {
            r.report(d, 10000);
        }
        // 100 is the 1% mark — fires.
        r.report(100, 10000);
        assert!(calls.len() <= 3, "calls={calls:?}");
        // Must include both first (0) and 100.
        assert!(calls.contains(&(0, 10000)));
        assert!(calls.contains(&(100, 10000)));
    }

    #[test]
    fn finish_always_fires() {
        let mut calls: Vec<(u64, u64)> = Vec::new();
        let mut cb = |d, t| calls.push((d, t));
        let mut r = ProgressReporter::new(Some(&mut cb));
        r.report(0, 10);
        // Even though we just reported 0%, a finish to (10,10) must fire.
        r.finish(10, 10);
        assert!(calls.contains(&(10, 10)));
    }

    #[test]
    fn none_callback_is_noop() {
        let mut r = ProgressReporter::new(None);
        r.report(50, 100); // must not panic / allocate / etc.
        r.finish(100, 100);
    }
}
