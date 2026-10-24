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
