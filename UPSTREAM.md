# Upstream baseline

- Project: https://github.com/swiftwasm/WasmKit
- Release tag: `0.4.1`
- Exact commit: `a0471eaee817c523b8023d8ebb1c70ff70b7950a`
- Release date: 29 September 2026
- License: MIT, retained in `LICENSE`

The Crabrix branch starts at the release commit. The fork retains upstream
commits and tags; `docs/UPSTREAM_README.md` is the original root README.
The app must pin an exact fork revision. Upstream's later `main` is not a
release input until deliberately reviewed and tested.

WasmKit 0.4.1 already includes fuel metering, malformed-input fixes, and
descriptor-relative WASI path fixes. Crabrix's old instruction limiter is
not layered on top of upstream fuel in this adapter.
