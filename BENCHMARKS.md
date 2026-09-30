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
published verbatim. The candidate passed three reserved-memory Swift tests,
eight selected app compiler/sandbox gates, and a fresh-source compile/Run gate.

The 0.3.1 A and clean 0.4.1 B device baselines remain outstanding. The
`swift test` fuel and adapter results are correctness tests, not speed
measurements.
