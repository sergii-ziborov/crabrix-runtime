# Security boundary

WebAssembly modules and guest source are untrusted inputs. Parsed modules do
not carry mutable execution state; each invocation creates a new `Store` and
instance. The Crabrix adapter enables upstream fuel metering and enforces
memory and table limits during allocation. It does not provide wall-clock Stop,
bounded host I/O, output capture, or a read-only WASI preopen by itself.

The caller must separately bound time, host calls, output and writable storage,
and must link only its intended WASI imports and preopens. A folder named
`readonly` is not a capability: upstream WASI 0.4.1 preopens do not expose a
read-only rights constructor, so compiler-host read-only enforcement needs a
tested additional design before the app moves to this fork.

Report security issues privately to the repository owner through GitHub's
private vulnerability reporting when available. Do not include user source,
paths, device identifiers, or credentials in public reports.
