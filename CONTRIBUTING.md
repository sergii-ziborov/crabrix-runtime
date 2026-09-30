# Contributing

Base changes on `crabrix/0.4.1`, keep upstream history and notices, and make
one focused patch per behavior. Add a regression test for security or runtime
semantics, and record the reason, test, measured performance impact, and
upstream issue or PR in `PATCHES.md`.

Use `swift test --filter CrabrixRuntimeTests` for the adapter and the relevant
upstream suites for parser, fuel, and WASI changes. Do not weaken resource
limits to obtain a benchmark gain. Keep credentials and user data out of the
repository and test fixtures.
