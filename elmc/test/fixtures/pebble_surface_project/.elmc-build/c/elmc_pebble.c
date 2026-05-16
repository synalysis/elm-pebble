#include "elmc_pebble.h"
#include <time.h>
#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
#define ELMC_PEBBLE_PLATFORM 1
#endif
#ifdef ELMC_PEBBLE_PLATFORM
#include <pebble.h>
#endif
#include <stdlib.h>
#include <string.h>

#if defined(ELMC_PEBBLE_TRACE_FUNCTIONS) && defined(ELMC_PEBBLE_PLATFORM)
#define ELMC_PEBBLE_GENERATED_TRACE_ENTER(name) app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "g+%d", __LINE__)
#define ELMC_PEBBLE_GENERATED_TRACE_EXIT(name) app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "g-%d", __LINE__)
#define ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT(name, value) \
  do { \
    int elmc_pebble_trace_rc__ = (value); \
    app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "g-%d rc=%d", __LINE__, elmc_pebble_trace_rc__); \
    return elmc_pebble_trace_rc__; \
  } while (0)
#else
#define ELMC_PEBBLE_GENERATED_TRACE_ENTER(name) do { } while (0)
#define ELMC_PEBBLE_GENERATED_TRACE_EXIT(name) do { } while (0)
#define ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT(name, value) return (value)
#endif

#ifndef ELMC_AGENT_PROBES
#define ELMC_AGENT_PROBES 0
#endif

#ifndef ELMC_PEBBLE_DIRTY_REGION_ENABLED
#if defined(ELMC_PEBBLE_PLATFORM)
#define ELMC_PEBBLE_DIRTY_REGION_ENABLED 0
#else
#define ELMC_PEBBLE_DIRTY_REGION_ENABLED 1
#endif
#endif

#ifdef ELMC_PEBBLE_PLATFORM
extern long time(long *timer);

static int elmc_current_second(void) {
  long now = time(NULL);
  if (now == -1L) return 0;
  return (int)(now % 60);
}
#else
static int elmc_current_second(void) {
  time_t now = time(NULL);
  if (now == (time_t)-1) return 0;
  return (int)(now % 60);
}
#endif


// #region agent log
#if defined(ELMC_PEBBLE_PLATFORM) && ELMC_AGENT_PROBES
static bool elmc_agent_scene_probe_enabled(uint32_t tag) {
  return tag == 0xED997A00 ||
         tag == 0xED997C02 ||
         tag == 0xED996191 ||
         tag == 0xED996211 ||
         tag == 0xED996213 ||
         tag == 0xED996300 ||
         tag == 0xED9963F0 ||
         tag == 0xED996410 ||
         tag == 0xED996411 ||
         tag == 0xED996412 ||
         tag == 0xED996413 ||
         tag == 0xED996500 ||
         tag == 0xED996501 ||
         (tag & 0xFFFFFF00) == 0xED997000 ||
         (tag & 0xFFFFFF00) == 0xED997100 ||
         (tag & 0xFFFFFF00) == 0xED997B00 ||
         (tag & 0xFFFFFF00) == 0xED997D00 ||
         (tag & 0xFFFFFF00) == 0xED997E00 ||
         (tag & 0xFFFFFF00) == 0xED997F00 ||
         (tag & 0xFFFFFF00) == 0xED998000 ||
         (tag & 0xFFFFFF00) == 0xED998100;
}

static void elmc_agent_scene_probe(uint32_t tag) {
  if (!elmc_agent_scene_probe_enabled(tag)) return;
  static uint32_t seen_tags[16];
  static int seen_count = 0;
  for (int i = 0; i < seen_count; i++) {
    if (seen_tags[i] == tag) return;
  }
  if (seen_count >= 16) return;
  DataLoggingSessionRef session =
      data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
  if (session) {
    seen_tags[seen_count++] = tag;
    data_logging_finish(session);
  }
}
#else
#define elmc_agent_scene_probe(tag) do { (void)(tag); } while (0)
#endif

#if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
static uint32_t elmc_agent_value_shape(ElmcValue *value) {
  if (!value) return 0x0;
  switch (value->tag) {
    case ELMC_TAG_INT: return 0x1;
    case ELMC_TAG_BOOL: return 0x2;
    case ELMC_TAG_STRING: return 0x3;
    case ELMC_TAG_LIST: return value->payload ? 0x41 : 0x40;
    case ELMC_TAG_RESULT: return 0x5;
    case ELMC_TAG_MAYBE: return 0x6;
    case ELMC_TAG_TUPLE2: return value->payload ? 0x71 : 0x70;
    case ELMC_TAG_PORT_PAYLOAD: return 0x9;
    case ELMC_TAG_FLOAT: return 0xA;
    default: return 0xF;
  }
}
#endif

// #endregion

static int elmc_unpack_draw_payload(ElmcValue *payload, int64_t out[6]) {
  if (!payload) return -1;
  ElmcValue *current = payload;
  for (int i = 0; i < 5; i++) {
    if (!current || current->tag != ELMC_TAG_TUPLE2 || current->payload == NULL) return -2;
    ElmcTuple2 *tuple = (ElmcTuple2 *)current->payload;
    if (!tuple->first || !tuple->second) return -3;
    out[i] = elmc_as_int(tuple->first);
    current = tuple->second;
  }
  if (!current) return -4;
  out[5] = elmc_as_int(current);
  return 0;
}

#if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
static int elmc_decode_path_payload(ElmcValue *payload, ElmcPebbleDrawCmd *out_cmd);
#endif

static int elmc_draw_cmd_from_value(ElmcValue *value, ElmcPebbleDrawCmd *out_cmd) {
  if (!out_cmd) return -1;
  out_cmd->kind = ELMC_PEBBLE_DRAW_NONE;
  out_cmd->p0 = 0;
  out_cmd->p1 = 0;
  out_cmd->p2 = 0;
  out_cmd->p3 = 0;
  out_cmd->p4 = 0;
  out_cmd->p5 = 0;
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  out_cmd->path_point_count = 0;
  out_cmd->path_offset_x = 0;
  out_cmd->path_offset_y = 0;
  out_cmd->path_rotation = 0;
  for (int i = 0; i < 16; i++) {
    out_cmd->path_x[i] = 0;
    out_cmd->path_y[i] = 0;
  }
#endif
  out_cmd->text[0] = '\0';
  if (!value) return -2;

  if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (!tuple->first || !tuple->second) return -3;
    out_cmd->kind = elmc_as_int(tuple->first);
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
    if (out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
        out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
        out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
      return elmc_decode_path_payload(tuple->second, out_cmd);
    }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT
    if (out_cmd->kind == ELMC_PEBBLE_DRAW_TEXT) {
      int64_t payload[5] = {0, 0, 0, 0, 0};
      ElmcValue *current = tuple->second;
      for (int i = 0; i < 5; i++) {
        if (!current || current->tag != ELMC_TAG_TUPLE2 || current->payload == NULL) return -5;
        ElmcTuple2 *node = (ElmcTuple2 *)current->payload;
        if (!node->first || !node->second) return -6;
        payload[i] = elmc_as_int(node->first);
        current = node->second;
      }
      out_cmd->p0 = payload[0];
      out_cmd->p1 = payload[1];
      out_cmd->p2 = payload[2];
      out_cmd->p3 = payload[3];
      out_cmd->p4 = payload[4];
      if (current && current->tag == ELMC_TAG_STRING && current->payload != NULL) {
        strncpy(out_cmd->text, (const char *)current->payload, sizeof(out_cmd->text) - 1);
        out_cmd->text[sizeof(out_cmd->text) - 1] = '\0';
      }
      return 0;
    }
#endif
    int64_t payload[6] = {0, 0, 0, 0, 0, 0};
    if (elmc_unpack_draw_payload(tuple->second, payload) == 0) {
      out_cmd->p0 = payload[0];
      out_cmd->p1 = payload[1];
      out_cmd->p2 = payload[2];
      out_cmd->p3 = payload[3];
      out_cmd->p4 = payload[4];
      out_cmd->p5 = payload[5];
    } else {
      out_cmd->p0 = elmc_as_int(tuple->second);
    }
    return 0;
  }

  return -4;
}

#if ELMC_PEBBLE_FEATURE_DRAW_PATH
static int elmc_decode_path_payload(ElmcValue *payload, ElmcPebbleDrawCmd *out_cmd) {
  if (!payload || !out_cmd) return -1;
  if (payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) return -2;
  ElmcTuple2 *outer = (ElmcTuple2 *)payload->payload;
  if (!outer->first || !outer->second) return -3;

  ElmcValue *points = outer->first;
  ElmcValue *offset_and_rotation = outer->second;

  if (!offset_and_rotation || offset_and_rotation->tag != ELMC_TAG_TUPLE2 || offset_and_rotation->payload == NULL) return -4;
  ElmcTuple2 *off1 = (ElmcTuple2 *)offset_and_rotation->payload;
  if (!off1->first || !off1->second) return -5;
  out_cmd->path_offset_x = elmc_as_int(off1->first);

  if (off1->second->tag != ELMC_TAG_TUPLE2 || off1->second->payload == NULL) return -6;
  ElmcTuple2 *off2 = (ElmcTuple2 *)off1->second->payload;
  if (!off2->first || !off2->second) return -7;
  out_cmd->path_offset_y = elmc_as_int(off2->first);
  out_cmd->path_rotation = elmc_as_int(off2->second);

  int count = 0;
  ElmcValue *cursor = points;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < 16) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (!node->head || node->head->tag != ELMC_TAG_TUPLE2 || node->head->payload == NULL) break;
    ElmcTuple2 *point = (ElmcTuple2 *)node->head->payload;
    if (!point->first || !point->second) break;
    out_cmd->path_x[count] = elmc_as_int(point->first);
    out_cmd->path_y[count] = elmc_as_int(point->second);
    count += 1;
    cursor = node->tail;
  }
  out_cmd->path_point_count = count;
  return count > 0 ? 0 : -8;
}
#endif

static int elmc_draw_setting_cmd_from_value(ElmcValue *value, ElmcPebbleDrawCmd *out_cmd) {
  if (!out_cmd || !value || value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return -1;
  ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
  if (!tuple->first || !tuple->second) return -2;

  int64_t setting_tag = elmc_as_int(tuple->first);
  int64_t setting_value = elmc_as_int(tuple->second);

  out_cmd->kind = ELMC_PEBBLE_DRAW_NONE;
  out_cmd->p0 = setting_value;
  out_cmd->p1 = 0;
  out_cmd->p2 = 0;
  out_cmd->p3 = 0;
  out_cmd->p4 = 0;
  out_cmd->p5 = 0;
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  out_cmd->path_point_count = 0;
  out_cmd->path_offset_x = 0;
  out_cmd->path_offset_y = 0;
  out_cmd->path_rotation = 0;
  for (int i = 0; i < 16; i++) {
    out_cmd->path_x[i] = 0;
    out_cmd->path_y[i] = 0;
  }
#endif
  out_cmd->text[0] = '\0';
  switch (setting_tag) {
#if ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH
    case 1: out_cmd->kind = ELMC_PEBBLE_DRAW_STROKE_WIDTH; return 0;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
    case 2: out_cmd->kind = ELMC_PEBBLE_DRAW_ANTIALIASED; return 0;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR
    case 3: out_cmd->kind = ELMC_PEBBLE_DRAW_STROKE_COLOR; return 0;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR
    case 4: out_cmd->kind = ELMC_PEBBLE_DRAW_FILL_COLOR; return 0;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR
    case 5: out_cmd->kind = ELMC_PEBBLE_DRAW_TEXT_COLOR; return 0;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
    case 6: out_cmd->kind = ELMC_PEBBLE_DRAW_COMPOSITING_MODE; return 0;
#endif
    default: return -3;
  }
}
#endif

static void elmc_draw_cmd_init(ElmcPebbleDrawCmd *cmd, int32_t kind) {
  if (!cmd) return;
  cmd->kind = kind;
  cmd->p0 = 0;
  cmd->p1 = 0;
  cmd->p2 = 0;
  cmd->p3 = 0;
  cmd->p4 = 0;
  cmd->p5 = 0;
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  cmd->path_point_count = 0;
  cmd->path_offset_x = 0;
  cmd->path_offset_y = 0;
  cmd->path_rotation = 0;
  for (int i = 0; i < 16; i++) {
    cmd->path_x[i] = 0;
    cmd->path_y[i] = 0;
  }
#endif
  cmd->text[0] = '\0';
}

static void elmc_pebble_scene_reset(ElmcPebbleApp *app) {
  if (!app) return;
  app->scene.byte_count = 0;
  app->scene.command_count = 0;
  app->scene.hash = 1469598103934665603ULL;
}

static void elmc_pebble_scene_buffer_free(ElmcPebbleSceneBuffer *scene) {
  if (!scene) return;
  if (scene->bytes) {
    free(scene->bytes);
  }
  scene->bytes = NULL;
  scene->byte_count = 0;
  scene->byte_capacity = 0;
  scene->command_count = 0;
  scene->hash = 0;
  scene->dirty = 1;
}

static void elmc_pebble_scene_free(ElmcPebbleApp *app) {
  if (!app) return;
  elmc_pebble_scene_buffer_free(&app->scene);
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  elmc_pebble_scene_buffer_free(&app->prev_scene);
  app->dirty_rect_valid = 0;
  app->dirty_rect_full = 1;
#endif
}

static void elmc_pebble_mark_scene_dirty(ElmcPebbleApp *app) {
  if (!app) return;
  app->scene.dirty = 1;
}

static void elmc_pebble_prepare_scene_rebuild(ElmcPebbleApp *app) {
  if (!app) return;
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  elmc_pebble_scene_buffer_free(&app->prev_scene);
  app->prev_scene = app->scene;
  app->scene.bytes = NULL;
  app->scene.byte_count = 0;
  app->scene.byte_capacity = 0;
#else
  app->scene.byte_count = 0;
#endif
  app->scene.command_count = 0;
  app->scene.hash = 0;
  app->scene.dirty = 1;
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  app->dirty_rect_valid = 0;
  app->dirty_rect_full = 1;
#endif
}

#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
static void elmc_pebble_scene_mark_full_dirty(ElmcPebbleApp *app) {
  if (!app) return;
  app->dirty_rect_valid = 0;
  app->dirty_rect_full = 1;
  app->dirty_rect.x = 0;
  app->dirty_rect.y = 0;
  app->dirty_rect.w = 0;
  app->dirty_rect.h = 0;
}
#endif

static int elmc_pebble_scene_reserve(ElmcPebbleApp *app, int extra) {
  if (!app || extra < 0) return -1;
  int needed = app->scene.byte_count + extra;
  if (needed <= app->scene.byte_capacity) return 0;
  int next_capacity = app->scene.byte_capacity > 0 ? app->scene.byte_capacity : 512;
  while (next_capacity < needed) {
    next_capacity *= 2;
  }
  unsigned char *next = (unsigned char *)realloc(app->scene.bytes, (size_t)next_capacity);
  if (!next) return -2;
  app->scene.bytes = next;
  app->scene.byte_capacity = next_capacity;
  return 0;
}

static void elmc_pebble_scene_hash_byte(ElmcPebbleApp *app, unsigned char byte) {
  app->scene.hash ^= (uint64_t)byte;
  app->scene.hash *= 1099511628211ULL;
}

static int elmc_pebble_scene_put_u8(ElmcPebbleApp *app, unsigned char value) {
  int rc = elmc_pebble_scene_reserve(app, 1);
  if (rc != 0) return rc;
  app->scene.bytes[app->scene.byte_count++] = value;
  elmc_pebble_scene_hash_byte(app, value);
  return 0;
}

#if ELMC_PEBBLE_FEATURE_DRAW_PATH
static int elmc_pebble_scene_put_i16(ElmcPebbleApp *app, int32_t value) {
  if (value < -32768) value = -32768;
  if (value > 32767) value = 32767;
  uint16_t raw = (uint16_t)((int16_t)value);
  int rc = elmc_pebble_scene_reserve(app, 2);
  if (rc != 0) return rc;
  unsigned char b0 = (unsigned char)(raw & 0xff);
  unsigned char b1 = (unsigned char)((raw >> 8) & 0xff);
  app->scene.bytes[app->scene.byte_count++] = b0;
  app->scene.bytes[app->scene.byte_count++] = b1;
  elmc_pebble_scene_hash_byte(app, b0);
  elmc_pebble_scene_hash_byte(app, b1);
  return 0;
}
#endif

static int elmc_pebble_scene_put_i32(ElmcPebbleApp *app, int32_t value) {
  uint32_t raw = (uint32_t)value;
  int rc = elmc_pebble_scene_reserve(app, 4);
  if (rc != 0) return rc;
  for (int i = 0; i < 4; i++) {
    unsigned char byte = (unsigned char)((raw >> (i * 8)) & 0xff);
    app->scene.bytes[app->scene.byte_count++] = byte;
    elmc_pebble_scene_hash_byte(app, byte);
  }
  return 0;
}

#if ELMC_PEBBLE_FEATURE_DRAW_PATH
static int32_t elmc_pebble_scene_read_i16(const unsigned char *bytes, int *offset, int limit) {
  if (!bytes || !offset || *offset + 2 > limit) return 0;
  uint16_t raw = (uint16_t)bytes[*offset] | ((uint16_t)bytes[*offset + 1] << 8);
  *offset += 2;
  return (int32_t)((int16_t)raw);
}
#endif

static int32_t elmc_pebble_scene_read_i32(const unsigned char *bytes, int *offset, int limit) {
  if (!bytes || !offset || *offset + 4 > limit) return 0;
  uint32_t raw = 0;
  for (int i = 0; i < 4; i++) {
    raw |= ((uint32_t)bytes[*offset + i]) << (i * 8);
  }
  *offset += 4;
  return (int32_t)raw;
}

static int elmc_pebble_scene_cmd_extra_size(const ElmcPebbleDrawCmd *cmd) {
  if (!cmd) return 0;
  int extra = 0;
  if (cmd->kind == ELMC_PEBBLE_DRAW_TEXT) {
    int text_len = 0;
    while (text_len < (int)sizeof(cmd->text) && cmd->text[text_len] != '\0') text_len++;
    extra += 1 + text_len;
  }
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  if (cmd->kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
      cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
      cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
    int count = cmd->path_point_count;
    if (count < 0) count = 0;
    if (count > 16) count = 16;
    extra += 7 + (count * 4);
  }
#endif
  return extra;
}

static int elmc_pebble_scene_encode_cmd(ElmcPebbleApp *app, const ElmcPebbleDrawCmd *cmd) {
  if (!app || !cmd) return -1;
  int payload_len = 24 + elmc_pebble_scene_cmd_extra_size(cmd);
  if (payload_len > 255) return -2;
  int rc = elmc_pebble_scene_put_u8(app, (unsigned char)cmd->kind);
  if (rc != 0) return rc;
  rc = elmc_pebble_scene_put_u8(app, (unsigned char)payload_len);
  if (rc != 0) return rc;
  rc = elmc_pebble_scene_put_i32(app, cmd->p0); if (rc != 0) return rc;
  rc = elmc_pebble_scene_put_i32(app, cmd->p1); if (rc != 0) return rc;
  rc = elmc_pebble_scene_put_i32(app, cmd->p2); if (rc != 0) return rc;
  rc = elmc_pebble_scene_put_i32(app, cmd->p3); if (rc != 0) return rc;
  rc = elmc_pebble_scene_put_i32(app, cmd->p4); if (rc != 0) return rc;
  rc = elmc_pebble_scene_put_i32(app, cmd->p5); if (rc != 0) return rc;
  if (cmd->kind == ELMC_PEBBLE_DRAW_TEXT) {
    int text_len = 0;
    while (text_len < (int)sizeof(cmd->text) && cmd->text[text_len] != '\0') text_len++;
    rc = elmc_pebble_scene_put_u8(app, (unsigned char)text_len);
    if (rc != 0) return rc;
    rc = elmc_pebble_scene_reserve(app, text_len);
    if (rc != 0) return rc;
    for (int i = 0; i < text_len; i++) {
      unsigned char byte = (unsigned char)cmd->text[i];
      app->scene.bytes[app->scene.byte_count++] = byte;
      elmc_pebble_scene_hash_byte(app, byte);
    }
  }
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  if (cmd->kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
      cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
      cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
    int count = cmd->path_point_count;
    if (count < 0) count = 0;
    if (count > 16) count = 16;
    rc = elmc_pebble_scene_put_u8(app, (unsigned char)count); if (rc != 0) return rc;
    rc = elmc_pebble_scene_put_i16(app, cmd->path_offset_x); if (rc != 0) return rc;
    rc = elmc_pebble_scene_put_i16(app, cmd->path_offset_y); if (rc != 0) return rc;
    rc = elmc_pebble_scene_put_i16(app, cmd->path_rotation); if (rc != 0) return rc;
    for (int i = 0; i < count; i++) {
      rc = elmc_pebble_scene_put_i16(app, cmd->path_x[i]); if (rc != 0) return rc;
      rc = elmc_pebble_scene_put_i16(app, cmd->path_y[i]); if (rc != 0) return rc;
    }
  }
#endif
  app->scene.command_count += 1;
  return 0;
}

static int elmc_pebble_scene_decode_record(
    const unsigned char *bytes,
    int byte_count,
    int *offset,
    ElmcPebbleDrawCmd *out_cmd) {
  if (!bytes || !offset || !out_cmd || *offset + 2 > byte_count) return -1;
  int kind = bytes[*offset];
  int payload_len = bytes[*offset + 1];
  *offset += 2;
  int payload_end = *offset + payload_len;
  if (payload_end > byte_count) return -2;
  elmc_draw_cmd_init(out_cmd, kind);
  out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p1 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p2 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p4 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  if (kind == ELMC_PEBBLE_DRAW_TEXT && *offset < payload_end) {
    int text_len = bytes[*offset];
    *offset += 1;
    if (text_len > (int)sizeof(out_cmd->text) - 1) text_len = (int)sizeof(out_cmd->text) - 1;
    if (*offset + text_len <= payload_end) {
      memcpy(out_cmd->text, bytes + *offset, (size_t)text_len);
      out_cmd->text[text_len] = '\0';
    }
  }
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  if ((kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
       kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
       kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) &&
      *offset < payload_end) {
    int count = bytes[*offset];
    *offset += 1;
    if (count < 0) count = 0;
    if (count > 16) count = 16;
    out_cmd->path_point_count = count;
    out_cmd->path_offset_x = elmc_pebble_scene_read_i16(bytes, offset, payload_end);
    out_cmd->path_offset_y = elmc_pebble_scene_read_i16(bytes, offset, payload_end);
    out_cmd->path_rotation = elmc_pebble_scene_read_i16(bytes, offset, payload_end);
    for (int i = 0; i < count; i++) {
      out_cmd->path_x[i] = (int16_t)elmc_pebble_scene_read_i16(bytes, offset, payload_end);
      out_cmd->path_y[i] = (int16_t)elmc_pebble_scene_read_i16(bytes, offset, payload_end);
    }
  }
#endif
  *offset = payload_end;
  return 0;
}

#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
static int elmc_pebble_scene_next_record(
    const unsigned char *bytes,
    int byte_count,
    int *offset,
    const unsigned char **out_record,
    int *out_record_len,
    ElmcPebbleDrawCmd *out_cmd) {
  if (!bytes || !offset || !out_record || !out_record_len || !out_cmd) return -1;
  if (*offset >= byte_count) return 1;
  if (*offset + 2 > byte_count) return -2;
  int start = *offset;
  int payload_len = bytes[start + 1];
  int record_len = 2 + payload_len;
  if (start + record_len > byte_count) return -3;
  int decode_offset = start;
  int rc = elmc_pebble_scene_decode_record(bytes, byte_count, &decode_offset, out_cmd);
  if (rc != 0) return rc;
  *out_record = bytes + start;
  *out_record_len = record_len;
  *offset = start + record_len;
  return 0;
}

static int elmc_rect_empty(const ElmcPebbleRect *rect) {
  return !rect || rect->w <= 0 || rect->h <= 0;
}

static void elmc_rect_set(ElmcPebbleRect *rect, int x, int y, int w, int h) {
  if (!rect) return;
  rect->x = x;
  rect->y = y;
  rect->w = w < 0 ? 0 : w;
  rect->h = h < 0 ? 0 : h;
}

static int elmc_min_int(int a, int b) { return a < b ? a : b; }
static int elmc_max_int(int a, int b) { return a > b ? a : b; }

static void elmc_rect_union_into(ElmcPebbleRect *acc, const ElmcPebbleRect *rect) {
  if (!acc || elmc_rect_empty(rect)) return;
  if (elmc_rect_empty(acc)) {
    *acc = *rect;
    return;
  }
  int x1 = elmc_min_int(acc->x, rect->x);
  int y1 = elmc_min_int(acc->y, rect->y);
  int x2 = elmc_max_int(acc->x + acc->w, rect->x + rect->w);
  int y2 = elmc_max_int(acc->y + acc->h, rect->y + rect->h);
  acc->x = x1;
  acc->y = y1;
  acc->w = x2 - x1;
  acc->h = y2 - y1;
}

static int elmc_pebble_cmd_visual_bounds(const ElmcPebbleDrawCmd *cmd, ElmcPebbleRect *out) {
  if (!cmd || !out) return 0;
  switch (cmd->kind) {
    case ELMC_PEBBLE_DRAW_PIXEL:
      elmc_rect_set(out, cmd->p0, cmd->p1, 1, 1);
      return 1;
    case ELMC_PEBBLE_DRAW_LINE: {
      int x1 = elmc_min_int(cmd->p0, cmd->p2);
      int y1 = elmc_min_int(cmd->p1, cmd->p3);
      int x2 = elmc_max_int(cmd->p0, cmd->p2);
      int y2 = elmc_max_int(cmd->p1, cmd->p3);
      elmc_rect_set(out, x1, y1, x2 - x1 + 1, y2 - y1 + 1);
      return 1;
    }
    case ELMC_PEBBLE_DRAW_RECT:
    case ELMC_PEBBLE_DRAW_FILL_RECT:
    case ELMC_PEBBLE_DRAW_ROUND_RECT:
    case ELMC_PEBBLE_DRAW_ARC:
    case ELMC_PEBBLE_DRAW_FILL_RADIAL:
      elmc_rect_set(out, cmd->p0, cmd->p1, cmd->p2, cmd->p3);
      return !elmc_rect_empty(out);
    case ELMC_PEBBLE_DRAW_TEXT:
    case ELMC_PEBBLE_DRAW_BITMAP_IN_RECT:
      elmc_rect_set(out, cmd->p1, cmd->p2, cmd->p3, cmd->p4);
      return !elmc_rect_empty(out);
    case ELMC_PEBBLE_DRAW_CIRCLE:
    case ELMC_PEBBLE_DRAW_FILL_CIRCLE: {
      int r = cmd->p2 < 0 ? 0 : cmd->p2;
      elmc_rect_set(out, cmd->p0 - r, cmd->p1 - r, r * 2 + 1, r * 2 + 1);
      return !elmc_rect_empty(out);
    }
    default:
      return 0;
  }
}

static int elmc_pebble_cmd_is_visual(const ElmcPebbleDrawCmd *cmd) {
  if (!cmd) return 0;
  switch (cmd->kind) {
    case ELMC_PEBBLE_DRAW_CLEAR:
    case ELMC_PEBBLE_DRAW_PIXEL:
    case ELMC_PEBBLE_DRAW_LINE:
    case ELMC_PEBBLE_DRAW_RECT:
    case ELMC_PEBBLE_DRAW_FILL_RECT:
    case ELMC_PEBBLE_DRAW_ROUND_RECT:
    case ELMC_PEBBLE_DRAW_ARC:
    case ELMC_PEBBLE_DRAW_FILL_RADIAL:
    case ELMC_PEBBLE_DRAW_CIRCLE:
    case ELMC_PEBBLE_DRAW_FILL_CIRCLE:
    case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT:
    case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT:
    case ELMC_PEBBLE_DRAW_TEXT:
    case ELMC_PEBBLE_DRAW_BITMAP_IN_RECT:
    case ELMC_PEBBLE_DRAW_ROTATED_BITMAP:
  #if ELMC_PEBBLE_FEATURE_DRAW_PATH
    case ELMC_PEBBLE_DRAW_PATH_FILLED:
    case ELMC_PEBBLE_DRAW_PATH_OUTLINE:
    case ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN:
  #endif
      return 1;
    default:
      return 0;
  }
}

static int elmc_pebble_cmd_requires_full_dirty(const ElmcPebbleDrawCmd *cmd) {
  if (!cmd) return 1;
  switch (cmd->kind) {
    case ELMC_PEBBLE_DRAW_CLEAR:
    case ELMC_PEBBLE_DRAW_PUSH_CONTEXT:
    case ELMC_PEBBLE_DRAW_POP_CONTEXT:
    case ELMC_PEBBLE_DRAW_STROKE_WIDTH:
    case ELMC_PEBBLE_DRAW_ANTIALIASED:
    case ELMC_PEBBLE_DRAW_STROKE_COLOR:
    case ELMC_PEBBLE_DRAW_FILL_COLOR:
    case ELMC_PEBBLE_DRAW_TEXT_COLOR:
    case ELMC_PEBBLE_DRAW_CONTEXT_GROUP:
    case ELMC_PEBBLE_DRAW_COMPOSITING_MODE:
    case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT:
    case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT:
    case ELMC_PEBBLE_DRAW_ROTATED_BITMAP:
  #if ELMC_PEBBLE_FEATURE_DRAW_PATH
    case ELMC_PEBBLE_DRAW_PATH_FILLED:
    case ELMC_PEBBLE_DRAW_PATH_OUTLINE:
    case ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN:
  #endif
      return 1;
    default:
      return 0;
  }
}

static void elmc_pebble_scene_compute_dirty_rect(ElmcPebbleApp *app) {
  if (!app) return;
  app->dirty_rect_valid = 0;
  app->dirty_rect_full = 1;
  elmc_rect_set(&app->dirty_rect, 0, 0, 0, 0);

  if (app->prev_scene.hash == app->scene.hash &&
      app->prev_scene.command_count == app->scene.command_count &&
      app->prev_scene.byte_count == app->scene.byte_count) {
    app->dirty_rect_full = 0;
    app->dirty_rect_valid = 1;
    return;
  }

  int old_offset = 0;
  int new_offset = 0;
  ElmcPebbleRect union_rect = {0, 0, 0, 0};

  while (old_offset < app->prev_scene.byte_count || new_offset < app->scene.byte_count) {
    const unsigned char *old_record = NULL;
    const unsigned char *new_record = NULL;
    int old_len = 0;
    int new_len = 0;
    ElmcPebbleDrawCmd old_cmd;
    ElmcPebbleDrawCmd new_cmd;
    int old_rc = elmc_pebble_scene_next_record(app->prev_scene.bytes, app->prev_scene.byte_count,
                                               &old_offset, &old_record, &old_len, &old_cmd);
    int new_rc = elmc_pebble_scene_next_record(app->scene.bytes, app->scene.byte_count,
                                               &new_offset, &new_record, &new_len, &new_cmd);
    if (old_rc < 0 || new_rc < 0) {
      return;
    }
    if (old_rc == 1 && new_rc == 1) {
      break;
    }
    if (old_rc == 0 && new_rc == 0 && old_len == new_len && memcmp(old_record, new_record, (size_t)old_len) == 0) {
      continue;
    }

    if ((old_rc == 0 && elmc_pebble_cmd_requires_full_dirty(&old_cmd)) ||
        (new_rc == 0 && elmc_pebble_cmd_requires_full_dirty(&new_cmd))) {
      return;
    }

    if (old_rc == 0 && elmc_pebble_cmd_is_visual(&old_cmd)) {
      ElmcPebbleRect bounds;
      if (!elmc_pebble_cmd_visual_bounds(&old_cmd, &bounds)) return;
      elmc_rect_union_into(&union_rect, &bounds);
    }
    if (new_rc == 0 && elmc_pebble_cmd_is_visual(&new_cmd)) {
      ElmcPebbleRect bounds;
      if (!elmc_pebble_cmd_visual_bounds(&new_cmd, &bounds)) return;
      elmc_rect_union_into(&union_rect, &bounds);
    }
  }

  app->dirty_rect = union_rect;
  app->dirty_rect_full = 0;
  app->dirty_rect_valid = 1;
}
#else
#endif

#if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
static void elmc_emit_draw_cmd(
    const ElmcPebbleDrawCmd *cmd,
    ElmcPebbleDrawCmd *out_cmds,
    int max_cmds,
    int *count,
    int *emitted,
    int skip) {
  if (!cmd || !out_cmds || !count || !emitted) return;
  if (*emitted >= skip && *count < max_cmds) {
    out_cmds[*count] = *cmd;
    *count += 1;
  }
  *emitted += 1;
}

static int elmc_append_draw_cmd_from_value_window(
    ElmcValue *value,
    ElmcPebbleDrawCmd *out_cmds,
    int max_cmds,
    int *count,
    int *emitted,
    int skip,
    int depth) {
  if (!value || !out_cmds || !count || !emitted) return -1;
  if (depth > 32) return -2;
  if (*count >= max_cmds) return 0;

  if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (tuple->first && tuple->second && elmc_as_int(tuple->first) == ELMC_PEBBLE_DRAW_CONTEXT_GROUP) {
      if (tuple->second->tag != ELMC_TAG_TUPLE2 || tuple->second->payload == NULL) return -3;
      ElmcTuple2 *ctx = (ElmcTuple2 *)tuple->second->payload;
      if (!ctx->first || !ctx->second) return -4;

      ElmcPebbleDrawCmd push_cmd;
      elmc_draw_cmd_init(&push_cmd, ELMC_PEBBLE_DRAW_PUSH_CONTEXT);
      elmc_emit_draw_cmd(&push_cmd, out_cmds, max_cmds, count, emitted, skip);
      if (*count >= max_cmds) return 0;

      ElmcValue *setting_cursor = ctx->first;
      while (setting_cursor && setting_cursor->tag == ELMC_TAG_LIST && setting_cursor->payload != NULL && *count < max_cmds) {
        ElmcCons *node = (ElmcCons *)setting_cursor->payload;
        ElmcPebbleDrawCmd setting_cmd;
        if (elmc_draw_setting_cmd_from_value(node->head, &setting_cmd) == 0) {
          elmc_emit_draw_cmd(&setting_cmd, out_cmds, max_cmds, count, emitted, skip);
        }
        setting_cursor = node->tail;
      }

      ElmcValue *cmd_cursor = ctx->second;
      while (cmd_cursor && cmd_cursor->tag == ELMC_TAG_LIST && cmd_cursor->payload != NULL && *count < max_cmds) {
        ElmcCons *node = (ElmcCons *)cmd_cursor->payload;
        elmc_append_draw_cmd_from_value_window(node->head, out_cmds, max_cmds, count, emitted, skip, depth + 1);
        cmd_cursor = node->tail;
      }

      ElmcPebbleDrawCmd pop_cmd;
      elmc_draw_cmd_init(&pop_cmd, ELMC_PEBBLE_DRAW_POP_CONTEXT);
      elmc_emit_draw_cmd(&pop_cmd, out_cmds, max_cmds, count, emitted, skip);
      return 0;
    }
  }

  ElmcPebbleDrawCmd cmd;
  if (elmc_draw_cmd_from_value(value, &cmd) == 0) {
    elmc_emit_draw_cmd(&cmd, out_cmds, max_cmds, count, emitted, skip);
  }
  return 0;
}
#endif

static int elmc_cmd_from_value(ElmcValue *value, ElmcPebbleCmd *out_cmd) {
  if (!out_cmd) return -1;
  out_cmd->kind = ELMC_PEBBLE_CMD_NONE;
  out_cmd->p0 = 0;
  out_cmd->p1 = 0;
  out_cmd->p2 = 0;
  out_cmd->p3 = 0;
  out_cmd->p4 = 0;
  out_cmd->p5 = 0;
  out_cmd->text[0] = '\0';
  if (!value) return -2;

  if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) {
    out_cmd->kind = elmc_as_int(value);
    return 0;
  }

  if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (!tuple->first || !tuple->second) return -3;
    out_cmd->kind = elmc_as_int(tuple->first);
    if (out_cmd->kind == ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING &&
        tuple->second->tag == ELMC_TAG_TUPLE2 &&
        tuple->second->payload != NULL) {
      ElmcTuple2 *payload_tuple = (ElmcTuple2 *)tuple->second->payload;
      if (!payload_tuple->first || !payload_tuple->second) return -3;
      out_cmd->p0 = elmc_as_int(payload_tuple->first);
      ElmcValue *text_value = payload_tuple->second;
      while (text_value && text_value->tag == ELMC_TAG_TUPLE2 && text_value->payload != NULL) {
        ElmcTuple2 *nested = (ElmcTuple2 *)text_value->payload;
        text_value = nested->first;
      }
      if (text_value && text_value->tag == ELMC_TAG_STRING && text_value->payload) {
        strncpy(out_cmd->text, (const char *)text_value->payload, sizeof(out_cmd->text) - 1);
        out_cmd->text[sizeof(out_cmd->text) - 1] = '\0';
      }
      return 0;
    }
    int64_t payload[6] = {0, 0, 0, 0, 0, 0};
    if (elmc_unpack_draw_payload(tuple->second, payload) == 0) {
      out_cmd->p0 = payload[0];
      out_cmd->p1 = payload[1];
      out_cmd->p2 = payload[2];
      out_cmd->p3 = payload[3];
      out_cmd->p4 = payload[4];
      out_cmd->p5 = payload[5];
    } else {
      out_cmd->p0 = elmc_as_int(tuple->second);
    }
    return 0;
  }

  return -4;
}

#if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
static uint64_t elmc_hash_value(ElmcValue *value, int depth) {
  if (!value || depth > 64) return 1469598103934665603ULL;
  uint64_t h = 1469598103934665603ULL;
  h ^= (uint64_t)value->tag;
  h *= 1099511628211ULL;

  switch (value->tag) {
    case ELMC_TAG_INT:
    case ELMC_TAG_BOOL: {
      uint64_t raw = (uint64_t)elmc_as_int(value);
      h ^= raw;
      h *= 1099511628211ULL;
      return h;
    }
    case ELMC_TAG_STRING: {
      const unsigned char *s = (const unsigned char *)value->payload;
      if (!s) return h;
      while (*s) {
        h ^= (uint64_t)(*s++);
        h *= 1099511628211ULL;
      }
      return h;
    }
    case ELMC_TAG_LIST: {
      ElmcValue *cursor = value;
      int count = 0;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < 128) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        uint64_t head_h = elmc_hash_value(node->head, depth + 1);
        h ^= head_h;
        h *= 1099511628211ULL;
        cursor = node->tail;
        count += 1;
      }
      return h;
    }
    case ELMC_TAG_TUPLE2: {
      if (!value->payload) return h;
      ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
      h ^= elmc_hash_value(tuple->first, depth + 1);
      h *= 1099511628211ULL;
      h ^= elmc_hash_value(tuple->second, depth + 1);
      h *= 1099511628211ULL;
      return h;
    }
    default:
      return h;
  }
}

static int elmc_is_virtual_ui_tag(ElmcValue *value, int64_t encoded_tag) {
  if (!value) return 0;
  int64_t tag = elmc_as_int(value);
  return tag == encoded_tag;
}

static int elmc_extract_virtual_canvas_ops(
    ElmcValue *view,
    int64_t *out_window_id,
    int64_t *out_layer_id,
    ElmcValue **out_ops) {
  if (!view || !out_window_id || !out_layer_id || !out_ops) return -1;
  *out_window_id = 0;
  *out_layer_id = 0;
  *out_ops = NULL;

  if (view->tag != ELMC_TAG_TUPLE2 || view->payload == NULL) return -2;
  ElmcTuple2 *root = (ElmcTuple2 *)view->payload;
  if (!root->first || !root->second) return -3;
  if (!elmc_is_virtual_ui_tag(root->first, ELMC_PEBBLE_UI_WINDOW_STACK)) return -4;

  ElmcValue *window_cursor = root->second;
  ElmcValue *top_window = NULL;
  int64_t seen_window_ids[16] = {0};
  int seen_window_count = 0;
  while (window_cursor && window_cursor->tag == ELMC_TAG_LIST && window_cursor->payload != NULL) {
    ElmcCons *window_node = (ElmcCons *)window_cursor->payload;
    if (window_node->head && window_node->head->tag == ELMC_TAG_TUPLE2 && window_node->head->payload != NULL) {
      ElmcTuple2 *candidate_tuple = (ElmcTuple2 *)window_node->head->payload;
      if (candidate_tuple->first && candidate_tuple->second &&
          elmc_is_virtual_ui_tag(candidate_tuple->first, ELMC_PEBBLE_UI_WINDOW_NODE) &&
          candidate_tuple->second->tag == ELMC_TAG_TUPLE2 &&
          candidate_tuple->second->payload != NULL) {
        ElmcTuple2 *candidate_payload = (ElmcTuple2 *)candidate_tuple->second->payload;
        if (candidate_payload->first) {
          int64_t candidate_id = elmc_as_int(candidate_payload->first);
          for (int i = 0; i < seen_window_count; i++) {
            if (seen_window_ids[i] == candidate_id) return -30;
          }
          if (seen_window_count < 16) seen_window_ids[seen_window_count++] = candidate_id;
        }
      }
    }
    top_window = window_node->head;
    window_cursor = window_node->tail;
  }
  if (!top_window || top_window->tag != ELMC_TAG_TUPLE2 || top_window->payload == NULL) return -5;

  ElmcTuple2 *window_tuple = (ElmcTuple2 *)top_window->payload;
  if (!window_tuple->first || !window_tuple->second) return -6;
  if (!elmc_is_virtual_ui_tag(window_tuple->first, ELMC_PEBBLE_UI_WINDOW_NODE)) return -7;

  if (window_tuple->second->tag != ELMC_TAG_TUPLE2 || window_tuple->second->payload == NULL) return -8;
  ElmcTuple2 *window_payload = (ElmcTuple2 *)window_tuple->second->payload;
  if (!window_payload->first || !window_payload->second) return -9;
  *out_window_id = elmc_as_int(window_payload->first);

  ElmcValue *layer_cursor = window_payload->second;
  ElmcValue *top_layer = NULL;
  int64_t seen_layer_ids[32] = {0};
  int seen_layer_count = 0;
  while (layer_cursor && layer_cursor->tag == ELMC_TAG_LIST && layer_cursor->payload != NULL) {
    ElmcCons *layer_node = (ElmcCons *)layer_cursor->payload;
    if (layer_node->head && layer_node->head->tag == ELMC_TAG_TUPLE2 && layer_node->head->payload != NULL) {
      ElmcTuple2 *candidate_tuple = (ElmcTuple2 *)layer_node->head->payload;
      if (candidate_tuple->first && candidate_tuple->second &&
          elmc_is_virtual_ui_tag(candidate_tuple->first, ELMC_PEBBLE_UI_CANVAS_LAYER) &&
          candidate_tuple->second->tag == ELMC_TAG_TUPLE2 &&
          candidate_tuple->second->payload != NULL) {
        ElmcTuple2 *candidate_payload = (ElmcTuple2 *)candidate_tuple->second->payload;
        if (candidate_payload->first) {
          int64_t candidate_id = elmc_as_int(candidate_payload->first);
          for (int i = 0; i < seen_layer_count; i++) {
            if (seen_layer_ids[i] == candidate_id) return -31;
          }
          if (seen_layer_count < 32) seen_layer_ids[seen_layer_count++] = candidate_id;
        }
      }
    }
    top_layer = layer_node->head;
    layer_cursor = layer_node->tail;
  }
  if (!top_layer || top_layer->tag != ELMC_TAG_TUPLE2 || top_layer->payload == NULL) return -10;

  ElmcTuple2 *layer_tuple = (ElmcTuple2 *)top_layer->payload;
  if (!layer_tuple->first || !layer_tuple->second) return -11;
  if (!elmc_is_virtual_ui_tag(layer_tuple->first, ELMC_PEBBLE_UI_CANVAS_LAYER)) return -12;

  if (layer_tuple->second->tag != ELMC_TAG_TUPLE2 || layer_tuple->second->payload == NULL) return -13;
  ElmcTuple2 *layer_payload = (ElmcTuple2 *)layer_tuple->second->payload;
  if (!layer_payload->first || !layer_payload->second) return -14;
  // #region agent log
  elmc_agent_scene_probe(0xED996600 | elmc_agent_value_shape(layer_payload->first));
  elmc_agent_scene_probe(0xED996700 | elmc_agent_value_shape(layer_payload->second));
  if (layer_payload->second->tag == ELMC_TAG_TUPLE2 && layer_payload->second->payload != NULL) {
    ElmcTuple2 *ops_payload = (ElmcTuple2 *)layer_payload->second->payload;
    elmc_agent_scene_probe(0xED996800 | elmc_agent_value_shape(ops_payload->first));
    elmc_agent_scene_probe(0xED996900 | elmc_agent_value_shape(ops_payload->second));
  }
  // #endregion

  *out_layer_id = elmc_as_int(layer_payload->first);
  *out_ops = layer_payload->second;
  return 0;
}
#endif

static int elmc_pebble_is_subscribed(ElmcPebbleApp *app, int64_t flag) {
  if (!app || !app->initialized) return 0;
  int64_t active = elmc_worker_subscriptions(&app->worker);
  return (active & flag) != 0;
}

static int elmc_pebble_finish_dispatch(ElmcPebbleApp *app, int rc) {
  if (rc == 0) {
    elmc_pebble_mark_scene_dirty(app);
  }
  return rc;
}

int elmc_pebble_init(ElmcPebbleApp *app, ElmcValue *flags) {
  return elmc_pebble_init_with_mode(app, flags, ELMC_PEBBLE_MODE_APP);
}

int elmc_pebble_init_with_mode(ElmcPebbleApp *app, ElmcValue *flags, int run_mode) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_init_with_mode");
  if (!app) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_init_with_mode", -1);
  app->initialized = 0;
  app->run_mode = run_mode;
  app->has_prev_ui = 0;
  app->prev_window_id = 0;
  app->prev_layer_id = 0;
  app->prev_ops_hash = 0;
#if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
  app->stream_view_result = NULL;
#endif
  app->scene.bytes = NULL;
  app->scene.byte_count = 0;
  app->scene.byte_capacity = 0;
  app->scene.command_count = 0;
  app->scene.hash = 0;
  app->scene.dirty = 1;
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  app->prev_scene.bytes = NULL;
  app->prev_scene.byte_count = 0;
  app->prev_scene.byte_capacity = 0;
  app->prev_scene.command_count = 0;
  app->prev_scene.hash = 0;
  app->prev_scene.dirty = 1;
  app->dirty_rect.x = 0;
  app->dirty_rect.y = 0;
  app->dirty_rect.w = 0;
  app->dirty_rect.h = 0;
  app->dirty_rect_valid = 0;
  app->dirty_rect_full = 1;
#endif
  int rc = elmc_worker_init(&app->worker, flags);
  if (rc == 0) app->initialized = 1;
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_init_with_mode", rc);
}

int elmc_pebble_dispatch_int(ElmcPebbleApp *app, int64_t tag) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_int");
  if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", -1);
  ElmcValue *msg = elmc_new_int(tag);
  if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", -2);
  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", elmc_pebble_finish_dispatch(app, rc));
}

int elmc_pebble_dispatch_tag_value(ElmcPebbleApp *app, int64_t tag, int64_t value) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_value");
  if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -1);
  ElmcValue *tag_value = elmc_new_int(tag);
  ElmcValue *payload_value = elmc_new_int(value);
  if (!tag_value || !payload_value) {
    if (tag_value) elmc_release(tag_value);
    if (payload_value) elmc_release(payload_value);
    ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -2);
  }

  ElmcValue *msg = elmc_tuple2(tag_value, payload_value);
  elmc_release(tag_value);
  elmc_release(payload_value);
  if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -2);

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", elmc_pebble_finish_dispatch(app, rc));
}

int elmc_pebble_dispatch_tag_bool(ElmcPebbleApp *app, int64_t tag, int value) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_bool");
  if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", -1);
  ElmcValue *tag_value = elmc_new_int(tag);
  ElmcValue *payload_value = elmc_new_bool(value ? 1 : 0);
  if (!tag_value || !payload_value) {
    if (tag_value) elmc_release(tag_value);
    if (payload_value) elmc_release(payload_value);
    ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", -2);
  }

  ElmcValue *msg = elmc_tuple2(tag_value, payload_value);
  elmc_release(tag_value);
  elmc_release(payload_value);
  if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", -2);

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", elmc_pebble_finish_dispatch(app, rc));
}

int elmc_pebble_dispatch_tag_string(ElmcPebbleApp *app, int64_t tag, const char *value) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_string");
  if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_string", -1);
  ElmcValue *tag_value = elmc_new_int(tag);
  ElmcValue *payload_value = elmc_new_string(value ? value : "");
  if (!tag_value || !payload_value) {
    if (tag_value) elmc_release(tag_value);
    if (payload_value) elmc_release(payload_value);
    ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_string", -2);
  }

  ElmcValue *msg = elmc_tuple2(tag_value, payload_value);
  elmc_release(tag_value);
  elmc_release(payload_value);
  if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_string", -2);

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_string", elmc_pebble_finish_dispatch(app, rc));
}

int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_payload");
  if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -1);
  if (!payload) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -3);
  ElmcValue *tag_value = elmc_new_int(tag);
  if (!tag_value) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -2);

  ElmcValue *msg = elmc_tuple2(tag_value, payload);
  elmc_release(tag_value);
  if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -2);

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", elmc_pebble_finish_dispatch(app, rc));
}

static ElmcValue *elmc_pebble_int_tuple_from_values(const int64_t *field_values, int index, int field_count) {
  if (field_count <= 0) return elmc_new_int(0);
  if (!field_values || index < 0 || index >= field_count) return NULL;

  ElmcValue *head = elmc_new_int(field_values[index]);
  if (!head) return NULL;
  if (index == field_count - 1) return head;

  ElmcValue *tail = elmc_pebble_int_tuple_from_values(field_values, index + 1, field_count);
  if (!tail) {
    elmc_release(head);
    return NULL;
  }

  ElmcValue *tuple = elmc_tuple2(head, tail);
  elmc_release(head);
  elmc_release(tail);
  return tuple;
}

int elmc_pebble_dispatch_tag_int_values(
    ElmcPebbleApp *app,
    int64_t outer_tag,
    int64_t inner_tag,
    int field_count,
    const int64_t *field_values) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_int_values");
  if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -1);
  if (field_count < 0 || (field_count > 0 && !field_values)) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -3);

  ElmcValue *inner_tag_value = elmc_new_int(inner_tag);
  ElmcValue *inner_payload = elmc_pebble_int_tuple_from_values(field_values, 0, field_count);
  if (!inner_tag_value || !inner_payload) {
    if (inner_tag_value) elmc_release(inner_tag_value);
    if (inner_payload) elmc_release(inner_payload);
    ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -2);
  }

  ElmcValue *inner_msg = elmc_tuple2(inner_tag_value, inner_payload);
  elmc_release(inner_tag_value);
  elmc_release(inner_payload);
  if (!inner_msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -2);

  int rc = elmc_pebble_dispatch_tag_payload(app, outer_tag, inner_msg);
  elmc_release(inner_msg);
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", rc);
}

int elmc_pebble_dispatch_tag_record_int_fields(
    ElmcPebbleApp *app,
    int64_t tag,
    int field_count,
    const char **field_names,
    const int64_t *field_values) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_record_int_fields");
  if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -1);
  if (field_count <= 0 || !field_names || !field_values) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -3);

  ElmcValue *tag_value = elmc_new_int(tag);
  if (!tag_value) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);

  ElmcValue **record_values = (ElmcValue **)malloc(sizeof(ElmcValue *) * field_count);
  if (!record_values) {
    elmc_release(tag_value);
    ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);
  }

  int built = 0;
  for (int i = 0; i < field_count; i++) {
    record_values[i] = elmc_new_int(field_values[i]);
    if (!record_values[i]) {
      built = i;
      goto cleanup_values;
    }
  }
  built = field_count;

  ElmcValue *payload_value = elmc_record_new(field_count, field_names, record_values);
  for (int i = 0; i < built; i++) {
    if (record_values[i]) elmc_release(record_values[i]);
  }
  free(record_values);

  if (!payload_value) {
    elmc_release(tag_value);
    ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);
  }

  ElmcValue *msg = elmc_tuple2(tag_value, payload_value);
  elmc_release(tag_value);
  elmc_release(payload_value);
  if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", elmc_pebble_finish_dispatch(app, rc));

cleanup_values:
  for (int i = 0; i < built; i++) {
    if (record_values[i]) elmc_release(record_values[i]);
  }
  free(record_values);
  elmc_release(tag_value);
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);
}

int elmc_pebble_msg_from_appmessage(int32_t key, int32_t value, int64_t *out_tag) {
  if (!out_tag) return -1;

  if (key == 0) {
    switch (value) {
      case ELMC_PEBBLE_MSG_TICK: *out_tag = 1; return 0;
      case ELMC_PEBBLE_MSG_BUTTONUP: *out_tag = 2; return 0;
      case ELMC_PEBBLE_MSG_BUTTONSELECT: *out_tag = 3; return 0;
      case ELMC_PEBBLE_MSG_BUTTONDOWN: *out_tag = 4; return 0;
      case ELMC_PEBBLE_MSG_BUTTONLONGUP: *out_tag = 5; return 0;
      case ELMC_PEBBLE_MSG_BUTTONLONGSELECT: *out_tag = 6; return 0;
      case ELMC_PEBBLE_MSG_BUTTONLONGDOWN: *out_tag = 7; return 0;
      case ELMC_PEBBLE_MSG_ACCELTAP: *out_tag = 8; return 0;
      case ELMC_PEBBLE_MSG_BATTERYCHANGED: *out_tag = 9; return 0;
      case ELMC_PEBBLE_MSG_CONNECTIONCHANGED: *out_tag = 10; return 0;
      case ELMC_PEBBLE_MSG_HOURCHANGED: *out_tag = 11; return 0;
      case ELMC_PEBBLE_MSG_MINUTECHANGED: *out_tag = 12; return 0;
      case ELMC_PEBBLE_MSG_GOTCURRENTDATETIME: *out_tag = 13; return 0;
      case ELMC_PEBBLE_MSG_GOTTIME: *out_tag = 14; return 0;
      case ELMC_PEBBLE_MSG_GOTCLOCKSTYLE24H: *out_tag = 15; return 0;
      case ELMC_PEBBLE_MSG_GOTTIMEZONEISSET: *out_tag = 16; return 0;
      case ELMC_PEBBLE_MSG_GOTTIMEZONE: *out_tag = 17; return 0;
      case ELMC_PEBBLE_MSG_GOTSTOREDINT: *out_tag = 18; return 0;
      case ELMC_PEBBLE_MSG_GOTSTORAGESTRING: *out_tag = 19; return 0;
      case ELMC_PEBBLE_MSG_FRAMETICK: *out_tag = 20; return 0;
      case ELMC_PEBBLE_MSG_UPPRESSED: *out_tag = 21; return 0;
      case ELMC_PEBBLE_MSG_UPRELEASED: *out_tag = 22; return 0;
      case ELMC_PEBBLE_MSG_ACCELDATA: *out_tag = 23; return 0;
      case ELMC_PEBBLE_MSG_GOTWATCHMODEL: *out_tag = 24; return 0;
      case ELMC_PEBBLE_MSG_GOTWATCHCOLOR: *out_tag = 25; return 0;
      case ELMC_PEBBLE_MSG_GOTFIRMWAREVERSION: *out_tag = 26; return 0;
      case ELMC_PEBBLE_MSG_GOTBATTERYLEVEL: *out_tag = 27; return 0;
      case ELMC_PEBBLE_MSG_GOTCONNECTIONSTATUS: *out_tag = 28; return 0;
      case ELMC_PEBBLE_MSG_GOTHEALTHVALUE: *out_tag = 29; return 0;
      case ELMC_PEBBLE_MSG_GOTHEALTHSUMTODAY: *out_tag = 30; return 0;
      case ELMC_PEBBLE_MSG_GOTHEALTHSUM: *out_tag = 31; return 0;
      case ELMC_PEBBLE_MSG_GOTHEALTHACCESSIBLE: *out_tag = 32; return 0;
      case ELMC_PEBBLE_MSG_HEALTHEVENT: *out_tag = 33; return 0;
      default: return -3;
    }
  }

  if (value == 0) return -4;
  switch (key) {
      case ELMC_PEBBLE_MSG_TICK: *out_tag = 1; return 0;
      case ELMC_PEBBLE_MSG_BUTTONUP: *out_tag = 2; return 0;
      case ELMC_PEBBLE_MSG_BUTTONSELECT: *out_tag = 3; return 0;
      case ELMC_PEBBLE_MSG_BUTTONDOWN: *out_tag = 4; return 0;
      case ELMC_PEBBLE_MSG_BUTTONLONGUP: *out_tag = 5; return 0;
      case ELMC_PEBBLE_MSG_BUTTONLONGSELECT: *out_tag = 6; return 0;
      case ELMC_PEBBLE_MSG_BUTTONLONGDOWN: *out_tag = 7; return 0;
      case ELMC_PEBBLE_MSG_ACCELTAP: *out_tag = 8; return 0;
      case ELMC_PEBBLE_MSG_BATTERYCHANGED: *out_tag = 9; return 0;
      case ELMC_PEBBLE_MSG_CONNECTIONCHANGED: *out_tag = 10; return 0;
      case ELMC_PEBBLE_MSG_HOURCHANGED: *out_tag = 11; return 0;
      case ELMC_PEBBLE_MSG_MINUTECHANGED: *out_tag = 12; return 0;
      case ELMC_PEBBLE_MSG_GOTCURRENTDATETIME: *out_tag = 13; return 0;
      case ELMC_PEBBLE_MSG_GOTTIME: *out_tag = 14; return 0;
      case ELMC_PEBBLE_MSG_GOTCLOCKSTYLE24H: *out_tag = 15; return 0;
      case ELMC_PEBBLE_MSG_GOTTIMEZONEISSET: *out_tag = 16; return 0;
      case ELMC_PEBBLE_MSG_GOTTIMEZONE: *out_tag = 17; return 0;
      case ELMC_PEBBLE_MSG_GOTSTOREDINT: *out_tag = 18; return 0;
      case ELMC_PEBBLE_MSG_GOTSTORAGESTRING: *out_tag = 19; return 0;
      case ELMC_PEBBLE_MSG_FRAMETICK: *out_tag = 20; return 0;
      case ELMC_PEBBLE_MSG_UPPRESSED: *out_tag = 21; return 0;
      case ELMC_PEBBLE_MSG_UPRELEASED: *out_tag = 22; return 0;
      case ELMC_PEBBLE_MSG_ACCELDATA: *out_tag = 23; return 0;
      case ELMC_PEBBLE_MSG_GOTWATCHMODEL: *out_tag = 24; return 0;
      case ELMC_PEBBLE_MSG_GOTWATCHCOLOR: *out_tag = 25; return 0;
      case ELMC_PEBBLE_MSG_GOTFIRMWAREVERSION: *out_tag = 26; return 0;
      case ELMC_PEBBLE_MSG_GOTBATTERYLEVEL: *out_tag = 27; return 0;
      case ELMC_PEBBLE_MSG_GOTCONNECTIONSTATUS: *out_tag = 28; return 0;
      case ELMC_PEBBLE_MSG_GOTHEALTHVALUE: *out_tag = 29; return 0;
      case ELMC_PEBBLE_MSG_GOTHEALTHSUMTODAY: *out_tag = 30; return 0;
      case ELMC_PEBBLE_MSG_GOTHEALTHSUM: *out_tag = 31; return 0;
      case ELMC_PEBBLE_MSG_GOTHEALTHACCESSIBLE: *out_tag = 32; return 0;
      case ELMC_PEBBLE_MSG_HEALTHEVENT: *out_tag = 33; return 0;
    default: return -3;
  }
}

int elmc_pebble_dispatch_appmessage(ElmcPebbleApp *app, int32_t key, int32_t value) {
  int64_t tag = 0;
  int rc = elmc_pebble_msg_from_appmessage(key, value, &tag);
  if (rc != 0) return rc;
  return elmc_pebble_dispatch_int(app, tag);
}

int elmc_pebble_button_to_tag(int32_t button_id, int64_t *out_tag) {
  if (!out_tag) return -1;
  switch (button_id) {
    case ELMC_PEBBLE_BUTTON_UP:
      if (21 <= 0) return -5;
      *out_tag = 21;
      return 0;
    case ELMC_PEBBLE_BUTTON_SELECT:
      if (-1 <= 0) return -5;
      *out_tag = -1;
      return 0;
    case ELMC_PEBBLE_BUTTON_DOWN:
      if (-1 <= 0) return -5;
      *out_tag = -1;
      return 0;
    default:
      return -3;
  }
}

int elmc_pebble_dispatch_button(ElmcPebbleApp *app, int32_t button_id) {
  if (!app || !app->initialized) return -1;
  if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
  int64_t required = 0;
  if (button_id == ELMC_PEBBLE_BUTTON_UP) {
    required = ELMC_PEBBLE_SUB_BUTTON_UP;
  } else if (button_id == ELMC_PEBBLE_BUTTON_SELECT) {
    required = ELMC_PEBBLE_SUB_BUTTON_SELECT;
  } else if (button_id == ELMC_PEBBLE_BUTTON_DOWN) {
    required = ELMC_PEBBLE_SUB_BUTTON_DOWN;
  } else {
    return -3;
  }
  if (!elmc_pebble_is_subscribed(app, required)) return -8;
  int64_t tag = 0;
  int rc = elmc_pebble_button_to_tag(button_id, &tag);
  if (rc != 0) return rc;
  return elmc_pebble_dispatch_int(app, tag);
}

int elmc_pebble_dispatch_button_raw(ElmcPebbleApp *app, int32_t button_id, int32_t pressed) {
  if (!app || !app->initialized) return -1;
  if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BUTTON_RAW)) return -8;
  int64_t tag = 0;
  if (button_id == ELMC_PEBBLE_BUTTON_BACK) {
    tag = pressed ? -1 : -1;
  } else if (button_id == ELMC_PEBBLE_BUTTON_UP) {
    tag = pressed ? 21 : 22;
  } else if (button_id == ELMC_PEBBLE_BUTTON_SELECT) {
    tag = pressed ? -1 : -1;
  } else if (button_id == ELMC_PEBBLE_BUTTON_DOWN) {
    tag = pressed ? -1 : -1;
  } else {
    return -3;
  }
  if (tag <= 0) return 1;
  return elmc_pebble_dispatch_int(app, tag);
}

int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction) {
  (void)axis;
  (void)direction;
  if (!app || !app->initialized) return -1;
  if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_TAP)) return -8;
  if (8 <= 0) return -6;
  return elmc_pebble_dispatch_int(app, 8);
}

int elmc_pebble_dispatch_accel_data(ElmcPebbleApp *app, int32_t x, int32_t y, int32_t z) {
  if (!app || !app->initialized) return -1;
  if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_DATA)) return -8;
  if (23 <= 0) return -6;
  const char *names[] = {"x", "y", "z"};
  const int64_t values[] = {x, y, z};
  return elmc_pebble_dispatch_tag_record_int_fields(app, 23, 3, names, values);
}

int elmc_pebble_dispatch_frame(ElmcPebbleApp *app, int64_t dt_ms, int64_t elapsed_ms, int64_t frame) {
  if (!app || !app->initialized) return -1;
  if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_FRAME)) return -8;
  if (20 <= 0) return -6;
  const char *names[] = {"dtMs", "elapsedMs", "frame"};
  const int64_t values[] = {dt_ms, elapsed_ms, frame};
  return elmc_pebble_dispatch_tag_record_int_fields(app, 20, 3, names, values);
}

int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value) {
  if (!app || !app->initialized) return -1;
  if (19 <= 0) return -6;
  return elmc_pebble_dispatch_tag_string(app, 19, value ? value : "");
}

int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value) {
  if (!app || !app->initialized) return -1;
  if (-1 <= 0) return -6;
  return elmc_pebble_dispatch_tag_value(app, -1, value);
}

int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level) {
  if (!app || !app->initialized) return -1;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BATTERY)) return -8;
  if (9 <= 0) return -6;
  if (level < 0) level = 0;
  if (level > 100) level = 100;
  return elmc_pebble_dispatch_tag_value(app, 9, level);
}

int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected) {
  if (!app || !app->initialized) return -1;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_CONNECTION)) return -8;
  if (10 <= 0) return -6;
  return elmc_pebble_dispatch_tag_bool(app, 10, connected);
}

int elmc_pebble_dispatch_health(ElmcPebbleApp *app, int event) {
  if (!app || !app->initialized) return -1;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_HEALTH)) return -8;
  if (33 <= 0) return -6;
  if (event < 0) event = 0;
  if (event > 2) event = 0;
  return elmc_pebble_dispatch_tag_value(app, 33, event);
}

int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour) {
  if (!app || !app->initialized) return -1;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_HOUR)) return -8;
  if (11 <= 0) return -6;
  return elmc_pebble_dispatch_tag_value(app, 11, hour);
}

int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute) {
  if (!app || !app->initialized) return -1;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_MINUTE)) return -8;
  if (12 <= 0) return -6;
  return elmc_pebble_dispatch_tag_value(app, 12, minute);
}

int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd) {
  if (!app || !app->initialized || !out_cmd) return -1;
  ElmcValue *cmd = elmc_worker_take_cmd(&app->worker);
  if (!cmd) return -2;
  int rc = elmc_cmd_from_value(cmd, out_cmd);
  elmc_release(cmd);
  return rc;
}

static int elmc_pebble_view_commands_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe);
static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe);

int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd) {
  int count = elmc_pebble_view_commands(app, out_cmd, 1);
  if (count < 0) return count;
  if (count == 0) return -7;
  return 0;
}

int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds) {
  return elmc_pebble_view_commands_impl(app, out_cmds, max_cmds, 0, 1);
}

int elmc_pebble_view_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip) {
  int count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, 0);
  if (count < max_cmds) {
    elmc_pebble_clear_view_cache(app);
  }
  return count;
}

void elmc_pebble_clear_view_cache(ElmcPebbleApp *app) {
  if (!app) return;
#if defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
  (void)app;
#else
  if (app->stream_view_result) {
    elmc_release(app->stream_view_result);
    app->stream_view_result = NULL;
  }
#endif
}

int elmc_pebble_ensure_scene(ElmcPebbleApp *app) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_ensure_scene");
  if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -1);
  if (!app->scene.dirty) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", 0);
  elmc_pebble_prepare_scene_rebuild(app);
  elmc_pebble_scene_reset(app);
  enum {
    BUILD_HEAP_CHUNK_CAPACITY = 32,
    BUILD_MEDIUM_HEAP_CHUNK_CAPACITY = 16,
    BUILD_SMALL_HEAP_CHUNK_CAPACITY = 8,
    BUILD_TINY_HEAP_CHUNK_CAPACITY = 1,
    BUILD_CHUNK_GUARD = 256
  };
  int build_chunk_capacity = BUILD_HEAP_CHUNK_CAPACITY;
  ElmcPebbleDrawCmd *cmds =
      (ElmcPebbleDrawCmd *)malloc(sizeof(ElmcPebbleDrawCmd) * build_chunk_capacity);
  if (!cmds) {
    build_chunk_capacity = BUILD_MEDIUM_HEAP_CHUNK_CAPACITY;
    cmds = (ElmcPebbleDrawCmd *)malloc(sizeof(ElmcPebbleDrawCmd) * build_chunk_capacity);
  }
  if (!cmds) {
    build_chunk_capacity = BUILD_SMALL_HEAP_CHUNK_CAPACITY;
    cmds = (ElmcPebbleDrawCmd *)malloc(sizeof(ElmcPebbleDrawCmd) * build_chunk_capacity);
  }
  if (!cmds) {
    build_chunk_capacity = BUILD_TINY_HEAP_CHUNK_CAPACITY;
    cmds = (ElmcPebbleDrawCmd *)malloc(sizeof(ElmcPebbleDrawCmd) * build_chunk_capacity);
  }
  if (!cmds) {
    elmc_pebble_scene_buffer_free(&app->scene);
    // #region agent log
    elmc_agent_scene_probe(0xED997C02);
    // #endregion
    ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -2);
  }
  int skip = 0;
  for (int chunk = 0; chunk < BUILD_CHUNK_GUARD; chunk++) {
    // #region agent log
    if (chunk == 0 && skip == 0) elmc_agent_scene_probe(0xED997A00);
    // #endregion
    int count = elmc_pebble_view_commands_raw_impl(app, cmds, build_chunk_capacity, skip, 0);
    // #region agent log
    if (chunk == 0 && skip == 0) {
      uint32_t encoded_count = count < 0 ? (uint32_t)(128 + ((-count) & 0x7F)) : (uint32_t)(count > 127 ? 127 : count);
      elmc_agent_scene_probe(0xED997B00 | encoded_count);
      if (count > 0) {
        int probe_limit = count < 4 ? count : 4;
        for (int probe_i = 0; probe_i < probe_limit; probe_i++) {
          elmc_agent_scene_probe(0xED997D00 | ((uint32_t)probe_i << 4) | ((uint32_t)cmds[probe_i].kind & 0x0F));
          elmc_agent_scene_probe(0xED997E00 | ((uint32_t)probe_i << 4) | ((uint32_t)cmds[probe_i].p0 & 0x0F));
        }
      }
    }
    // #endregion
    if (count < 0) {
      elmc_pebble_clear_view_cache(app);
      elmc_pebble_scene_buffer_free(&app->scene);
      free(cmds);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", count);
    }
    if (count == 0) break;
    for (int i = 0; i < count; i++) {
      int rc = elmc_pebble_scene_encode_cmd(app, &cmds[i]);
      if (rc != 0) {
        // #region agent log
        elmc_agent_scene_probe(0xED997F00 | ((uint32_t)i & 0xFF));
        elmc_agent_scene_probe(0xED998000 | (rc < 0 ? (uint32_t)(0x80 | ((-rc) & 0x7F)) : (uint32_t)(rc & 0x7F)));
        // #endregion
        elmc_pebble_clear_view_cache(app);
        elmc_pebble_scene_buffer_free(&app->scene);
        free(cmds);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", rc);
      }
    }
    skip += count;
    if (count < build_chunk_capacity) break;
  }
  elmc_pebble_clear_view_cache(app);
  free(cmds);
  app->scene.dirty = 0;
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  if (!app->prev_scene.bytes || app->prev_scene.byte_count <= 0) {
    elmc_pebble_scene_mark_full_dirty(app);
  } else {
    elmc_pebble_scene_compute_dirty_rect(app);
  }
#endif
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", 0);
}

int elmc_pebble_scene_command_count(ElmcPebbleApp *app) {
  if (elmc_pebble_ensure_scene(app) != 0) return 0;
  return app->scene.command_count;
}

int elmc_pebble_scene_dirty_rect(ElmcPebbleApp *app, ElmcPebbleRect *out_rect, int *out_full) {
  if (!app || !out_rect || !out_full) return -1;
  int rc = elmc_pebble_ensure_scene(app);
  if (rc != 0) return rc;
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  *out_full = app->dirty_rect_full || !app->dirty_rect_valid;
  *out_rect = app->dirty_rect;
  return app->dirty_rect_valid ? 1 : 0;
#else
  *out_full = 1;
  out_rect->x = 0;
  out_rect->y = 0;
  out_rect->w = 0;
  out_rect->h = 0;
  return 0;
#endif
}

static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe);

int elmc_pebble_scene_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip) {
  ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_scene_commands_from");
  if (!app || !out_cmds || max_cmds <= 0 || skip < 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", -1);
  int rc = elmc_pebble_ensure_scene(app);
  if (rc == -2) {
    int fallback_count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, 0);
    // #region agent log
    elmc_agent_scene_probe(0xED998100 | (fallback_count < 0 ? (uint32_t)(0x80 | ((-fallback_count) & 0x7F)) : (uint32_t)(fallback_count > 0x7F ? 0x7F : fallback_count)));
    // #endregion
    ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", fallback_count);
  }
  if (rc != 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", rc);
  int byte_offset = 0;
  int emitted = 0;
  int count = 0;
  while (byte_offset < app->scene.byte_count && count < max_cmds) {
    ElmcPebbleDrawCmd cmd;
    rc = elmc_pebble_scene_decode_record(app->scene.bytes, app->scene.byte_count, &byte_offset, &cmd);
    if (rc != 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", rc);
    if (emitted >= skip) {
      out_cmds[count++] = cmd;
    }
    emitted += 1;
  }
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", count);
}

static int elmc_pebble_view_commands_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe) {
  if (!app || !app->initialized || !out_cmds || max_cmds <= 0) return -1;
  if (skip < 0) return -1;
  int rc = elmc_pebble_ensure_scene(app);
  if (rc != 0) return rc;
  if (skip == 0 && dedupe && app->scene.command_count < max_cmds) {
    if (app->has_prev_ui && app->prev_ops_hash == app->scene.hash) {
      return 0;
    }
    app->has_prev_ui = 1;
    app->prev_window_id = 0;
    app->prev_layer_id = 0;
    app->prev_ops_hash = app->scene.hash;
  }
  return elmc_pebble_scene_commands_from(app, out_cmds, max_cmds, skip);
}

static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe) {
  if (!app || !app->initialized || !out_cmds || max_cmds <= 0) return -1;
  if (skip < 0) return -1;
#if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
  int count = 0;
  ElmcValue *result = NULL;
  int result_is_cached = dedupe ? 0 : 1;
  if (!dedupe && skip == 0) {
    elmc_pebble_clear_view_cache(app);
  }
#endif
#if defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
      // #region agent log
      elmc_agent_scene_probe(0xED996100);
      // #endregion
      ElmcValue *direct_model = elmc_worker_model(&app->worker);
      if (!direct_model) return -2;
      ElmcValue *direct_args[] = { direct_model };
      int direct_count = elmc_fn_Main_view_commands_from(direct_args, 1, out_cmds, max_cmds, skip);
      elmc_release(direct_model);
      if (direct_count < 0) return direct_count;
      // #region agent log
      elmc_agent_scene_probe(direct_count == 0 ? 0xED996120 : 0xED996121);
      // #endregion
      if (skip == 0 && dedupe) {
        uint64_t direct_hash = 1469598103934665603ULL;
        for (int i = 0; i < direct_count; i++) {
          direct_hash ^= (uint64_t)out_cmds[i].kind;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].p0;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].p1;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].p2;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].p3;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].p4;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].p5;
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].path_point_count;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].path_offset_x;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].path_offset_y;
          direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].path_rotation;
          for (int j = 0; j < out_cmds[i].path_point_count && j < 16; j++) {
            direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].path_x[j];
            direct_hash = (direct_hash << 5) - direct_hash + (uint64_t)out_cmds[i].path_y[j];
          }
#endif
        }
        if (direct_count < max_cmds) {
          if (app->has_prev_ui && app->prev_ops_hash == direct_hash) {
            return 0;
          }
          app->has_prev_ui = 1;
          app->prev_window_id = 0;
          app->prev_layer_id = 0;
          app->prev_ops_hash = direct_hash;
        }
      }
      return direct_count;
#else
      if (!dedupe && app->stream_view_result) {
        // #region agent log
        elmc_agent_scene_probe(0xED9961A0);
        // #endregion
        result = app->stream_view_result;
      } else {
        // #region agent log
        elmc_agent_scene_probe(0xED996180);
        // #endregion
        ElmcValue *model = elmc_worker_model(&app->worker);
        // #region agent log
        elmc_agent_scene_probe(model ? 0xED996181 : 0xED99618F);
        // #endregion
        if (!model) return -2;
        ElmcValue *args[] = { model };
        // #region agent log
        elmc_agent_scene_probe(0xED996190);
        // #endregion
        result = elmc_fn_Main_view(args, 1);
        // #region agent log
        elmc_agent_scene_probe(0xED996191);
        // #endregion
        elmc_release(model);
        // #region agent log
        elmc_agent_scene_probe(0xED996200);
        if (!result) {
          elmc_agent_scene_probe(0xED996213);
        } else if (result->tag == ELMC_TAG_TUPLE2) {
          elmc_agent_scene_probe(0xED996211);
        } else if (result->tag == ELMC_TAG_LIST) {
          elmc_agent_scene_probe(0xED996212);
        } else {
          elmc_agent_scene_probe(0xED996210);
        }
        // #endregion
        if (!dedupe) {
          app->stream_view_result = result;
        }
      }
#endif


  #if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
    ElmcValue *ops = result;
    int64_t window_id = 0;
    int64_t layer_id = 0;
    int extracted = elmc_extract_virtual_canvas_ops(result, &window_id, &layer_id, &ops);
    // #region agent log
    elmc_agent_scene_probe(extracted == 0 ? 0xED996300 : 0xED9963F0);
    elmc_agent_scene_probe(0xED997000 | (uint32_t)((extracted < 0 ? -extracted : extracted) & 0xFF));
    // #endregion
    if (extracted != 0 || !ops) {
      ops = result;
    }

    // #region agent log
    if (!ops) {
      elmc_agent_scene_probe(0xED996413);
    } else if (ops->tag == ELMC_TAG_LIST) {
      elmc_agent_scene_probe(ops->payload == NULL ? 0xED996410 : 0xED996411);
    } else if (ops->tag == ELMC_TAG_TUPLE2) {
      elmc_agent_scene_probe(0xED996412);
    } else {
      elmc_agent_scene_probe(0xED996413);
    }
    // #endregion

    if (ops->tag == ELMC_TAG_LIST) {
      ElmcValue *cursor = ops;
      int emitted = 0;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < max_cmds) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        elmc_append_draw_cmd_from_value_window(node->head, out_cmds, max_cmds, &count, &emitted, skip, 0);
        cursor = node->tail;
      }
    } else {
      int emitted = 0;
      elmc_append_draw_cmd_from_value_window(ops, out_cmds, max_cmds, &count, &emitted, skip, 0);
    }

    // #region agent log
    elmc_agent_scene_probe(count == 0 ? 0xED996500 : 0xED996501);
    elmc_agent_scene_probe(0xED997100 | (uint32_t)(count > 255 ? 255 : count));
    // #endregion

    if (skip == 0 && dedupe && extracted == 0 && count < max_cmds) {
      uint64_t next_hash = elmc_hash_value(ops, 0);
      if (app->has_prev_ui &&
          app->prev_window_id == window_id &&
          app->prev_layer_id == layer_id &&
          app->prev_ops_hash == next_hash) {
        count = 0;
      }
      app->has_prev_ui = 1;
      app->prev_window_id = window_id;
      app->prev_layer_id = layer_id;
      app->prev_ops_hash = next_hash;
    }

    if (!result_is_cached) {
      elmc_release(result);
    }
    return count;
  #else
    return -11;
  #endif
}

int elmc_pebble_tick(ElmcPebbleApp *app) {
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_TICK)) return -8;
  return elmc_pebble_dispatch_tag_value(app, 1, elmc_current_second());
}

int64_t elmc_pebble_active_subscriptions(ElmcPebbleApp *app) {
  if (!app || !app->initialized) return 0;
  return elmc_worker_subscriptions(&app->worker);
}

int64_t elmc_pebble_model_as_int(ElmcPebbleApp *app) {
  if (!app || !app->initialized) return 0;
  ElmcValue *model = elmc_worker_model(&app->worker);
  if (!model) return 0;
  int64_t value = 0;
  if (model->tag == ELMC_TAG_TUPLE2 && model->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)model->payload;
    if (tuple->first) {
      value = elmc_as_int(tuple->first);
    }
  } else {
    value = elmc_as_int(model);
  }
  elmc_release(model);
  return value;
}

int elmc_pebble_run_mode(ElmcPebbleApp *app) {
  if (!app) return ELMC_PEBBLE_MODE_APP;
  return app->run_mode;
}

void elmc_pebble_deinit(ElmcPebbleApp *app) {
  if (!app) return;
  elmc_pebble_clear_view_cache(app);
  elmc_pebble_scene_free(app);
  if (app->initialized) {
    elmc_worker_deinit(&app->worker);
  }
  app->initialized = 0;
}
