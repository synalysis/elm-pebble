#include "pebble_sdk_spy.h"

#include <stdio.h>
#include <string.h>

static SpyRecord s_records[SPY_MAX_RECORDS];
static int s_count = 0;

static void spy_push(SpyOpKind kind) {
  if (s_count >= SPY_MAX_RECORDS) {
    return;
  }
  memset(&s_records[s_count], 0, sizeof(SpyRecord));
  s_records[s_count].kind = kind;
  s_count++;
}

void spy_reset(void) {
  s_count = 0;
  memset(s_records, 0, sizeof(s_records));
}

int spy_count(void) {
  return s_count;
}

const SpyRecord *spy_record(int index) {
  if (index < 0 || index >= s_count) {
    return NULL;
  }
  return &s_records[index];
}

int spy_count_op(SpyOpKind kind) {
  int n = 0;
  for (int i = 0; i < s_count; i++) {
    if (s_records[i].kind == kind) {
      n++;
    }
  }
  return n;
}

int spy_find_text(const char *substr) {
  if (!substr) {
    return 0;
  }
  for (int i = 0; i < s_count; i++) {
    if (s_records[i].kind != SPY_OP_DRAW_TEXT) {
      continue;
    }
    if (strstr(s_records[i].text, substr) != NULL) {
      return 1;
    }
  }
  return 0;
}

int spy_text_align_count(GTextAlignment align) {
  int n = 0;
  for (int i = 0; i < s_count; i++) {
    if (s_records[i].kind == SPY_OP_DRAW_TEXT && s_records[i].align == align) {
      n++;
    }
  }
  return n;
}

int spy_text_full_width_center_count(int min_width) {
  int n = 0;
  for (int i = 0; i < s_count; i++) {
    const SpyRecord *rec = &s_records[i];
    if (rec->kind != SPY_OP_DRAW_TEXT) {
      continue;
    }
    if (rec->align == GTextAlignmentCenter && rec->rect.size.w >= min_width) {
      n++;
    }
  }
  return n;
}

void graphics_context_set_fill_color(GContext *ctx, GColor color) {
  (void)ctx;
  spy_push(SPY_OP_SET_FILL_COLOR);
  s_records[s_count - 1].color = color;
}

void graphics_context_set_stroke_color(GContext *ctx, GColor color) {
  (void)ctx;
  spy_push(SPY_OP_SET_STROKE_COLOR);
  s_records[s_count - 1].color = color;
}

void graphics_context_set_text_color(GContext *ctx, GColor color) {
  (void)ctx;
  spy_push(SPY_OP_SET_TEXT_COLOR);
  s_records[s_count - 1].color = color;
}

void graphics_context_set_compositing_mode(GContext *ctx, GCompOp mode) {
  (void)ctx;
  (void)mode;
}

void graphics_context_set_stroke_width(GContext *ctx, int width) {
  (void)ctx;
  (void)width;
}

void graphics_context_set_antialiased(GContext *ctx, bool on) {
  (void)ctx;
  (void)on;
}

void graphics_draw_text(
    GContext *ctx,
    const char *text,
    GFont font,
    GRect box,
    GTextOverflowMode overflow,
    GTextAlignment alignment,
    void *attributes) {
  (void)ctx;
  (void)font;
  (void)attributes;
  spy_push(SPY_OP_DRAW_TEXT);
  SpyRecord *rec = &s_records[s_count - 1];
  rec->rect = box;
  rec->align = alignment;
  rec->overflow = overflow;
  if (text) {
    strncpy(rec->text, text, sizeof(rec->text) - 1);
    rec->text[sizeof(rec->text) - 1] = '\0';
  }
}

void graphics_fill_rect(GContext *ctx, const GRect *rect) {
  (void)ctx;
  spy_push(SPY_OP_FILL_RECT);
  if (rect) {
    s_records[s_count - 1].rect = *rect;
  }
}

void graphics_fill_circle(GContext *ctx, GPoint center, int16_t radius) {
  (void)ctx;
  spy_push(SPY_OP_FILL_CIRCLE);
  SpyRecord *rec = &s_records[s_count - 1];
  rec->point = center;
  rec->radius = radius;
}

void graphics_draw_circle(GContext *ctx, GPoint center, int16_t radius) {
  (void)ctx;
  spy_push(SPY_OP_DRAW_CIRCLE);
  SpyRecord *rec = &s_records[s_count - 1];
  rec->point = center;
  rec->radius = radius;
}
