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

No app/device benchmark result is published yet. The `swift test` fuel and
adapter results are correctness tests, not speed measurements. Any future
performance claim belongs here with raw observations and sample counts.
