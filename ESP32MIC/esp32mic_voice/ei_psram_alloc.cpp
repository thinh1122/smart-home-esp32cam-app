// Override ei_malloc/ei_calloc để dùng PSRAM trên ESP32-S3
// File này được compile cùng sketch, override weak functions trong thư viện EI

#include <Arduino.h>
#include "edge-impulse-sdk/porting/ei_classifier_porting.h"

void *ei_malloc(size_t size) {
  void *ptr = ps_malloc(size);
  if (!ptr) ptr = malloc(size);
  return ptr;
}

void *ei_calloc(size_t nitems, size_t size) {
  void *ptr = ps_calloc(nitems, size);
  if (!ptr) ptr = calloc(nitems, size);
  return ptr;
}

void ei_free(void *ptr) {
  free(ptr);
}
