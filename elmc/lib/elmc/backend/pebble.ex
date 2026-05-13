defmodule Elmc.Backend.Pebble do
  @moduledoc """
  Generates a Pebble-oriented host shim around the worker adapter.
  """

  alias ElmEx.IR

  @draw_kinds [
    none: 0,
    clear: 2,
    pixel: 3,
    line: 4,
    rect: 5,
    fill_rect: 6,
    circle: 7,
    fill_circle: 8,
    push_context: 10,
    pop_context: 11,
    stroke_width: 12,
    antialiased: 13,
    stroke_color: 14,
    fill_color: 15,
    text_color: 16,
    round_rect: 17,
    arc: 18,
    context_group: 19,
    path_filled: 20,
    path_outline: 21,
    path_outline_open: 22,
    fill_radial: 23,
    compositing_mode: 24,
    bitmap_in_rect: 25,
    rotated_bitmap: 26,
    text_int_with_font: 27,
    text_label_with_font: 28,
    text: 29
  ]

  @command_kinds [
    none: 0,
    timer_after_ms: 1,
    storage_write_int: 2,
    storage_read_int: 3,
    storage_delete: 4,
    companion_send: 5,
    backlight: 6,
    get_current_time_string: 7,
    get_clock_style_24h: 8,
    get_timezone_is_set: 9,
    get_timezone: 10,
    get_watch_model: 11,
    get_firmware_version: 12,
    vibes_cancel: 13,
    vibes_short_pulse: 14,
    vibes_long_pulse: 15,
    vibes_double_pulse: 16,
    get_watch_color: 17,
    wakeup_schedule_after_seconds: 18,
    wakeup_cancel: 19,
    log_info_code: 20,
    log_warn_code: 21,
    log_error_code: 22,
    get_current_date_time: 23,
    get_battery_level: 24,
    get_connection_status: 25,
    storage_write_string: 26,
    storage_read_string: 27,
    random_generate: 28,
    health_value: 29,
    health_sum_today: 30,
    health_sum: 31,
    health_accessible: 32
  ]

  @run_modes [
    app: 0,
    watchface: 1
  ]

  @button_ids [
    back: 0,
    up: 1,
    select: 2,
    down: 3
  ]

  @accel_axes [
    x: 1,
    y: 2,
    z: 3
  ]

  @ui_node_kinds [
    window_stack: 1000,
    window_node: 1001,
    canvas_layer: 1002
  ]

  @draw_kind_ids Map.new(@draw_kinds)
  @command_kind_ids Map.new(@command_kinds)
  @run_mode_ids Map.new(@run_modes)
  @button_id_ids Map.new(@button_ids)
  @accel_axis_ids Map.new(@accel_axes)
  @ui_node_kind_ids Map.new(@ui_node_kinds)

  @spec draw_kind_id!(atom()) :: non_neg_integer()
  def draw_kind_id!(kind), do: Map.fetch!(@draw_kind_ids, kind)

  @spec command_kind_id!(atom()) :: non_neg_integer()
  def command_kind_id!(kind), do: Map.fetch!(@command_kind_ids, kind)

  @spec run_mode_id!(atom()) :: non_neg_integer()
  def run_mode_id!(mode), do: Map.fetch!(@run_mode_ids, mode)

  @spec button_id!(atom()) :: non_neg_integer()
  def button_id!(button), do: Map.fetch!(@button_id_ids, button)

  @spec accel_axis_id!(atom()) :: non_neg_integer()
  def accel_axis_id!(axis), do: Map.fetch!(@accel_axis_ids, axis)

  @spec ui_node_kind_id!(atom()) :: non_neg_integer()
  def ui_node_kind_id!(kind), do: Map.fetch!(@ui_node_kind_ids, kind)

  @spec write_pebble_shim(IR.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def write_pebble_shim(%IR{} = ir, out_dir, entry_module) do
    c_dir = Path.join(out_dir, "c")
    msg_constructors = msg_constructors(ir, entry_module)
    msg_constructor_arities = msg_constructor_arities(ir, entry_module)
    msg_constructor_payload_specs = msg_constructor_payload_specs(ir, entry_module)
    watch_model_tags = union_constructors(ir, "Pebble.WatchInfo", "WatchModel")
    watch_color_tags = union_constructors(ir, "Pebble.WatchInfo", "WatchColor")
    has_view = has_view?(ir, entry_module)
    feature_flags = feature_flags(ir, msg_constructors, entry_module)
    random_generate_tag = random_generate_target_tag(ir, msg_constructors)
    health_event_tag = health_event_target_tag(ir, msg_constructors)

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
             pebble_source(
               msg_constructors,
               msg_constructor_arities,
               has_view,
               entry_module,
               random_generate_tag,
               health_event_tag
             )
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
    run_mode_enum = c_enum("ElmcPebbleRunMode", "ELMC_PEBBLE_MODE", @run_modes)
    button_id_enum = c_enum("ElmcPebbleButtonId", "ELMC_PEBBLE_BUTTON", @button_ids)
    accel_axis_enum = c_enum("ElmcPebbleAccelAxis", "ELMC_PEBBLE_ACCEL_AXIS", @accel_axes)
    draw_kind_enum = c_enum("ElmcPebbleDrawKind", "ELMC_PEBBLE_DRAW", @draw_kinds)
    command_kind_enum = c_enum("ElmcPebbleCommandKind", "ELMC_PEBBLE_CMD", @command_kinds)
    ui_node_kind_enum = c_enum("ElmcPebbleUiNodeKind", "ELMC_PEBBLE_UI", @ui_node_kinds)

    phone_to_watch_target =
      phone_to_watch_msg_target(msg_constructors, msg_constructor_payload_specs)

    """
    #ifndef ELMC_PEBBLE_H
    #define ELMC_PEBBLE_H

    #include "elmc_worker.h"

    #{feature_macros}

    #ifndef ELMC_PEBBLE_DIRTY_REGION_ENABLED
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 0
    #else
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 1
    #endif
    #endif

    typedef struct {
      unsigned char *bytes;
      int byte_count;
      int byte_capacity;
      int command_count;
      uint64_t hash;
      int dirty;
    } ElmcPebbleSceneBuffer;

    typedef struct {
      int x;
      int y;
      int w;
      int h;
    } ElmcPebbleRect;

    typedef struct {
      ElmcWorkerState worker;
      int initialized;
      int run_mode;
      int has_prev_ui;
      int64_t prev_window_id;
      int64_t prev_layer_id;
      uint64_t prev_ops_hash;
      ElmcValue *stream_view_result;
      ElmcPebbleSceneBuffer scene;
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      ElmcPebbleSceneBuffer prev_scene;
      ElmcPebbleRect dirty_rect;
      int dirty_rect_valid;
      int dirty_rect_full;
    #endif
    } ElmcPebbleApp;

    #{run_mode_enum}

    typedef enum {
      ELMC_PEBBLE_MSG_UNKNOWN = 0,
    #{msg_enum_members}
    } ElmcPebbleMsgTag;

    #{msg_presence_macros}

    #{button_id_enum}

    #{accel_axis_enum}

    typedef struct {
      int32_t kind;
      int32_t p0;
      int32_t p1;
      int32_t p2;
      int32_t p3;
      int32_t p4;
      int32_t p5;
    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
      int32_t path_point_count;
      int32_t path_offset_x;
      int32_t path_offset_y;
      int32_t path_rotation;
      int16_t path_x[16];
      int16_t path_y[16];
    #endif
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
      char text[128];
    } ElmcPebbleCmd;

    #{draw_kind_enum}

    #{command_kind_enum}

    #{ui_node_kind_enum}

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
    #define ELMC_PEBBLE_SUB_FRAME (1 << 13)
    #define ELMC_PEBBLE_SUB_BUTTON_RAW (1 << 14)
    #define ELMC_PEBBLE_SUB_ACCEL_DATA (1 << 15)
    #define ELMC_PEBBLE_SUB_HEALTH (1LL << 31)

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
    int elmc_pebble_dispatch_button_raw(ElmcPebbleApp *app, int32_t button_id, int32_t pressed);
    int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction);
    int elmc_pebble_dispatch_accel_data(ElmcPebbleApp *app, int32_t x, int32_t y, int32_t z);
    int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value);
    int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value);
    int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level);
    int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected);
    int elmc_pebble_dispatch_health(ElmcPebbleApp *app, int event);
    int elmc_pebble_dispatch_frame(ElmcPebbleApp *app, int64_t dt_ms, int64_t elapsed_ms, int64_t frame);
    int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour);
    int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute);
    int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd);
    int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd);
    int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds);
    int elmc_pebble_view_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip);
    int elmc_pebble_scene_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip);
    int elmc_pebble_ensure_scene(ElmcPebbleApp *app);
    int elmc_pebble_scene_command_count(ElmcPebbleApp *app);
    int elmc_pebble_scene_dirty_rect(ElmcPebbleApp *app, ElmcPebbleRect *out_rect, int *out_full);
    void elmc_pebble_clear_view_cache(ElmcPebbleApp *app);
    int elmc_pebble_tick(ElmcPebbleApp *app);
    int64_t elmc_pebble_active_subscriptions(ElmcPebbleApp *app);
    int64_t elmc_pebble_model_as_int(ElmcPebbleApp *app);
    int elmc_pebble_run_mode(ElmcPebbleApp *app);
    void elmc_pebble_deinit(ElmcPebbleApp *app);

    #endif
    """
  end

  @spec pebble_source([map()], map(), boolean(), String.t(), integer(), integer()) :: String.t()
  defp pebble_source(
         msg_constructors,
         msg_constructor_arities,
         has_view,
         entry_module,
         random_generate_tag,
         health_event_tag
       ) do
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
        """
      else
        ""
      end

    button_back_tag = pick_tag(msg_constructors, ["BackPressed", "LeftPressed"])
    button_up_tag = pick_tag(msg_constructors, ["UpPressed", "Increment"])
    button_select_tag = pick_tag(msg_constructors, ["SelectPressed", "RightPressed", "Increment"])
    button_down_tag = pick_tag(msg_constructors, ["DownPressed", "Decrement"])
    button_back_released_tag = pick_tag(msg_constructors, ["BackReleased", "LeftReleased"])
    button_up_released_tag = pick_tag(msg_constructors, ["UpReleased"])
    button_select_released_tag = pick_tag(msg_constructors, ["SelectReleased"])
    button_down_released_tag = pick_tag(msg_constructors, ["DownReleased"])
    frame_tag = pick_tag(msg_constructors, ["FrameTick", "Frame", "GameFrame"])
    accel_data_tag = pick_tag(msg_constructors, ["AccelData", "AccelSample", "GotAccel"])

    storage_string_tag =
      pick_tag(msg_constructors, ["StorageStringLoaded", "GotStorageString", "GotString"])

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
    direct_view_macro = direct_command_macro(entry_module, "view")

    entry_view_commands_from =
      "elmc_fn_#{String.replace(entry_module, ".", "_")}_view_commands_from"

    """
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
    #define ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT(name, value) \\
      do { \\
        int elmc_pebble_trace_rc__ = (value); \\
        app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "g-%d rc=%d", __LINE__, elmc_pebble_trace_rc__); \\
        return elmc_pebble_trace_rc__; \\
      } while (0)
    #else
    #define ELMC_PEBBLE_GENERATED_TRACE_ENTER(name) do { } while (0)
    #define ELMC_PEBBLE_GENERATED_TRACE_EXIT(name) do { } while (0)
    #define ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT(name, value) return (value)
    #endif

    #ifndef ELMC_PEBBLE_DIRTY_REGION_ENABLED
    #if defined(ELMC_PEBBLE_PLATFORM)
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 0
    #else
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 1
    #endif
    #endif

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
      out_cmd->text[0] = '\\0';
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
            out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
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
      out_cmd->text[0] = '\\0';
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
      cmd->text[0] = '\\0';
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

    static void elmc_pebble_scene_mark_full_dirty(ElmcPebbleApp *app) {
      if (!app) return;
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      app->dirty_rect_valid = 0;
      app->dirty_rect_full = 1;
      app->dirty_rect.x = 0;
      app->dirty_rect.y = 0;
      app->dirty_rect.w = 0;
      app->dirty_rect.h = 0;
    #endif
    }

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
        while (text_len < (int)sizeof(cmd->text) && cmd->text[text_len] != '\\0') text_len++;
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
        while (text_len < (int)sizeof(cmd->text) && cmd->text[text_len] != '\\0') text_len++;
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
          out_cmd->text[text_len] = '\\0';
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
    static void elmc_pebble_scene_compute_dirty_rect(ElmcPebbleApp *app) {
      elmc_pebble_scene_mark_full_dirty(app);
    }
    #endif

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

    static int elmc_cmd_from_value(ElmcValue *value, ElmcPebbleCmd *out_cmd) {
      if (!out_cmd) return -1;
      out_cmd->kind = ELMC_PEBBLE_CMD_NONE;
      out_cmd->p0 = 0;
      out_cmd->p1 = 0;
      out_cmd->p2 = 0;
      out_cmd->p3 = 0;
      out_cmd->p4 = 0;
      out_cmd->p5 = 0;
      out_cmd->text[0] = '\\0';
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
      app->stream_view_result = NULL;
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

    int elmc_pebble_dispatch_button_raw(ElmcPebbleApp *app, int32_t button_id, int32_t pressed) {
      if (!app || !app->initialized) return -1;
      if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BUTTON_RAW)) return -8;
      int64_t tag = 0;
      if (button_id == ELMC_PEBBLE_BUTTON_BACK) {
        tag = pressed ? #{button_back_tag} : #{button_back_released_tag};
      } else if (button_id == ELMC_PEBBLE_BUTTON_UP) {
        tag = pressed ? #{button_up_tag} : #{button_up_released_tag};
      } else if (button_id == ELMC_PEBBLE_BUTTON_SELECT) {
        tag = pressed ? #{button_select_tag} : #{button_select_released_tag};
      } else if (button_id == ELMC_PEBBLE_BUTTON_DOWN) {
        tag = pressed ? #{button_down_tag} : #{button_down_released_tag};
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
      if (#{accel_tap_tag} <= 0) return -6;
      return elmc_pebble_dispatch_int(app, #{accel_tap_tag});
    }

    int elmc_pebble_dispatch_accel_data(ElmcPebbleApp *app, int32_t x, int32_t y, int32_t z) {
      if (!app || !app->initialized) return -1;
      if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_DATA)) return -8;
      if (#{accel_data_tag} <= 0) return -6;
      const char *names[] = {"x", "y", "z"};
      const int64_t values[] = {x, y, z};
      return elmc_pebble_dispatch_tag_record_int_fields(app, #{accel_data_tag}, 3, names, values);
    }

    int elmc_pebble_dispatch_frame(ElmcPebbleApp *app, int64_t dt_ms, int64_t elapsed_ms, int64_t frame) {
      if (!app || !app->initialized) return -1;
      if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_FRAME)) return -8;
      if (#{frame_tag} <= 0) return -6;
      const char *names[] = {"dtMs", "elapsedMs", "frame"};
      const int64_t values[] = {dt_ms, elapsed_ms, frame};
      return elmc_pebble_dispatch_tag_record_int_fields(app, #{frame_tag}, 3, names, values);
    }

    int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value) {
      if (!app || !app->initialized) return -1;
      if (#{storage_string_tag} <= 0) return -6;
      return elmc_pebble_dispatch_tag_string(app, #{storage_string_tag}, value ? value : "");
    }

    int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value) {
      if (!app || !app->initialized) return -1;
      if (#{random_generate_tag} <= 0) return -6;
      return elmc_pebble_dispatch_tag_value(app, #{random_generate_tag}, value);
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

    int elmc_pebble_dispatch_health(ElmcPebbleApp *app, int event) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_HEALTH)) return -8;
      if (#{health_event_tag} <= 0) return -6;
      if (event < 0) event = 0;
      if (event > 2) event = 0;
      return elmc_pebble_dispatch_tag_value(app, #{health_event_tag}, event);
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
      if (app->stream_view_result) {
        elmc_release(app->stream_view_result);
        app->stream_view_result = NULL;
      }
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
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -2);
      }
      int skip = 0;
      for (int chunk = 0; chunk < BUILD_CHUNK_GUARD; chunk++) {
        int count = elmc_pebble_view_commands_raw_impl(app, cmds, build_chunk_capacity, skip, 0);
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

    int elmc_pebble_scene_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_scene_commands_from");
      if (!app || !out_cmds || max_cmds <= 0 || skip < 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", -1);
      int rc = elmc_pebble_ensure_scene(app);
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
      int count = 0;
      ElmcValue *result = NULL;
      int result_is_cached = dedupe ? 0 : 1;
      if (!dedupe && skip == 0) {
        elmc_pebble_clear_view_cache(app);
      }
    #{if has_view do
      """
      #if defined(#{direct_view_macro})
            ElmcValue *direct_model = elmc_worker_model(&app->worker);
            if (!direct_model) return -2;
            ElmcValue *direct_args[] = { direct_model };
            int direct_count = #{entry_view_commands_from}(direct_args, 1, out_cmds, max_cmds, skip);
            elmc_release(direct_model);
            if (direct_count < 0) return direct_count;
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
              result = app->stream_view_result;
            } else {
              ElmcValue *model = elmc_worker_model(&app->worker);
              if (!model) return -2;
              ElmcValue *args[] = { model };
              result = elmc_fn_#{String.replace(entry_module, ".", "_")}_view(args, 1);
              elmc_release(model);
              if (!dedupe) {
                app->stream_view_result = result;
              }
            }
      #endif
      """
    else
      """
            if (!dedupe && app->stream_view_result) {
              result = app->stream_view_result;
            } else {
              result = elmc_worker_model(&app->worker);
              if (!result) return -2;
              if (!dedupe) {
                app->stream_view_result = result;
              }
            }
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
      elmc_pebble_clear_view_cache(app);
      elmc_pebble_scene_free(app);
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

  @spec random_generate_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  defp random_generate_target_tag(%IR{} = ir, msg_constructors) do
    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.flat_map(fn declaration ->
      random_generate_target_names(Map.get(declaration, :expr) || Map.get(declaration, :body))
    end)
    |> Enum.find_value(-1, fn
      {:tag, tag} when is_integer(tag) ->
        tag

      name ->
        Enum.find_value(msg_constructors, fn
          {^name, tag} -> tag
          _ -> nil
        end)
    end)
  end

  defp random_generate_target_names(%{
         op: :qualified_call,
         target: target,
         args: [to_msg, _generator]
       })
       when target in ["Random.generate", "Elm.Kernel.Random.generate"] do
    callback_tagger_names(to_msg)
  end

  defp random_generate_target_names(%{} = node) do
    node
    |> Map.values()
    |> Enum.flat_map(&random_generate_target_names/1)
  end

  defp random_generate_target_names(list) when is_list(list),
    do: Enum.flat_map(list, &random_generate_target_names/1)

  defp random_generate_target_names(_), do: []

  defp callback_tagger_names(%{op: :var, name: name}) when is_binary(name), do: [name]

  defp callback_tagger_names(%{op: :int_literal, value: tag}) when is_integer(tag),
    do: [{:tag, tag}]

  defp callback_tagger_names(%{op: :qualified_var, target: target})
       when is_binary(target) do
    [target |> String.split(".") |> List.last()]
  end

  defp callback_tagger_names(%{op: :qualified_call, target: target, args: []})
       when is_binary(target) do
    [target |> String.split(".") |> List.last()]
  end

  defp callback_tagger_names(_), do: []

  @spec health_event_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  defp health_event_target_tag(%IR{} = ir, msg_constructors) do
    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.flat_map(fn declaration ->
      health_event_target_names(Map.get(declaration, :expr) || Map.get(declaration, :body))
    end)
    |> Enum.find_value(-1, fn
      {:tag, tag} when is_integer(tag) ->
        tag

      name ->
        Enum.find_value(msg_constructors, fn
          {^name, tag} -> tag
          _ -> nil
        end)
    end)
  end

  defp health_event_target_names(%{op: :qualified_call, target: target, args: [to_msg]})
       when target in ["Pebble.Health.onEvent", "Elm.Kernel.PebbleWatch.onHealthEvent"] do
    callback_tagger_names(to_msg)
  end

  defp health_event_target_names(%{} = node) do
    node
    |> Map.values()
    |> Enum.flat_map(&health_event_target_names/1)
  end

  defp health_event_target_names(list) when is_list(list),
    do: Enum.flat_map(list, &health_event_target_names/1)

  defp health_event_target_names(_), do: []

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

  @spec c_enum(String.t(), String.t(), keyword(non_neg_integer())) :: String.t()
  defp c_enum(type_name, prefix, entries) do
    members =
      entries
      |> Enum.map_join(",\n", fn {name, value} ->
        "  #{prefix}_#{macro_name(Atom.to_string(name))} = #{value}"
      end)

    """
    typedef enum {
    #{members}
    } #{type_name};
    """
  end

  @spec feature_flags(IR.t(), [{String.t(), non_neg_integer()}], String.t()) :: map()
  defp feature_flags(ir, msg_constructors, entry_module) do
    targets = reachable_call_targets(ir, entry_module)
    command_flags = command_feature_flags(targets)
    draw_flags = draw_feature_flags(targets)

    uses_time_every =
      uses_target?(targets, "Elm.Kernel.Time.every") or uses_target?(targets, "Time.every")

    command_flags
    |> Map.merge(draw_flags)
    |> Map.merge(%{
      tick_events:
        uses_time_every or
          pick_tag(msg_constructors, ["Tick", "Increment", "UpPressed"], fallback: -1) > 0,
      hour_events: uses_target?(targets, "Pebble.Events.onHourChange"),
      minute_events: uses_target?(targets, "Pebble.Events.onMinuteChange"),
      frame_events:
        uses_target?(targets, "Pebble.Frame.every") or
          uses_target?(targets, "Pebble.Frame.atFps") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onFrame"),
      button_events:
        has_any_constructor?(msg_constructors, ["UpPressed", "SelectPressed", "DownPressed"]),
      raw_button_events:
        uses_target?(targets, "Pebble.Button.on") or
          uses_target?(targets, "Pebble.Button.onPress") or
          uses_target?(targets, "Pebble.Button.onRelease") or
          uses_target?(targets, "Pebble.Button.onLongPress") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onButtonRaw"),
      accel_events: has_any_constructor?(msg_constructors, ["Shake", "AccelTap", "Tapped"]),
      accel_data_events:
        uses_target?(targets, "Pebble.Accel.onData") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onAccelData"),
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
      health_events:
        uses_target?(targets, "Pebble.Health.onEvent") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onHealthEvent"),
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
      {"ELMC_PEBBLE_FEATURE_FRAME_EVENTS", flags[:frame_events]},
      {"ELMC_PEBBLE_FEATURE_BUTTON_EVENTS", flags[:button_events]},
      {"ELMC_PEBBLE_FEATURE_RAW_BUTTON_EVENTS", flags[:raw_button_events]},
      {"ELMC_PEBBLE_FEATURE_ACCEL_EVENTS", flags[:accel_events]},
      {"ELMC_PEBBLE_FEATURE_ACCEL_DATA_EVENTS", flags[:accel_data_events]},
      {"ELMC_PEBBLE_FEATURE_BATTERY_EVENTS", flags[:battery_events]},
      {"ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS", flags[:connection_events]},
      {"ELMC_PEBBLE_FEATURE_HEALTH_EVENTS", flags[:health_events]},
      {"ELMC_PEBBLE_FEATURE_INBOX_EVENTS", flags[:inbox_events]},
      {"ELMC_PEBBLE_FEATURE_MSG_CURRENT_TIME", flags[:msg_current_time]},
      {"ELMC_PEBBLE_FEATURE_CMD_TIMER_AFTER_MS", flags[:cmd_timer_after_ms]},
      {"ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_INT", flags[:cmd_storage_write_int]},
      {"ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_INT", flags[:cmd_storage_read_int]},
      {"ELMC_PEBBLE_FEATURE_CMD_STORAGE_WRITE_STRING", flags[:cmd_storage_write_string]},
      {"ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_STRING", flags[:cmd_storage_read_string]},
      {"ELMC_PEBBLE_FEATURE_CMD_RANDOM_GENERATE", flags[:cmd_random_generate]},
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
      {"ELMC_PEBBLE_FEATURE_CMD_VIBES_DOUBLE_PULSE", flags[:cmd_vibes_double_pulse]},
      {"ELMC_PEBBLE_FEATURE_CMD_HEALTH_VALUE", flags[:cmd_health_value]},
      {"ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUM_TODAY", flags[:cmd_health_sum_today]},
      {"ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUM", flags[:cmd_health_sum]},
      {"ELMC_PEBBLE_FEATURE_CMD_HEALTH_ACCESSIBLE", flags[:cmd_health_accessible]},
      {"ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT", flags[:draw_text_int]},
      {"ELMC_PEBBLE_FEATURE_DRAW_CLEAR", flags[:draw_clear]},
      {"ELMC_PEBBLE_FEATURE_DRAW_PIXEL", flags[:draw_pixel]},
      {"ELMC_PEBBLE_FEATURE_DRAW_LINE", flags[:draw_line]},
      {"ELMC_PEBBLE_FEATURE_DRAW_RECT", flags[:draw_rect]},
      {"ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT", flags[:draw_fill_rect]},
      {"ELMC_PEBBLE_FEATURE_DRAW_CIRCLE", flags[:draw_circle]},
      {"ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE", flags[:draw_fill_circle]},
      {"ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL", flags[:draw_text_label]},
      {"ELMC_PEBBLE_FEATURE_DRAW_CONTEXT", flags[:draw_context]},
      {"ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH", flags[:draw_stroke_width]},
      {"ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED", flags[:draw_antialiased]},
      {"ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR", flags[:draw_stroke_color]},
      {"ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR", flags[:draw_fill_color]},
      {"ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR", flags[:draw_text_color]},
      {"ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT", flags[:draw_round_rect]},
      {"ELMC_PEBBLE_FEATURE_DRAW_ARC", flags[:draw_arc]},
      {"ELMC_PEBBLE_FEATURE_DRAW_PATH", flags[:draw_path]},
      {"ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL", false},
      {"ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE", flags[:draw_compositing_mode]},
      {"ELMC_PEBBLE_FEATURE_DRAW_BITMAP_IN_RECT", flags[:draw_bitmap_in_rect]},
      {"ELMC_PEBBLE_FEATURE_DRAW_ROTATED_BITMAP", flags[:draw_rotated_bitmap]},
      {"ELMC_PEBBLE_FEATURE_DRAW_TEXT", flags[:draw_text]}
    ]
    |> Enum.map_join("\n", fn {macro, enabled} ->
      "#define #{macro} #{if(enabled, do: 1, else: 0)}"
    end)
  end

  @spec reachable_call_targets(IR.t(), String.t()) :: MapSet.t(String.t())
  defp reachable_call_targets(%IR{} = ir, entry_module) do
    function_map =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {"#{mod.name}.#{decl.name}", {mod.name, decl.expr}} end)
      end)
      |> Map.new()

    roots =
      ["init", "update", "subscriptions", "view", "main"]
      |> Enum.map(&"#{entry_module}.#{&1}")
      |> Enum.filter(&Map.has_key?(function_map, &1))

    reachable_targets(function_map, MapSet.new(roots), roots, MapSet.new())
  end

  defp reachable_targets(_function_map, _seen, [], targets), do: targets

  defp reachable_targets(function_map, seen, [current | rest], targets) do
    {module_name, expr} = Map.fetch!(function_map, current)

    {calls, targets} =
      expr
      |> collect_targets()
      |> Enum.reduce({[], targets}, fn target, {calls, targets} ->
        targets = MapSet.put(targets, target)

        case Map.fetch(function_map, target) do
          {:ok, _decl} ->
            if MapSet.member?(seen, target) do
              {calls, targets}
            else
              {[target | calls], targets}
            end

          :error ->
            local_target = "#{module_name}.#{target}"

            if Map.has_key?(function_map, local_target) and not MapSet.member?(seen, local_target) do
              {[local_target | calls], targets}
            else
              {calls, targets}
            end
        end
      end)

    seen = Enum.reduce(calls, seen, &MapSet.put(&2, &1))
    reachable_targets(function_map, seen, rest ++ Enum.reverse(calls), targets)
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

  defp collect_targets(%{op: op, name: name} = expr)
       when op in [:call, :call1] and is_binary(name) do
    [name | collect_targets(Map.values(expr))]
  end

  defp collect_targets(%{op: :var, name: name} = expr) when is_binary(name) do
    [name | collect_targets(Map.delete(expr, :name))]
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
      cmd_storage_write_string:
        uses_target?(targets, "Pebble.Storage.writeString") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.storageWriteString"),
      cmd_storage_read_string:
        uses_target?(targets, "Pebble.Storage.readString") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.storageReadString"),
      cmd_random_generate:
        uses_target?(targets, "Random.generate") or
          uses_target?(targets, "Elm.Kernel.Random.generate"),
      cmd_storage_delete: uses_target?(targets, "Pebble.Cmd.storageDelete"),
      cmd_companion_send: uses_target?(targets, "Pebble.Internal.Companion.companionSend"),
      cmd_backlight:
        uses_target?(targets, "Pebble.Cmd.backlight") or
          uses_target?(targets, "Pebble.Light.interaction") or
          uses_target?(targets, "Pebble.Light.disable") or
          uses_target?(targets, "Pebble.Light.enable") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.backlight"),
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
          uses_target?(targets, "Pebble.Vibes.doublePulse"),
      cmd_health_value: uses_target?(targets, "Elm.Kernel.PebbleWatch.healthValue"),
      cmd_health_sum_today: uses_target?(targets, "Elm.Kernel.PebbleWatch.healthSumToday"),
      cmd_health_sum: uses_target?(targets, "Elm.Kernel.PebbleWatch.healthSum"),
      cmd_health_accessible: uses_target?(targets, "Elm.Kernel.PebbleWatch.healthAccessible")
    }
  end

  @spec draw_feature_flags(MapSet.t(String.t())) :: map()
  defp draw_feature_flags(targets) do
    context =
      uses_target?(targets, "Pebble.Ui.group") or uses_target?(targets, "Pebble.Ui.context")

    text_int = uses_target?(targets, "Pebble.Ui.textInt")
    text_label = uses_target?(targets, "Pebble.Ui.textLabel")

    %{
      draw_text_int: text_int,
      draw_clear: uses_target?(targets, "Pebble.Ui.clear"),
      draw_pixel: uses_target?(targets, "Pebble.Ui.pixel"),
      draw_line: uses_target?(targets, "Pebble.Ui.line"),
      draw_rect: uses_target?(targets, "Pebble.Ui.rect"),
      draw_fill_rect: uses_target?(targets, "Pebble.Ui.fillRect"),
      draw_circle: uses_target?(targets, "Pebble.Ui.circle"),
      draw_fill_circle: uses_target?(targets, "Pebble.Ui.fillCircle"),
      draw_text_label: text_label,
      draw_context: context,
      draw_stroke_width: context and uses_target?(targets, "Pebble.Ui.strokeWidth"),
      draw_antialiased: context and uses_target?(targets, "Pebble.Ui.antialiased"),
      draw_stroke_color: context and uses_target?(targets, "Pebble.Ui.strokeColor"),
      draw_fill_color: context and uses_target?(targets, "Pebble.Ui.fillColor"),
      draw_text_color: context and uses_target?(targets, "Pebble.Ui.textColor"),
      draw_round_rect: uses_target?(targets, "Pebble.Ui.roundRect"),
      draw_arc: uses_target?(targets, "Pebble.Ui.arc"),
      draw_path:
        uses_target?(targets, "Pebble.Ui.pathFilled") or
          uses_target?(targets, "Pebble.Ui.pathOutline") or
          uses_target?(targets, "Pebble.Ui.pathOutlineOpen"),
      draw_fill_radial: uses_target?(targets, "Pebble.Ui.fillRadial"),
      draw_compositing_mode: context and uses_target?(targets, "Pebble.Ui.compositingMode"),
      draw_bitmap_in_rect: uses_target?(targets, "Pebble.Ui.drawBitmapInRect"),
      draw_rotated_bitmap: uses_target?(targets, "Pebble.Ui.drawRotatedBitmap"),
      draw_text: uses_target?(targets, "Pebble.Ui.text"),
      draw_text_any: text_int or text_label or uses_target?(targets, "Pebble.Ui.text")
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

  @spec direct_command_macro(String.t(), String.t()) :: String.t()
  defp direct_command_macro(module_name, decl_name) do
    safe =
      "#{module_name}_#{decl_name}"
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> String.upcase()

    "ELMC_HAVE_DIRECT_COMMANDS_#{safe}"
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
