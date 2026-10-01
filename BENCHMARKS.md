# Runtime comparison contract

The performance gate uses the same compiler artifact and corpus for:

1. Crabrix's retained WasmKit 0.3.1 baseline.
2. Clean WasmKit 0.4.1 with the minimum app adapter.
3. This fork with each tested Crabrix patch.

Record raw source/runtime/toolchain IDs, device and OS, Release configuration,
workload digest, cold/warm/cache state, wall time, peak memory metric, result
and diagnostic digest, thermal state, and Stop latency. Keep compute-only and
end-to-end download samples separate. Cold first Check, changed Check and Run,
unchanged cache hit, dependency builds, diagnostics, cancellation, unique
revisions, and memory-pressure recovery are distinct workloads.

## Reserved software memory, iOS Simulator, 30 September 2026

The app measured the old fork `719f94d7d27368549502828217e3dbc7e6738852`
against the reserved-memory source commit
`6f9e307c9c3069560d1a00a277dce51964309bdc` with the same bundled
compiler artifact and warning-Check corpus. Five separate Release test
processes per revision ran on an iOS 18.2 arm64 Simulator using Xcode 27.0
beta (`27A5228h`). All ten probe tests passed; first and changed Check
returned the same two warnings, and unchanged Check retained diagnostics.

| Check phase | Preceding fork median | Reserved-memory median | Ratio |
| --- | ---: | ---: | ---: |
| First Check | 1228.261 ms | 696.862 ms | 1.76× |
| Changed Check | 1143.668 ms | 601.456 ms | 1.90× |
| Unchanged cached Check | 0.750 ms | 0.765 ms | 0.98× |

The [raw observations and input identities](https://github.com/sergii-ziborov/Crabrix/blob/codex/reserved-memory-2026-09-30/docs/performance/2026-09-30-reserved-memory-simulator.json)
are in the app repository. This is a Simulator result for one source workload,
not a whole-app, device, Cargo, peak-RSS, thermal, or p95 claim. A profiling
sample identified repeated whole-memory copies during `memory.grow`; the
reserved path commits pages in place while keeping the same software bounds
and `ResourceLimiter` checks. The sample included local host paths and is not
published verbatim. The measured source commit passed three reserved-memory
Swift tests, eight selected app compiler/sandbox gates, and a fresh-source
compile/Run gate.

## Safety-gated candidate, same Simulator workload

Source commit `fbe46d928a4592ca274e5fdf07fdbafcf9538868` additionally
selects token dispatch whenever memory bounds are checked in software. An
isolated Release test found that the direct dispatcher returned zero for an
out-of-bounds load instead of trapping; token dispatch trapped as required.
The full runtime Release suite then passed 462 tests across 15 targets,
including the new explicit-direct fallback regression. The app passed nine
selected Release Simulator compiler/sandbox gates on this exact revision,
including a fresh-source compile/Run, E0502, guided Check, Stop, and memory
limit gates.

Five more separate Release Simulator warning-Check processes used the same
compiler and source. The [raw observations](https://github.com/sergii-ziborov/Crabrix/blob/codex/reserved-memory-2026-09-30/docs/performance/2026-09-30-reserved-memory-safety-simulator.json)
are published with exact app/runtime IDs.

| Check phase | Preceding fork median | Safety-gated median | Ratio |
| --- | ---: | ---: | ---: |
| First Check | 1228.261 ms | 859.161 ms | 1.43× |
| Changed Check | 1143.668 ms | 566.340 ms | 2.02× |
| Unchanged cached Check | 0.750 ms | 0.836 ms | 0.90× |

The first-Check samples varied more in the safety-gated series. The
fallback is not credited with a speed improvement; the app was already
requesting token dispatch in the preceding series. This remains one Simulator
workload with no physical-device, RSS, thermal, Cargo, or p95 result.

The 0.3.1 A and clean 0.4.1 B device baselines remain outstanding. The
`swift test` fuel and adapter results are correctness tests, not speed
measurements.

## Sampled cancellation, dependency-rich CLI, iOS Simulator, 2 October 2026

The app compared prior fork `fbe46d928a4592ca274e5fdf07fdbafcf9538868`
with sampled-cancellation fork `d996f0d11dff54734b5670d58062e22c6e01f949`
in A/B/A order. All three Release iOS 18.2 arm64 Simulator runs compiled and
ran the same three-file `clap 4.5.50` + `regex 1.13.1` + `hashbrown 0.17.1` +
`smallvec 1.15.1` CLI and asserted the same output. Each run used the own
stripped test compiler SHA-256
`5da690fe77625d55602e400ebdb0d57fb496c1f3e26d1376c1a8ef0e56e378bd`
and removed candidate Cargo artifacts before execution.

| Run | Runtime | Test wall time | Guest execution phase sum |
| --- | --- | ---: | ---: |
| A1 | sampled `d996f0d` | 345.835 s | 342.212 s |
| B | prior `fbe46d9` | 563.758 s | 560.021 s |
| A2 | sampled `d996f0d` | 351.106 s | 346.398 s |

This is about 1.61–1.63× faster for the selected CLI. It is not a
several-fold whole-app claim. Registry/system caches and thermal state were
not independently controlled; Xcode may have replaced the app data container
between binary revisions. Peak RSS and physical-device measurements are
missing. [Sanitized raw observations](https://github.com/sergii-ziborov/Crabrix/blob/codex/runtime-sampled-probe-2026-10-02/docs/performance/2026-10-02-sampled-cancellation-heavy-cli-simulator.json)
retain all 23 guest phase times per run.

The fork's full `swift test` run passed 464 tests across 15 targets. App-level
old-compiler and own-compiler selections each passed fuel exhaustion, user
Stop, and a 20 ms pure-compute wall-clock deadline, five tests per selection.
Those correctness results do not establish a physical-device Stop latency.
