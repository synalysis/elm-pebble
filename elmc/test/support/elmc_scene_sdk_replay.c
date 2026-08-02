#include "elmc_scene_sdk_replay.h"

#include <string.h>

#define REPLAY_STUB_FONT ((GFont)(void *)1)

typedef struct {
  GColor stroke_color;
  GColor fill_color;
  GColor text_color;
} ReplayStyle;

static GTextAlignment text_alignment_from_options(int32_t options) {
  static const GTextAlignment alignment_lut[4] = {
      GTextAlignmentLeft,
      GTextAlignmentCenter,
      GTextAlignmentRight,
      GTextAlignmentCenter,
  };
  return alignment_lut[options & 0x3];
}

static GTextOverflowMode text_overflow_from_options(int32_t options) {
  static const GTextOverflowMode overflow_lut[4] = {
      GTextOverflowModeWordWrap,
      GTextOverflowModeTrailingEllipsis,
      GTextOverflowModeFill,
      GTextOverflowModeWordWrap,
  };
  return overflow_lut[(options >> 2) & 0x3];
}

static GColor color_from_code(int32_t value) {
  return (GColor)(value & 0xff);
}

static bool rect_params_are_valid(int32_t w, int32_t h) {
  return w > 0 && h > 0;
}

static GRect rect_from_params(int32_t x, int32_t y, int32_t w, int32_t h) {
  GRect rect = {
      .origin = {.x = (int16_t)x, .y = (int16_t)y},
      .size = {.w = (int16_t)w, .h = (int16_t)h},
  };
  return rect;
}

static void replay_cmd(GContext *ctx, ReplayStyle *style, const ElmcPebbleDrawCmd *cmd) {
  switch (cmd->kind) {
  case ELMC_PEBBLE_DRAW_FILL_COLOR:
    style->fill_color = color_from_code(cmd->p0);
    graphics_context_set_fill_color(ctx, style->fill_color);
    break;

  case ELMC_PEBBLE_DRAW_STROKE_COLOR:
    style->stroke_color = color_from_code(cmd->p0);
    graphics_context_set_stroke_color(ctx, style->stroke_color);
    break;

  case ELMC_PEBBLE_DRAW_TEXT_COLOR:
    style->text_color = color_from_code(cmd->p0);
    graphics_context_set_text_color(ctx, style->text_color);
    break;

  case ELMC_PEBBLE_DRAW_FILL_RECT:
    if (rect_params_are_valid(cmd->p2, cmd->p3)) {
      GRect rect = rect_from_params(cmd->p0, cmd->p1, cmd->p2, cmd->p3);
      graphics_context_set_fill_color(ctx, color_from_code(cmd->p4));
      graphics_fill_rect(ctx, &rect);
      graphics_context_set_fill_color(ctx, style->fill_color);
    }
    break;

  case ELMC_PEBBLE_DRAW_CIRCLE: {
    GPoint center = {(int16_t)cmd->p0, (int16_t)cmd->p1};
    graphics_context_set_stroke_color(ctx, color_from_code(cmd->p3));
    graphics_draw_circle(ctx, center, (int16_t)cmd->p2);
    graphics_context_set_stroke_color(ctx, style->stroke_color);
    break;
  }

  case ELMC_PEBBLE_DRAW_FILL_CIRCLE: {
    GPoint center = {(int16_t)cmd->p0, (int16_t)cmd->p1};
    graphics_context_set_fill_color(ctx, color_from_code(cmd->p3));
    graphics_fill_circle(ctx, center, (int16_t)cmd->p2);
    graphics_context_set_fill_color(ctx, style->fill_color);
    break;
  }

  case ELMC_PEBBLE_DRAW_TEXT:
    if (rect_params_are_valid(cmd->p3, cmd->p4) && cmd->text[0] != '\0') {
      GRect text_rect = rect_from_params(cmd->p1, cmd->p2, cmd->p3, cmd->p4);
      GTextOverflowMode overflow = text_overflow_from_options(cmd->p5);
      GTextAlignment align = text_alignment_from_options(cmd->p5);
      graphics_draw_text(ctx, cmd->text, REPLAY_STUB_FONT, text_rect, overflow, align, NULL);
    }
    break;

  default:
    break;
  }
}

int elmc_scene_replay_to_sdk(const ElmcPebbleApp *app, ElmcSceneSdkReplayStats *stats) {
  if (!app || !stats) {
    return -1;
  }
  if (elmc_pebble_ensure_scene((ElmcPebbleApp *)app) != 0) {
    return -2;
  }

  memset(stats, 0, sizeof(*stats));
  spy_reset();

  GContext ctx = {0};
  ReplayStyle style = {
      .stroke_color = GColorBlack,
      .fill_color = GColorBlack,
      .text_color = GColorBlack,
  };

  int byte_offset = 0;
  while (byte_offset < app->scene.byte_count) {
    ElmcPebbleDrawCmd cmd;
    if (elmc_pebble_scene_decode_record(app->scene.bytes, app->scene.byte_count, &byte_offset, &cmd) != 0) {
      return -3;
    }

    stats->scene_cmds++;

    switch (cmd.kind) {
    case ELMC_PEBBLE_DRAW_TEXT:
      stats->scene_text++;
      if (cmd.p3 > 0 && cmd.p1 == 0 && cmd.p2 == 0) {
        stats->scene_text_origin++;
      }
      break;
    case ELMC_PEBBLE_DRAW_FILL_RECT:
      stats->scene_fill_rect++;
      break;
    case ELMC_PEBBLE_DRAW_FILL_CIRCLE:
      stats->scene_fill_circle++;
      break;
    case ELMC_PEBBLE_DRAW_CIRCLE:
      stats->scene_circle++;
      break;
    case ELMC_PEBBLE_DRAW_FILL_RADIAL:
      stats->scene_fill_radial++;
      break;
    default:
      break;
    }

    replay_cmd(&ctx, &style, &cmd);
  }

  stats->sdk_text = spy_count_op(SPY_OP_DRAW_TEXT);
  stats->sdk_fill_rect = spy_count_op(SPY_OP_FILL_RECT);
  stats->sdk_fill_circle = spy_count_op(SPY_OP_FILL_CIRCLE);
  stats->sdk_circle = spy_count_op(SPY_OP_DRAW_CIRCLE);
  return 0;
}
