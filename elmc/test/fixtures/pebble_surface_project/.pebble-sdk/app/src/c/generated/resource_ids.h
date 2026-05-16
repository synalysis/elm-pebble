#ifndef ELM_PEBBLE_RESOURCE_IDS_H
#define ELM_PEBBLE_RESOURCE_IDS_H

#include <stdint.h>

#define ELM_PEBBLE_RESOURCE_ID_MISSING UINT32_MAX

static inline uint32_t elm_pebble_bitmap_resource_id(int64_t bitmap_id) {
  switch (bitmap_id) {

    default: return ELM_PEBBLE_RESOURCE_ID_MISSING;
  }
}

static inline uint32_t elm_pebble_font_resource_id(int64_t font_id) {
  switch (font_id) {

    default: return ELM_PEBBLE_RESOURCE_ID_MISSING;
  }
}

static inline int64_t elm_pebble_font_resource_height(int64_t font_id) {
  switch (font_id) {

    default: return 0;
  }
}

#endif
