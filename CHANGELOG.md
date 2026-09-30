# Changelog

## Unreleased

- Added a cancellation probe on WasmKit 0.4.1 fuel checkpoints and guarded,
  network-free WASI linking for the Crabrix app adapter.
- Exposed typed out-of-fuel inspection for app stop reason mapping.

## Crabrix branch from WasmKit 0.4.1 — 2026-09-30

- Added a separate `CrabrixRuntime` product with explicit execution policy,
  immutable module handle, fresh stores, upstream fuel, and memory/table caps.
- Preserved upstream README, MIT license, commit history, and original module
  identities.
