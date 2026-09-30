# CrabrixRuntime

CrabrixRuntime is the [WasmKit](https://github.com/swiftwasm/WasmKit) 0.4.1 fork used to embed WebAssembly in Crabrix's native iPhone and iPad Rust workspace. It keeps the upstream WasmKit modules and history while adding a small `CrabrixRuntime` library for per-execution policy and engine identity.

The current adapter parses immutable modules, creates a fresh `Store` for each invocation, enables WasmKit's fuel metering, and enforces memory and table limits. A thread-safe cancellation probe is checked at those fuel checkpoints, so Stop can interrupt pure-compute guests without a second instruction counter. A guarded WASI link overload checks host calls and leaves sockets unimplemented. It selects token dispatch and software bounds checking, matching the conservative app configuration. Guest process capture remains at the app integration boundary; the compiler and Cargo gates are separate from adapter unit tests.

## Use as a Swift package

The package requires Swift tools 6.3, macOS 15 or iOS 18 as declared by the upstream manifest. Pin this fork to an exact commit in the app; do not follow a moving branch for release builds.

```swift
import CrabrixRuntime

let runtime = CrabrixRuntime()
let policy = try ExecutionPolicy(
    maximumMemoryBytes: 64 * 1024 * 1024,
    maximumTableElements: 4096,
    fuel: 1_000_000_000
)
let module = try runtime.parse(bytes: wasmBytes)
let stop = CancellationToken()
let store = runtime.makeStore(policy: policy, cancellation: stop)
let instance = try runtime.instantiate(module, store: store)
```

Those example limits are the existing user-program values. The compiler host needs a separately measured policy. Fuel bounds guest instruction work; it is not a wall-clock deadline or prompt user cancellation.

## Build and test

```sh
swift test --filter CrabrixRuntimeTests
swift test --filter FuelTests
```

The first command checks the Crabrix adapter; the second runs WasmKit's upstream fuel suite. The app's compiler, Cargo, WASI rights, output quotas, and device performance have separate integration gates documented in [BENCHMARKS.md](BENCHMARKS.md) and [SECURITY.md](SECURITY.md).

## Architecture and provenance

`CrabrixRuntime` sits above the original `WasmKit` product. Parsed `Module` state may be shared as immutable code; each `Store` and instance is new. The wrapper contains the sole `@_spi(Fuzzing)` use needed for WasmKit's resource limiter, rather than spreading it into Crabrix UI files. Upstream module names remain intact.

- [UPSTREAM.md](UPSTREAM.md) pins release 0.4.1 and its exact commit.
- [PATCHES.md](PATCHES.md) records local changes and removal criteria.
- [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md) preserves the original introduction.
- [SECURITY.md](SECURITY.md) describes the sandbox boundary and reporting.
- [BENCHMARKS.md](BENCHMARKS.md) defines comparison and evidence fields.

WasmKit and this fork remain under the upstream [MIT license](LICENSE), with original notices and Git history preserved. Contribution guidance is in [CONTRIBUTING.md](CONTRIBUTING.md).
