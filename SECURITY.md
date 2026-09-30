# Security boundary

WebAssembly modules and guest source are untrusted inputs. Parsed modules do
not carry mutable execution state; each invocation creates a new `Store` and
instance. The Crabrix adapter enables upstream fuel metering and enforces
memory and table limits during allocation. Wall-clock Stop and output capture
are caller responsibilities. The WASI layer provides read-only host preopens
and an optional shared stdout/stderr write budget, but callers must select and
test these capabilities for each execution policy.

The caller must separately bound time, host calls, and writable storage, and
must link only its intended WASI imports and preopens. The output budget caps
bytes written through the configured stdout and stderr resources; it does not
cap files opened under writable preopens or pre-existing bytes in caller-owned
capture files. A folder named `readonly` is not a capability: pass the fork's
`readOnly` preopen flag and test nested descriptor rights.

Report security issues privately to the repository owner through GitHub's
private vulnerability reporting when available. Do not include user source,
paths, device identifiers, or credentials in public reports.
