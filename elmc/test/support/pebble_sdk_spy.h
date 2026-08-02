#ifndef PEBBLE_SDK_SPY_H
#define PEBBLE_SDK_SPY_H

#include <stdbool.h>
#include <stdint.h>

typedef struct GPoint {
  int16_t x;
  int16_t y;
} GPoint;

typedef struct GSize {
  int16_t w;
  int16_t h;
} GSize;

typedef struct GRect {
  GPoint origin;
  GSize size;
} GRect;

typedef const void *GFont;

typedef enum {
  GColorBlack = 0,
  GColorWhite = 1
} GColor;

typedef enum {
  GTextAlignmentLeft = 0,
  GTextAlignmentCenter = 1,
  GTextAlignmentRight = 2
} GTextAlignment;

typedef enum {
  GTextOverflowModeWordWrap = 0,
  GTextOverflowModeTrailingEllipsis = 1,
  GTextOverflowModeFill = 2
} GTextOverflowMode;

typedef enum {
  GCompOpAssign = 0
} GCompOp;

typedef struct GContext {
  int unused;
} GContext;

#define SPY_MAX_RECORDS 256
#define SPY_MAX_TEXT_LEN 128

typedef enum {
  SPY_OP_NONE = 0,
  SPY_OP_DRAW_TEXT = 1,
  SPY_OP_FILL_RECT = 2,
  SPY_OP_FILL_CIRCLE = 3,
  SPY_OP_DRAW_CIRCLE = 4,
  SPY_OP_SET_FILL_COLOR = 5,
  SPY_OP_SET_STROKE_COLOR = 6,
  SPY_OP_SET_TEXT_COLOR = 7
} SpyOpKind;

typedef struct {
  SpyOpKind kind;
  GRect rect;
  GPoint point;
  int16_t radius;
  GTextAlignment align;
  GTextOverflowMode overflow;
  GColor color;
  char text[SPY_MAX_TEXT_LEN];
} SpyRecord;

void spy_reset(void);
int spy_count(void);
const SpyRecord *spy_record(int index);

int spy_count_op(SpyOpKind kind);
int spy_find_text(const char *substr);
int spy_text_align_count(GTextAlignment align);
int spy_text_full_width_center_count(int min_width);

void graphics_context_set_fill_color(GContext *ctx, GColor color);
void graphics_context_set_stroke_color(GContext *ctx, GColor color);
void graphics_context_set_text_color(GContext *ctx, GColor color);
void graphics_context_set_compositing_mode(GContext *ctx, GCompOp mode);
void graphics_context_set_stroke_width(GContext *ctx, int width);
void graphics_context_set_antialiased(GContext *ctx, bool on);

void graphics_draw_text(
    GContext *ctx,
    const char *text,
    GFont font,
    GRect box,
    GTextOverflowMode overflow,
    GTextAlignment alignment,
    void *attributes);

void graphics_fill_rect(GContext *ctx, const GRect *rect);
void graphics_fill_circle(GContext *ctx, GPoint center, int16_t radius);
void graphics_draw_circle(GContext *ctx, GPoint center, int16_t radius);

#endif
