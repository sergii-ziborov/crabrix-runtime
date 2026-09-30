# Crabrix changes from WasmKit 0.4.1

| Patch | Reason | Test | Performance impact | Upstream path / removal |
| --- | --- | --- | --- | --- |
| `CrabrixRuntime` product and policy wrapper | Centralize immutable module handling, fresh stores, fuel and hard memory/table limits | `CrabrixRuntimeTests` | No device benchmark yet | Retain as app-specific embedding surface; propose reusable API upstream if it stabilizes |
| Cancellation probe at existing fuel checkpoints | Stop pure-compute guests without a second instruction counter or cross-thread Store mutation | `CrabrixRuntimeTests.cancellationStopsPureLoopAtFuelCheckpoint`, app `WasmSandboxPolicyTests` | Host-side cost not yet measured on device | Propose upstream cancellation API; remove local patch after adoption |
| Guarded, network-free WASI link overload | Check deadlines/Stop at every host call; socket imports return `ENOSYS` | App sandbox and compiler gates; upstream WASI suite | Not benchmarked | Propose a general pre-host-call hook upstream |
| Typed `Trap.isOutOfFuel` | Preserve budget reason without string matching | App pure-loop budget test | Not measured | Remove if upstream exposes public trap reason |
| Read-only host WASI preopens | Deny write/truncate/unlink/rename/symlink/timestamp mutation through input mounts and nested descriptors; advertise reduced rights | `ReadOnlyPreopenTests` | Not measured | Propose capability flags upstream; keep until equivalent upstream rights enforcement exists |
| `pwrite` access-mode check | Reject writes through a descriptor opened without `FD_WRITE` before reaching the host syscall | `ReadOnlyPreopenTests`, existing WASI access-mode suite | Negligible expected; not benchmarked | Propose upstream as a bug fix |
| Shared bounded stdout/stderr WASI resources | Reject a guest write before the combined capture exceeds its byte budget; prevent seek, positioned write, and truncate bypass; signal the host Stop path | `BoundedStdioTests`, app compiler/user output stress gate pending | Host-call cost not yet measured | Propose an optional bounded stdio wrapper upstream; remove local patch after equivalent API exists |
| Reserved virtual memory for software-checked linear memory | Avoid copying all committed bytes on each allowed `memory.grow`; retain software bounds checks and resource limits, falling back to malloc when reservation fails or is exceeded | Three `ReservedSoftwareMemoryTests`; eight selected Release Simulator compiler/sandbox gates and a fresh-source compile/Run gate | Five Release Simulator warning-Check samples: changed-Check median 1143.668 → 601.456 ms (1.90×) against the preceding fork; no device result | Propose a configurable upstream reservation after device correctness and memory measurements |
| README and provenance documents | Make the fork's origin and supported commands explicit | Link and command smoke | None | Keep with the fork |

No upstream dispatch mode, parser, or memory layout is modified. The
`@_spi(Fuzzing)` bridge is isolated to one wrapper source file and should be
removed once upstream exposes a supported resource-limiter setter. Read-only
WASI rights for compiler source mounts and bounded stdio require app-level
integration and stress tests with the real compiler workload before their
release gates can be closed.
