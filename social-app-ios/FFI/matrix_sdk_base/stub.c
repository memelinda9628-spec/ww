#include "matrix_sdk_baseFFI.h"

// No FFI functions to stub - module only has type definitions

RustBuffer ffi_matrix_sdk_base_rustbuffer_from_bytes(ForeignBytes bytes, RustCallStatus *_Nonnull out_status
) {
    // Stub: return empty buffer
    return (RustBuffer){0};
}

void ffi_matrix_sdk_base_rustbuffer_free(RustBuffer buf, RustCallStatus *_Nonnull out_status
) {
    // Stub
}

uint32_t ffi_matrix_sdk_base_uniffi_contract_version(void
) {
    // Stub: return version 0
    return 0;
}
