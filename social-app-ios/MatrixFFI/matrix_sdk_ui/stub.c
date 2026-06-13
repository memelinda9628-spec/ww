#include "matrix_sdk_uiFFI.h"

// No FFI functions to stub - module only has type definitions

RustBuffer ffi_matrix_sdk_ui_rustbuffer_from_bytes(ForeignBytes bytes, RustCallStatus *_Nonnull out_status
) {
    // Stub: return empty buffer
    return (RustBuffer){0};
}

void ffi_matrix_sdk_ui_rustbuffer_free(RustBuffer buf, RustCallStatus *_Nonnull out_status
) {
    // Stub
}

uint32_t ffi_matrix_sdk_ui_uniffi_contract_version(void
) {
    // Stub: return version 0
    return 0;
}
