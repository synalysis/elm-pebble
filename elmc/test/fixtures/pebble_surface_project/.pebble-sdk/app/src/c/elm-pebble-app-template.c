#include <pebble.h>
#include <stdio.h>
#include <stdbool.h>
#include "elmc/c/elmc_pebble.h"
#include "generated/companion_protocol.h"

static Window *s_main_window;
static Layer *s_draw_layer;
static GFont s_font;
static ElmcPebbleApp s_elm_app = {0};
static ElmcPebbleDrawCmd s_draw_cmds[16];
static int s_draw_count = 0;
static AppTimer *s_timer = NULL;
typedef struct {
  int32_t resource_id;
  GBitmap *bitmap;
} BitmapCacheEntry;
static BitmapCacheEntry s_bitmap_cache[24] = {0};
typedef struct {
  int32_t resource_id;
  GFont font;
} FontCacheEntry;
static FontCacheEntry s_font_cache[16] = {0};
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
static bool s_pending_companion_request = false;
static int s_pending_request_tag = 0;
static int s_pending_request_value = 0;
#endif
static ElmcPebbleRunMode s_run_mode = ELMC_PEBBLE_MODE_APP;

typedef struct {
  GColor stroke_color;
  GColor fill_color;
  GColor text_color;
  GCompOp compositing_mode;
  uint8_t stroke_width;
  bool antialiased;
} DrawStyleState;

static void render_model(void);
static void apply_pending_cmd(void);
static GBitmap *bitmap_cache_get(int32_t resource_id);
static void bitmap_cache_clear(void);
static GFont font_cache_get(int32_t resource_id);
static void font_cache_clear(void);
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
static bool send_companion_request(int request_tag, int request_value);
static void flush_pending_companion_request(void);
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_MODEL
static int64_t watch_model_to_elm_tag(WatchInfoModel model);
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_COLOR
static int64_t watch_color_to_elm_tag(WatchInfoColor color);
#endif

#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_MODEL
static int64_t watch_model_to_elm_tag(WatchInfoModel model) {
  (void)model;
  return 0;
}
#endif

#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_COLOR
static int64_t watch_color_to_elm_tag(WatchInfoColor color) {
  (void)color;
  return 0;
}
#endif

#if ELMC_PEBBLE_FEATURE_CMD_TIMER_AFTER_MS
static void timer_cmd_callback(void *data) {
  (void)data;
  s_timer = NULL;
  if (elmc_pebble_tick(&s_elm_app) == 0) {
    apply_pending_cmd();
    render_model();
  }
}
#endif

static void apply_pending_cmd(void) {
  ElmcPebbleCmd cmd = {0};
  if (elmc_pebble_take_cmd(&s_elm_app, &cmd) != 0) {
    return;
  }

  switch (cmd.kind) {
#if ELMC_PEBBLE_FEATURE_CMD_TIMER_AFTER_MS
    case ELMC_PEBBLE_CMD_TIMER_AFTER_MS: {
      uint32_t timeout_ms = cmd.p0 > 0 ? (uint32_t)cmd.p0 : 1;
      if (s_timer) {
        if (!app_timer_reschedule(s_timer, timeout_ms)) {
          app_timer_cancel(s_timer);
          s_timer = app_timer_register(timeout_ms, timer_cmd_callback, NULL);
        }
      } else {
        s_timer = app_timer_register(timeout_ms, timer_cmd_callback, NULL);
      }
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd timer_after_ms=%lu", (unsigned long)timeout_ms);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_INT
    case ELMC_PEBBLE_CMD_STORAGE_WRITE_INT: {
      uint32_t key = (uint32_t)cmd.p0;
      int32_t value = (int32_t)cmd.p1;
      status_t status = persist_write_int(key, value);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd storage_write key=%lu value=%ld status=%ld",
              (unsigned long)key, (long)value, (long)status);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_INT
    case ELMC_PEBBLE_CMD_STORAGE_READ_INT: {
      uint32_t key = (uint32_t)cmd.p0;
      int32_t value = persist_read_int(key);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd storage_read key=%lu value=%ld",
              (unsigned long)key, (long)value);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_STORAGE_DELETE
    case ELMC_PEBBLE_CMD_STORAGE_DELETE: {
      uint32_t key = (uint32_t)cmd.p0;
      status_t status = persist_delete(key);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd storage_delete key=%lu status=%ld",
              (unsigned long)key, (long)status);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
    case ELMC_PEBBLE_CMD_COMPANION_SEND: {
      int request_tag = (int)cmd.p0;
      int request_value = (int)cmd.p1;
      if (!send_companion_request(request_tag, request_value)) {
        s_pending_companion_request = true;
        s_pending_request_tag = request_tag;
        s_pending_request_value = request_value;
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_BACKLIGHT
    case ELMC_PEBBLE_CMD_BACKLIGHT: {
      if (cmd.p0 == 0) {
        light_enable_interaction();
        APP_LOG(APP_LOG_LEVEL_INFO, "cmd backlight interaction");
      } else if (cmd.p0 == 1) {
        light_enable(false);
        APP_LOG(APP_LOG_LEVEL_INFO, "cmd backlight disable");
      } else if (cmd.p0 == 2) {
        light_enable(true);
        APP_LOG(APP_LOG_LEVEL_INFO, "cmd backlight enable");
      } else {
        APP_LOG(APP_LOG_LEVEL_WARNING, "cmd backlight unknown mode=%ld", (long)cmd.p0);
      }
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_TIME_STRING
    case ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING: {
      char time_buffer[16] = {0};
      clock_copy_time_string(time_buffer, sizeof(time_buffer));
#if ELMC_PEBBLE_FEATURE_MSG_CURRENT_TIME
      int rc =
          elmc_pebble_dispatch_tag_string(&s_elm_app, ELMC_PEBBLE_MSG_CURRENTTIME, time_buffer);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd current_time=%s rc=%d", time_buffer, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
#else
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd current_time ignored (no msg tag)");
#endif
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_CLOCK_STYLE_24H
    case ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H: {
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd get_clock_style_24h ignored (no msg tag)");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_TIMEZONE_IS_SET
    case ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET: {
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd get_timezone_is_set ignored (no msg tag)");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_TIMEZONE
    case ELMC_PEBBLE_CMD_GET_TIMEZONE: {
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd get_timezone ignored (no msg tag)");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_MODEL
    case ELMC_PEBBLE_CMD_GET_WATCH_MODEL: {
      int64_t model_tag = watch_model_to_elm_tag(watch_info_get_model());
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd watch_model_tag=%ld ignored (no msg tag)", (long)model_tag);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_COLOR
    case ELMC_PEBBLE_CMD_GET_WATCH_COLOR: {
      int64_t color_tag = watch_color_to_elm_tag(watch_info_get_color());
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd watch_color_tag=%ld ignored (no msg tag)", (long)color_tag);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_GET_FIRMWARE_VERSION
    case ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION: {
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd get_firmware_version ignored (no msg tag)");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_WAKEUP_SCHEDULE_AFTER_SECONDS
    case ELMC_PEBBLE_CMD_WAKEUP_SCHEDULE_AFTER_SECONDS: {
      time_t now = time(NULL);
      WakeupId id = wakeup_schedule(now + cmd.p0, 0, true);
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd wakeup_schedule_after=%ld id=%ld", (long)cmd.p0, (long)id);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_WAKEUP_CANCEL
    case ELMC_PEBBLE_CMD_WAKEUP_CANCEL: {
      WakeupId id = (WakeupId)cmd.p0;
      wakeup_cancel(id);
      bool ok = true;
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd wakeup_cancel id=%ld ok=%d", (long)id, ok ? 1 : 0);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_LOG_INFO_CODE
    case ELMC_PEBBLE_CMD_LOG_INFO_CODE: {
      APP_LOG(APP_LOG_LEVEL_INFO, "elm log info code=%ld", (long)cmd.p0);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_LOG_WARN_CODE
    case ELMC_PEBBLE_CMD_LOG_WARN_CODE: {
      APP_LOG(APP_LOG_LEVEL_WARNING, "elm log warn code=%ld", (long)cmd.p0);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_LOG_ERROR_CODE
    case ELMC_PEBBLE_CMD_LOG_ERROR_CODE: {
      APP_LOG(APP_LOG_LEVEL_ERROR, "elm log error code=%ld", (long)cmd.p0);
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_CANCEL
    case ELMC_PEBBLE_CMD_VIBES_CANCEL: {
      vibes_cancel();
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_cancel");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_SHORT_PULSE
    case ELMC_PEBBLE_CMD_VIBES_SHORT_PULSE: {
      vibes_short_pulse();
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_short_pulse");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_LONG_PULSE
    case ELMC_PEBBLE_CMD_VIBES_LONG_PULSE: {
      vibes_long_pulse();
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_long_pulse");
      break;
    }
#endif
#if ELMC_PEBBLE_FEATURE_CMD_VIBES_DOUBLE_PULSE
    case ELMC_PEBBLE_CMD_VIBES_DOUBLE_PULSE: {
      vibes_double_pulse();
      APP_LOG(APP_LOG_LEVEL_INFO, "cmd vibes_double_pulse");
      break;
    }
#endif
    default:
      break;
  }
}

static GColor color_from_code(int64_t value) {
  return value == 0 ? GColorWhite : GColorBlack;
}

static GCompOp compositing_from_code(int64_t value) {
  switch ((int)value) {
    case 1:
      return GCompOpAnd;
    case 2:
      return GCompOpOr;
    case 3:
      return GCompOpSet;
    case 4:
      return GCompOpClear;
    case 0:
    default:
      return GCompOpAssign;
  }
}

static DrawStyleState draw_style_default(void) {
  DrawStyleState style = {
      .stroke_color = GColorBlack,
      .fill_color = GColorBlack,
      .text_color = GColorBlack,
      .compositing_mode = GCompOpAssign,
      .stroke_width = 1,
      .antialiased = true,
  };
  return style;
}

static void apply_draw_style(GContext *ctx, const DrawStyleState *style) {
  if (!ctx || !style) {
    return;
  }
  graphics_context_set_stroke_color(ctx, style->stroke_color);
  graphics_context_set_fill_color(ctx, style->fill_color);
  graphics_context_set_text_color(ctx, style->text_color);
  graphics_context_set_compositing_mode(ctx, style->compositing_mode);
  graphics_context_set_stroke_width(ctx, style->stroke_width > 0 ? style->stroke_width : 1);
  graphics_context_set_antialiased(ctx, style->antialiased);
}

static GBitmap *bitmap_cache_get(int32_t resource_id) {
  if (resource_id <= 0) {
    return NULL;
  }

  for (size_t i = 0; i < sizeof(s_bitmap_cache) / sizeof(s_bitmap_cache[0]); i++) {
    if (s_bitmap_cache[i].resource_id == resource_id && s_bitmap_cache[i].bitmap) {
      return s_bitmap_cache[i].bitmap;
    }
  }

  GBitmap *bitmap = gbitmap_create_with_resource((uint32_t)resource_id);
  if (!bitmap) {
    return NULL;
  }

  for (size_t i = 0; i < sizeof(s_bitmap_cache) / sizeof(s_bitmap_cache[0]); i++) {
    if (s_bitmap_cache[i].bitmap == NULL) {
      s_bitmap_cache[i].resource_id = resource_id;
      s_bitmap_cache[i].bitmap = bitmap;
      return bitmap;
    }
  }

  gbitmap_destroy(bitmap);
  return NULL;
}

static void bitmap_cache_clear(void) {
  for (size_t i = 0; i < sizeof(s_bitmap_cache) / sizeof(s_bitmap_cache[0]); i++) {
    if (s_bitmap_cache[i].bitmap) {
      gbitmap_destroy(s_bitmap_cache[i].bitmap);
      s_bitmap_cache[i].bitmap = NULL;
      s_bitmap_cache[i].resource_id = 0;
    }
  }
}

static GFont font_cache_get(int32_t resource_id) {
  if (resource_id <= 0) {
    return NULL;
  }

  for (size_t i = 0; i < sizeof(s_font_cache) / sizeof(s_font_cache[0]); i++) {
    if (s_font_cache[i].resource_id == resource_id && s_font_cache[i].font) {
      return s_font_cache[i].font;
    }
  }

  ResHandle handle = resource_get_handle((uint32_t)resource_id);
  if (!handle) {
    return NULL;
  }

  GFont font = fonts_load_custom_font(handle);
  if (!font) {
    return NULL;
  }

  for (size_t i = 0; i < sizeof(s_font_cache) / sizeof(s_font_cache[0]); i++) {
    if (s_font_cache[i].font == NULL) {
      s_font_cache[i].resource_id = resource_id;
      s_font_cache[i].font = font;
      return font;
    }
  }

  fonts_unload_custom_font(font);
  return NULL;
}

static void font_cache_clear(void) {
  for (size_t i = 0; i < sizeof(s_font_cache) / sizeof(s_font_cache[0]); i++) {
    if (s_font_cache[i].font) {
      fonts_unload_custom_font(s_font_cache[i].font);
      s_font_cache[i].font = NULL;
      s_font_cache[i].resource_id = 0;
    }
  }
}

static void draw_update_proc(Layer *layer, GContext *ctx) {
  GRect bounds = layer_get_bounds(layer);
  graphics_context_set_fill_color(ctx, GColorWhite);
  graphics_fill_rect(ctx, bounds, 0, GCornerNone);

  char text_buf[32];
  bool drew_text = false;
  DrawStyleState style_stack[8];
  int style_top = 0;
  style_stack[style_top] = draw_style_default();
  apply_draw_style(ctx, &style_stack[style_top]);

  for (int i = 0; i < s_draw_count; i++) {
    ElmcPebbleDrawCmd cmd = s_draw_cmds[i];
    switch (cmd.kind) {
      case ELMC_PEBBLE_DRAW_PUSH_CONTEXT:
        if (style_top < (int)(sizeof(style_stack) / sizeof(style_stack[0])) - 1) {
          style_stack[style_top + 1] = style_stack[style_top];
          style_top += 1;
          apply_draw_style(ctx, &style_stack[style_top]);
        }
        break;
      case ELMC_PEBBLE_DRAW_POP_CONTEXT:
        if (style_top > 0) {
          style_top -= 1;
          apply_draw_style(ctx, &style_stack[style_top]);
        }
        break;
      case ELMC_PEBBLE_DRAW_STROKE_WIDTH: {
        uint8_t width = (uint8_t)(cmd.p0 <= 0 ? 1 : cmd.p0);
        style_stack[style_top].stroke_width = width;
        graphics_context_set_stroke_width(ctx, width);
        break;
      }
      case ELMC_PEBBLE_DRAW_ANTIALIASED:
        style_stack[style_top].antialiased = cmd.p0 != 0;
        graphics_context_set_antialiased(ctx, style_stack[style_top].antialiased);
        break;
      case ELMC_PEBBLE_DRAW_STROKE_COLOR:
        style_stack[style_top].stroke_color = color_from_code(cmd.p0);
        graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        break;
      case ELMC_PEBBLE_DRAW_FILL_COLOR:
        style_stack[style_top].fill_color = color_from_code(cmd.p0);
        graphics_context_set_fill_color(ctx, style_stack[style_top].fill_color);
        break;
      case ELMC_PEBBLE_DRAW_TEXT_COLOR:
        style_stack[style_top].text_color = color_from_code(cmd.p0);
        graphics_context_set_text_color(ctx, style_stack[style_top].text_color);
        break;
      case ELMC_PEBBLE_DRAW_COMPOSITING_MODE:
        style_stack[style_top].compositing_mode = compositing_from_code(cmd.p0);
        graphics_context_set_compositing_mode(ctx, style_stack[style_top].compositing_mode);
        break;
      case ELMC_PEBBLE_DRAW_CLEAR:
        graphics_context_set_fill_color(ctx, color_from_code(cmd.p0));
        graphics_fill_rect(ctx, bounds, 0, GCornerNone);
        graphics_context_set_fill_color(ctx, style_stack[style_top].fill_color);
        break;
      case ELMC_PEBBLE_DRAW_LINE: {
        int16_t x1 = (int16_t)cmd.p0;
        int16_t y1 = (int16_t)cmd.p1;
        int16_t x2 = (int16_t)cmd.p2;
        int16_t y2 = (int16_t)cmd.p3;
        graphics_draw_line(ctx, GPoint(x1, y1), GPoint(x2, y2));
        break;
      }
      case ELMC_PEBBLE_DRAW_FILL_RECT: {
        int16_t x = (int16_t)cmd.p0;
        int16_t y = (int16_t)cmd.p1;
        int16_t w = (int16_t)cmd.p2;
        int16_t h = (int16_t)cmd.p3;
        graphics_fill_rect(ctx, GRect(x, y, w, h), 0, GCornerNone);
        break;
      }
      case ELMC_PEBBLE_DRAW_RECT: {
        int16_t x = (int16_t)cmd.p0;
        int16_t y = (int16_t)cmd.p1;
        int16_t w = (int16_t)cmd.p2;
        int16_t h = (int16_t)cmd.p3;
        graphics_draw_rect(ctx, GRect(x, y, w, h));
        break;
      }
      case ELMC_PEBBLE_DRAW_ROUND_RECT: {
        int16_t x = (int16_t)cmd.p0;
        int16_t y = (int16_t)cmd.p1;
        int16_t w = (int16_t)cmd.p2;
        int16_t h = (int16_t)cmd.p3;
        uint16_t radius = (uint16_t)(cmd.p4 < 0 ? 0 : cmd.p4);
        graphics_context_set_stroke_color(ctx, color_from_code(cmd.p5));
        graphics_draw_round_rect(ctx, GRect(x, y, w, h), radius);
        graphics_context_set_stroke_color(ctx, style_stack[style_top].stroke_color);
        break;
      }
      case ELMC_PEBBLE_DRAW_ARC: {
        int16_t x = (int16_t)cmd.p0;
        int16_t y = (int16_t)cmd.p1;
        int16_t w = (int16_t)cmd.p2;
        int16_t h = (int16_t)cmd.p3;
        int32_t angle_start = (int32_t)cmd.p4;
        int32_t angle_end = (int32_t)cmd.p5;
        graphics_draw_arc(ctx, GRect(x, y, w, h), GOvalScaleModeFitCircle, angle_start, angle_end);
        break;
      }
      case ELMC_PEBBLE_DRAW_FILL_RADIAL: {
        int16_t x = (int16_t)cmd.p0;
        int16_t y = (int16_t)cmd.p1;
        int16_t w = (int16_t)cmd.p2;
        int16_t h = (int16_t)cmd.p3;
        int32_t angle_start = (int32_t)cmd.p4;
        int32_t angle_end = (int32_t)cmd.p5;
        uint16_t thickness = (uint16_t)((w < h ? w : h) / 2);
        graphics_fill_radial(ctx, GRect(x, y, w, h), GOvalScaleModeFitCircle, thickness, angle_start, angle_end);
        break;
      }
      case ELMC_PEBBLE_DRAW_BITMAP_IN_RECT: {
        int32_t resource_id = (int32_t)cmd.p0;
        int16_t x = (int16_t)cmd.p1;
        int16_t y = (int16_t)cmd.p2;
        int16_t w = (int16_t)cmd.p3;
        int16_t h = (int16_t)cmd.p4;
        GBitmap *bitmap = bitmap_cache_get(resource_id);
        if (bitmap) {
          graphics_draw_bitmap_in_rect(ctx, bitmap, GRect(x, y, w, h));
        }
        break;
      }
      case ELMC_PEBBLE_DRAW_ROTATED_BITMAP: {
        int32_t resource_id = (int32_t)cmd.p0;
        int16_t src_w = (int16_t)cmd.p1;
        int16_t src_h = (int16_t)cmd.p2;
        int32_t angle = (int32_t)cmd.p3;
        int16_t center_x = (int16_t)cmd.p4;
        int16_t center_y = (int16_t)cmd.p5;
        GBitmap *bitmap = bitmap_cache_get(resource_id);
        if (bitmap) {
          graphics_draw_rotated_bitmap(
              ctx, bitmap, GRect(0, 0, src_w, src_h), angle, GPoint(center_x, center_y));
        }
        break;
      }
      case ELMC_PEBBLE_DRAW_PATH_FILLED:
      case ELMC_PEBBLE_DRAW_PATH_OUTLINE:
      case ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN: {
        int count = (int)cmd.path_point_count;
        if (count <= 1) {
          break;
        }
        if (count > 16) {
          count = 16;
        }
        GPoint points[16];
        for (int j = 0; j < count; j++) {
          points[j] = GPoint((int16_t)cmd.path_x[j], (int16_t)cmd.path_y[j]);
        }
        GPathInfo path_info = {
            .num_points = (uint32_t)count,
            .points = points,
        };
        GPath *path = gpath_create(&path_info);
        if (!path) {
          break;
        }
        gpath_move_to(path, GPoint((int16_t)cmd.path_offset_x, (int16_t)cmd.path_offset_y));
        if (cmd.path_rotation != 0) {
          gpath_rotate_to(path, (int32_t)cmd.path_rotation);
        }
        if (cmd.kind == ELMC_PEBBLE_DRAW_PATH_FILLED) {
          gpath_draw_filled(ctx, path);
        } else if (cmd.kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE) {
          gpath_draw_outline(ctx, path);
        } else {
          gpath_draw_outline_open(ctx, path);
        }
        gpath_destroy(path);
        break;
      }
      case ELMC_PEBBLE_DRAW_CIRCLE: {
        int16_t x = (int16_t)cmd.p0;
        int16_t y = (int16_t)cmd.p1;
        int16_t r = (int16_t)cmd.p2;
        graphics_draw_circle(ctx, GPoint(x, y), r);
        break;
      }
      case ELMC_PEBBLE_DRAW_FILL_CIRCLE: {
        int16_t x = (int16_t)cmd.p0;
        int16_t y = (int16_t)cmd.p1;
        int16_t r = (int16_t)cmd.p2;
        graphics_fill_circle(ctx, GPoint(x, y), r);
        break;
      }
      case ELMC_PEBBLE_DRAW_PIXEL: {
        int16_t x = (int16_t)cmd.p0;
        int16_t y = (int16_t)cmd.p1;
        graphics_draw_pixel(ctx, GPoint(x, y));
        break;
      }
      case ELMC_PEBBLE_DRAW_TEXT_INT:
        snprintf(text_buf, sizeof(text_buf), "%lld", (long long)cmd.p2);
        graphics_draw_text(ctx, text_buf, s_font,
                           GRect((int16_t)cmd.p0, (int16_t)cmd.p1, bounds.size.w, bounds.size.h),
                           GTextOverflowModeWordWrap,
                           GTextAlignmentCenter, NULL);
        drew_text = true;
        break;
      case ELMC_PEBBLE_DRAW_TEXT_LABEL: {
        const char *label = "Label";
        if (cmd.p2 == 0) {
          label = "Waiting for companion app";
        }
        graphics_draw_text(ctx, label, s_font,
                           GRect((int16_t)cmd.p0, (int16_t)cmd.p1, bounds.size.w, bounds.size.h),
                           GTextOverflowModeWordWrap,
                           GTextAlignmentCenter, NULL);
        drew_text = true;
        break;
      }
      case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT: {
        int32_t font_resource_id = (int32_t)cmd.p0;
        GFont active_font = font_cache_get(font_resource_id);
        if (!active_font) {
          active_font = s_font;
        }
        snprintf(text_buf, sizeof(text_buf), "%lld", (long long)cmd.p3);
        graphics_draw_text(ctx, text_buf, active_font,
                           GRect((int16_t)cmd.p1, (int16_t)cmd.p2, bounds.size.w, bounds.size.h),
                           GTextOverflowModeWordWrap,
                           GTextAlignmentCenter, NULL);
        drew_text = true;
        break;
      }
      case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT: {
        int32_t font_resource_id = (int32_t)cmd.p0;
        GFont active_font = font_cache_get(font_resource_id);
        if (!active_font) {
          active_font = s_font;
        }
        const char *label = "Label";
        if (cmd.p3 == 0) {
          label = "Waiting for companion app";
        }
        graphics_draw_text(ctx, label, active_font,
                           GRect((int16_t)cmd.p1, (int16_t)cmd.p2, bounds.size.w, bounds.size.h),
                           GTextOverflowModeWordWrap,
                           GTextAlignmentCenter, NULL);
        drew_text = true;
        break;
      }
      default:
        break;
    }
  }

  (void)drew_text;

}

static void render_model(void) {
  int rc = elmc_pebble_view_commands(&s_elm_app, s_draw_cmds, (int)(sizeof(s_draw_cmds) / sizeof(s_draw_cmds[0])));
  int64_t value = elmc_pebble_model_as_int(&s_elm_app);

  if (rc > 0) {
    s_draw_count = rc;
    layer_mark_dirty(s_draw_layer);
  } else if (rc < 0) {
    s_draw_count = 0;
    layer_mark_dirty(s_draw_layer);
  }
  APP_LOG(APP_LOG_LEVEL_INFO, "elmc view_count=%d model=%lld rc=%d",
          s_draw_count, (long long)value, rc);
}

static void tick_handler(struct tm *tick_time, TimeUnits units_changed) {
  (void)tick_time;
  (void)units_changed;
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
  flush_pending_companion_request();
#endif
  if (elmc_pebble_tick(&s_elm_app) == 0) {
    apply_pending_cmd();
    render_model();
  }
}

#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
static bool send_companion_request(int request_tag, int request_value) {
  DictionaryIterator *iter = NULL;
  AppMessageResult rc = app_message_outbox_begin(&iter);
  if (rc != APP_MSG_OK || !iter) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "outbox_begin failed: %d", rc);
    return false;
  }

  if (!companion_protocol_encode_watch_to_phone(iter, request_tag, request_value)) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "protocol encode failed tag=%d value=%d", request_tag, request_value);
    return false;
  }
  dict_write_end(iter);

  rc = app_message_outbox_send();
  APP_LOG(APP_LOG_LEVEL_INFO, "watch -> companion tag=%d value=%d rc=%d", request_tag, request_value, rc);
  return rc == APP_MSG_OK;
}

static void flush_pending_companion_request(void) {
  if (!s_pending_companion_request) {
    return;
  }
  if (send_companion_request(s_pending_request_tag, s_pending_request_value)) {
    s_pending_companion_request = false;
  }
}
#endif

#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
static void inbox_received_handler(DictionaryIterator *iter, void *context) {
  (void)context;
  Tuple *tuple = dict_read_first(iter);
  CompanionProtocolPhoneToWatchDecoder decoder;
  companion_protocol_phone_to_watch_decoder_init(&decoder);

  while (tuple) {
    companion_protocol_phone_to_watch_decoder_push_tuple(&decoder, tuple);

    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      int rc = elmc_pebble_dispatch_appmessage(&s_elm_app, tuple->key, tuple->value->int32);
      APP_LOG(APP_LOG_LEVEL_INFO, "appmessage key=%lu value=%ld rc=%d",
              (unsigned long)tuple->key, (long)tuple->value->int32, rc);
      if (rc == 0) {
        apply_pending_cmd();
        render_model();
      }
    }
    tuple = dict_read_next(iter);
  }

  CompanionProtocolPhoneToWatchMessage message = {0};
  if (companion_protocol_phone_to_watch_decoder_finish(&decoder, &message) &&
      message.kind != COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN) {
#if ELMC_PEBBLE_FEATURE_MSG_PROVIDE_TEMPERATURE
    int rc = elmc_pebble_dispatch_tag_value(
        &s_elm_app,
        ELMC_PEBBLE_MSG_PROVIDETEMPERATURE,
        message.value);
    APP_LOG(APP_LOG_LEVEL_INFO, "companion response msg_tag=%d value=%d rc=%d",
            ELMC_PEBBLE_MSG_PROVIDETEMPERATURE,
            message.value,
            rc);
    if (rc == 0) {
      apply_pending_cmd();
      render_model();
    } else {
      layer_mark_dirty(s_draw_layer);
    }
#else
    layer_mark_dirty(s_draw_layer);
#endif
  }
}

static void inbox_dropped_handler(AppMessageResult reason, void *context) {
  (void)context;
  APP_LOG(APP_LOG_LEVEL_WARNING, "inbox dropped: %d", reason);
}
#endif

#if ELMC_PEBBLE_FEATURE_BUTTON_EVENTS
static void click_handler(ClickRecognizerRef recognizer, void *context) {
  (void)context;
  ButtonId pebble_button_id = click_recognizer_get_button_id(recognizer);
  ElmcPebbleButtonId button_id = ELMC_PEBBLE_BUTTON_SELECT;
  if (pebble_button_id == BUTTON_ID_UP) {
    button_id = ELMC_PEBBLE_BUTTON_UP;
  } else if (pebble_button_id == BUTTON_ID_DOWN) {
    button_id = ELMC_PEBBLE_BUTTON_DOWN;
  }

  int rc = elmc_pebble_dispatch_button(&s_elm_app, button_id);
  APP_LOG(APP_LOG_LEVEL_INFO, "button dispatch id=%d rc=%d", (int)button_id, rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
}

static void click_config_provider(void *context) {
  (void)context;
  window_single_click_subscribe(BUTTON_ID_UP, click_handler);
  window_single_click_subscribe(BUTTON_ID_SELECT, click_handler);
  window_single_click_subscribe(BUTTON_ID_DOWN, click_handler);
}
#endif

#if ELMC_PEBBLE_FEATURE_ACCEL_EVENTS
static void accel_tap_handler(AccelAxisType axis, int32_t direction) {
  int32_t mapped_axis = ELMC_PEBBLE_ACCEL_AXIS_X;
  if (axis == ACCEL_AXIS_Y) {
    mapped_axis = ELMC_PEBBLE_ACCEL_AXIS_Y;
  } else if (axis == ACCEL_AXIS_Z) {
    mapped_axis = ELMC_PEBBLE_ACCEL_AXIS_Z;
  }

  int rc = elmc_pebble_dispatch_accel_tap(&s_elm_app, mapped_axis, direction);
  APP_LOG(APP_LOG_LEVEL_INFO, "accel tap axis=%ld dir=%ld rc=%d", (long)mapped_axis, (long)direction,
          rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
}
#endif

#if ELMC_PEBBLE_FEATURE_BATTERY_EVENTS
static void battery_handler(BatteryChargeState state) {
  int rc = elmc_pebble_dispatch_battery(&s_elm_app, state.charge_percent);
  APP_LOG(APP_LOG_LEVEL_INFO, "battery dispatch rc=%d", rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
}
#endif

#if ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS
static void connection_handler(bool connected) {
  int rc = elmc_pebble_dispatch_connection(&s_elm_app, connected);
  APP_LOG(APP_LOG_LEVEL_INFO, "connection dispatch rc=%d", rc);
  if (rc == 0) {
    apply_pending_cmd();
    render_model();
  }
}
#endif

static void main_window_load(Window *window) {
  Layer *window_layer = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(window_layer);

  s_font = fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD);
  s_draw_layer = layer_create(bounds);
  layer_set_update_proc(s_draw_layer, draw_update_proc);
  layer_add_child(window_layer, s_draw_layer);
}

static void main_window_unload(Window *window) {
  (void)window;
  layer_destroy(s_draw_layer);
  s_draw_layer = NULL;
}

static void init(void) {
#ifdef ELMC_WATCHFACE_MODE
  s_run_mode = ELMC_PEBBLE_MODE_WATCHFACE;
#else
  s_run_mode = ELMC_PEBBLE_MODE_APP;
#endif

  s_main_window = window_create();
  window_set_window_handlers(s_main_window, (WindowHandlers){
                                               .load = main_window_load,
                                               .unload = main_window_unload,
                                           });
#if ELMC_PEBBLE_FEATURE_BUTTON_EVENTS
  if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
    window_set_click_config_provider(s_main_window, click_config_provider);
  }
#endif
  window_stack_push(s_main_window, true);

  AppLaunchReason launch = launch_reason();
  ElmcValue *flags = elmc_new_int((int64_t)launch);
  int rc = elmc_pebble_init_with_mode(&s_elm_app, flags, s_run_mode);
  elmc_release(flags);
  APP_LOG(APP_LOG_LEVEL_INFO, "launch_reason=%d mode=%d", (int)launch, (int)s_run_mode);

  if (rc == 0) {
#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS
    app_message_register_inbox_received(inbox_received_handler);
    app_message_register_inbox_dropped(inbox_dropped_handler);
#endif
#if ELMC_PEBBLE_FEATURE_INBOX_EVENTS || ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
    app_message_open(256, 256);
#endif
    apply_pending_cmd();
#if ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND
    flush_pending_companion_request();
#endif
    render_model();
#if ELMC_PEBBLE_FEATURE_TICK_EVENTS
    tick_timer_service_subscribe(SECOND_UNIT, tick_handler);
#endif
#if ELMC_PEBBLE_FEATURE_ACCEL_EVENTS
    if (s_run_mode == ELMC_PEBBLE_MODE_APP) {
      accel_tap_service_subscribe(accel_tap_handler);
    }
#endif
#if ELMC_PEBBLE_FEATURE_BATTERY_EVENTS
    battery_state_service_subscribe(battery_handler);
#endif
#if ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS
    connection_service_subscribe((ConnectionHandlers){
        .pebble_app_connection_handler = connection_handler,
    });
#endif
  } else {
    APP_LOG(APP_LOG_LEVEL_ERROR, "elmc_pebble_init failed: %d", rc);
  }
}

static void deinit(void) {
#if ELMC_PEBBLE_FEATURE_TICK_EVENTS
  tick_timer_service_unsubscribe();
#endif
  if (s_timer) {
    app_timer_cancel(s_timer);
    s_timer = NULL;
  }
  if (s_run_mode == ELMC_PEBBLE_MODE_APP && ELMC_PEBBLE_FEATURE_ACCEL_EVENTS) {
    accel_tap_service_unsubscribe();
  }
#if ELMC_PEBBLE_FEATURE_BATTERY_EVENTS
  battery_state_service_unsubscribe();
#endif
#if ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS
  connection_service_unsubscribe();
#endif
  bitmap_cache_clear();
  font_cache_clear();
  elmc_pebble_deinit(&s_elm_app);
  window_destroy(s_main_window);
}

int main(void) {
  init();
  app_event_loop();
  deinit();
}
