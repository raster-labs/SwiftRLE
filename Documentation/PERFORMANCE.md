# Performance engineering and regression gates

Contract **0.7.0**. All performance claims require measurement.

**PERF-01.** Measure before optimising. Preserve the scalar reference. Priorities are latency/throughput, compression efficiency and resource efficiency, subject to correct fidelity, reliability and security. A faster result that drops precision, copies unexpectedly, ignores limits or produces non-conformant data fails.

## Baselines and experiments

Record two baselines: (a) the pinned predecessor using its supported API/platform, and (b) the first validated successor using the common API. Separate migration overhead from subsequent kernel improvements. Fix compiler optimisation, hardware, OS, power/thermal conditions, parallelism, image layout, fidelity and codec options. Compare like-for-like. Do not attribute a backend or quality-setting change to API overhead.

Use a redistributable corpus covering small images, odd dimensions, 512x512, 2048x2048, a large image within the configured budget, flat/ramp/noisy patterns, representative greyscale 12/16-bit data and supported colour modes. Report per-case results; do not hide a severe outlier behind an average. Warm and cold measurements are separate, especially Metal compilation/session creation. Multi-frame stress uses a bounded queue and records steady-state memory.

**PERF-02.** Benchmark release builds without sanitizers, tracing or coverage. Use at least five warm-ups and twenty timed iterations per case where runtime permits; record actual counts for expensive cases. Report median, p95, spread, throughput in pixels/s, encoded size, peak resident memory, peak pixel/workspace allocation, copy bytes and allocation count. Interleave baseline/candidate runs to reduce thermal bias. No one-shot speedup claims. Archive raw samples. CI wall-clock performance on an uncontrolled shared runner is advisory; controlled hardware evidence is the release gate.

## Initial regression policy

**PERF-03.** A reproducible median latency or peak-memory increase over 5% on a controlled representative case triggers investigation. Repeat interleaved runs to distinguish noise; report the confidence/spread rather than asserting a tiny change is real. An unexplained confirmed regression blocks the stable release. A deliberate safety/correctness trade-off may be accepted only with a recorded reason, measured cost and updated baseline; the agent may not silently waive it. No fixed universal MB/s claim is prescribed before measurement.

For unchanged lossless mode/settings, a consistent encoded-size increase above 1% triggers investigation and explanation. Different conformant encoding decisions may be accepted deliberately; do not trade off size by changing fidelity. For lossy work, compare rate-distortion at equivalent settings/targets and retain explicit error/quality measures. These percentages are initial engineering gates, not results or guarantees, and are revised transparently if evidence warrants.

The shared-storage milestone has a strict gate: **zero additional full decoded-image allocations or byte copies solely for the codec hand-off**. This is not a statistical tolerance. Report all necessary algorithm workspaces separately. Do not substitute reduced overall RSS for direct proof of no hand-off copy. A helper that converts arrays to another full image has not met the gate even if copy-on-write postpones some allocation.

## Optimisation order and architecture

**PERF-04.** First remove accidental allocation/conversion and fix access patterns; then bounded reuse, scalar hot loops, SIMD/NEON and suitable Apple frameworks; then consider measured GPU or narrow native kernels. GPU dispatch, synchronisation and transfers can outweigh compute savings on small images. Runtime automatic selection needs measured thresholds and a reported backend. Never assume UMA alone proves no copy.

Maintain CPU fallback and explicit backend selection for diagnostics. Acceleration receives the same validated descriptor and safe owner. GPU command buffers retain resources through completion. Avoid CPU/GPU races; account for staging textures/buffers and layout conversion. Any IOSurface-backed path must prove its allocation/export compatibility and lifetime on the target. Plain pointer wrapping must not be advertised as guaranteed GPU sharing.

**PERF-05.** Profile memory under concurrent operations and cancellation as well as one-frame throughput. Budget scratch per worker, use back-pressure and cap caches/pools. Warm caches need eviction tests and must not retain sensitive frame data unnecessarily. Pool exhaustion returns a defined limit error or waits with cancellation, never allocates without bounds. State which operations are serialised and why.

Do not publish comparative third-party benchmark prose in repository marketing. Keep independent-oracle comparisons and raw engineering evidence in the validation material, with versions, settings and licences. README performance numbers, if later added, must be reproducible measurements of this library under a stated configuration.

## Native transcoding measurements

**PERF-06.** Measure J2K ↔ HTJ2K and JPEG ↔ JPEG XL forward/reverse operations separately for each qualified profile. Record the actual processing path, coefficient/reconstruction workspace, any materialised pixels, compressed input/output, copy/allocation counts, peak memory, latency and output size. For J2K compare a coefficient path against a measured compatible decode/re-encode path; exact fidelity is a prerequisite to a speed comparison. For JPEG reconstruction compare original JPEG bytes exactly before accepting a performance result.

No fixed size reduction or speedup is promised: valid JPEG XL recompression can be larger on some inputs, and preserving reconstruction metadata has a cost. Apply the established regression methodology to like-for-like baselines. Retain only measured claims. Prove absence of unnecessary full-image/coefficient handoff copies and intermediate file I/O rather than inferring it from throughput or memory usage alone.
