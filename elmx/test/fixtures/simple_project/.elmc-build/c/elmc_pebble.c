#include <time.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
#define ELMC_PEBBLE_PLATFORM 1
#endif
#ifdef ELMC_PEBBLE_PLATFORM
#include <pebble.h>
#if defined(__has_include)
#if __has_include("../../elmc_emulator_build_flags.h")
#include "../../elmc_emulator_build_flags.h"
#elif __has_include("elmc_emulator_build_flags.h")
#include "elmc_emulator_build_flags.h"
#endif
#endif
#ifndef ELMC_PEBBLE_DEBUG_LOGS
#define ELMC_PEBBLE_DEBUG_LOGS 0
#endif
#endif
#ifndef ELMC_PEBBLE_HEAP_LOG
#define ELMC_PEBBLE_HEAP_LOG 0
#endif
#include "elmc_pebble.h"

#if defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
#define ELMC_PEBBLE_DIRECT_VIEW_SCENE 1
#endif

#if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_DEBUG_LOGS
#define ELMC_PEBBLE_SCENE_LOG(...) APP_LOG(APP_LOG_LEVEL_INFO, __VA_ARGS__)
#else
#define ELMC_PEBBLE_SCENE_LOG(...) do { } while (0)
#endif

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

#if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_HEAP_LOG
void elmc_pebble_heap_log(const char *label) {
  APP_LOG(
    APP_LOG_LEVEL_INFO,
    "ELMC heap %s used=%lu free=%lu",
    label ? label : "?",
    (unsigned long)heap_bytes_used(),
    (unsigned long)heap_bytes_free());
}

void elmc_pebble_render_diag_log(const char *phase, int render_seq, const ElmcPebbleApp *app) {
  if (app) {
    APP_LOG(
      APP_LOG_LEVEL_INFO,
      "ELMC render %s seq=%d heap_used=%lu heap_free=%lu scene_dirty=%d scene_bytes=%d scene_cmds=%d",
      phase ? phase : "?",
      render_seq,
      (unsigned long)heap_bytes_used(),
      (unsigned long)heap_bytes_free(),
      app->scene.dirty,
      app->scene.byte_count,
      app->scene.command_count);
  } else {
    elmc_pebble_heap_log(phase);
  }
}
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
        #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_AGENT_PROBES && !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
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

#if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
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

    #if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
    static int elmc_decode_path_payload(ElmcValue *payload, ElmcPebbleDrawCmd *out_cmd);
    #endif

        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
        static int elmc_copy_draw_text_value(ElmcValue *value, char *out_text, size_t out_size) {
          if (!out_text || out_size == 0) return -1;
          out_text[0] = '\0';
          if (!value) return -1;
          if (value->tag == ELMC_TAG_STRING && value->payload != NULL) {
            strncpy(out_text, (const char *)value->payload, out_size - 1);
            out_text[out_size - 1] = '\0';
            return 0;
          }
          if (value->tag != ELMC_TAG_LIST) return -1;
          size_t used = 0;
          ElmcValue *cursor = value;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            const char *piece = NULL;
            char char_buf[2] = {0, 0};
            if (!node->head) {
              cursor = node->tail;
              continue;
            }
            if (node->head->tag == ELMC_TAG_STRING && node->head->payload != NULL) {
              piece = (const char *)node->head->payload;
            } else {
              char_buf[0] = (char)elmc_as_int(node->head);
              piece = char_buf;
            }
            size_t piece_len = strlen(piece);
            if (piece_len == 0) {
              cursor = node->tail;
              continue;
            }
            if (used + piece_len >= out_size) {
              size_t copy_len = out_size - used - 1;
              if (copy_len > 0) {
                memcpy(out_text + used, piece, copy_len);
                used += copy_len;
              }
              break;
            }
            memcpy(out_text + used, piece, piece_len);
            used += piece_len;
            cursor = node->tail;
          }
          out_text[used] = '\0';
          return used > 0 ? 0 : -1;
        }
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
        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
            if (out_cmd->kind == ELMC_PEBBLE_DRAW_TEXT ||
                out_cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT) {
              int text_payload_count = out_cmd->kind == ELMC_PEBBLE_DRAW_TEXT ? 6 : 5;
              int64_t payload[6] = {0, 0, 0, 0, 0, 0};
              ElmcValue *current = tuple->second;
              for (int i = 0; i < text_payload_count; i++) {
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
              out_cmd->p5 = payload[5];
              (void)elmc_copy_draw_text_value(current, out_cmd->text, sizeof(out_cmd->text));
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

      if (off1->first->tag == ELMC_TAG_TUPLE2 && off1->first->payload != NULL) {
        /* Pebble.Ui.path: tuple2(points, tuple2(tuple2(offset_x, offset_y), rotation)) */
        ElmcTuple2 *xy = (ElmcTuple2 *)off1->first->payload;
        if (!xy->first || !xy->second) return -6;
        out_cmd->path_offset_x = elmc_as_int(xy->first);
        out_cmd->path_offset_y = elmc_as_int(xy->second);
        out_cmd->path_rotation = elmc_as_int(off1->second);
      } else {
        /* path_expr: tuple2(points, tuple2(offset_x, tuple2(offset_y, rotation))) */
        out_cmd->path_offset_x = elmc_as_int(off1->first);

        if (off1->second->tag != ELMC_TAG_TUPLE2 || off1->second->payload == NULL) return -6;
        ElmcTuple2 *off2 = (ElmcTuple2 *)off1->second->payload;
        if (!off2->first || !off2->second) return -7;
        out_cmd->path_offset_y = elmc_as_int(off2->first);
        out_cmd->path_rotation = elmc_as_int(off2->second);
      }

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

    void elmc_draw_cmd_init(ElmcPebbleDrawCmd *cmd, int32_t kind) {
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

#if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
typedef struct {
  unsigned char *bytes;
  int capacity;
} ElmcPebbleScenePoolSlot;

static ElmcPebbleScenePoolSlot elmc_pebble_scene_pool[ELMC_PEBBLE_SCENE_POOL_SLOTS];

static int elmc_pebble_scene_using_pool(const ElmcPebbleSceneBuffer *scene) {
  return scene && scene->pool_slot >= 0 && scene->pool_slot < ELMC_PEBBLE_SCENE_POOL_SLOTS;
}

static void elmc_pebble_scene_pool_sync_from_slot(ElmcPebbleSceneBuffer *scene) {
  if (!elmc_pebble_scene_using_pool(scene)) return;
  ElmcPebbleScenePoolSlot *slot = &elmc_pebble_scene_pool[scene->pool_slot];
  scene->bytes = slot->bytes;
  scene->byte_capacity = slot->capacity;
}

static int elmc_pebble_scene_pool_grow_slot(ElmcPebbleSceneBuffer *scene, int min_capacity) {
  if (!scene || min_capacity < 0) return -1;
  if (!elmc_pebble_scene_using_pool(scene)) return -1;
  ElmcPebbleScenePoolSlot *slot = &elmc_pebble_scene_pool[scene->pool_slot];
  if (slot->capacity >= min_capacity) {
    elmc_pebble_scene_pool_sync_from_slot(scene);
    return 0;
  }
  int next_capacity = slot->capacity > 0 ? slot->capacity : 0;
  while (next_capacity < min_capacity) {
    if (next_capacity == 0) {
      next_capacity = ELMC_PEBBLE_SCENE_INITIAL_CAPACITY;
    } else if (next_capacity < ELMC_PEBBLE_SCENE_INITIAL_CAPACITY) {
      next_capacity += ELMC_PEBBLE_SCENE_GROW_CHUNK;
    } else {
      next_capacity *= 2;
    }
  }
  unsigned char *grown = (unsigned char *)malloc((size_t)next_capacity);
  if (!grown) return -2;
  if (slot->bytes && scene->byte_count > 0) {
    memcpy(grown, slot->bytes, (size_t)scene->byte_count);
  }
  free(slot->bytes);
  slot->bytes = grown;
  slot->capacity = next_capacity;
  elmc_pebble_scene_pool_sync_from_slot(scene);
  return 0;
}

static void elmc_pebble_scene_pool_free_all(void) {
  for (int i = 0; i < ELMC_PEBBLE_SCENE_POOL_SLOTS; i++) {
    free(elmc_pebble_scene_pool[i].bytes);
    elmc_pebble_scene_pool[i].bytes = NULL;
    elmc_pebble_scene_pool[i].capacity = 0;
  }
}
#else
static int elmc_pebble_scene_using_pool(const ElmcPebbleSceneBuffer *scene) {
  (void)scene;
  return 0;
}

static void elmc_pebble_scene_pool_free_all(void) {
}
#endif

    #if ELMC_PEBBLE_SCENE_STATIC_CAPACITY > 0
    static unsigned char elmc_pebble_scene_static_bytes[ELMC_PEBBLE_SCENE_STATIC_CAPACITY];

    static int elmc_pebble_scene_using_static(const ElmcPebbleSceneBuffer *scene) {
      return scene && scene->bytes == elmc_pebble_scene_static_bytes;
    }

    static void elmc_pebble_scene_bind_static(ElmcPebbleSceneBuffer *scene) {
      if (!scene) return;
      scene->bytes = elmc_pebble_scene_static_bytes;
      scene->byte_capacity = ELMC_PEBBLE_SCENE_STATIC_CAPACITY;
    }
    #endif

#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
static void elmc_pebble_scene_chunks_free(ElmcPebbleSceneBuffer *scene) {
  if (!scene) return;
  while (scene->chunks) {
    ElmcPebbleSceneChunk *next = scene->chunks->next;
    free(scene->chunks);
    scene->chunks = next;
  }
}

static ElmcPebbleSceneChunk *elmc_pebble_scene_chunk_tail(ElmcPebbleSceneChunk *head) {
  ElmcPebbleSceneChunk *tail = head;
  while (tail && tail->next) tail = tail->next;
  return tail;
}

static int elmc_pebble_scene_chunk_append(ElmcPebbleSceneBuffer *scene) {
  ElmcPebbleSceneChunk *chunk = (ElmcPebbleSceneChunk *)malloc(sizeof(ElmcPebbleSceneChunk));
  if (!chunk) return -2;
  chunk->next = NULL;
  chunk->used = 0;
  if (!scene->chunks) {
    scene->chunks = chunk;
  } else {
    ElmcPebbleSceneChunk *tail = elmc_pebble_scene_chunk_tail(scene->chunks);
    if (!tail) {
      free(chunk);
      return -2;
    }
    tail->next = chunk;
  }
  scene->byte_capacity += ELMC_PEBBLE_SCENE_CHUNK_SIZE;
  return 0;
}

static int elmc_pebble_scene_materialize_chunks(ElmcPebbleSceneBuffer *scene) {
  if (!scene || !scene->chunks) return 0;
  if (scene->byte_count <= 0) {
    elmc_pebble_scene_chunks_free(scene);
    return 0;
  }
  unsigned char *dest = (unsigned char *)realloc(scene->bytes, (size_t)scene->byte_count);
  if (!dest) return -2;
  scene->bytes = dest;
  scene->byte_capacity = scene->byte_count;
  int pos = 0;
  for (ElmcPebbleSceneChunk *chunk = scene->chunks; chunk; chunk = chunk->next) {
    memcpy(dest + pos, chunk->bytes, (size_t)chunk->used);
    pos += chunk->used;
  }
  elmc_pebble_scene_chunks_free(scene);
  return 0;
}
#endif

    static void elmc_pebble_scene_reset(ElmcPebbleApp *app) {
      if (!app) return;
      app->scene.byte_count = 0;
      app->scene.command_count = 0;
      app->scene.hash = 1469598103934665603ULL;
    }

    static void elmc_pebble_scene_discard_build(ElmcPebbleApp *app) {
      if (!app) return;
      app->scene.byte_count = 0;
      app->scene.command_count = 0;
      app->scene.dirty = 1;
    }

    static void elmc_pebble_scene_buffer_detach(ElmcPebbleSceneBuffer *scene) {
      if (!scene) return;
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      elmc_pebble_scene_chunks_free(scene);
    #endif
      scene->bytes = NULL;
      scene->byte_count = 0;
      scene->byte_capacity = 0;
      scene->command_count = 0;
      scene->hash = 0;
      scene->dirty = 1;
    }

    static void elmc_pebble_scene_abort_build(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_clear_view_cache(app);
      elmc_pebble_scene_discard_build(app);
      elmc_pebble_scene_buffer_detach(&app->scene);
    }

    static void elmc_pebble_scene_free(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_scene_buffer_detach(&app->scene);
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      elmc_pebble_scene_buffer_detach(&app->prev_scene);
    #endif
      elmc_pebble_scene_pool_free_all();
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
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
  elmc_pebble_scene_buffer_detach(&app->prev_scene);
  app->prev_scene = app->scene;
  app->scene.bytes = NULL;
  app->scene.byte_count = 0;
  app->scene.byte_capacity = 0;
  app->scene.pool_slot = app->prev_scene.pool_slot == 0 ? 1 : 0;
#else
  app->scene.byte_count = 0;
#if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
  elmc_pebble_scene_pool_sync_from_slot(&app->scene);
#endif
#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
  elmc_pebble_scene_chunks_free(&app->scene);
  /* byte_capacity tracks chunk reservation during build; reset before chunk append. */
  app->scene.byte_capacity = 0;
#endif
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

void elmc_pebble_invalidate_scene(ElmcPebbleApp *app) {
  if (!app) return;
#if ELMC_PEBBLE_SCENE_CACHE_ENABLED
  elmc_pebble_mark_scene_dirty(app);
  app->scene_draw_byte_offset = 0;
#endif
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  elmc_pebble_scene_mark_full_dirty(app);
#endif
}
static int elmc_pebble_scene_reserve_capacity(ElmcPebbleApp *app, int min_capacity) {
  if (!app || min_capacity < 0) return -1;
#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
  while (app->scene.byte_capacity < min_capacity) {
    if (elmc_pebble_scene_chunk_append(&app->scene) != 0) return -2;
  }
  return 0;
#else
#if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
  if (app->scene.pool_slot < 0) {
    app->scene.pool_slot = 0;
  }
  if (elmc_pebble_scene_using_pool(&app->scene)) {
    return elmc_pebble_scene_pool_grow_slot(&app->scene, min_capacity);
  }
#endif
#if ELMC_PEBBLE_SCENE_STATIC_CAPACITY > 0
  if (!app->scene.bytes) {
    elmc_pebble_scene_bind_static(&app->scene);
  }
  if (elmc_pebble_scene_using_static(&app->scene)) {
    if (min_capacity > ELMC_PEBBLE_SCENE_STATIC_CAPACITY) return -2;
    return 0;
  }
#endif
  if (app->scene.byte_capacity >= min_capacity) return 0;
  int next_capacity = app->scene.byte_capacity > 0 ? app->scene.byte_capacity : 0;
  while (next_capacity < min_capacity) {
    if (next_capacity == 0) {
      next_capacity = ELMC_PEBBLE_SCENE_INITIAL_CAPACITY;
    } else if (next_capacity < ELMC_PEBBLE_SCENE_INITIAL_CAPACITY) {
      next_capacity += ELMC_PEBBLE_SCENE_GROW_CHUNK;
    } else {
      next_capacity *= 2;
    }
  }
  unsigned char *next = (unsigned char *)malloc((size_t)next_capacity);
  if (!next) return -2;
  if (app->scene.bytes && app->scene.byte_count > 0) {
    memcpy(next, app->scene.bytes, (size_t)app->scene.byte_count);
  }
  free(app->scene.bytes);
  app->scene.bytes = next;
  app->scene.byte_capacity = next_capacity;
  return 0;
#endif
}

#if ELMC_PEBBLE_SCENE_TRIM_SLACK > 0
static void elmc_pebble_scene_trim_capacity(ElmcPebbleApp *app) {
  if (!app || !app->scene.bytes || app->scene.byte_count <= 0) return;
#if ELMC_PEBBLE_SCENE_STATIC_CAPACITY > 0
  if (elmc_pebble_scene_using_static(&app->scene)) return;
#endif
  int target = app->scene.byte_count + ELMC_PEBBLE_SCENE_TRIM_SLACK;
  if (app->scene.byte_capacity <= target) return;
  unsigned char *next = (unsigned char *)realloc(app->scene.bytes, (size_t)target);
  if (!next) return;
  app->scene.bytes = next;
  app->scene.byte_capacity = target;
}
#endif

static int elmc_pebble_scene_reserve(ElmcPebbleApp *app, int extra) {
  if (!app || extra < 0) return -1;
  int needed = app->scene.byte_count + extra;
  if (needed <= app->scene.byte_capacity) return 0;
  return elmc_pebble_scene_reserve_capacity(app, needed);
}

static void elmc_pebble_scene_hash_byte(ElmcPebbleApp *app, unsigned char byte) {
  app->scene.hash ^= (uint64_t)byte;
  app->scene.hash *= 1099511628211ULL;
}

static int elmc_pebble_scene_put_u8(ElmcPebbleApp *app, unsigned char value) {
  int rc = elmc_pebble_scene_reserve(app, 1);
  if (rc != 0) return rc;
#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
  ElmcPebbleSceneChunk *tail = elmc_pebble_scene_chunk_tail(app->scene.chunks);
  if (!tail || tail->used >= ELMC_PEBBLE_SCENE_CHUNK_SIZE) {
    if (elmc_pebble_scene_chunk_append(&app->scene) != 0) return -2;
    tail = elmc_pebble_scene_chunk_tail(app->scene.chunks);
    if (!tail) return -2;
  }
  tail->bytes[tail->used++] = value;
  app->scene.byte_count++;
#else
  app->scene.bytes[app->scene.byte_count++] = value;
#endif
  elmc_pebble_scene_hash_byte(app, value);
  return 0;
}

static int elmc_scene_put_i16(ElmcPebbleApp *app, int32_t value) {
  if (value < -32768) value = -32768;
  if (value > 32767) value = 32767;
  uint16_t raw = (uint16_t)((int16_t)value);
  int rc = elmc_pebble_scene_reserve(app, 2);
  if (rc != 0) return rc;
  unsigned char b0 = (unsigned char)(raw & 0xff);
  unsigned char b1 = (unsigned char)((raw >> 8) & 0xff);
#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
  rc = elmc_pebble_scene_put_u8(app, b0);
  if (rc != 0) return rc;
  return elmc_pebble_scene_put_u8(app, b1);
#else
  app->scene.bytes[app->scene.byte_count++] = b0;
  app->scene.bytes[app->scene.byte_count++] = b1;
  elmc_pebble_scene_hash_byte(app, b0);
  elmc_pebble_scene_hash_byte(app, b1);
  return 0;
#endif
}

static int elmc_pebble_scene_put_i32(ElmcPebbleApp *app, int32_t value) {
  uint32_t raw = (uint32_t)value;
  int rc = elmc_pebble_scene_reserve(app, 4);
  if (rc != 0) return rc;
#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
  for (int i = 0; i < 4; i++) {
    unsigned char byte = (unsigned char)((raw >> (i * 8)) & 0xff);
    rc = elmc_pebble_scene_put_u8(app, byte);
    if (rc != 0) return rc;
  }
  return 0;
#else
  for (int i = 0; i < 4; i++) {
    unsigned char byte = (unsigned char)((raw >> (i * 8)) & 0xff);
    app->scene.bytes[app->scene.byte_count++] = byte;
    elmc_pebble_scene_hash_byte(app, byte);
  }
  return 0;
#endif
}

static int32_t elmc_scene_read_i16(const unsigned char *bytes, int *offset, int limit) {
  if (!bytes || !offset || *offset + 2 > limit) return 0;
  uint16_t raw = (uint16_t)bytes[*offset] | ((uint16_t)bytes[*offset + 1] << 8);
  *offset += 2;
  return (int32_t)((int16_t)raw);
}

static int32_t elmc_pebble_scene_read_i32(const unsigned char *bytes, int *offset, int limit) {
  if (!bytes || !offset || *offset + 4 > limit) return 0;
  uint32_t raw = 0;
  for (int i = 0; i < 4; i++) {
    raw |= ((uint32_t)bytes[*offset + i]) << (i * 8);
  }
  *offset += 4;
  return (int32_t)raw;
}

#if ELMC_PEBBLE_FEATURE_DRAW_PIXEL || ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT || ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT || ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL || ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
static int elmc_scene_value_fits_i16(int32_t value) {
  return value >= -32768 && value <= 32767;
}
#endif

#if ELMC_PEBBLE_FEATURE_DRAW_PIXEL || ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT || ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT || ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR || ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR || ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR || ELMC_PEBBLE_FEATURE_DRAW_CLEAR || ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE || ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH || ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
static int elmc_scene_value_fits_u8(int32_t value) {
  return value >= 0 && value <= 255;
}
#endif

#if ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT || ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
static int elmc_scene_bounds_fit_i16(const ElmcPebbleDrawCmd *cmd) {
  if (!cmd) return 0;
  return elmc_scene_value_fits_i16(cmd->p0) &&
         elmc_scene_value_fits_i16(cmd->p1) &&
         elmc_scene_value_fits_i16(cmd->p2) &&
         elmc_scene_value_fits_i16(cmd->p3);
}
#endif

#if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
static int elmc_scene_text_len(const ElmcPebbleDrawCmd *cmd) {
  int text_len = 0;
  if (!cmd) return 0;
  while (text_len < (int)sizeof(cmd->text) && cmd->text[text_len] != '\0') text_len++;
  return text_len;
}
#endif

static int elmc_scene_path_extra_size(const ElmcPebbleDrawCmd *cmd) {
  (void)cmd;
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  if (!cmd) return 0;
  if (cmd->kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
      cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
      cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
    int count = cmd->path_point_count;
    if (count < 0) count = 0;
    if (count > 16) count = 16;
    return 7 + (count * 4);
  }
#endif
  return 0;
}

static int elmc_pebble_scene_payload_len(const ElmcPebbleDrawCmd *cmd) {
      if (!cmd) return -1;
      int32_t kind = cmd->kind;
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      int text_len = elmc_scene_text_len(cmd);
    #endif

    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
      if (kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
          kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
          kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
        return ELMC_SCENE_PL_FULL + elmc_scene_path_extra_size(cmd);
      }
    #endif

      switch (kind) {
    #if ELMC_PEBBLE_FEATURE_DRAW_CONTEXT
      case ELMC_PEBBLE_DRAW_PUSH_CONTEXT:
      case ELMC_PEBBLE_DRAW_POP_CONTEXT:
        return ELMC_SCENE_PL_EMPTY;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH || ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
    #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH
      case ELMC_PEBBLE_DRAW_STROKE_WIDTH:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
      case ELMC_PEBBLE_DRAW_ANTIALIASED:
    #endif
        return elmc_scene_value_fits_u8(cmd->p0) ? ELMC_SCENE_PL_U8 : ELMC_SCENE_PL_I32;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR || ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR || ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR || ELMC_PEBBLE_FEATURE_DRAW_CLEAR || ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
    #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR
      case ELMC_PEBBLE_DRAW_STROKE_COLOR:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR
      case ELMC_PEBBLE_DRAW_FILL_COLOR:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR
      case ELMC_PEBBLE_DRAW_TEXT_COLOR:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_CLEAR
      case ELMC_PEBBLE_DRAW_CLEAR:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
      case ELMC_PEBBLE_DRAW_COMPOSITING_MODE:
    #endif
        return elmc_scene_value_fits_u8(cmd->p0) ? ELMC_SCENE_PL_U8 : ELMC_SCENE_PL_I32;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_PIXEL
      case ELMC_PEBBLE_DRAW_PIXEL:
        if (elmc_scene_value_fits_i16(cmd->p0) &&
            elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_u8(cmd->p2)) {
          return ELMC_SCENE_PL_PIXEL;
        }
        return ELMC_SCENE_PL_FULL;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT
    #if ELMC_PEBBLE_FEATURE_DRAW_LINE
      case ELMC_PEBBLE_DRAW_LINE:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_RECT
      case ELMC_PEBBLE_DRAW_RECT:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT
      case ELMC_PEBBLE_DRAW_FILL_RECT:
    #endif
        if (!elmc_scene_bounds_fit_i16(cmd) || cmd->p5 != 0) return ELMC_SCENE_PL_FULL;
        return elmc_scene_value_fits_u8(cmd->p4) ? ELMC_SCENE_PL_COORDS_COLOR_U8 : ELMC_SCENE_PL_COORDS_COLOR_I32;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
    #if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE
      case ELMC_PEBBLE_DRAW_CIRCLE:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
      case ELMC_PEBBLE_DRAW_FILL_CIRCLE:
    #endif
        if (elmc_scene_value_fits_i16(cmd->p0) &&
            elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_i16(cmd->p2) &&
            cmd->p4 == 0 && cmd->p5 == 0) {
          return elmc_scene_value_fits_u8(cmd->p3) ? ELMC_SCENE_PL_CIRCLE_U8 : ELMC_SCENE_PL_CIRCLE_I32;
        }
        return ELMC_SCENE_PL_FULL;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
      case ELMC_PEBBLE_DRAW_ROUND_RECT:
        if (elmc_scene_bounds_fit_i16(cmd) && elmc_scene_value_fits_i16(cmd->p4)) {
          return elmc_scene_value_fits_u8(cmd->p5) ? ELMC_SCENE_PL_ROUND_U8 : ELMC_SCENE_PL_ROUND_I32;
        }
        return ELMC_SCENE_PL_FULL;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
      case ELMC_PEBBLE_DRAW_TEXT:
        if (elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_i16(cmd->p2) &&
            elmc_scene_value_fits_i16(cmd->p3) &&
            elmc_scene_value_fits_i16(cmd->p4)) {
          return ELMC_SCENE_PL_TEXT_BASE + 1 + text_len;
        }
        return ELMC_SCENE_PL_FULL + 1 + text_len;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT:
        if (elmc_scene_value_fits_i16(cmd->p1) && elmc_scene_value_fits_i16(cmd->p2)) {
          return ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 + text_len;
        }
        return ELMC_SCENE_PL_FULL + 1 + text_len;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
      case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT:
        if (elmc_scene_value_fits_i16(cmd->p1) && elmc_scene_value_fits_i16(cmd->p2)) {
          return ELMC_SCENE_PL_COORDS_COLOR_I32;
        }
        return ELMC_SCENE_PL_FULL;
    #endif
      default:
        return ELMC_SCENE_PL_FULL;
      }
    }
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
    static int elmc_scene_read_text_tail(
        const unsigned char *bytes,
        int *offset,
        int payload_end,
        ElmcPebbleDrawCmd *out_cmd) {
      if (*offset >= payload_end) return 0;
      int text_len = bytes[*offset];
      *offset += 1;
      if (text_len > (int)sizeof(out_cmd->text) - 1) text_len = (int)sizeof(out_cmd->text) - 1;
      if (*offset + text_len > payload_end) return -3;
      memcpy(out_cmd->text, bytes + *offset, (size_t)text_len);
      out_cmd->text[text_len] = '\0';
      *offset += text_len;
      return 0;
    }
    #endif

    static int elmc_scene_read_coords_i16(
        const unsigned char *bytes,
        int *offset,
        int payload_end,
        ElmcPebbleDrawCmd *out_cmd) {
      out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p3 = elmc_scene_read_i16(bytes, offset, payload_end);
      return 0;
    }

    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
    static int elmc_scene_read_text_bounds_i16(
        const unsigned char *bytes,
        int *offset,
        int payload_end,
        ElmcPebbleDrawCmd *out_cmd) {
      out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p3 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p4 = elmc_scene_read_i16(bytes, offset, payload_end);
      return 0;
    }
    #endif

static int elmc_scene_is_path_kind(int32_t kind) {
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  return kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
         kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
         kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN;
#else
  (void)kind;
  return 0;
#endif
}

static int elmc_scene_read_full_i32s(
    const unsigned char *bytes,
    int *offset,
    int payload_end,
    ElmcPebbleDrawCmd *out_cmd) {
  out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p1 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p2 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p4 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
  return 0;
}

static int elmc_scene_read_path_tail(
    const unsigned char *bytes,
    int *offset,
    int payload_end,
    ElmcPebbleDrawCmd *out_cmd) {
#if ELMC_PEBBLE_FEATURE_DRAW_PATH
  if (*offset >= payload_end) return 0;
  int count = bytes[*offset];
  *offset += 1;
  if (count < 0) count = 0;
  if (count > 16) count = 16;
  out_cmd->path_point_count = count;
  out_cmd->path_offset_x = elmc_scene_read_i16(bytes, offset, payload_end);
  out_cmd->path_offset_y = elmc_scene_read_i16(bytes, offset, payload_end);
  out_cmd->path_rotation = elmc_scene_read_i16(bytes, offset, payload_end);
  for (int i = 0; i < count; i++) {
    out_cmd->path_x[i] = (int16_t)elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->path_y[i] = (int16_t)elmc_scene_read_i16(bytes, offset, payload_end);
  }
  return 0;
#else
  (void)bytes;
  (void)offset;
  (void)payload_end;
  (void)out_cmd;
  return 0;
#endif
}
static int elmc_pebble_scene_decode_payload(
    int kind,
    int payload_len,
    const unsigned char *bytes,
    int *offset,
    int payload_end,
    ElmcPebbleDrawCmd *out_cmd) {
  int rc = 0;
  /* Compact text-label payloads (8 + 1 + text_len) overlap fixed enum
     payload sizes such as ELMC_SCENE_PL_ROUND_U8 (11); decode by kind first. */
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
  if (kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
      payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 &&
      payload_len < ELMC_SCENE_PL_TEXT_BASE) {
    out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
    return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
  }
#endif
  switch (payload_len) {
  case ELMC_SCENE_PL_EMPTY:
    return 0;
  case ELMC_SCENE_PL_U8:
    if (*offset >= payload_end) return -3;
    out_cmd->p0 = bytes[*offset];
    *offset += 1;
    return 0;
  case ELMC_SCENE_PL_I32:
    out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    return 0;
#if ELMC_PEBBLE_FEATURE_DRAW_PIXEL
  case ELMC_SCENE_PL_PIXEL:
    out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
    if (*offset >= payload_end) return -3;
    out_cmd->p2 = bytes[*offset];
    *offset += 1;
    return 0;
#endif
  case ELMC_SCENE_PL_COORDS_COLOR_U8:
    rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
    if (*offset >= payload_end) return -3;
    out_cmd->p4 = bytes[*offset];
    *offset += 1;
    return 0;
  case ELMC_SCENE_PL_COORDS_COLOR_I32:
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
    if (kind == ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT) {
      out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
      out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
      return 0;
    }
#endif
    rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
    out_cmd->p4 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    return 0;
#if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
  case ELMC_SCENE_PL_CIRCLE_U8:
    out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
    if (*offset >= payload_end) return -3;
    out_cmd->p3 = bytes[*offset];
    *offset += 1;
    return 0;
  case ELMC_SCENE_PL_CIRCLE_I32:
    out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    return 0;
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
  case ELMC_SCENE_PL_ROUND_U8:
    rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
    out_cmd->p4 = elmc_scene_read_i16(bytes, offset, payload_end);
    if (*offset >= payload_end) return -3;
    out_cmd->p5 = bytes[*offset];
    *offset += 1;
    return 0;
  case ELMC_SCENE_PL_ROUND_I32:
    rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
    out_cmd->p4 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    return 0;
#endif
  default:
    break;
  }
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT
  if (payload_len >= ELMC_SCENE_PL_TEXT_BASE &&
      kind == ELMC_PEBBLE_DRAW_TEXT &&
      payload_len >= ELMC_SCENE_PL_TEXT_BASE + 1) {
    rc = elmc_scene_read_text_bounds_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
    out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
  }
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
  if (payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE &&
      kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
      payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE + 1) {
    out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
    out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
    return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
  }
#endif
  if ((payload_len == ELMC_SCENE_PL_FULL && !elmc_scene_is_path_kind(kind)) ||
      (payload_len > ELMC_SCENE_PL_FULL && elmc_scene_is_path_kind(kind))) {
    rc = elmc_scene_read_full_i32s(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
    if (elmc_scene_is_path_kind(kind)) {
      rc = elmc_scene_read_path_tail(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
    }
    return 0;
  }
#if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
  if (payload_len > ELMC_SCENE_PL_FULL &&
      (kind == ELMC_PEBBLE_DRAW_TEXT ||
       kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT)) {
    out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    out_cmd->p1 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    out_cmd->p2 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    out_cmd->p4 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
    return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
  }
#endif
  return -4;
}
#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT || ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT
#ifndef ELM_PEBBLE_RESOURCE_ID_MISSING
#define ELM_PEBBLE_RESOURCE_ID_MISSING UINT32_MAX
#endif
#ifndef PLAY_COUNT_INFINITE
#define PLAY_COUNT_INFINITE 0xFFFF
#endif

static ElmcPebbleApp *s_sequence_playback_app = NULL;

static void elmc_sequence_track_app(ElmcPebbleApp *app) {
  if (app) {
    s_sequence_playback_app = app;
  }
}

static int64_t elmc_sequence_monotonic_ms(void) {
#ifdef ELMC_PEBBLE_PLATFORM
  time_t seconds = 0;
  uint16_t milliseconds = 0;
  time_ms(&seconds, &milliseconds);
  return ((int64_t)seconds * 1000) + milliseconds;
#else
  return (int64_t)time(NULL) * 1000;
#endif
}

static bool elmc_sequence_play_loops(uint32_t play_count) {
  return play_count == 0 || play_count == PLAY_COUNT_INFINITE || play_count == 0xFFFF;
}

__attribute__((weak)) void elmc_pebble_schedule_layer_redraw(void) {
}

__attribute__((weak)) void elmc_pebble_after_worker_dispatch(void) {
}
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT
#ifdef ELMC_PEBBLE_PLATFORM
#define ELMC_VECTOR_SEQUENCE_MAX_INSTANCES 8

typedef struct {
  int32_t animation_id;
  uint32_t resource_id;
  int16_t origin_x;
  int16_t origin_y;
  int64_t started_at_ms;
  uint32_t duration_ms;
  uint16_t play_count;
  uint8_t active;
  uint8_t seen_this_frame;
  uint8_t finished_pending;
} ElmcVectorSequenceInstance;

static ElmcVectorSequenceInstance s_vector_sequence_instances[ELMC_VECTOR_SEQUENCE_MAX_INSTANCES];
static AppTimer *s_vector_sequence_timer = NULL;
static uint32_t s_cached_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
static uint32_t s_failed_vector_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
static uint32_t s_cached_vector_sequence_duration_ms = 0;
static GDrawCommandSequence *s_cached_sequence = NULL;

static void vector_sequence_timer_callback(void *data);
static void vector_sequence_flush_finished(ElmcPebbleApp *app);

static void vector_sequence_cache_clear(void) {
  if (s_cached_sequence) {
    gdraw_command_sequence_destroy(s_cached_sequence);
    s_cached_sequence = NULL;
  }
  s_cached_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
  s_failed_vector_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
  s_cached_vector_sequence_duration_ms = 0;
}

static uint32_t vector_sequence_total_duration_ms(GDrawCommandSequence *sequence) {
  if (!sequence) {
    return 0;
  }

  uint32_t frame_count = gdraw_command_sequence_get_num_frames(sequence);
  if (frame_count == 0) {
    return 0;
  }

  uint32_t total_ms = 0;
  for (uint32_t index = 0; index < frame_count; index++) {
    GDrawCommandFrame *frame = gdraw_command_sequence_get_frame_by_index(sequence, index);
    if (!frame) {
      continue;
    }
    total_ms += gdraw_command_frame_get_duration(frame);
  }

  return total_ms;
}

static uint32_t vector_sequence_playable_duration_ms(GDrawCommandSequence *sequence) {
  if (!sequence) {
    return 0;
  }

  uint32_t total_ms = gdraw_command_sequence_get_total_duration(sequence);
  if (total_ms > 0) {
    return total_ms;
  }

  return vector_sequence_total_duration_ms(sequence);
}

static GDrawCommandFrame *vector_sequence_frame_at_elapsed(
    GDrawCommandSequence *sequence,
    uint32_t elapsed_ms,
    uint32_t total_duration_ms,
    uint16_t play_count) {
  if (!sequence) {
    return NULL;
  }

  uint32_t frame_count = gdraw_command_sequence_get_num_frames(sequence);
  if (frame_count == 0) {
    return NULL;
  }

  if (total_duration_ms == 0) {
    total_duration_ms = vector_sequence_playable_duration_ms(sequence);
  }

  if (total_duration_ms > 0) {
    if (elmc_sequence_play_loops(play_count)) {
      elapsed_ms = elapsed_ms % total_duration_ms;
    } else if (play_count > 0) {
      uint32_t max_elapsed = total_duration_ms * (uint32_t)play_count;
      if (elapsed_ms >= max_elapsed) {
        elapsed_ms = max_elapsed > 0 ? max_elapsed - 1 : 0;
      }
    }

    uint32_t remaining = elapsed_ms;
    for (uint32_t index = 0; index < frame_count; index++) {
      GDrawCommandFrame *frame = gdraw_command_sequence_get_frame_by_index(sequence, index);
      if (!frame) {
        continue;
      }
      uint32_t frame_duration = gdraw_command_frame_get_duration(frame);
      if (frame_duration == 0) {
        frame_duration = total_duration_ms / frame_count;
        if (frame_duration == 0) {
          frame_duration = 100;
        }
      }
      if (remaining < frame_duration || index + 1 == frame_count) {
        return frame;
      }
      remaining -= frame_duration;
    }
  }

  return gdraw_command_sequence_get_frame_by_index(sequence, frame_count - 1);
}

static GDrawCommandSequence *vector_sequence_cached(uint32_t resource_id) {
  if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
    return NULL;
  }
  if (resource_id == s_failed_vector_sequence_resource_id) {
    return NULL;
  }
  if (s_cached_sequence && s_cached_sequence_resource_id == resource_id) {
    return s_cached_sequence;
  }
  vector_sequence_cache_clear();
  s_cached_sequence_resource_id = resource_id;
  s_cached_sequence = gdraw_command_sequence_create_with_resource(resource_id);
  if (!s_cached_sequence) {
    s_failed_vector_sequence_resource_id = resource_id;
    APP_LOG(APP_LOG_LEVEL_WARNING, "vector sequence load failed resource_id=%lu", (unsigned long)resource_id);
    return NULL;
  }

  s_cached_vector_sequence_duration_ms = vector_sequence_playable_duration_ms(s_cached_sequence);
  if (s_cached_vector_sequence_duration_ms == 0) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "vector sequence has no playable frames resource_id=%lu",
            (unsigned long)resource_id);
  }
  return s_cached_sequence;
}

static ElmcVectorSequenceInstance *vector_sequence_instance_find(int32_t animation_id) {
  for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
    if (inst->active && inst->animation_id == animation_id) {
      return inst;
    }
  }
  return NULL;
}

static ElmcVectorSequenceInstance *vector_sequence_instance_alloc(int32_t animation_id) {
  ElmcVectorSequenceInstance *existing = vector_sequence_instance_find(animation_id);
  if (existing) {
    return existing;
  }

  for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
    if (!inst->active) {
      memset(inst, 0, sizeof(*inst));
      inst->animation_id = animation_id;
      inst->active = 1;
      inst->started_at_ms = elmc_sequence_monotonic_ms();
      return inst;
    }
  }

  return NULL;
}

static bool vector_sequence_instance_animating(
    ElmcVectorSequenceInstance *inst,
    GDrawCommandSequence *sequence,
    uint32_t total_duration_ms) {
  if (!inst || !sequence) {
    return false;
  }

  uint32_t play_count = inst->play_count;
  if (elmc_sequence_play_loops(play_count) && total_duration_ms > 0) {
    return true;
  }

  if (play_count > 0 && total_duration_ms > 0) {
    uint32_t elapsed = (uint32_t)(elmc_sequence_monotonic_ms() - inst->started_at_ms);
    return elapsed < total_duration_ms * (uint32_t)play_count;
  }

  return false;
}

static void vector_sequence_schedule_timer_if_needed(bool animating) {
  if (animating && !s_vector_sequence_timer) {
    s_vector_sequence_timer = app_timer_register(33, vector_sequence_timer_callback, NULL);
  } else if (!animating && s_vector_sequence_timer) {
    app_timer_cancel(s_vector_sequence_timer);
    s_vector_sequence_timer = NULL;
  }
}

static void vector_sequence_timer_callback(void *data) {
  (void)data;
  s_vector_sequence_timer = NULL;
  bool any_animating = false;

  for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
    if (!inst->active) {
      continue;
    }

    GDrawCommandSequence *sequence = vector_sequence_cached(inst->resource_id);
    if (!sequence) {
      inst->active = 0;
      continue;
    }

    if (vector_sequence_instance_animating(inst, sequence, inst->duration_ms)) {
      any_animating = true;
    } else {
      inst->finished_pending = 1;
      inst->active = 0;
    }
  }

  vector_sequence_flush_finished(s_sequence_playback_app);
  if (s_sequence_playback_app) {
    elmc_pebble_invalidate_scene(s_sequence_playback_app);
  }
  elmc_pebble_schedule_layer_redraw();
  vector_sequence_schedule_timer_if_needed(any_animating);
}

static void vector_sequence_flush_finished(ElmcPebbleApp *app) {
  if (!app) {
    return;
  }

  for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
    if (!inst->finished_pending) {
      continue;
    }

    int rc = elmc_pebble_dispatch_animation_finished(app, inst->animation_id);
    if (rc == 0) {
      elmc_pebble_after_worker_dispatch();
    }
    inst->finished_pending = 0;
    inst->active = 0;
  }
}

void elmc_vector_sequence_frame_begin(void) {
  for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
    if (s_vector_sequence_instances[i].active) {
      s_vector_sequence_instances[i].seen_this_frame = 0;
    }
  }
}

void elmc_vector_sequence_draw_at(
    GContext *ctx,
    ElmcPebbleApp *app,
    int32_t animation_id,
    uint32_t resource_id,
    int16_t x,
    int16_t y) {
  if (!ctx || animation_id <= 0) {
    return;
  }

  elmc_sequence_track_app(app);

  GDrawCommandSequence *sequence = vector_sequence_cached(resource_id);
  if (!sequence) {
    return;
  }

  ElmcVectorSequenceInstance *inst = vector_sequence_instance_alloc(animation_id);
  if (!inst) {
    return;
  }

  bool fresh = inst->resource_id == 0;
  inst->resource_id = resource_id;
  inst->origin_x = x;
  inst->origin_y = y;
  inst->seen_this_frame = 1;
  inst->play_count = gdraw_command_sequence_get_play_count(sequence);
  inst->duration_ms = vector_sequence_playable_duration_ms(sequence);
  if (inst->duration_ms == 0 && s_cached_vector_sequence_duration_ms > 0) {
    inst->duration_ms = s_cached_vector_sequence_duration_ms;
  }

  if (fresh) {
    inst->started_at_ms = elmc_sequence_monotonic_ms();
  }

  uint32_t elapsed = (uint32_t)(elmc_sequence_monotonic_ms() - inst->started_at_ms);
  uint32_t total_duration = inst->duration_ms;
  GDrawCommandFrame *frame =
      vector_sequence_frame_at_elapsed(sequence, elapsed, total_duration, inst->play_count);
  if (frame) {
    gdraw_command_frame_draw(ctx, sequence, frame, GPoint(x, y));
  }

  bool animating = vector_sequence_instance_animating(inst, sequence, total_duration);
  if (!animating) {
    inst->finished_pending = 1;
    inst->active = 0;
  }

  vector_sequence_schedule_timer_if_needed(animating);
}

void elmc_vector_sequence_frame_end(ElmcPebbleApp *app) {
  elmc_sequence_track_app(app);
  bool any_animating = false;

  for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
    if (!inst->active) {
      continue;
    }

    if (!inst->seen_this_frame) {
      inst->active = 0;
      continue;
    }

    GDrawCommandSequence *sequence = vector_sequence_cached(inst->resource_id);
    if (!sequence) {
      inst->active = 0;
      continue;
    }

    if (vector_sequence_instance_animating(inst, sequence, inst->duration_ms)) {
      any_animating = true;
    } else {
      inst->finished_pending = 1;
      inst->active = 0;
    }
  }

  vector_sequence_flush_finished(app);
  vector_sequence_schedule_timer_if_needed(any_animating);
}

void elmc_vector_sequence_deinit(void) {
  if (s_vector_sequence_timer) {
    app_timer_cancel(s_vector_sequence_timer);
    s_vector_sequence_timer = NULL;
  }
  vector_sequence_cache_clear();
  memset(s_vector_sequence_instances, 0, sizeof(s_vector_sequence_instances));
}
#else
void elmc_vector_sequence_frame_begin(void) {
}

void elmc_vector_sequence_draw_at(
    GContext *ctx,
    ElmcPebbleApp *app,
    int32_t animation_id,
    uint32_t resource_id,
    int16_t x,
    int16_t y) {
  (void)ctx;
  (void)app;
  (void)animation_id;
  (void)resource_id;
  (void)x;
  (void)y;
}

void elmc_vector_sequence_frame_end(ElmcPebbleApp *app) {
  (void)app;
}

void elmc_vector_sequence_deinit(void) {
}
#endif
#endif
#if ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT
#ifdef ELMC_PEBBLE_PLATFORM
#define ELMC_BITMAP_SEQUENCE_MAX_INSTANCES 8

typedef struct {
  int32_t animation_id;
  uint32_t resource_id;
  int16_t origin_x;
  int16_t origin_y;
  int64_t started_at_ms;
  uint32_t duration_ms;
  uint16_t play_count;
  GBitmapSequence *sequence;
  uint8_t active;
  uint8_t seen_this_frame;
  uint8_t finished_pending;
} ElmcBitmapSequenceInstance;

static ElmcBitmapSequenceInstance s_bitmap_sequence_instances[ELMC_BITMAP_SEQUENCE_MAX_INSTANCES];
static AppTimer *s_bitmap_sequence_timer = NULL;
static uint32_t s_failed_bitmap_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;

static void bitmap_sequence_timer_callback(void *data);

static void bitmap_sequence_normalize_play_count(GBitmapSequence *sequence) {
  if (!sequence) {
    return;
  }

  if (gbitmap_sequence_get_play_count(sequence) == 0) {
    gbitmap_sequence_set_play_count(sequence, PLAY_COUNT_INFINITE);
  }
}

static uint32_t bitmap_sequence_total_duration_ms(GBitmapSequence *sequence) {
  if (!sequence) {
    return 0;
  }

  uint16_t frame_count = gbitmap_sequence_get_total_num_frames(sequence);
  if (frame_count == 0) {
    return 0;
  }

  GSize size = gbitmap_sequence_get_bitmap_size(sequence);
  if (size.w <= 0 || size.h <= 0) {
    return 0;
  }

  GBitmap *scratch = gbitmap_create_blank(size, GBitmapFormat8Bit);
  if (!scratch) {
    return 0;
  }

  gbitmap_sequence_restart(sequence);
  uint32_t total_ms = 0;
  uint32_t delay_ms = 0;

  for (uint16_t frame = 0; frame < frame_count; frame++) {
    if (!gbitmap_sequence_update_bitmap_next_frame(sequence, scratch, &delay_ms)) {
      break;
    }
    total_ms += delay_ms;
  }

  gbitmap_destroy(scratch);
  gbitmap_sequence_restart(sequence);
  return total_ms;
}

static GBitmapSequence *bitmap_sequence_create(uint32_t resource_id) {
  if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
    return NULL;
  }
  if (resource_id == s_failed_bitmap_sequence_resource_id) {
    return NULL;
  }

  GBitmapSequence *sequence = gbitmap_sequence_create_with_resource(resource_id);
  if (!sequence) {
    s_failed_bitmap_sequence_resource_id = resource_id;
    APP_LOG(APP_LOG_LEVEL_WARNING, "bitmap sequence load failed resource_id=%lu",
            (unsigned long)resource_id);
    return NULL;
  }

  bitmap_sequence_normalize_play_count(sequence);
  return sequence;
}

static void bitmap_sequence_instance_release(ElmcBitmapSequenceInstance *inst) {
  if (!inst) {
    return;
  }

  if (inst->sequence) {
    gbitmap_sequence_destroy(inst->sequence);
    inst->sequence = NULL;
  }
}

static ElmcBitmapSequenceInstance *bitmap_sequence_instance_find(int32_t animation_id) {
  for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
    if (inst->active && inst->animation_id == animation_id) {
      return inst;
    }
  }
  return NULL;
}

static ElmcBitmapSequenceInstance *bitmap_sequence_instance_alloc(int32_t animation_id) {
  ElmcBitmapSequenceInstance *existing = bitmap_sequence_instance_find(animation_id);
  if (existing) {
    return existing;
  }

  for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
    if (!inst->active) {
      memset(inst, 0, sizeof(*inst));
      inst->animation_id = animation_id;
      inst->active = 1;
      inst->started_at_ms = elmc_sequence_monotonic_ms();
      return inst;
    }
  }

  return NULL;
}

static bool bitmap_sequence_seek_elapsed(
    GBitmapSequence *sequence,
    GBitmap *bitmap,
    uint32_t elapsed_ms,
    uint32_t total_duration_ms,
    uint16_t play_count) {
  if (!sequence || !bitmap) {
    return false;
  }

  gbitmap_sequence_restart(sequence);
  bitmap_sequence_normalize_play_count(sequence);

  if (total_duration_ms > 0) {
    if (elmc_sequence_play_loops(play_count)) {
      elapsed_ms = elapsed_ms % total_duration_ms;
    } else if (play_count > 0) {
      uint32_t max_elapsed = total_duration_ms * (uint32_t)play_count;
      if (elapsed_ms >= max_elapsed) {
        return false;
      }
    }
  }

  uint32_t accumulated = 0;
  while (true) {
    uint32_t delay_ms = 0;
    if (!gbitmap_sequence_update_bitmap_next_frame(sequence, bitmap, &delay_ms)) {
      return accumulated <= elapsed_ms;
    }

    if (delay_ms == 0) {
      delay_ms = 1;
    }

    if (accumulated + delay_ms > elapsed_ms) {
      return true;
    }

    accumulated += delay_ms;
  }
}

static bool bitmap_sequence_instance_animating(ElmcBitmapSequenceInstance *inst) {
  if (!inst) {
    return false;
  }

  if (elmc_sequence_play_loops(inst->play_count) && inst->duration_ms > 0) {
    return true;
  }

  if (inst->play_count > 0 && inst->duration_ms > 0) {
    uint32_t elapsed = (uint32_t)(elmc_sequence_monotonic_ms() - inst->started_at_ms);
    return elapsed < inst->duration_ms * (uint32_t)inst->play_count;
  }

  return false;
}

static void bitmap_sequence_schedule_timer_if_needed(bool animating) {
  if (animating && !s_bitmap_sequence_timer) {
    s_bitmap_sequence_timer = app_timer_register(33, bitmap_sequence_timer_callback, NULL);
  } else if (!animating && s_bitmap_sequence_timer) {
    app_timer_cancel(s_bitmap_sequence_timer);
    s_bitmap_sequence_timer = NULL;
  }
}

static void bitmap_sequence_flush_finished(ElmcPebbleApp *app) {
  if (!app) {
    return;
  }

  for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
    if (!inst->finished_pending) {
      continue;
    }

    int rc = elmc_pebble_dispatch_animation_finished(app, inst->animation_id);
    if (rc == 0) {
      elmc_pebble_after_worker_dispatch();
    }
    inst->finished_pending = 0;
    bitmap_sequence_instance_release(inst);
    inst->active = 0;
  }
}

static void bitmap_sequence_timer_callback(void *data) {
  (void)data;
  s_bitmap_sequence_timer = NULL;
  bool any_animating = false;

  for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
    if (!inst->active) {
      continue;
    }

    if (!inst->sequence) {
      inst->active = 0;
      continue;
    }

    if (bitmap_sequence_instance_animating(inst)) {
      any_animating = true;
    } else {
      inst->finished_pending = 1;
      inst->active = 0;
    }
  }

  bitmap_sequence_flush_finished(s_sequence_playback_app);
  if (s_sequence_playback_app) {
    elmc_pebble_invalidate_scene(s_sequence_playback_app);
  }
  elmc_pebble_schedule_layer_redraw();
  bitmap_sequence_schedule_timer_if_needed(any_animating);
}

void elmc_bitmap_sequence_frame_begin(void) {
  for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
    if (s_bitmap_sequence_instances[i].active) {
      s_bitmap_sequence_instances[i].seen_this_frame = 0;
    }
  }
}

void elmc_bitmap_sequence_draw_at(
    GContext *ctx,
    ElmcPebbleApp *app,
    int32_t animation_id,
    uint32_t resource_id,
    int16_t x,
    int16_t y) {
  if (!ctx || animation_id <= 0) {
    return;
  }

  elmc_sequence_track_app(app);

  ElmcBitmapSequenceInstance *inst = bitmap_sequence_instance_alloc(animation_id);
  if (!inst) {
    return;
  }

  bool fresh = inst->resource_id == 0;
  bool resource_changed = inst->resource_id != 0 && inst->resource_id != resource_id;

  if (fresh || resource_changed || !inst->sequence) {
    bitmap_sequence_instance_release(inst);
    inst->sequence = bitmap_sequence_create(resource_id);
    if (!inst->sequence) {
      inst->active = 0;
      return;
    }
    inst->started_at_ms = elmc_sequence_monotonic_ms();
    inst->duration_ms = bitmap_sequence_total_duration_ms(inst->sequence);
    inst->play_count = gbitmap_sequence_get_play_count(inst->sequence);
    if (inst->duration_ms == 0) {
      APP_LOG(APP_LOG_LEVEL_WARNING, "bitmap sequence has no playable frames resource_id=%lu",
              (unsigned long)resource_id);
    }
  }

  inst->resource_id = resource_id;
  inst->origin_x = x;
  inst->origin_y = y;
  inst->seen_this_frame = 1;

  GSize size = gbitmap_sequence_get_bitmap_size(inst->sequence);
  if (size.w <= 0 || size.h <= 0) {
    return;
  }

  GBitmap *frame = gbitmap_create_blank(size, GBitmapFormat8Bit);
  if (!frame) {
    return;
  }

  uint32_t elapsed = (uint32_t)(elmc_sequence_monotonic_ms() - inst->started_at_ms);
  bool has_frame = bitmap_sequence_seek_elapsed(
      inst->sequence,
      frame,
      elapsed,
      inst->duration_ms,
      inst->play_count);

  if (has_frame) {
    graphics_draw_bitmap_in_rect(ctx, frame, GRect(x, y, size.w, size.h));
  }

  gbitmap_destroy(frame);

  bool animating = bitmap_sequence_instance_animating(inst);
  if (!animating) {
    inst->finished_pending = 1;
    inst->active = 0;
  }

  bitmap_sequence_schedule_timer_if_needed(animating);
}

void elmc_bitmap_sequence_frame_end(ElmcPebbleApp *app) {
  elmc_sequence_track_app(app);
  bool any_animating = false;

  for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
    ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
    if (!inst->active) {
      continue;
    }

    if (!inst->seen_this_frame) {
      inst->active = 0;
      bitmap_sequence_instance_release(inst);
      continue;
    }

    if (bitmap_sequence_instance_animating(inst)) {
      any_animating = true;
    } else {
      inst->finished_pending = 1;
      inst->active = 0;
    }
  }

  bitmap_sequence_flush_finished(app);
  bitmap_sequence_schedule_timer_if_needed(any_animating);
}

void elmc_bitmap_sequence_deinit(void) {
  if (s_bitmap_sequence_timer) {
    app_timer_cancel(s_bitmap_sequence_timer);
    s_bitmap_sequence_timer = NULL;
  }

  for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
    bitmap_sequence_instance_release(&s_bitmap_sequence_instances[i]);
  }

  memset(s_bitmap_sequence_instances, 0, sizeof(s_bitmap_sequence_instances));
  s_failed_bitmap_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
}
#else
void elmc_bitmap_sequence_frame_begin(void) {
}

void elmc_bitmap_sequence_draw_at(
    GContext *ctx,
    ElmcPebbleApp *app,
    int32_t animation_id,
    uint32_t resource_id,
    int16_t x,
    int16_t y) {
  (void)ctx;
  (void)app;
  (void)animation_id;
  (void)resource_id;
  (void)x;
  (void)y;
}

void elmc_bitmap_sequence_frame_end(ElmcPebbleApp *app) {
  (void)app;
}

void elmc_bitmap_sequence_deinit(void) {
}
#endif
#endif
        void elmc_scene_writer_init_app(ElmcSceneWriter *writer, ElmcPebbleApp *app) {
          if (!writer) return;
          writer->app = app;
          writer->command_count = 0;
        }

        static int elmc_scene_writer_put_u8(ElmcSceneWriter *writer, unsigned char value) {
          if (!writer || !writer->app) return -1;
          return elmc_pebble_scene_put_u8(writer->app, value);
        }

        static int elmc_scene_writer_put_i16(ElmcSceneWriter *writer, int32_t value) {
          if (!writer || !writer->app) return -1;
          return elmc_scene_put_i16(writer->app, value);
        }

        static int elmc_scene_writer_put_i32(ElmcSceneWriter *writer, int32_t value) {
          if (!writer || !writer->app) return -1;
          return elmc_pebble_scene_put_i32(writer->app, value);
        }

    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
    static int elmc_scene_writer_write_text_tail(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
      if (!writer || !writer->app) return -1;
      int text_len = elmc_scene_text_len(cmd);
      int rc = elmc_scene_writer_put_u8(writer, (unsigned char)text_len);
      if (rc != 0) return rc;
      rc = elmc_pebble_scene_reserve(writer->app, text_len);
      if (rc != 0) return rc;
      for (int i = 0; i < text_len; i++) {
        unsigned char byte = (unsigned char)cmd->text[i];
        rc = elmc_pebble_scene_put_u8(writer->app, byte);
        if (rc != 0) return rc;
      }
      return 0;
    }
    #endif

        static int elmc_scene_writer_write_coords_i16(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
          return elmc_scene_writer_put_i16(writer, cmd->p3);
        }

        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
        static int elmc_scene_writer_write_text_bounds_i16(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p3); if (rc != 0) return rc;
          return elmc_scene_writer_put_i16(writer, cmd->p4);
        }
        #endif

        static int elmc_scene_writer_write_full_i32s(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p2); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p3); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p4); if (rc != 0) return rc;
          return elmc_scene_writer_put_i32(writer, cmd->p5);
        }

        static int elmc_scene_writer_write_path_tail(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
        #if ELMC_PEBBLE_FEATURE_DRAW_PATH
          int count = cmd->path_point_count;
          if (count < 0) count = 0;
          if (count > 16) count = 16;
          int rc = elmc_scene_writer_put_u8(writer, (unsigned char)count); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->path_offset_x); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->path_offset_y); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->path_rotation); if (rc != 0) return rc;
          for (int i = 0; i < count; i++) {
            rc = elmc_scene_writer_put_i16(writer, cmd->path_x[i]); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->path_y[i]); if (rc != 0) return rc;
          }
          return 0;
        #else
          (void)writer;
          (void)cmd;
          return 0;
        #endif
        }
    static int elmc_scene_writer_encode_payload(
        ElmcSceneWriter *writer,
        const ElmcPebbleDrawCmd *cmd,
        int payload_len) {
      int rc = 0;
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      if (payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE &&
          cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
          payload_len == ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 + elmc_scene_text_len(cmd)) {
        int rc2 = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc2 != 0) return rc2;
        return elmc_scene_writer_write_text_tail(writer, cmd);
      }
    #endif
      switch (payload_len) {
      case ELMC_SCENE_PL_EMPTY:
        return 0;
      case ELMC_SCENE_PL_U8:
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p0);
      case ELMC_SCENE_PL_I32:
        return elmc_scene_writer_put_i32(writer, cmd->p0);
    #if ELMC_PEBBLE_FEATURE_DRAW_PIXEL
      case ELMC_SCENE_PL_PIXEL:
        rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p2);
    #endif
      case ELMC_SCENE_PL_COORDS_COLOR_U8:
        rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p4);
      case ELMC_SCENE_PL_COORDS_COLOR_I32:
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
        if (cmd->kind == ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT) {
          rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
          return elmc_scene_writer_put_i32(writer, cmd->p3);
        }
    #endif
        rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
        return elmc_scene_writer_put_i32(writer, cmd->p4);
    #if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
      case ELMC_SCENE_PL_CIRCLE_U8:
        rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p3);
      case ELMC_SCENE_PL_CIRCLE_I32:
        rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
        return elmc_scene_writer_put_i32(writer, cmd->p3);
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
      case ELMC_SCENE_PL_ROUND_U8:
        rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p4); if (rc != 0) return rc;
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p5);
      case ELMC_SCENE_PL_ROUND_I32:
        rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p4); if (rc != 0) return rc;
        return elmc_scene_writer_put_i32(writer, cmd->p5);
    #endif
      default:
        break;
      }
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
      if (payload_len >= ELMC_SCENE_PL_TEXT_BASE &&
          cmd->kind == ELMC_PEBBLE_DRAW_TEXT &&
          payload_len == ELMC_SCENE_PL_TEXT_BASE + 1 + elmc_scene_text_len(cmd)) {
        int rc2 = elmc_scene_writer_write_text_bounds_i16(writer, cmd); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i32(writer, cmd->p5); if (rc2 != 0) return rc2;
        return elmc_scene_writer_write_text_tail(writer, cmd);
      }
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      if (payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE &&
          cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
          payload_len == ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 + elmc_scene_text_len(cmd)) {
        int rc2 = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc2 != 0) return rc2;
        return elmc_scene_writer_write_text_tail(writer, cmd);
      }
    #endif
      if (payload_len >= ELMC_SCENE_PL_FULL &&
          (!elmc_scene_is_path_kind(cmd->kind) ||
           payload_len == ELMC_SCENE_PL_FULL + elmc_scene_path_extra_size(cmd))) {
        rc = elmc_scene_writer_write_full_i32s(writer, cmd); if (rc != 0) return rc;
        if (elmc_scene_is_path_kind(cmd->kind) && payload_len > ELMC_SCENE_PL_FULL) {
          rc = elmc_scene_writer_write_path_tail(writer, cmd); if (rc != 0) return rc;
        }
        return 0;
      }
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      if (payload_len > ELMC_SCENE_PL_FULL &&
          (cmd->kind == ELMC_PEBBLE_DRAW_TEXT ||
           cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT)) {
        rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p1); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p2); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p3); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p4); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p5); if (rc != 0) return rc;
        return elmc_scene_writer_write_text_tail(writer, cmd);
      }
    #endif
      return -4;
    }
    int elmc_scene_writer_push_cmd(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          if (!writer || !writer->app || !cmd) return -1;
          int payload_len = elmc_pebble_scene_payload_len(cmd);
          if (payload_len < 0 || payload_len > 255) return -3;
          int rc = elmc_scene_writer_put_u8(writer, (unsigned char)cmd->kind);
          if (rc != 0) return rc;
          rc = elmc_scene_writer_put_u8(writer, (unsigned char)payload_len);
          if (rc != 0) return rc;
          rc = elmc_scene_writer_encode_payload(writer, cmd, payload_len);
          if (rc != 0) return rc;
          writer->command_count += 1;
          writer->app->scene.command_count = writer->command_count;
          return 0;
        }


    int elmc_pebble_scene_decode_record(
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
      int rc = elmc_pebble_scene_decode_payload(kind, payload_len, bytes, offset, payload_end, out_cmd);
      if (rc != 0) return rc;
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
        case ELMC_PEBBLE_DRAW_VECTOR_AT:
        case ELMC_PEBBLE_DRAW_VECTOR_SEQUENCE_AT:
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
        case ELMC_PEBBLE_DRAW_VECTOR_AT:
        case ELMC_PEBBLE_DRAW_VECTOR_SEQUENCE_AT:
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
    #if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
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
          while (setting_cursor && setting_cursor->tag == ELMC_TAG_LIST && setting_cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)setting_cursor->payload;
            ElmcPebbleDrawCmd setting_cmd;
            if (elmc_draw_setting_cmd_from_value(node->head, &setting_cmd) == 0) {
              elmc_emit_draw_cmd(&setting_cmd, out_cmds, max_cmds, count, emitted, skip);
              if (*count >= max_cmds) return 0;
            }
            setting_cursor = node->tail;
          }

          ElmcValue *cmd_cursor = ctx->second;
          while (cmd_cursor && cmd_cursor->tag == ELMC_TAG_LIST && cmd_cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cmd_cursor->payload;
            elmc_append_draw_cmd_from_value_window(node->head, out_cmds, max_cmds, count, emitted, skip, depth + 1);
            if (*count >= max_cmds) return 0;
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
    #if ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN || ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_NOTES || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_TRACKS || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_STREAM_WRITE
    static int elmc_serialize_append_int(
        char *out_text,
        size_t out_size,
        size_t *used,
        int32_t *out_count,
        int64_t item) {
      if (!out_text || !used || !out_count) return -1;
      char chunk[24];
      int n = snprintf(
          chunk,
          sizeof(chunk),
          (*out_count == 0) ? "%ld" : ",%ld",
          (long)item);
      if (n <= 0 || *used + (size_t)n >= out_size) return -2;
      strncat(out_text, chunk, out_size - *used - 1);
      *used += (size_t)n;
      *out_count += 1;
      return 0;
    }

    static int elmc_serialize_int_list(
        ElmcValue *value,
        char *out_text,
        size_t out_size,
        int32_t *out_count) {
      if (!out_text || out_size == 0 || !out_count) return -1;
      out_text[0] = '\0';
      *out_count = 0;
      if (!value) return 0;

      size_t used = 0;
      ElmcValue *cursor = value;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) break;
        if (elmc_serialize_append_int(out_text, out_size, &used, out_count, elmc_as_int(node->head)) != 0) {
          return -2;
        }
        cursor = node->tail;
        if (*out_count >= 64) break;
      }
      return 0;
    }
    #endif

    #if ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_NOTES || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_TRACKS
    static int elmc_serialize_speaker_note_record(
        ElmcValue *note,
        char *out_text,
        size_t out_size,
        size_t *used,
        int32_t *out_count) {
      if (!note || note->tag != ELMC_TAG_RECORD || !note->payload) return -3;
      if (elmc_serialize_append_int(out_text, out_size, used, out_count,
                                    elmc_record_get_int(note, "midiNote")) != 0) return -2;
      if (elmc_serialize_append_int(out_text, out_size, used, out_count,
                                    elmc_record_get_int(note, "waveform")) != 0) return -2;
      if (elmc_serialize_append_int(out_text, out_size, used, out_count,
                                    elmc_record_get_int(note, "durationMs")) != 0) return -2;
      if (elmc_serialize_append_int(out_text, out_size, used, out_count,
                                    elmc_record_get_int(note, "velocity")) != 0) return -2;
      return 0;
    }

    static int elmc_serialize_speaker_notes(
        ElmcValue *value,
        char *out_text,
        size_t out_size,
        int32_t *out_count) {
      if (!out_text || out_size == 0 || !out_count) return -1;
      out_text[0] = '\0';
      *out_count = 0;
      if (!value) return 0;

      size_t used = 0;
      ElmcValue *cursor = value;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) break;
        if (node->head->tag == ELMC_TAG_RECORD) {
          if (elmc_serialize_speaker_note_record(node->head, out_text, out_size, &used, out_count) != 0) return -2;
        } else if (node->head->tag == ELMC_TAG_INT || node->head->tag == ELMC_TAG_BOOL) {
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count, elmc_as_int(node->head)) != 0) return -2;
        } else {
          return -3;
        }
        cursor = node->tail;
        if (*out_count >= 64) break;
      }
      return 0;
    }

    static int32_t elmc_speaker_sample_index_from_maybe(ElmcValue *maybe_sample) {
      ElmcValue *sample = elmc_maybe_or_tuple_just_payload_borrow(maybe_sample);
      if (!sample) return 0;
      if (sample->tag == ELMC_TAG_INT || sample->tag == ELMC_TAG_BOOL) {
        int32_t slot = (int32_t)elmc_as_int(sample);
        return slot > 0 ? slot : 0;
      }
      return 0;
    }

    static int elmc_serialize_speaker_tracks(
        ElmcValue *value,
        char *out_text,
        size_t out_size,
        int32_t *out_count) {
      if (!out_text || out_size == 0 || !out_count) return -1;
      out_text[0] = '\0';
      *out_count = 0;
      if (!value) return 0;

      size_t used = 0;
      ElmcValue *cursor = value;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) break;

        if (node->head->tag == ELMC_TAG_RECORD && node->head->payload) {
          ElmcValue *notes = elmc_record_get(node->head, "notes");
          ElmcValue *sample = elmc_record_get(node->head, "sample");
          int32_t note_count = 0;
          ElmcValue *note_cursor = notes;
          while (note_cursor && note_cursor->tag == ELMC_TAG_LIST && note_cursor->payload != NULL) {
            ElmcCons *note_node = (ElmcCons *)note_cursor->payload;
            if (!note_node->head) break;
            note_count++;
            note_cursor = note_node->tail;
            if (note_count > 256) break;
          }
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count, note_count) != 0) return -2;
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count,
                                        elmc_speaker_sample_index_from_maybe(sample)) != 0) return -2;
          note_cursor = notes;
          int32_t serialized_notes = 0;
          while (note_cursor && note_cursor->tag == ELMC_TAG_LIST && note_cursor->payload != NULL) {
            ElmcCons *note_node = (ElmcCons *)note_cursor->payload;
            if (!note_node->head) break;
            if (elmc_serialize_speaker_note_record(note_node->head, out_text, out_size, &used, out_count) != 0) {
              return -2;
            }
            serialized_notes++;
            note_cursor = note_node->tail;
            if (serialized_notes >= note_count || *out_count >= 64) break;
          }
        } else if (node->head->tag == ELMC_TAG_INT || node->head->tag == ELMC_TAG_BOOL) {
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count, elmc_as_int(node->head)) != 0) {
            return -2;
          }
        } else {
          return -3;
        }

        cursor = node->tail;
        if (*out_count >= 64) break;
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

      if (value->tag == ELMC_TAG_CMD && value->payload != NULL) {
        ElmcCmdPayload *cmd = (ElmcCmdPayload *)value->payload;
        out_cmd->kind = cmd->kind;
        if (cmd->arity > 0) out_cmd->p0 = cmd->p0;
        if (cmd->arity > 1) out_cmd->p1 = cmd->p1;
        if (cmd->arity > 2) out_cmd->p2 = cmd->p2;
        if (cmd->arity > 3) out_cmd->p3 = cmd->p3;
        if (cmd->arity > 4) out_cmd->p4 = cmd->p4;
        if (cmd->arity > 5) out_cmd->p5 = cmd->p5;
        if (cmd->text && cmd->text->tag == ELMC_TAG_STRING && cmd->text->payload) {
          strncpy(out_cmd->text, (const char *)cmd->text->payload, sizeof(out_cmd->text) - 1);
          out_cmd->text[sizeof(out_cmd->text) - 1] = '\0';
        }
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

#if ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN
    if (out_cmd->kind == ELMC_PEBBLE_CMD_VIBES_CUSTOM_PATTERN) {
      int32_t count = 0;
      if (elmc_serialize_int_list(tuple->second, out_cmd->text, sizeof(out_cmd->text), &count) != 0) return -5;
      out_cmd->p0 = count;
      return 0;
    }
#endif

#if ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES
    if (out_cmd->kind == ELMC_PEBBLE_CMD_DATA_LOG_BYTES &&
        tuple->second->tag == ELMC_TAG_TUPLE2 &&
        tuple->second->payload != NULL) {
      ElmcTuple2 *payload_tuple = (ElmcTuple2 *)tuple->second->payload;
      if (!payload_tuple->first || !payload_tuple->second) return -3;
      out_cmd->p0 = elmc_as_int(payload_tuple->first);
      int32_t count = 0;
      if (elmc_serialize_int_list(payload_tuple->second, out_cmd->text, sizeof(out_cmd->text), &count) != 0) return -5;
      out_cmd->p1 = count;
      return 0;
    }
#endif

#if ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_NOTES
    if (out_cmd->kind == ELMC_PEBBLE_CMD_SPEAKER_PLAY_NOTES &&
        tuple->second->tag == ELMC_TAG_TUPLE2 &&
        tuple->second->payload != NULL) {
      ElmcTuple2 *payload_tuple = (ElmcTuple2 *)tuple->second->payload;
      if (!payload_tuple->first || !payload_tuple->second) return -3;
      out_cmd->p0 = elmc_as_int(payload_tuple->first);
      int32_t count = 0;
      if (elmc_serialize_speaker_notes(payload_tuple->second, out_cmd->text, sizeof(out_cmd->text), &count) != 0) return -5;
      out_cmd->p1 = count;
      return 0;
    }
#endif

#if ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_TRACKS
    if (out_cmd->kind == ELMC_PEBBLE_CMD_SPEAKER_PLAY_TRACKS &&
        tuple->second->tag == ELMC_TAG_TUPLE2 &&
        tuple->second->payload != NULL) {
      ElmcTuple2 *payload_tuple = (ElmcTuple2 *)tuple->second->payload;
      if (!payload_tuple->first || !payload_tuple->second) return -3;
      out_cmd->p0 = elmc_as_int(payload_tuple->first);
      int32_t count = 0;
      if (elmc_serialize_speaker_tracks(payload_tuple->second, out_cmd->text, sizeof(out_cmd->text), &count) != 0) return -5;
      out_cmd->p1 = count;
      return 0;
    }
#endif

#if ELMC_PEBBLE_FEATURE_CMD_SPEAKER_STREAM_WRITE
    if (out_cmd->kind == ELMC_PEBBLE_CMD_SPEAKER_STREAM_WRITE) {
      int32_t count = 0;
      if (elmc_serialize_int_list(tuple->second, out_cmd->text, sizeof(out_cmd->text), &count) != 0) return -5;
      out_cmd->p0 = count;
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
#if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
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

    static elmc_int_t elmc_pebble_sub_tag(ElmcPebbleApp *app, int64_t flag) {
      return elmc_worker_sub_msg_tag(&app->worker, flag);
    }
static int elmc_msg_constructor_arity(elmc_int_t tag) {
  switch (tag) {
      case ELMC_PEBBLE_MSG_INCREMENT: return 0;
      case ELMC_PEBBLE_MSG_DECREMENT: return 0;
      case ELMC_PEBBLE_MSG_TICK: return 1;
      case ELMC_PEBBLE_MSG_UPPRESSED: return 0;
      case ELMC_PEBBLE_MSG_SELECTPRESSED: return 0;
      case ELMC_PEBBLE_MSG_DOWNPRESSED: return 0;
      case ELMC_PEBBLE_MSG_ACCELTAP: return 0;
      case ELMC_PEBBLE_MSG_PROVIDETEMPERATURE: return 1;
      case ELMC_PEBBLE_MSG_CURRENTTIMESTRING: return 1;
      case ELMC_PEBBLE_MSG_CLOCKSTYLE24H: return 1;
      case ELMC_PEBBLE_MSG_TIMEZONEISSET: return 1;
      case ELMC_PEBBLE_MSG_TIMEZONENAME: return 1;
      case ELMC_PEBBLE_MSG_WATCHMODELNAME: return 1;
      case ELMC_PEBBLE_MSG_WATCHCOLORNAME: return 1;
      case ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING: return 1;
    default: return 0;
  }
}
    static void elmc_pebble_prepare_dispatch(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_heap_log("dispatch:prepare:before");
      elmc_pebble_clear_view_cache(app);
    #if !ELMC_PEBBLE_DIRTY_REGION_ENABLED
      /* Invalidate encoded scene; retain materialized bytes to avoid heap churn on Aplite.
         Chunked rebuild uses scene.chunks; stale bytes are not read while dirty. */
      app->scene.byte_count = 0;
      app->scene.command_count = 0;
      app->scene.hash = 0;
    #if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
      elmc_pebble_scene_pool_sync_from_slot(&app->scene);
    #endif
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      elmc_pebble_scene_chunks_free(&app->scene);
      app->scene.byte_capacity = 0;
    #endif
    #endif
      elmc_pebble_mark_scene_dirty(app);
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED
      app->scene_draw_byte_offset = 0;
    #endif
      elmc_pebble_heap_log("dispatch:prepare:after");
    }

    static int elmc_pebble_finish_dispatch(ElmcPebbleApp *app, int rc) {
      if (rc == 0) {
        app->has_prev_ui = 0;
        app->prev_ops_hash = 0;
        elmc_pebble_mark_scene_dirty(app);
      }
      elmc_pebble_heap_log("dispatch:after");
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
#if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
  app->stream_view_result = NULL;
#endif
#if ELMC_PEBBLE_SCENE_STATIC_CAPACITY > 0
  elmc_pebble_scene_bind_static(&app->scene);
  app->scene.byte_count = 0;
  app->scene.pool_slot = -1;
#else
  app->scene.bytes = NULL;
  app->scene.byte_capacity = 0;
  app->scene.pool_slot = 0;
#if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
  app->scene.chunks = NULL;
#endif
#endif
  app->scene.command_count = 0;
  app->scene.hash = 0;
  app->scene.dirty = 1;
#if ELMC_PEBBLE_SCENE_CACHE_ENABLED
  app->scene_draw_byte_offset = 0;
#endif
#if ELMC_PEBBLE_DIRTY_REGION_ENABLED
  app->prev_scene.bytes = NULL;
  app->prev_scene.byte_count = 0;
  app->prev_scene.byte_capacity = 0;
  app->prev_scene.command_count = 0;
  app->prev_scene.hash = 0;
  app->prev_scene.dirty = 1;
  app->prev_scene.pool_slot = 1;
  app->dirty_rect.x = 0;
  app->dirty_rect.y = 0;
  app->dirty_rect.w = 0;
  app->dirty_rect.h = 0;
  app->dirty_rect_valid = 0;
  app->dirty_rect_full = 1;
#endif
  elmc_pebble_heap_log("init:before");
  int rc = elmc_worker_init(&app->worker, flags);
  if (rc == 0) app->initialized = 1;
  elmc_pebble_heap_log("init:after");
  ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_init_with_mode", rc);
}

        int elmc_pebble_dispatch_int(ElmcPebbleApp *app, int64_t tag) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_int");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", -1);
          ElmcValue *msg = elmc_new_int_take(tag);
          if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", -2);
          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", elmc_pebble_finish_dispatch(app, rc));
        }

    int elmc_pebble_dispatch_tag_value(ElmcPebbleApp *app, int64_t tag, int64_t value) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_value");
      if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -1);
      ElmcValue *tag_value = elmc_new_int_take(tag);
      ElmcValue *payload_value = elmc_new_int_take(value);
      if (!tag_value || !payload_value) {
        if (tag_value) elmc_release(tag_value);
        if (payload_value) elmc_release(payload_value);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -2);
      }

      ElmcValue *msg = elmc_tuple2_take_value(tag_value, payload_value);
      if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -2);

      elmc_pebble_prepare_dispatch(app);
      int rc = elmc_worker_dispatch(&app->worker, msg);
      elmc_release(msg);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", elmc_pebble_finish_dispatch(app, rc));
    }

    int elmc_pebble_dispatch_tag_bool(ElmcPebbleApp *app, int64_t tag, int value) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_bool");
      if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", -1);
      ElmcValue *tag_value = elmc_new_int_take(tag);
      ElmcValue *payload_value = elmc_new_bool_take(value ? 1 : 0);
      if (!tag_value || !payload_value) {
        if (tag_value) elmc_release(tag_value);
        if (payload_value) elmc_release(payload_value);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", -2);
      }

      ElmcValue *msg = elmc_tuple2_take_value(tag_value, payload_value);
      if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", -2);

      elmc_pebble_prepare_dispatch(app);
      int rc = elmc_worker_dispatch(&app->worker, msg);
      elmc_release(msg);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", elmc_pebble_finish_dispatch(app, rc));
    }

    int elmc_pebble_dispatch_tag_string(ElmcPebbleApp *app, int64_t tag, const char *value) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_string");
      if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_string", -1);
      ElmcValue *tag_value = elmc_new_int_take(tag);
      ElmcValue *payload_value = elmc_new_string_take(value ? value : "");
      if (!tag_value || !payload_value) {
        if (tag_value) elmc_release(tag_value);
        if (payload_value) elmc_release(payload_value);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_string", -2);
      }

      ElmcValue *msg = elmc_tuple2_take_value(tag_value, payload_value);
      if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_string", -2);

      elmc_pebble_prepare_dispatch(app);
      int rc = elmc_worker_dispatch(&app->worker, msg);
      elmc_release(msg);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_string", elmc_pebble_finish_dispatch(app, rc));
    }

        int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_payload");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -1);
          if (!payload) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -3);
          ElmcValue *tag_value = elmc_new_int_take(tag);
          if (!tag_value) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -2);

          ElmcValue *msg = elmc_tuple2_take_value(tag_value, payload);
          if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -2);

          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", elmc_pebble_finish_dispatch(app, rc));
        }
    static ElmcValue *elmc_pebble_int_tuple_from_values(const int64_t *field_values, int index, int field_count) {
          if (field_count <= 0) return elmc_new_int_take(0);
          if (!field_values || index < 0 || index >= field_count) return NULL;

          ElmcValue *head = elmc_new_int_take(field_values[index]);
          if (!head) return NULL;
          if (index == field_count - 1) return head;

          ElmcValue *tail = elmc_pebble_int_tuple_from_values(field_values, index + 1, field_count);
          if (!tail) {
            elmc_release(head);
            return NULL;
          }

          return elmc_tuple2_take_value(head, tail);
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

          ElmcValue *inner_tag_value = elmc_new_int_take(inner_tag);
          ElmcValue *inner_payload = elmc_pebble_int_tuple_from_values(field_values, 0, field_count);
          if (!inner_tag_value || !inner_payload) {
            if (inner_tag_value) elmc_release(inner_tag_value);
            if (inner_payload) elmc_release(inner_payload);
            ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -2);
          }

          ElmcValue *inner_msg = elmc_tuple2_take_value(inner_tag_value, inner_payload);
          if (!inner_msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -2);

          int rc = elmc_pebble_dispatch_tag_payload(app, outer_tag, inner_msg);
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

      ElmcValue *tag_value = elmc_new_int_take(tag);
      if (!tag_value) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);

      ElmcValue **record_values = (ElmcValue **)malloc(sizeof(ElmcValue *) * field_count);
      if (!record_values) {
        elmc_release(tag_value);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);
      }

      int built = 0;
      for (int i = 0; i < field_count; i++) {
        record_values[i] = elmc_new_int_take(field_values[i]);
        if (!record_values[i]) {
          built = i;
          goto cleanup_values;
        }
      }
      built = field_count;

      ElmcValue *payload_value = elmc_record_new_take_value(field_count, field_names, record_values);
      free(record_values);

      if (!payload_value) {
        elmc_release(tag_value);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);
      }

      ElmcValue *msg = elmc_tuple2_take_value(tag_value, payload_value);
      if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);

      elmc_pebble_prepare_dispatch(app);
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
          case ELMC_PEBBLE_MSG_INCREMENT: *out_tag = 1; return 0;
      case ELMC_PEBBLE_MSG_DECREMENT: *out_tag = 2; return 0;
      case ELMC_PEBBLE_MSG_TICK: *out_tag = 3; return 0;
      case ELMC_PEBBLE_MSG_UPPRESSED: *out_tag = 4; return 0;
      case ELMC_PEBBLE_MSG_SELECTPRESSED: *out_tag = 5; return 0;
      case ELMC_PEBBLE_MSG_DOWNPRESSED: *out_tag = 6; return 0;
      case ELMC_PEBBLE_MSG_ACCELTAP: *out_tag = 7; return 0;
      case ELMC_PEBBLE_MSG_PROVIDETEMPERATURE: *out_tag = 8; return 0;
      case ELMC_PEBBLE_MSG_CURRENTTIMESTRING: *out_tag = 9; return 0;
      case ELMC_PEBBLE_MSG_CLOCKSTYLE24H: *out_tag = 10; return 0;
      case ELMC_PEBBLE_MSG_TIMEZONEISSET: *out_tag = 11; return 0;
      case ELMC_PEBBLE_MSG_TIMEZONENAME: *out_tag = 12; return 0;
      case ELMC_PEBBLE_MSG_WATCHMODELNAME: *out_tag = 13; return 0;
      case ELMC_PEBBLE_MSG_WATCHCOLORNAME: *out_tag = 14; return 0;
      case ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING: *out_tag = 15; return 0;
          default: return -3;
        }
      }

      if (value == 0) return -4;
      switch (key) {
          case ELMC_PEBBLE_MSG_INCREMENT: *out_tag = 1; return 0;
      case ELMC_PEBBLE_MSG_DECREMENT: *out_tag = 2; return 0;
      case ELMC_PEBBLE_MSG_TICK: *out_tag = 3; return 0;
      case ELMC_PEBBLE_MSG_UPPRESSED: *out_tag = 4; return 0;
      case ELMC_PEBBLE_MSG_SELECTPRESSED: *out_tag = 5; return 0;
      case ELMC_PEBBLE_MSG_DOWNPRESSED: *out_tag = 6; return 0;
      case ELMC_PEBBLE_MSG_ACCELTAP: *out_tag = 7; return 0;
      case ELMC_PEBBLE_MSG_PROVIDETEMPERATURE: *out_tag = 8; return 0;
      case ELMC_PEBBLE_MSG_CURRENTTIMESTRING: *out_tag = 9; return 0;
      case ELMC_PEBBLE_MSG_CLOCKSTYLE24H: *out_tag = 10; return 0;
      case ELMC_PEBBLE_MSG_TIMEZONEISSET: *out_tag = 11; return 0;
      case ELMC_PEBBLE_MSG_TIMEZONENAME: *out_tag = 12; return 0;
      case ELMC_PEBBLE_MSG_WATCHMODELNAME: *out_tag = 13; return 0;
      case ELMC_PEBBLE_MSG_WATCHCOLORNAME: *out_tag = 14; return 0;
      case ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING: *out_tag = 15; return 0;
        default: return -3;
      }
    }

    int elmc_pebble_dispatch_appmessage(ElmcPebbleApp *app, int32_t key, int32_t value) {
      int64_t tag = 0;
      int rc = elmc_pebble_msg_from_appmessage(key, value, &tag);
      if (rc != 0) return rc;
      return elmc_pebble_dispatch_int(app, tag);
    }

    static elmc_int_t elmc_pebble_button_event(int32_t pressed) {
      return pressed ? ELMC_BUTTON_EVENT_PRESSED : ELMC_BUTTON_EVENT_RELEASED;
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
      elmc_int_t tag = elmc_worker_sub_msg_tag(&app->worker, required);
      if (tag <= 0) return -6;
      return elmc_pebble_dispatch_int(app, tag);
    }

    int elmc_pebble_dispatch_button_raw(ElmcPebbleApp *app, int32_t button_id, int32_t pressed) {
      if (!app || !app->initialized) return -1;
      if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BUTTON_RAW)) return -8;
      elmc_int_t event = elmc_pebble_button_event(pressed);
      elmc_int_t tag = elmc_worker_button_raw_msg_tag(&app->worker, button_id, event);
      if (tag <= 0) return 1;
      return elmc_pebble_dispatch_int(app, tag);
    }

    int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction) {
      (void)axis;
      (void)direction;
      if (!app || !app->initialized) return -1;
      if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_TAP)) return -8;
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_ACCEL_TAP);
      if (tag <= 0) return -6;
      return elmc_pebble_dispatch_int(app, tag);
    }

    int elmc_pebble_dispatch_accel_data(ElmcPebbleApp *app, int32_t x, int32_t y, int32_t z) {
      if (!app || !app->initialized) return -1;
      if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_DATA)) return -8;
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_ACCEL_DATA);
      if (tag <= 0) return -6;
      const char *names[] = {"x", "y", "z"};
      const int64_t values[] = {x, y, z};
      return elmc_pebble_dispatch_tag_record_int_fields(app, tag, 3, names, values);
    }

    int elmc_pebble_dispatch_frame(ElmcPebbleApp *app, int64_t dt_ms, int64_t elapsed_ms, int64_t frame) {
          if (!app || !app->initialized) return -1;
          if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_FRAME)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_FRAME);
          if (tag <= 0) return -6;
          const char *names[] = {"dtMs", "elapsedMs", "frame"};
          const int64_t values[] = {dt_ms, elapsed_ms, frame};
          return elmc_pebble_dispatch_tag_record_int_fields(app, tag, 3, names, values);
        }

    int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BATTERY)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_BATTERY);
          if (tag <= 0) return -6;
          if (level < 0) level = 0;
          if (level > 100) level = 100;
          return elmc_pebble_dispatch_tag_value(app, tag, level);
        }

        int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_CONNECTION)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_CONNECTION);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_bool(app, tag, connected);
        }

        int elmc_pebble_dispatch_health(ElmcPebbleApp *app, int event) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_HEALTH)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_HEALTH);
          if (tag <= 0) return -6;
          if (event < 0) event = 0;
          if (event > 2) event = 0;
          return elmc_pebble_dispatch_tag_value(app, tag, event);
        }

        int elmc_pebble_dispatch_app_focus(ElmcPebbleApp *app, int in_focus) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_APP_FOCUS)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_APP_FOCUS);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, in_focus ? 0 : 1);
        }

        int elmc_pebble_dispatch_backlight(ElmcPebbleApp *app, int is_on) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BACKLIGHT)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_BACKLIGHT);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, is_on ? 0 : 1);
        }

        int elmc_pebble_dispatch_screen_change(ElmcPebbleApp *app, int width, int height, int shape, int color_mode) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_SCREEN_CHANGE)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_SCREEN_CHANGE);
          if (tag <= 0) return -6;
          const char *field_names[] = {"width", "height", "shape", "colorMode"};
          int64_t field_values[] = {width, height, shape, color_mode};
          return elmc_pebble_dispatch_tag_record_int_fields(app, tag, 4, field_names, field_values);
        }

        int elmc_pebble_dispatch_speaker_finished(ElmcPebbleApp *app, int reason) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_SPEAKER_FINISHED)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_SPEAKER_FINISHED);
          if (tag <= 0) return -6;
          if (reason < 0) reason = 0;
          if (reason > 3) reason = 0;
          return elmc_pebble_dispatch_tag_value(app, tag, reason);
        }

    int elmc_pebble_dispatch_dictation_status(ElmcPebbleApp *app, int status) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_DICTATION)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_DICTATION);
          if (tag <= 0) return -6;
          if (status < 0) status = 0;
          if (status > 2) status = 2;
          return elmc_pebble_dispatch_tag_value(app, tag, status);
        }

        int elmc_pebble_dispatch_dictation_result(ElmcPebbleApp *app, int is_ok, int error_code, const char *text) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_DICTATION)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_DICTATION);
          if (tag <= 0) return -6;

          ElmcValue *result_payload = NULL;
          if (is_ok) {
            ElmcValue *ok_value = elmc_new_string_take(text ? text : "");
            if (elmc_result_ok(&result_payload, ok_value) != RC_SUCCESS) return -2;
            elmc_release(ok_value);
          } else {
            ElmcValue *error_value = NULL;
            if (error_code == 3) {
              error_value =
                  elmc_tuple2_take_value(elmc_new_int_take(3), elmc_new_string_take(text ? text : ""));
            } else {
              error_value = elmc_new_int_take(error_code);
            }
            if (!error_value) return -2;
            if (elmc_result_err(&result_payload, error_value) != RC_SUCCESS) return -2;
            elmc_release(error_value);
          }
          if (!result_payload) return -2;

          int rc = elmc_pebble_dispatch_tag_payload(app, tag, result_payload);
          elmc_release(result_payload);
          return rc;
        }

    int elmc_pebble_dispatch_unobstructed_will_change(ElmcPebbleApp *app, int x, int y, int w, int h) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA);
          if (tag <= 0) return -6;

          const char *names[] = {"x", "y", "w", "h"};
          int64_t values[] = {x, y, w, h};
          return elmc_pebble_dispatch_tag_record_int_fields(app, tag, 4, names, values);
        }

        int elmc_pebble_dispatch_unobstructed_changing(ElmcPebbleApp *app, int progress) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA);
          if (tag <= 0) return -6;
          if (progress < 0) progress = 0;
          if (progress > 255) progress = 255;
          return elmc_pebble_dispatch_tag_value(app, tag, progress);
        }

        int elmc_pebble_dispatch_unobstructed_did_change(ElmcPebbleApp *app) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_int(app, tag);
        }

    int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_HOUR)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_HOUR);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, hour);
        }

        int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_MINUTE)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_MINUTE);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, minute);
        }

        int elmc_pebble_dispatch_day(ElmcPebbleApp *app, int day) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_DAY)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_DAY);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, day);
        }

        int elmc_pebble_dispatch_month(ElmcPebbleApp *app, int month) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_MONTH)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_MONTH);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, month);
        }

        int elmc_pebble_dispatch_year(ElmcPebbleApp *app, int year) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_YEAR)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_YEAR);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, year);
        }

    int elmc_pebble_dispatch_animation_finished(ElmcPebbleApp *app, int animation_id) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ANIMATION_FINISHED)) return -8;
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_ANIMATION_FINISHED);
      if (tag <= 0) return -6;
      return elmc_pebble_dispatch_tag_value(app, tag, animation_id);
    }

    int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value) {
      if (!app || !app->initialized) return -1;
      if (-1 <= 0) return -6;
      return elmc_pebble_dispatch_tag_string(app, -1, value ? value : "");
    }

    int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value) {
      if (!app || !app->initialized) return -1;
      if (-1 <= 0) return -6;
      return elmc_pebble_dispatch_tag_value(app, -1, value);
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
    static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe, int *out_emitted_end);

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
      int count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, 0, NULL);
      if (count < max_cmds) {
        elmc_pebble_clear_view_cache(app);
      }
      return count;
    }
    void elmc_pebble_clear_view_cache(ElmcPebbleApp *app) {
  if (!app) return;
  if (app->stream_view_result) {
    elmc_release(app->stream_view_result);
    app->stream_view_result = NULL;
  }
    }

    int elmc_pebble_ensure_scene(ElmcPebbleApp *app) {
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_ENTER);
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_ensure_scene");
      if (!app || !app->initialized) {
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -1);
      }
    #if !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -2);
    #endif
      if (!app->scene.dirty) {
        ELMC_PEBBLE_SCENE_LOG("elmc-scene ensure skip clean cmds=%d bytes=%d",
                app->scene.command_count, app->scene.byte_count);
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", 0);
      }
      ELMC_PEBBLE_SCENE_LOG("elmc-scene ensure rebuild begin");
      elmc_pebble_prepare_scene_rebuild(app);
      elmc_pebble_scene_reset(app);
#if defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
  {
    ElmcSceneWriter writer;
    elmc_scene_writer_init_app(&writer, app);
    ElmcValue *direct_model = elmc_worker_model(&app->worker);
    if (!direct_model) {
      elmc_pebble_scene_abort_build(app);
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -2);
    }
    ElmcValue *direct_args[] = { direct_model };
    ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_VIEW_APPEND_ENTER);
    RC rc = elmc_fn_Main_view_scene_append(direct_args, 1, &writer);
    ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_VIEW_APPEND_EXIT);
    elmc_release(direct_model);
    ELMC_PEBBLE_SCENE_LOG("elmc-scene view append rc=%u writer_cmds=%d",
            (unsigned)rc, writer.command_count);
    if (rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(rc, "elmc_pebble_ensure_scene", "view_scene_append");
      elmc_pebble_scene_abort_build(app);
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -1);
    }
  }
    #else
      enum { BUILD_CHUNK_GUARD = 256 };
      ElmcPebbleDrawCmd cmd;
      ElmcSceneWriter writer;
      int skip = 0;
      elmc_scene_writer_init_app(&writer, app);
      for (int chunk = 0; chunk < BUILD_CHUNK_GUARD; chunk++) {
        int emitted_end = 0;
        int count = elmc_pebble_view_commands_raw_impl(app, &cmd, 1, skip, 0, &emitted_end);
        if (count < 0) {
          elmc_pebble_scene_abort_build(app);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", count);
        }
        if (count == 0) break;
        int rc = elmc_scene_writer_push_cmd(&writer, &cmd);
        if (rc != 0) {
          elmc_pebble_scene_abort_build(app);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", rc);
        }
        skip = emitted_end;
      }
    #endif
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      {
        int mat_rc = elmc_pebble_scene_materialize_chunks(&app->scene);
        if (mat_rc != 0) {
          elmc_pebble_scene_abort_build(app);
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", mat_rc);
        }
      }
    #endif
      elmc_pebble_clear_view_cache(app);
      app->scene.dirty = 0;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED
      app->scene_draw_byte_offset = 0;
    #endif
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      if (!app->prev_scene.bytes || app->prev_scene.byte_count <= 0) {
        elmc_pebble_scene_mark_full_dirty(app);
      } else {
        elmc_pebble_scene_compute_dirty_rect(app);
      }
    #endif
    #if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
      elmc_pebble_scene_pool_sync_from_slot(&app->scene);
    #endif
    #if ELMC_PEBBLE_SCENE_TRIM_SLACK > 0
      elmc_pebble_scene_trim_capacity(app);
    #endif
      ELMC_PEBBLE_SCENE_LOG("elmc-scene ensure ok cmds=%d bytes=%d cap=%d",
              app->scene.command_count, app->scene.byte_count, app->scene.byte_capacity);
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

static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe, int *out_emitted_end);

static int elmc_pebble_scene_decode_from(
    ElmcPebbleApp *app,
    ElmcPebbleDrawCmd *out_cmds,
    int max_cmds,
    int skip,
    int *out_emitted_end) {
  int byte_offset = 0;
  int emitted = 0;
  int count = 0;
  int rc = 0;
  while (byte_offset < app->scene.byte_count && count < max_cmds) {
    ElmcPebbleDrawCmd cmd;
    rc = elmc_pebble_scene_decode_record(
        app->scene.bytes, app->scene.byte_count, &byte_offset, &cmd);
    if (rc != 0) return rc;
    if (emitted >= skip) {
      out_cmds[count++] = cmd;
    }
    emitted += 1;
  }
  if (out_emitted_end) *out_emitted_end = emitted;
  return count;
}

    void elmc_pebble_scene_reset_draw_cursor(ElmcPebbleApp *app) {
      if (!app) return;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED
      app->scene_draw_byte_offset = 0;
    #endif
    }

    int elmc_pebble_scene_commands_next(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds) {
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_ENTER);
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_scene_commands_next");
      if (!app || !out_cmds || max_cmds <= 0) {
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", -1);
      }
    #if !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      int direct_count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, 0, 0, NULL);
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", direct_count);
    #endif
      /* Scene cache is built off the draw stack (deferred timer in the app template).
         While dirty or empty, skip drawing rather than calling ensure_scene here.
         Mid-stream reads may finish draining a cached scene after dirty is set. */
      if (app->scene.byte_count <= 0) {
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", 0);
      }
      if (app->scene.dirty && app->scene_draw_byte_offset == 0) {
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", 0);
      }
      int rc = 0;
      int byte_offset = app->scene_draw_byte_offset;
      int count = 0;
      while (byte_offset < app->scene.byte_count && count < max_cmds) {
        ElmcPebbleDrawCmd cmd;
        rc = elmc_pebble_scene_decode_record(app->scene.bytes, app->scene.byte_count, &byte_offset, &cmd);
        if (rc != 0) {
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", rc);
        }
        out_cmds[count++] = cmd;
      }
      app->scene_draw_byte_offset = byte_offset;
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", count);
    }

    int elmc_pebble_scene_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_scene_commands_from");
      if (!app || !out_cmds || max_cmds <= 0 || skip < 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", -1);
    #if !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      int direct_count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, 0, NULL);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", direct_count);
    #endif
      int rc = elmc_pebble_ensure_scene(app);
      if (rc != 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", rc);
      int count = elmc_pebble_scene_decode_from(app, out_cmds, max_cmds, skip, NULL);
      if (count < 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", count);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", count);
    }

    static int elmc_pebble_view_commands_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe) {
      if (!app || !app->initialized || !out_cmds || max_cmds <= 0) return -1;
      if (skip < 0) return -1;
    #if !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      return elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, dedupe, NULL);
    #endif
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
static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe, int *out_emitted_end) {
  if (!app || !app->initialized || !out_cmds || max_cmds <= 0) return -1;
  if (skip < 0) return -1;
  if (out_emitted_end) *out_emitted_end = skip;
#if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
  int count = 0;
  ElmcValue *result = NULL;
  int result_is_cached = dedupe ? 0 : 1;
  if (!dedupe && skip == 0) {
    elmc_pebble_clear_view_cache(app);
  }
#endif
  #if defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
        int direct_rc = elmc_pebble_ensure_scene(app);
        if (direct_rc != 0) return direct_rc;
        if (skip == 0 && dedupe && app->scene.command_count < max_cmds) {
          if (app->has_prev_ui && app->prev_ops_hash == app->scene.hash) {
            return 0;
          }
          app->has_prev_ui = 1;
          app->prev_window_id = 0;
          app->prev_layer_id = 0;
          app->prev_ops_hash = app->scene.hash;
        }
        return elmc_pebble_scene_decode_from(app, out_cmds, max_cmds, skip, out_emitted_end);
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
              elmc_pebble_heap_log("view:start");
              RC view_rc = elmc_fn_Main_view(&result, args, 1);
              elmc_pebble_heap_log("view:end");
              if (view_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(view_rc, "elmc_pebble_view_commands_raw_impl", "view");
                elmc_release(model);
                return -2;
              }
              if (!result) {
                ELMC_RC_LOG_FAIL(RC_ERR_OUT_OF_MEMORY, "elmc_pebble_view_commands_raw_impl", "view");
                elmc_release(model);
                return -2;
              }
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
  #if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
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

    int emitted = 0;
    if (ops->tag == ELMC_TAG_LIST) {
      ElmcValue *cursor = ops;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < max_cmds) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        elmc_append_draw_cmd_from_value_window(node->head, out_cmds, max_cmds, &count, &emitted, skip, 0);
        cursor = node->tail;
      }
    } else {
      elmc_append_draw_cmd_from_value_window(ops, out_cmds, max_cmds, &count, &emitted, skip, 0);
    }
    if (out_emitted_end) *out_emitted_end = emitted;
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
  elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_TICK);
  if (tag <= 0) return -6;
  if (elmc_msg_constructor_arity(tag) > 0) return elmc_pebble_dispatch_tag_value(app, tag, elmc_current_second());
  return elmc_pebble_dispatch_int(app, tag);
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
