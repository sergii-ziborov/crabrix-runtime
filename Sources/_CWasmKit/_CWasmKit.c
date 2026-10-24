#include "_CWasmKit.h"

#if WASMKIT_USE_DIRECT_THREADED_CODE
void wasmkit_tc_start(
    wasmkit_tc_exec exec, Sp sp, Pc pc, Md md, Ms ms, void *state
) {
    exec(sp, pc, md, ms, 0, 0.0, state);
}
#endif

int
wasmkit_address_sanitizer_enabled(void)
{
    return WASMKIT_ADDRESS_SANITIZER_ENABLED;
}
