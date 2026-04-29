defmodule Elmc.Backend.Pebble do
  @moduledoc """
  Generates a Pebble-oriented host shim around the worker adapter.
  """

  alias ElmEx.IR

  @spec write_pebble_shim(IR.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def write_pebble_shim(%IR{} = ir, out_dir, entry_module) do
    c_dir = Path.join(out_dir, "c")
    msg_constructors = msg_constructors(ir, entry_module)
    msg_constructor_arities = msg_constructor_arities(ir, entry_module)
    msg_constructor_payload_specs = msg_constructor_payload_specs(ir, entry_module)
    watch_model_tags = union_constructors(ir, "Pebble.WatchInfo", "WatchModel")
    watch_color_tags = union_constructors(ir, "Pebble.WatchInfo", "WatchColor")
    has_view = has_view?(ir, entry_module)
    feature_flags = feature_flags(ir, msg_constructors)

    with :ok <- File.mkdir_p(c_dir),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_pebble.h"),
             pebble_header(
               msg_constructors,
               msg_constructor_payload_specs,
               watch_model_tags,
               watch_color_tags,
               feature_flags
             )
           ),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_pebble.c"),
             pebble_source(msg_constructors, msg_constructor_arities, has_view, entry_module)
           ) do
      :ok
    end
  end

  @spec pebble_header([map()], map(), [map()], [map()], map()) :: String.t()
  defp pebble_header(
         msg_constructors,
         msg_constructor_payload_specs,
         watch_model_tags,
         watch_color_tags,
         feature_flags
       ) do
    msg_enum_members =
      msg_constructors
      |> Enum.map_join("\n", fn {name, tag} ->
        "  ELMC_PEBBLE_MSG_#{macro_name(name)} = #{tag},"
      end)

    msg_presence_macros =
      msg_constructors
      |> Enum.map_join("\n", fn {name, _tag} ->
        "#define ELMC_PEBBLE_HAS_MSG_#{macro_name(name)} 1"
      end)

    watch_model_macros = constructor_tag_macros("ELMC_PEBBLE_WATCH_MODEL", watch_model_tags)
    watch_color_macros = constructor_tag_macros("ELMC_PEBBLE_WATCH_COLOR", watch_color_tags)
    feature_macros = feature_flag_macros(feature_flags)

    phone_to_watch_target =
      phone_to_watch_msg_target(msg_constructors, msg_constructor_payload_specs)

    """
    #ifndef ELMC_PEBBLE_H
    #define ELMC_PEBBLE_H

    #include "elmc_worker.h"

    typedef struct {
      ElmcWorkerState worker;
      int initialized;
      int run_mode;
      int has_prev_ui;
      int64_t prev_window_id;
      int64_t prev_layer_id;
      uint64_t prev_ops_hash;
    } ElmcPebbleApp;

    typedef enum {
      ELMC_PEBBLE_MODE_APP = 0,
      ELMC_PEBBLE_MODE_WATCHFACE = 1
    } ElmcPebbleRunMode;

    typedef enum {
      ELMC_PEBBLE_MSG_UNKNOWN = 0,
    #{msg_enum_members}
    } ElmcPebbleMsgTag;

    #{msg_presence_macros}

    typedef enum {
      ELMC_PEBBLE_BUTTON_UP = 1,
      ELMC_PEBBLE_BUTTON_SELECT = 2,
      ELMC_PEBBLE_BUTTON_DOWN = 3
    } ElmcPebbleButtonId;

    typedef enum {
      ELMC_PEBBLE_ACCEL_AXIS_X = 1,
      ELMC_PEBBLE_ACCEL_AXIS_Y = 2,
      ELMC_PEBBLE_ACCEL_AXIS_Z = 3
    } ElmcPebbleAccelAxis;

    typedef struct {
      int64_t kind;
      int64_t p0;
      int64_t p1;
      int64_t p2;
      int64_t p3;
      int64_t p4;
      int64_t p5;
      int64_t path_point_count;
      int64_t path_offset_x;
      int64_t path_offset_y;
      int64_t path_rotation;
      int64_t path_x[16];
      int64_t path_y[16];
      char text[64];
    } ElmcPebbleDrawCmd;

    typedef struct {
      int64_t kind;
      int64_t p0;
      int64_t p1;
      int64_t p2;
      int64_t p3;
      int64_t p4;
      int64_t p5;
    } ElmcPebbleCmd;

    #define ELMC_PEBBLE_DRAW_NONE 0
    #define ELMC_PEBBLE_DRAW_TEXT_INT 1
    #define ELMC_PEBBLE_DRAW_CLEAR 2
    #define ELMC_PEBBLE_DRAW_PIXEL 3
    #define ELMC_PEBBLE_DRAW_LINE 4
    #define ELMC_PEBBLE_DRAW_RECT 5
    #define ELMC_PEBBLE_DRAW_FILL_RECT 6
    #define ELMC_PEBBLE_DRAW_CIRCLE 7
    #define ELMC_PEBBLE_DRAW_FILL_CIRCLE 8
    #define ELMC_PEBBLE_DRAW_TEXT_LABEL 9
    #define ELMC_PEBBLE_DRAW_PUSH_CONTEXT 10
    #define ELMC_PEBBLE_DRAW_POP_CONTEXT 11
    #define ELMC_PEBBLE_DRAW_STROKE_WIDTH 12
    #define ELMC_PEBBLE_DRAW_ANTIALIASED 13
    #define ELMC_PEBBLE_DRAW_STROKE_COLOR 14
    #define ELMC_PEBBLE_DRAW_FILL_COLOR 15
    #define ELMC_PEBBLE_DRAW_TEXT_COLOR 16
    #define ELMC_PEBBLE_DRAW_ROUND_RECT 17
    #define ELMC_PEBBLE_DRAW_ARC 18
    #define ELMC_PEBBLE_DRAW_CONTEXT_GROUP 19
    #define ELMC_PEBBLE_DRAW_PATH_FILLED 20
    #define ELMC_PEBBLE_DRAW_PATH_OUTLINE 21
    #define ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN 22
    #define ELMC_PEBBLE_DRAW_FILL_RADIAL 23
    #define ELMC_PEBBLE_DRAW_COMPOSITING_MODE 24
    #define ELMC_PEBBLE_DRAW_BITMAP_IN_RECT 25
    #define ELMC_PEBBLE_DRAW_ROTATED_BITMAP 26
    #define ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT 27
    #define ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT 28
    #define ELMC_PEBBLE_DRAW_TEXT 29
    #define ELMC_PEBBLE_CMD_NONE 0
    #define ELMC_PEBBLE_CMD_TIMER_AFTER_MS 1
    #define ELMC_PEBBLE_CMD_STORAGE_WRITE_INT 2
    #define ELMC_PEBBLE_CMD_STORAGE_READ_INT 3
    #define ELMC_PEBBLE_CMD_STORAGE_DELETE 4
    #define ELMC_PEBBLE_CMD_COMPANION_SEND 5
    #define ELMC_PEBBLE_CMD_BACKLIGHT 6
    #define ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING 7
    #define ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H 8
    #define ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET 9
    #define ELMC_PEBBLE_CMD_GET_TIMEZONE 10
    #define ELMC_PEBBLE_CMD_GET_WATCH_MODEL 11
    #define ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION 12
    #define ELMC_PEBBLE_CMD_VIBES_CANCEL 13
    #define ELMC_PEBBLE_CMD_VIBES_SHORT_PULSE 14
    #define ELMC_PEBBLE_CMD_VIBES_LONG_PULSE 15
    #define ELMC_PEBBLE_CMD_VIBES_DOUBLE_PULSE 16
    #define ELMC_PEBBLE_CMD_GET_WATCH_COLOR 17
    #define ELMC_PEBBLE_CMD_WAKEUP_SCHEDULE_AFTER_SECONDS 18
    #define ELMC_PEBBLE_CMD_WAKEUP_CANCEL 19
    #define ELMC_PEBBLE_CMD_LOG_INFO_CODE 20
    #define ELMC_PEBBLE_CMD_LOG_WARN_CODE 21
    #define ELMC_PEBBLE_CMD_LOG_ERROR_CODE 22
    #define ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME 23
    #define ELMC_PEBBLE_CMD_GET_BATTERY_LEVEL 24
    #define ELMC_PEBBLE_CMD_GET_CONNECTION_STATUS 25
    #{feature_macros}
    #define ELMC_PEBBLE_MSG_CURRENT_TIME_TARGET #{Map.get(feature_flags, :msg_current_time_target, -1)}
    #define ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET #{Map.get(feature_flags, :msg_current_date_time_target, -1)}
    #define ELMC_PEBBLE_MSG_BATTERY_LEVEL_TARGET #{Map.get(feature_flags, :msg_battery_level_target, -1)}
    #define ELMC_PEBBLE_MSG_CONNECTION_STATUS_TARGET #{Map.get(feature_flags, :msg_connection_status_target, -1)}
    #define ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET #{phone_to_watch_target}
    #{watch_model_macros}
    #{watch_color_macros}
    #define ELMC_PEBBLE_SUB_TICK (1 << 0)
    #define ELMC_PEBBLE_SUB_BUTTON_UP (1 << 1)
    #define ELMC_PEBBLE_SUB_BUTTON_SELECT (1 << 2)
    #define ELMC_PEBBLE_SUB_BUTTON_DOWN (1 << 3)
    #define ELMC_PEBBLE_SUB_ACCEL_TAP (1 << 4)
    #define ELMC_PEBBLE_SUB_BATTERY (1 << 5)
    #define ELMC_PEBBLE_SUB_CONNECTION (1 << 6)
    #define ELMC_PEBBLE_SUB_HOUR (1 << 10)
    #define ELMC_PEBBLE_SUB_MINUTE (1 << 11)
    #define ELMC_PEBBLE_SUB_APPMESSAGE (1 << 12)
    #define ELMC_PEBBLE_UI_WINDOW_STACK 1000
    #define ELMC_PEBBLE_UI_WINDOW_NODE 1001
    #define ELMC_PEBBLE_UI_CANVAS_LAYER 1002

    int elmc_pebble_init(ElmcPebbleApp *app, ElmcValue *flags);
    int elmc_pebble_init_with_mode(ElmcPebbleApp *app, ElmcValue *flags, int run_mode);
    int elmc_pebble_dispatch_int(ElmcPebbleApp *app, int64_t tag);
    int elmc_pebble_dispatch_tag_value(ElmcPebbleApp *app, int64_t tag, int64_t value);
    int elmc_pebble_dispatch_tag_bool(ElmcPebbleApp *app, int64_t tag, int value);
    int elmc_pebble_dispatch_tag_string(ElmcPebbleApp *app, int64_t tag, const char *value);
    int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload);
    int elmc_pebble_dispatch_tag_record_int_fields(
        ElmcPebbleApp *app,
        int64_t tag,
        int field_count,
        const char **field_names,
        const int64_t *field_values);
    int elmc_pebble_msg_from_appmessage(int32_t key, int32_t value, int64_t *out_tag);
    int elmc_pebble_dispatch_appmessage(ElmcPebbleApp *app, int32_t key, int32_t value);
    int elmc_pebble_button_to_tag(int32_t button_id, int64_t *out_tag);
    int elmc_pebble_dispatch_button(ElmcPebbleApp *app, int32_t button_id);
    int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction);
    int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level);
    int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected);
    int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour);
    int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute);
    int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd);
    int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd);
    int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds);
    int elmc_pebble_tick(ElmcPebbleApp *app);
    int64_t elmc_pebble_active_subscriptions(ElmcPebbleApp *app);
    int64_t elmc_pebble_model_as_int(ElmcPebbleApp *app);
    int elmc_pebble_run_mode(ElmcPebbleApp *app);
    void elmc_pebble_deinit(ElmcPebbleApp *app);

    #endif
    """
  end

  @spec pebble_source([map()], map(), boolean(), String.t()) :: String.t()
  defp pebble_source(msg_constructors, msg_constructor_arities, has_view, entry_module) do
    value_decode_cases =
      msg_constructors
      |> Enum.map_join("\n", fn {name, tag} ->
        "      case ELMC_PEBBLE_MSG_#{macro_name(name)}: *out_tag = #{tag}; return 0;"
      end)

    key_decode_cases =
      msg_constructors
      |> Enum.map_join("\n", fn {name, tag} ->
        "      case ELMC_PEBBLE_MSG_#{macro_name(name)}: *out_tag = #{tag}; return 0;"
      end)

    tick_tag = pick_tag(msg_constructors, ["Tick", "Increment", "UpPressed"], fallback: 1)
    tick_constructor_name = constructor_name_for_tag(msg_constructors, tick_tag)
    tick_constructor_arity = Map.get(msg_constructor_arities, tick_constructor_name, 0)

    current_second_helper =
      if tick_constructor_arity > 0 do
        """
        extern time_t time(time_t *timer);

        static int elmc_current_second(void) {
          time_t now = time(NULL);
          if (now == (time_t)-1) return 0;
          return (int)(now % 60);
        }
        """
      else
        ""
      end

    button_up_tag = pick_tag(msg_constructors, ["UpPressed", "Increment"])
    button_select_tag = pick_tag(msg_constructors, ["SelectPressed", "Increment"])
    button_down_tag = pick_tag(msg_constructors, ["DownPressed", "Decrement"])
    accel_tap_tag = pick_tag(msg_constructors, ["Shake", "AccelTap", "Tapped", "Increment"])

    battery_tag =
      pick_tag(msg_constructors, ["BatteryLevelChanged", "BatteryChanged", "BatteryUpdate"])

    connection_tag =
      pick_tag(msg_constructors, [
        "ConnectionStatusChanged",
        "ConnectionChanged",
        "BluetoothChanged"
      ])

    hour_tag = pick_tag(msg_constructors, ["HourChanged"])
    minute_tag = pick_tag(msg_constructors, ["MinuteChanged"])

    """
    #include "elmc_pebble.h"
    #include <stdlib.h>
    #include <string.h>
    #include <time.h>

    #{current_second_helper}

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
      out_cmd->text[0] = '\\0';
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
            out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
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
      out_cmd->text[0] = '\\0';
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
            out_cmds[*count].text[0] = '\\0';
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
            out_cmds[*count].text[0] = '\\0';
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

    static int elmc_is_virtual_ui_tag(ElmcValue *value, int64_t encoded_tag) {
      if (!value) return 0;
      int64_t tag = elmc_as_int(value);
      return tag == encoded_tag || tag == 1;
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

    int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload) {
      if (!app || !app->initialized) return -1;
      if (!payload) return -3;
      ElmcValue *tag_value = elmc_new_int(tag);
      if (!tag_value) return -2;

      ElmcValue *msg = elmc_tuple2(tag_value, payload);
      elmc_release(tag_value);
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
    #{value_decode_cases}
          default: return -3;
        }
      }

      if (value == 0) return -4;
      switch (key) {
    #{key_decode_cases}
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
          if (#{button_up_tag} <= 0) return -5;
          *out_tag = #{button_up_tag};
          return 0;
        case ELMC_PEBBLE_BUTTON_SELECT:
          if (#{button_select_tag} <= 0) return -5;
          *out_tag = #{button_select_tag};
          return 0;
        case ELMC_PEBBLE_BUTTON_DOWN:
          if (#{button_down_tag} <= 0) return -5;
          *out_tag = #{button_down_tag};
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
      if (#{accel_tap_tag} <= 0) return -6;
      return elmc_pebble_dispatch_int(app, #{accel_tap_tag});
    }

    int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BATTERY)) return -8;
      if (#{battery_tag} <= 0) return -6;
      if (level < 0) level = 0;
      if (level > 100) level = 100;
      return elmc_pebble_dispatch_tag_value(app, #{battery_tag}, level);
    }

    int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_CONNECTION)) return -8;
      if (#{connection_tag} <= 0) return -6;
      return elmc_pebble_dispatch_tag_bool(app, #{connection_tag}, connected);
    }

    int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_HOUR)) return -8;
      if (#{hour_tag} <= 0) return -6;
      return elmc_pebble_dispatch_tag_value(app, #{hour_tag}, hour);
    }

    int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_MINUTE)) return -8;
      if (#{minute_tag} <= 0) return -6;
      return elmc_pebble_dispatch_tag_value(app, #{minute_tag}, minute);
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
    #{if has_view do
      """
            ElmcValue *model = elmc_worker_model(&app->worker);
            if (!model) return -2;
            ElmcValue *args[] = { model };
            ElmcValue *result = elmc_fn_#{String.replace(entry_module, ".", "_")}_view(args, 1);
            elmc_release(model);
      """
    else
      """
            ElmcValue *result = elmc_worker_model(&app->worker);
            if (!result) return -2;
      """
    end}

      ElmcValue *ops = result;
      int64_t window_id = 0;
      int64_t layer_id = 0;
      int extracted = elmc_extract_virtual_canvas_ops(result, &window_id, &layer_id, &ops);
      if (extracted != 0 || !ops) {
        ops = result;
      }

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
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_TICK)) return -8;
    #{if tick_constructor_arity > 0 do
      "  return elmc_pebble_dispatch_tag_value(app, #{tick_tag}, elmc_current_second());"
    else
      "  return elmc_pebble_dispatch_int(app, #{tick_tag});"
    end}
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
    """
  end

  @spec msg_constructors(ElmEx.IR.t(), String.t()) :: [map()]
  defp msg_constructors(ir, entry_module) do
    module = Enum.find(ir.modules, &(&1.name == entry_module))

    union =
      if module do
        module.unions["Msg"]
      else
        nil
      end

    tags = if union, do: union.tags, else: %{}

    tags
    |> Map.to_list()
    |> Enum.sort_by(fn {_name, tag} -> tag end)
  end

  @spec msg_constructor_arities(ElmEx.IR.t(), String.t()) :: %{
          optional(String.t()) => non_neg_integer()
        }
  defp msg_constructor_arities(ir, entry_module) do
    module = Enum.find(ir.modules, &(&1.name == entry_module))
    union = if module, do: module.unions["Msg"], else: nil
    constructors = if union, do: Map.get(union, :constructors, []), else: []

    constructors
    |> Enum.reduce(%{}, fn constructor, acc ->
      name = Map.get(constructor, :name)
      spec = Map.get(constructor, :arg)

      if is_binary(name) and name != "" do
        Map.put(acc, name, payload_arity_for_spec(spec))
      else
        acc
      end
    end)
  end

  @spec msg_constructor_payload_specs(ElmEx.IR.t(), String.t()) :: %{
          optional(String.t()) => String.t() | nil
        }
  defp msg_constructor_payload_specs(ir, entry_module) do
    module = Enum.find(ir.modules, &(&1.name == entry_module))
    union = if module, do: module.unions["Msg"], else: nil
    constructors = if union, do: Map.get(union, :constructors, []), else: []

    constructors
    |> Map.new(fn constructor ->
      {Map.get(constructor, :name), Map.get(constructor, :arg)}
    end)
  end

  @spec phone_to_watch_msg_target([{String.t(), non_neg_integer()}], map()) :: integer()
  defp phone_to_watch_msg_target(msg_constructors, payload_specs) do
    Enum.find_value(msg_constructors, -1, fn {name, tag} ->
      case Map.get(payload_specs, name) do
        "PhoneToWatch" -> tag
        "Companion.Types.PhoneToWatch" -> tag
        _ -> nil
      end
    end)
  end

  @spec constructor_name_for_tag([{String.t(), non_neg_integer()}], non_neg_integer()) ::
          String.t() | nil
  defp constructor_name_for_tag(constructors, tag) when is_integer(tag) do
    Enum.find_value(constructors, fn
      {name, ^tag} -> name
      _ -> nil
    end)
  end

  @spec has_view?(ElmEx.IR.t(), String.t()) :: boolean()
  defp has_view?(ir, entry_module) do
    ir.modules
    |> Enum.find(&(&1.name == entry_module))
    |> case do
      nil -> false
      mod -> Enum.any?(mod.declarations, &(&1.kind == :function and &1.name == "view"))
    end
  end

  @spec pick_tag([map()], [String.t()], keyword()) :: non_neg_integer()
  defp pick_tag(msg_constructors, names, opts \\ []) do
    fallback = Keyword.get(opts, :fallback, -1)

    Enum.find_value(names, fallback, fn name ->
      Enum.find_value(msg_constructors, fn
        {^name, tag} -> tag
        _ -> nil
      end)
    end)
  end

  @spec union_constructors(ElmEx.IR.t(), String.t(), String.t()) :: [
          {String.t(), non_neg_integer()}
        ]
  defp union_constructors(ir, module_name, union_name) do
    ir.modules
    |> Enum.find(&(&1.name == module_name))
    |> case do
      nil ->
        []

      mod ->
        mod.unions
        |> Map.get(union_name, %{tags: %{}})
        |> Map.get(:tags, %{})
        |> Map.to_list()
        |> Enum.sort_by(fn {_ctor, tag} -> tag end)
    end
  end

  @spec constructor_tag_macros(String.t(), [{String.t(), non_neg_integer()}]) :: String.t()
  defp constructor_tag_macros(prefix, constructors) do
    constructors
    |> Enum.map_join("\n", fn {name, tag} ->
      "#define #{prefix}_#{macro_name(name)} #{tag}"
    end)
  end

  @spec feature_flags(IR.t(), [{String.t(), non_neg_integer()}]) :: map()
  defp feature_flags(ir, msg_constructors) do
    targets = call_targets(ir)
    command_flags = command_feature_flags(targets)

    uses_time_every =
      uses_target?(targets, "Elm.Kernel.Time.every") or uses_target?(targets, "Time.every")

    Map.merge(command_flags, %{
      tick_events:
        uses_time_every or
          pick_tag(msg_constructors, ["Tick", "Increment", "UpPressed"], fallback: -1) > 0,
      hour_events: uses_target?(targets, "Pebble.Events.onHourChange"),
      minute_events: uses_target?(targets, "Pebble.Events.onMinuteChange"),
      button_events:
        has_any_constructor?(msg_constructors, ["UpPressed", "SelectPressed", "DownPressed"]),
      accel_events: has_any_constructor?(msg_constructors, ["Shake", "AccelTap", "Tapped"]),
      battery_events:
        has_any_constructor?(msg_constructors, [
          "BatteryLevelChanged",
          "BatteryChanged",
          "BatteryUpdate"
        ]),
      connection_events:
        has_any_constructor?(msg_constructors, [
          "ConnectionStatusChanged",
          "ConnectionChanged",
          "BluetoothChanged"
        ]),
      inbox_events: uses_target?(targets, "Companion.Watch.onPhoneToWatch"),
      msg_current_time:
        has_any_constructor?(msg_constructors, ["CurrentTime", "CurrentTimeString", "GotTime"]),
      msg_current_time_target:
        pick_tag(msg_constructors, ["CurrentTime", "CurrentTimeString", "GotTime"]),
      msg_current_date_time:
        uses_target?(targets, "Pebble.Time.currentDateTime") or
          uses_target?(targets, "Pebble.Cmd.getCurrentDateTime"),
      msg_current_date_time_target:
        pick_tag(msg_constructors, ["CurrentDateTime", "GotCurrentDateTime"]),
      msg_battery_level_target:
        pick_tag(msg_constructors, ["BatteryLevelChanged", "BatteryLevel", "GotBatteryLevel"]),
      msg_connection_status_target:
        pick_tag(msg_constructors, [
          "ConnectionStatusChanged",
          "ConnectionStatus",
          "GotConnectionStatus"
        ])
    })
  end

  @spec has_any_constructor?([{String.t(), non_neg_integer()}], [String.t()]) :: boolean()
  defp has_any_constructor?(msg_constructors, names) do
    Enum.any?(msg_constructors, fn {name, _tag} -> name in names end)
  end

  @spec feature_flag_macros(map()) :: String.t()
  defp feature_flag_macros(flags) do
    [
      {"ELMC_PEBBLE_FEATURE_TICK_EVENTS", flags[:tick_events]},
      {"ELMC_PEBBLE_FEATURE_HOUR_EVENTS", flags[:hour_events]},
      {"ELMC_PEBBLE_FEATURE_MINUTE_EVENTS", flags[:minute_events]},
      {"ELMC_PEBBLE_FEATURE_BUTTON_EVENTS", flags[:button_events]},
      {"ELMC_PEBBLE_FEATURE_ACCEL_EVENTS", flags[:accel_events]},
      {"ELMC_PEBBLE_FEATURE_BATTERY_EVENTS", flags[:battery_events]},
      {"ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS", flags[:connection_events]},
      {"ELMC_PEBBLE_FEATURE_INBOX_EVENTS", flags[:inbox_events]},
      {"ELMC_PEBBLE_FEATURE_MSG_CURRENT_TIME", flags[:msg_current_time]},
      {"ELMC_PEBBLE_FEATURE_CMD_TIMER_AFTER_MS", flags[:cmd_timer_after_ms]},
      {"ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_INT", flags[:cmd_storage_write_int]},
      {"ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_INT", flags[:cmd_storage_read_int]},
      {"ELMC_PEBBLE_FEATURE_CMD_STORAGE_DELETE", flags[:cmd_storage_delete]},
      {"ELMC_PEBBLE_FEATURE_CMD_COMPANION_SEND", flags[:cmd_companion_send]},
      {"ELMC_PEBBLE_FEATURE_CMD_BACKLIGHT", flags[:cmd_backlight]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_TIME_STRING", flags[:cmd_get_current_time_string]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_DATE_TIME", flags[:cmd_get_current_date_time]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_BATTERY_LEVEL", flags[:cmd_get_battery_level]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_CONNECTION_STATUS", flags[:cmd_get_connection_status]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_CLOCK_STYLE_24H", flags[:cmd_get_clock_style_24h]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_TIMEZONE_IS_SET", flags[:cmd_get_timezone_is_set]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_TIMEZONE", flags[:cmd_get_timezone]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_MODEL", flags[:cmd_get_watch_model]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_WATCH_COLOR", flags[:cmd_get_watch_color]},
      {"ELMC_PEBBLE_FEATURE_CMD_GET_FIRMWARE_VERSION", flags[:cmd_get_firmware_version]},
      {"ELMC_PEBBLE_FEATURE_CMD_WAKEUP_SCHEDULE_AFTER_SECONDS",
       flags[:cmd_wakeup_schedule_after_seconds]},
      {"ELMC_PEBBLE_FEATURE_CMD_WAKEUP_CANCEL", flags[:cmd_wakeup_cancel]},
      {"ELMC_PEBBLE_FEATURE_CMD_LOG_INFO_CODE", flags[:cmd_log_info_code]},
      {"ELMC_PEBBLE_FEATURE_CMD_LOG_WARN_CODE", flags[:cmd_log_warn_code]},
      {"ELMC_PEBBLE_FEATURE_CMD_LOG_ERROR_CODE", flags[:cmd_log_error_code]},
      {"ELMC_PEBBLE_FEATURE_CMD_VIBES_CANCEL", flags[:cmd_vibes_cancel]},
      {"ELMC_PEBBLE_FEATURE_CMD_VIBES_SHORT_PULSE", flags[:cmd_vibes_short_pulse]},
      {"ELMC_PEBBLE_FEATURE_CMD_VIBES_LONG_PULSE", flags[:cmd_vibes_long_pulse]},
      {"ELMC_PEBBLE_FEATURE_CMD_VIBES_DOUBLE_PULSE", flags[:cmd_vibes_double_pulse]}
    ]
    |> Enum.map_join("\n", fn {macro, enabled} ->
      "#define #{macro} #{if(enabled, do: 1, else: 0)}"
    end)
  end

  @spec call_targets(IR.t()) :: MapSet.t(String.t())
  defp call_targets(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.flat_map(fn decl -> collect_targets(decl.expr) end)
    end)
    |> MapSet.new()
  end

  @spec collect_targets(term()) :: [String.t()]
  defp collect_targets(nil), do: []
  defp collect_targets(value) when is_binary(value), do: []
  defp collect_targets(value) when is_number(value), do: []
  defp collect_targets(value) when is_atom(value), do: []

  defp collect_targets(list) when is_list(list) do
    Enum.flat_map(list, &collect_targets/1)
  end

  defp collect_targets(%{op: op, target: target} = expr)
       when op in [:qualified_call, :qualified_call1, :constructor_call] and is_binary(target) do
    [target | collect_targets(Map.values(expr))]
  end

  defp collect_targets(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.flat_map(&collect_targets/1)
  end

  @spec command_feature_flags(MapSet.t(String.t())) :: map()
  defp command_feature_flags(targets) do
    %{
      cmd_timer_after_ms: uses_target?(targets, "Pebble.Cmd.timerAfter"),
      cmd_storage_write_int: uses_target?(targets, "Pebble.Cmd.storageWriteInt"),
      cmd_storage_read_int: uses_target?(targets, "Pebble.Cmd.storageReadInt"),
      cmd_storage_delete: uses_target?(targets, "Pebble.Cmd.storageDelete"),
      cmd_companion_send: uses_target?(targets, "Pebble.Internal.Companion.companionSend"),
      cmd_backlight: uses_target?(targets, "Pebble.Cmd.backlight"),
      cmd_get_current_time_string: uses_target?(targets, "Pebble.Cmd.getCurrentTimeString"),
      cmd_get_current_date_time:
        uses_target?(targets, "Pebble.Cmd.getCurrentDateTime") or
          uses_target?(targets, "Pebble.Time.currentDateTime") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.getCurrentDateTime"),
      cmd_get_battery_level:
        uses_target?(targets, "Pebble.System.batteryLevel") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.getBatteryLevel"),
      cmd_get_connection_status:
        uses_target?(targets, "Pebble.System.connectionStatus") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.getConnectionStatus"),
      cmd_get_clock_style_24h: uses_target?(targets, "Pebble.Cmd.getClockStyle24h"),
      cmd_get_timezone_is_set: uses_target?(targets, "Pebble.Cmd.getTimezoneIsSet"),
      cmd_get_timezone: uses_target?(targets, "Pebble.Cmd.getTimezone"),
      cmd_get_watch_model: uses_target?(targets, "Pebble.Cmd.getWatchModel"),
      cmd_get_watch_color: uses_target?(targets, "Pebble.Cmd.getWatchColor"),
      cmd_get_firmware_version: uses_target?(targets, "Pebble.Cmd.getFirmwareVersion"),
      cmd_wakeup_schedule_after_seconds:
        uses_target?(targets, "Pebble.Cmd.wakeupScheduleAfterSeconds"),
      cmd_wakeup_cancel: uses_target?(targets, "Pebble.Cmd.wakeupCancel"),
      cmd_log_info_code: uses_target?(targets, "Pebble.Cmd.logInfoCode"),
      cmd_log_warn_code: uses_target?(targets, "Pebble.Cmd.logWarnCode"),
      cmd_log_error_code: uses_target?(targets, "Pebble.Cmd.logErrorCode"),
      cmd_vibes_cancel:
        uses_target?(targets, "Pebble.Cmd.vibesCancel") or
          uses_target?(targets, "Pebble.Vibes.cancel"),
      cmd_vibes_short_pulse:
        uses_target?(targets, "Pebble.Cmd.vibesShortPulse") or
          uses_target?(targets, "Pebble.Vibes.shortPulse"),
      cmd_vibes_long_pulse:
        uses_target?(targets, "Pebble.Cmd.vibesLongPulse") or
          uses_target?(targets, "Pebble.Vibes.longPulse"),
      cmd_vibes_double_pulse:
        uses_target?(targets, "Pebble.Cmd.vibesDoublePulse") or
          uses_target?(targets, "Pebble.Vibes.doublePulse")
    }
  end

  @spec uses_target?(MapSet.t(String.t()), String.t()) :: boolean()
  defp uses_target?(targets, target), do: MapSet.member?(targets, target)

  @spec macro_name(String.t()) :: String.t()
  defp macro_name(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9]/, "_")
    |> String.upcase()
  end

  @spec payload_arity_for_spec(String.t() | nil) :: non_neg_integer()
  defp payload_arity_for_spec(nil), do: 0

  defp payload_arity_for_spec(spec) when is_binary(spec) do
    normalized = spec |> String.trim() |> String.trim_leading("(") |> String.trim_trailing(")")

    cond do
      normalized == "" ->
        0

      String.contains?(normalized, "->") ->
        1

      String.contains?(normalized, ",") ->
        normalized |> String.split(",") |> length()

      true ->
        1
    end
  end
end
