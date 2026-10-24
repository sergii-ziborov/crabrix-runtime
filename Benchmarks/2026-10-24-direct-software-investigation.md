# Direct software dispatch investigation — 2026-10-24

Research branch: `codex/runtime-dispatch-20261024`. Production software-bounds engines still select token dispatch. The new opt-in SPI exists solely for regression and performance investigation; the app’s released runtime pin remains `0689cc5`.

The explicit direct/software tests reproduced the existing defect on optimized arm64 macOS: an out-of-bounds load returned `i32(0)` instead of a trap, and a fuel-exhaustion/recovery test exited with signal 11. No speedup is claimed. The direct dispatch path must pass memory, fuel, cancellation, recovery and real-compiler gates before a production change.

The C dead-accumulator macro previously read an uninitialized automatic variable. Replacing it with a defined zero removes that hazard but did not fix the reproduced trap defect. This change is experimental and is not in the app release.

Opt-in regression command:

```sh
CRABRIX_RUN_EXPERIMENTAL_DIRECT=1 swift test -c release --filter ExperimentalDirectSoftwareTests
```

Normal test runs skip these known-failing experimental probes. The existing token-dispatch safety gates remain active. Raw diagnostic logs are retained in the app workspace under `build/compatibility-blog-20261024/`.

A separate Binaryen 133 `wasm-opt -O2 --strip-debug` trial on the exact 129,350,419-byte compiler was stopped after 180 seconds at about 1.53 GB observed RSS. It produced no completed candidate and provides no compilation-speed evidence. The original signed compiler artifact was preserved.

## Controlled C entry-point repair

On Xcode 27.1 RC, moving `wasmkit_tc_start` from a Clang-imported static inline body to an external C implementation made both original probes pass. Restoring the inline implementation under the same SDK reproduced signal 11; restoring the external entry passed again. This confines the calling-convention transition to C. The production software-bounds default remains token dispatch while device and compiler gates continue.

The expanded optimized host gate passed 19 tests, including 179 official core/Crabrix instruction scripts with direct dispatch and software bounds. Cancellation is compared against fuel remaining immediately before its loop; the preceding memory growth correctly consumes its own fuel and must not be omitted from accounting.

Four process-cold compilations of an identical std/BTreeMap Rust input produced identical Wasm hashes: token 6.575/8.675 s, experimental direct 7.525/6.549 s. These host ranges overlap and do not prove a speedup. CLI memory policy differs from the app, so these are not iPhone resource or startup measurements. The opt-in hidden CLI flag is research-only.

The physical iPhone production-token baseline freshly compiled/generated a web page in 7.348 s. A fresh Tokio feature-profile dependency build exceeded the 240 s test bound; bytes alone took approximately 63 s. The requested 30 s large-project target is not met by this baseline.
