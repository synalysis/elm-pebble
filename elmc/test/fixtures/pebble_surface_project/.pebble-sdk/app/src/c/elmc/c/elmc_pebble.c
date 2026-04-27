#include "elmc_pebble.h"
#include <stdlib.h>

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

static int elmc_decode_path_payload(ElmcValue *payload, ElmcPebbleDrawCmd *out_cmd);

static int elmc_draw_cmd_from_value(ElmcValue *value, ElmcPebbleDrawCmd *out_cmd) {
  if (!out_cmd) return -1;
  out_cmd->kind = ELMC_PEBBLE_DRAW_NONE;
  out_cmd->p0 = 0;
  out_cmd->p1 = 0;
  out_cmd->p2 = 0;
  out_cmd->p3 = 0;
  out_cmd->p4 = 0;
  out_cmd->p5 = 0;
  out_cmd->path_point_count = 0;
  out_cmd->path_offset_x = 0;
  out_cmd->path_offset_y = 0;
  out_cmd->path_rotation = 0;
  for (int i = 0; i < 16; i++) {
    out_cmd->path_x[i] = 0;
    out_cmd->path_y[i] = 0;
  }
  if (!value) return -2;

  if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) {
    out_cmd->kind = ELMC_PEBBLE_DRAW_TEXT_INT;
    out_cmd->p2 = elmc_as_int(value);
    return 0;
  }

  if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (!tuple->first || !tuple->second) return -3;
    out_cmd->kind = elmc_as_int(tuple->first);
    if (out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
        out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
        out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
      return elmc_decode_path_payload(tuple->second, out_cmd);
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
  out_cmd->path_point_count = 0;
  out_cmd->path_offset_x = 0;
  out_cmd->path_offset_y = 0;
  out_cmd->path_rotation = 0;
  for (int i = 0; i < 16; i++) {
    out_cmd->path_x[i] = 0;
    out_cmd->path_y[i] = 0;
  }
  switch (setting_tag) {
    case 1: out_cmd->kind = ELMC_PEBBLE_DRAW_STROKE_WIDTH; return 0;
    case 2: out_cmd->kind = ELMC_PEBBLE_DRAW_ANTIALIASED; return 0;
    case 3: out_cmd->kind = ELMC_PEBBLE_DRAW_STROKE_COLOR; return 0;
    case 4: out_cmd->kind = ELMC_PEBBLE_DRAW_FILL_COLOR; return 0;
    case 5: out_cmd->kind = ELMC_PEBBLE_DRAW_TEXT_COLOR; return 0;
    case 6: out_cmd->kind = ELMC_PEBBLE_DRAW_COMPOSITING_MODE; return 0;
    default: return -3;
  }
}

static int elmc_append_draw_cmd_from_value(ElmcValue *value, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int *count, int depth) {
  if (!value || !out_cmds || !count) return -1;
  if (depth > 32) return -2;
  if (*count >= max_cmds) return 0;

  if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (tuple->first && tuple->second && elmc_as_int(tuple->first) == ELMC_PEBBLE_DRAW_CONTEXT_GROUP) {
      if (tuple->second->tag != ELMC_TAG_TUPLE2 || tuple->second->payload == NULL) return -3;
      ElmcTuple2 *ctx = (ElmcTuple2 *)tuple->second->payload;
      if (!ctx->first || !ctx->second) return -4;

      if (*count < max_cmds) {
        out_cmds[*count].kind = ELMC_PEBBLE_DRAW_PUSH_CONTEXT;
        out_cmds[*count].p0 = 0;
        out_cmds[*count].p1 = 0;
        out_cmds[*count].p2 = 0;
        out_cmds[*count].p3 = 0;
        out_cmds[*count].p4 = 0;
        out_cmds[*count].p5 = 0;
        out_cmds[*count].path_point_count = 0;
        out_cmds[*count].path_offset_x = 0;
        out_cmds[*count].path_offset_y = 0;
        out_cmds[*count].path_rotation = 0;
        for (int i = 0; i < 16; i++) {
          out_cmds[*count].path_x[i] = 0;
          out_cmds[*count].path_y[i] = 0;
        }
        *count += 1;
      }

      ElmcValue *setting_cursor = ctx->first;
      while (setting_cursor && setting_cursor->tag == ELMC_TAG_LIST && setting_cursor->payload != NULL && *count < max_cmds) {
        ElmcCons *node = (ElmcCons *)setting_cursor->payload;
        if (elmc_draw_setting_cmd_from_value(node->head, &out_cmds[*count]) == 0) {
          *count += 1;
        }
        setting_cursor = node->tail;
      }

      ElmcValue *cmd_cursor = ctx->second;
      while (cmd_cursor && cmd_cursor->tag == ELMC_TAG_LIST && cmd_cursor->payload != NULL && *count < max_cmds) {
        ElmcCons *node = (ElmcCons *)cmd_cursor->payload;
        elmc_append_draw_cmd_from_value(node->head, out_cmds, max_cmds, count, depth + 1);
        cmd_cursor = node->tail;
      }

      if (*count < max_cmds) {
        out_cmds[*count].kind = ELMC_PEBBLE_DRAW_POP_CONTEXT;
        out_cmds[*count].p0 = 0;
        out_cmds[*count].p1 = 0;
        out_cmds[*count].p2 = 0;
        out_cmds[*count].p3 = 0;
        out_cmds[*count].p4 = 0;
        out_cmds[*count].p5 = 0;
        out_cmds[*count].path_point_count = 0;
        out_cmds[*count].path_offset_x = 0;
        out_cmds[*count].path_offset_y = 0;
        out_cmds[*count].path_rotation = 0;
        for (int i = 0; i < 16; i++) {
          out_cmds[*count].path_x[i] = 0;
          out_cmds[*count].path_y[i] = 0;
        }
        *count += 1;
      }
      return 0;
    }
  }

  if (elmc_draw_cmd_from_value(value, &out_cmds[*count]) == 0) {
    *count += 1;
  }
  return 0;
}

static int elmc_cmd_from_value(ElmcValue *value, ElmcPebbleCmd *out_cmd) {
  if (!out_cmd) return -1;
  out_cmd->kind = ELMC_PEBBLE_CMD_NONE;
  out_cmd->p0 = 0;
  out_cmd->p1 = 0;
  out_cmd->p2 = 0;
  out_cmd->p3 = 0;
  out_cmd->p4 = 0;
  out_cmd->p5 = 0;
  if (!value) return -2;

  if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) {
    out_cmd->kind = elmc_as_int(value);
    return 0;
  }

  if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (!tuple->first || !tuple->second) return -3;
    out_cmd->kind = elmc_as_int(tuple->first);
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
  if (elmc_as_int(root->first) != ELMC_PEBBLE_UI_WINDOW_STACK) return -4;

  ElmcValue *window_cursor = root->second;
  ElmcValue *top_window = NULL;
  int64_t seen_window_ids[16] = {0};
  int seen_window_count = 0;
  while (window_cursor && window_cursor->tag == ELMC_TAG_LIST && window_cursor->payload != NULL) {
    ElmcCons *window_node = (ElmcCons *)window_cursor->payload;
    if (window_node->head && window_node->head->tag == ELMC_TAG_TUPLE2 && window_node->head->payload != NULL) {
      ElmcTuple2 *candidate_tuple = (ElmcTuple2 *)window_node->head->payload;
      if (candidate_tuple->first && candidate_tuple->second &&
          elmc_as_int(candidate_tuple->first) == ELMC_PEBBLE_UI_WINDOW_NODE &&
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
  if (elmc_as_int(window_tuple->first) != ELMC_PEBBLE_UI_WINDOW_NODE) return -7;

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
          elmc_as_int(candidate_tuple->first) == ELMC_PEBBLE_UI_CANVAS_LAYER &&
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
  if (elmc_as_int(layer_tuple->first) != ELMC_PEBBLE_UI_CANVAS_LAYER) return -12;

  if (layer_tuple->second->tag != ELMC_TAG_TUPLE2 || layer_tuple->second->payload == NULL) return -13;
  ElmcTuple2 *layer_payload = (ElmcTuple2 *)layer_tuple->second->payload;
  if (!layer_payload->first || !layer_payload->second) return -14;

  *out_layer_id = elmc_as_int(layer_payload->first);
  *out_ops = layer_payload->second;
  return 0;
}

static int elmc_pebble_is_subscribed(ElmcPebbleApp *app, int64_t flag) {
  if (!app || !app->initialized) return 0;
  int64_t active = elmc_worker_subscriptions(&app->worker);
  return (active & flag) != 0;
}

int elmc_pebble_init(ElmcPebbleApp *app, ElmcValue *flags) {
  return elmc_pebble_init_with_mode(app, flags, ELMC_PEBBLE_MODE_APP);
}

int elmc_pebble_init_with_mode(ElmcPebbleApp *app, ElmcValue *flags, int run_mode) {
  if (!app) return -1;
  app->initialized = 0;
  app->run_mode = run_mode;
  app->has_prev_ui = 0;
  app->prev_window_id = 0;
  app->prev_layer_id = 0;
  app->prev_ops_hash = 0;
  int rc = elmc_worker_init(&app->worker, flags);
  if (rc == 0) app->initialized = 1;
  return rc;
}

int elmc_pebble_dispatch_int(ElmcPebbleApp *app, int64_t tag) {
  if (!app || !app->initialized) return -1;
  ElmcValue *msg = elmc_new_int(tag);
  if (!msg) return -2;
  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  return rc;
}

int elmc_pebble_dispatch_tag_value(ElmcPebbleApp *app, int64_t tag, int64_t value) {
  if (!app || !app->initialized) return -1;
  ElmcValue *tag_value = elmc_new_int(tag);
  ElmcValue *payload_value = elmc_new_int(value);
  if (!tag_value || !payload_value) {
    if (tag_value) elmc_release(tag_value);
    if (payload_value) elmc_release(payload_value);
    return -2;
  }

  ElmcValue *msg = elmc_tuple2(tag_value, payload_value);
  elmc_release(tag_value);
  elmc_release(payload_value);
  if (!msg) return -2;

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  return rc;
}

int elmc_pebble_dispatch_tag_bool(ElmcPebbleApp *app, int64_t tag, int value) {
  if (!app || !app->initialized) return -1;
  ElmcValue *tag_value = elmc_new_int(tag);
  ElmcValue *payload_value = elmc_new_bool(value ? 1 : 0);
  if (!tag_value || !payload_value) {
    if (tag_value) elmc_release(tag_value);
    if (payload_value) elmc_release(payload_value);
    return -2;
  }

  ElmcValue *msg = elmc_tuple2(tag_value, payload_value);
  elmc_release(tag_value);
  elmc_release(payload_value);
  if (!msg) return -2;

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  return rc;
}

int elmc_pebble_dispatch_tag_string(ElmcPebbleApp *app, int64_t tag, const char *value) {
  if (!app || !app->initialized) return -1;
  ElmcValue *tag_value = elmc_new_int(tag);
  ElmcValue *payload_value = elmc_new_string(value ? value : "");
  if (!tag_value || !payload_value) {
    if (tag_value) elmc_release(tag_value);
    if (payload_value) elmc_release(payload_value);
    return -2;
  }

  ElmcValue *msg = elmc_tuple2(tag_value, payload_value);
  elmc_release(tag_value);
  elmc_release(payload_value);
  if (!msg) return -2;

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  return rc;
}

int elmc_pebble_dispatch_tag_record_int_fields(
    ElmcPebbleApp *app,
    int64_t tag,
    int field_count,
    const char **field_names,
    const int64_t *field_values) {
  if (!app || !app->initialized) return -1;
  if (field_count <= 0 || !field_names || !field_values) return -3;

  ElmcValue *tag_value = elmc_new_int(tag);
  if (!tag_value) return -2;

  ElmcValue **record_values = (ElmcValue **)malloc(sizeof(ElmcValue *) * field_count);
  if (!record_values) {
    elmc_release(tag_value);
    return -2;
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
    return -2;
  }

  ElmcValue *msg = elmc_tuple2(tag_value, payload_value);
  elmc_release(tag_value);
  elmc_release(payload_value);
  if (!msg) return -2;

  int rc = elmc_worker_dispatch(&app->worker, msg);
  elmc_release(msg);
  return rc;

cleanup_values:
  for (int i = 0; i < built; i++) {
    if (record_values[i]) elmc_release(record_values[i]);
  }
  free(record_values);
  elmc_release(tag_value);
  return -2;
}

int elmc_pebble_msg_from_appmessage(int32_t key, int32_t value, int64_t *out_tag) {
  if (!out_tag) return -1;

  if (key == 0) {
    switch (value) {
      case ELMC_PEBBLE_MSG_TICK: *out_tag = 1; return 0;
      case ELMC_PEBBLE_MSG_BUTTONUP: *out_tag = 2; return 0;
      case ELMC_PEBBLE_MSG_BUTTONSELECT: *out_tag = 3; return 0;
      case ELMC_PEBBLE_MSG_BUTTONDOWN: *out_tag = 4; return 0;
      case ELMC_PEBBLE_MSG_ACCELTAP: *out_tag = 5; return 0;
      case ELMC_PEBBLE_MSG_BATTERYCHANGED: *out_tag = 6; return 0;
      case ELMC_PEBBLE_MSG_CONNECTIONCHANGED: *out_tag = 7; return 0;
      case ELMC_PEBBLE_MSG_GOTTIME: *out_tag = 8; return 0;
      case ELMC_PEBBLE_MSG_GOTCLOCKSTYLE24H: *out_tag = 9; return 0;
      case ELMC_PEBBLE_MSG_GOTTIMEZONEISSET: *out_tag = 10; return 0;
      case ELMC_PEBBLE_MSG_GOTTIMEZONE: *out_tag = 11; return 0;
      case ELMC_PEBBLE_MSG_GOTSTOREDINT: *out_tag = 12; return 0;
      case ELMC_PEBBLE_MSG_GOTWATCHMODEL: *out_tag = 13; return 0;
      case ELMC_PEBBLE_MSG_GOTWATCHCOLOR: *out_tag = 14; return 0;
      case ELMC_PEBBLE_MSG_GOTFIRMWAREVERSION: *out_tag = 15; return 0;
      case ELMC_PEBBLE_MSG_GOTBATTERYLEVEL: *out_tag = 16; return 0;
      case ELMC_PEBBLE_MSG_GOTCONNECTIONSTATUS: *out_tag = 17; return 0;
      default: return -3;
    }
  }

  if (value == 0) return -4;
  switch (key) {
      case ELMC_PEBBLE_MSG_TICK: *out_tag = 1; return 0;
      case ELMC_PEBBLE_MSG_BUTTONUP: *out_tag = 2; return 0;
      case ELMC_PEBBLE_MSG_BUTTONSELECT: *out_tag = 3; return 0;
      case ELMC_PEBBLE_MSG_BUTTONDOWN: *out_tag = 4; return 0;
      case ELMC_PEBBLE_MSG_ACCELTAP: *out_tag = 5; return 0;
      case ELMC_PEBBLE_MSG_BATTERYCHANGED: *out_tag = 6; return 0;
      case ELMC_PEBBLE_MSG_CONNECTIONCHANGED: *out_tag = 7; return 0;
      case ELMC_PEBBLE_MSG_GOTTIME: *out_tag = 8; return 0;
      case ELMC_PEBBLE_MSG_GOTCLOCKSTYLE24H: *out_tag = 9; return 0;
      case ELMC_PEBBLE_MSG_GOTTIMEZONEISSET: *out_tag = 10; return 0;
      case ELMC_PEBBLE_MSG_GOTTIMEZONE: *out_tag = 11; return 0;
      case ELMC_PEBBLE_MSG_GOTSTOREDINT: *out_tag = 12; return 0;
      case ELMC_PEBBLE_MSG_GOTWATCHMODEL: *out_tag = 13; return 0;
      case ELMC_PEBBLE_MSG_GOTWATCHCOLOR: *out_tag = 14; return 0;
      case ELMC_PEBBLE_MSG_GOTFIRMWAREVERSION: *out_tag = 15; return 0;
      case ELMC_PEBBLE_MSG_GOTBATTERYLEVEL: *out_tag = 16; return 0;
      case ELMC_PEBBLE_MSG_GOTCONNECTIONSTATUS: *out_tag = 17; return 0;
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
      if (-1 <= 0) return -5;
      *out_tag = -1;
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

int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction) {
  (void)axis;
  (void)direction;
  if (!app || !app->initialized) return -1;
  if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_TAP)) return -8;
  if (5 <= 0) return -6;
  return elmc_pebble_dispatch_int(app, 5);
}

int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level) {
  if (!app || !app->initialized) return -1;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BATTERY)) return -8;
  if (6 <= 0) return -6;
  if (level < 0) level = 0;
  if (level > 100) level = 100;
  return elmc_pebble_dispatch_tag_value(app, 6, level);
}

int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected) {
  if (!app || !app->initialized) return -1;
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_CONNECTION)) return -8;
  if (7 <= 0) return -6;
  return elmc_pebble_dispatch_tag_bool(app, 7, connected);
}

int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd) {
  if (!app || !app->initialized || !out_cmd) return -1;
  ElmcValue *cmd = elmc_worker_take_cmd(&app->worker);
  if (!cmd) return -2;
  int rc = elmc_cmd_from_value(cmd, out_cmd);
  elmc_release(cmd);
  return rc;
}

int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd) {
  int count = elmc_pebble_view_commands(app, out_cmd, 1);
  if (count < 0) return count;
  if (count == 0) return -7;
  return 0;
}

int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds) {
  if (!app || !app->initialized || !out_cmds || max_cmds <= 0) return -1;
  int count = 0;
      ElmcValue *model = elmc_worker_model(&app->worker);
      if (!model) return -2;
      ElmcValue *args[] = { model };
      ElmcValue *result = elmc_fn_Main_view(args, 1);
      elmc_release(model);


  ElmcValue *ops = result;
  int64_t window_id = 0;
  int64_t layer_id = 0;
  int extracted = elmc_extract_virtual_canvas_ops(result, &window_id, &layer_id, &ops);

  if (ops->tag == ELMC_TAG_LIST) {
    ElmcValue *cursor = ops;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < max_cmds) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      elmc_append_draw_cmd_from_value(node->head, out_cmds, max_cmds, &count, 0);
      cursor = node->tail;
    }
  } else {
    elmc_append_draw_cmd_from_value(ops, out_cmds, max_cmds, &count, 0);
  }

  if (extracted == 0) {
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

  elmc_release(result);
  return count;
}

int elmc_pebble_tick(ElmcPebbleApp *app) {
  /* Convention for the current worker subset: tick emits Increment-like message. */
  if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_TICK)) return -8;
  return elmc_pebble_dispatch_int(app, 1);
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
  if (app->initialized) {
    elmc_worker_deinit(&app->worker);
  }
  app->initialized = 0;
}
