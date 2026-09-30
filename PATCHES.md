# Crabrix changes from WasmKit 0.4.1

| Patch | Reason | Test | Performance impact | Upstream path / removal |
| --- | --- | --- | --- | --- |
| `CrabrixRuntime` product and policy wrapper | Centralize immutable module handling, fresh stores, fuel and hard memory/table limits | `CrabrixRuntimeTests` | No device benchmark yet | Retain as app-specific embedding surface; propose reusable API upstream if it stabilizes |
| README and provenance documents | Make the fork's origin and supported commands explicit | Link and command smoke | None | Keep with the fork |

No upstream engine dispatch, WASI rights, parser, or memory layout code is
modified in this first branch. Changes in those areas require their own test
evidence and an entry here. The `@_spi(Fuzzing)` bridge is isolated to one
wrapper source file and should be removed once upstream exposes a supported
resource-limiter setter.
