#include <stddef.h>
#include <stdint.h>

#include "moonbit.h"

MOONBIT_FFI_EXPORT void *moonbit_epoxy_pointer_null(void) {
  return NULL;
}

MOONBIT_FFI_EXPORT int32_t moonbit_epoxy_pointer_is_null(void *pointer) {
  return pointer == NULL;
}

MOONBIT_FFI_EXPORT void *moonbit_epoxy_pointer_from_int64(int64_t value) {
  return (void *)(uintptr_t)value;
}
