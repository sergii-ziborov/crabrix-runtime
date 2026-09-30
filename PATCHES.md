# Crabrix changes from WasmKit 0.4.1

| Patch | Reason | Test | Performance impact | Upstream path / removal |
| --- | --- | --- | --- | --- |
| `CrabrixRuntime` product and policy wrapper | Centralize immutable module handling, fresh stores, fuel and hard memory/table limits | `CrabrixRuntimeTests` | No device benchmark yet | Retain as app-specific embedding surface; propose reusable API upstream if it stabilizes |
| Cancellation probe at existing fuel checkpoints | Stop pure-compute guests without a second instruction counter or cross-thread Store mutation | `CrabrixRuntimeTests.cancellationStopsPureLoopAtFuelCheckpoint`, app `WasmSandboxPolicyTests` | Host-side cost not yet measured on device | Propose upstream cancellation API; remove local patch after adoption |
| Guarded, network-free WASI link overload | Check deadlines/Stop at every host call; socket imports return `ENOSYS` | App sandbox and compiler gates; upstream WASI suite | Not benchmarked | Propose a general pre-host-call hook upstream |
| Typed `Trap.isOutOfFuel` | Preserve budget reason without string matching | App pure-loop budget test | Not measured | Remove if upstream exposes public trap reason |
| README and provenance documents | Make the fork's origin and supported commands explicit | Link and command smoke | None | Keep with the fork |

No upstream dispatch mode, parser, or memory layout is modified. The
`@_spi(Fuzzing)` bridge is isolated to one wrapper source file and should be
removed once upstream exposes a supported resource-limiter setter. Read-only
WASI rights for compiler source mounts are still an app integration gate.
