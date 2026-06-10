defmodule Elmc.Backend.Pebble do
  @moduledoc """
  Generates a Pebble-oriented host shim around the worker adapter.
  """

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Pebble.{IRAnalysis, Kinds, SceneWriter, Util}
  alias Elmc.Types

  defdelegate draw_kind_id!(kind), to: Kinds
  defdelegate draw_kind_c_name!(kind), to: Kinds
  defdelegate command_kind_id!(kind), to: Kinds
  defdelegate command_kind_c_name!(kind), to: Kinds
  defdelegate run_mode_id!(mode), to: Kinds
  defdelegate button_id!(button), to: Kinds
  defdelegate accel_axis_id!(axis), to: Kinds
  defdelegate ui_node_kind_id!(kind), to: Kinds

  @spec write_pebble_shim(IR.t(), String.t(), String.t()) :: :ok | {:error, Types.file_error()}
  def write_pebble_shim(%IR{} = ir, out_dir, entry_module) do
    c_dir = Path.join(out_dir, "c")
    msg_constructors = IRAnalysis.msg_constructors(ir, entry_module)
    msg_constructor_arities = IRAnalysis.msg_constructor_arities(ir, entry_module)
    msg_constructor_payload_specs = IRAnalysis.msg_constructor_payload_specs(ir, entry_module)
    watch_model_tags = IRAnalysis.union_constructors(ir, "Pebble.WatchInfo", "WatchModel")
    watch_color_tags = IRAnalysis.union_constructors(ir, "Pebble.WatchInfo", "WatchColor")
    has_view = IRAnalysis.has_view?(ir, entry_module)
    feature_flags = feature_flags(ir, msg_constructors, entry_module)
    random_generate_tag = IRAnalysis.random_generate_target_tag(ir, msg_constructors)
    accel_config = IRAnalysis.accel_config_from_ir(ir, entry_module)

    with :ok <- File.mkdir_p(c_dir),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_pebble.h"),
             pebble_header(
               msg_constructors,
               msg_constructor_payload_specs,
               watch_model_tags,
               watch_color_tags,
               feature_flags,
               accel_config,
               entry_module
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
               random_generate_tag
             )
           ) do
      :ok
    end
  end

  @spec pebble_header([map()], map(), [map()], [map()], map(), map(), String.t()) :: String.t()
  defp pebble_header(
         msg_constructors,
         msg_constructor_payload_specs,
         watch_model_tags,
         watch_color_tags,
         feature_flags,
         accel_config,
         entry_module
       ) do
    msg_enum_members =
      msg_constructors
      |> Enum.map_join("\n", fn {name, tag} ->
        "  ELMC_PEBBLE_MSG_#{Util.macro_name(name)} = #{tag},"
      end)

    msg_presence_macros =
      msg_constructors
      |> Enum.map_join("\n", fn {name, _tag} ->
        "#define ELMC_PEBBLE_HAS_MSG_#{Util.macro_name(name)} 1"
      end)

    watch_model_macros = constructor_tag_macros("ELMC_PEBBLE_WATCH_MODEL", watch_model_tags)
    watch_color_macros = constructor_tag_macros("ELMC_PEBBLE_WATCH_COLOR", watch_color_tags)
    feature_macros = feature_flag_macros(feature_flags)
    run_mode_enum = c_enum("ElmcPebbleRunMode", "ELMC_PEBBLE_MODE", Kinds.run_modes())
    button_id_enum = c_enum("ElmcPebbleButtonId", "ELMC_PEBBLE_BUTTON", Kinds.button_ids())

    button_event_macros = """
    #define ELMC_BUTTON_EVENT_PRESSED 1
    #define ELMC_BUTTON_EVENT_RELEASED 2
    #define ELMC_BUTTON_EVENT_LONG_PRESSED 3
    """

    accel_axis_enum = c_enum("ElmcPebbleAccelAxis", "ELMC_PEBBLE_ACCEL_AXIS", Kinds.accel_axes())
    draw_kind_enum = c_enum("ElmcPebbleDrawKind", "ELMC_PEBBLE_DRAW", Kinds.draw_kinds())
    command_kind_enum = c_enum("ElmcPebbleCommandKind", "ELMC_PEBBLE_CMD", Kinds.command_kinds())
    ui_node_kind_enum = c_enum("ElmcPebbleUiNodeKind", "ELMC_PEBBLE_UI", Kinds.ui_node_kinds())

    phone_to_watch_target =
      IRAnalysis.phone_to_watch_msg_target(msg_constructors, msg_constructor_payload_specs)

    scene_writer_early = SceneWriter.header_early_declarations()
    scene_writer_late = SceneWriter.header_late_declarations()

    entry_view_scene_append =
      "elmc_fn_#{String.replace(entry_module, ".", "_")}_view_scene_append"

    """
    #ifndef ELMC_PEBBLE_H
    #define ELMC_PEBBLE_H

    #{scene_writer_early}

    #include "elmc_worker.h"

    #{feature_macros}

    #ifndef ELMC_PEBBLE_DIRTY_REGION_ENABLED
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 0
    #else
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 1
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_CACHE_ENABLED
    /* Encode the view once into a compact byte stream; draw decodes with a cursor.
       Incremental dirty regions (prev_scene diff) stay off on Pebble targets until reliable. */
    #define ELMC_PEBBLE_SCENE_CACHE_ENABLED 1
    #endif

    #ifndef ELMC_PEBBLE_SCENE_INITIAL_CAPACITY
    #define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 512
    #endif

    #ifndef ELMC_PEBBLE_SCENE_GROW_CHUNK
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_GROW_CHUNK 32
    #else
    #define ELMC_PEBBLE_SCENE_GROW_CHUNK 64
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_TRIM_SLACK
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_TRIM_SLACK 16
    #else
    #define ELMC_PEBBLE_SCENE_TRIM_SLACK 0
    #endif
    #endif

    #ifndef ELMC_PEBBLE_DRAW_PATH_PROBES
    #define ELMC_PEBBLE_DRAW_PATH_PROBES 0
    #endif

    #define ELMC_DRAW_PATH_RENDER_MODEL_ENTER 0xED9A0101U
    #define ELMC_DRAW_PATH_RENDER_MODEL_EXIT 0xED9A8101U
    #define ELMC_DRAW_PATH_DRAW_UPDATE_ENTER 0xED9A0102U
    #define ELMC_DRAW_PATH_DRAW_UPDATE_EXIT 0xED9A8102U
    #define ELMC_DRAW_PATH_ENSURE_SCENE_ENTER 0xED9A0103U
    #define ELMC_DRAW_PATH_ENSURE_SCENE_EXIT 0xED9A8103U
    #define ELMC_DRAW_PATH_SCENE_NEXT_ENTER 0xED9A0104U
    #define ELMC_DRAW_PATH_SCENE_NEXT_EXIT 0xED9A8104U
    #define ELMC_DRAW_PATH_VIEW_APPEND_ENTER 0xED9A0105U
    #define ELMC_DRAW_PATH_VIEW_APPEND_EXIT 0xED9A8105U
    #define ELMC_DRAW_PATH_ELM_INIT_ENTER 0xED9A0106U
    #define ELMC_DRAW_PATH_ELM_INIT_EXIT 0xED9A8106U
    #define ELMC_DRAW_PATH_FONT_FOR_TEXT_ENTER 0xED9A0107U
    #define ELMC_DRAW_PATH_FONT_FOR_TEXT_EXIT 0xED9A8107U
    #define ELMC_DRAW_PATH_GRAPHICS_TEXT_ENTER 0xED9A0108U
    #define ELMC_DRAW_PATH_GRAPHICS_TEXT_EXIT 0xED9A8108U

    #if ELMC_PEBBLE_DRAW_PATH_PROBES && defined(ELMC_PEBBLE_PLATFORM)
    #include <data_logging.h>
    static inline void elmc_draw_path_probe(uint32_t tag) {
      DataLoggingSessionRef session = data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
      if (session) {
        data_logging_finish(session);
      }
    }
    #define ELMC_DRAW_PATH_PROBE(tag) elmc_draw_path_probe((uint32_t)(tag))
    #else
    #define ELMC_DRAW_PATH_PROBE(tag) do { (void)(tag); } while (0)
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

    typedef struct ElmcPebbleApp {
      ElmcWorkerState worker;
      int initialized;
      int run_mode;
      int has_prev_ui;
      int64_t prev_window_id;
      int64_t prev_layer_id;
      uint64_t prev_ops_hash;
      ElmcValue *stream_view_result;
      ElmcPebbleSceneBuffer scene;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED
      int scene_draw_byte_offset;
    #endif
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
    #{button_event_macros}

    #{accel_axis_enum}

    typedef struct {
      int32_t kind;
      int32_t p0;
      int32_t p1;
      int32_t p2;
      int32_t p3;
      int32_t p4;
      int32_t p5;
      union {
        char text[64];
    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
        struct {
          int16_t path_x[16];
          int16_t path_y[16];
          int16_t path_offset_x;
          int16_t path_offset_y;
          int16_t path_rotation;
          uint8_t path_point_count;
        };
    #endif
      };
    } ElmcPebbleDrawCmd;

    #{scene_writer_late}

    int #{entry_view_scene_append}(
        ElmcValue ** const args,
        const int argc,
        ElmcSceneWriter * const writer);

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
    #define ELMC_PEBBLE_SUB_DAY (1 << 16)
    #define ELMC_PEBBLE_SUB_MONTH (1 << 17)
    #define ELMC_PEBBLE_SUB_YEAR (1 << 18)
    #define ELMC_PEBBLE_SUB_APP_FOCUS (1 << 19)
    #define ELMC_PEBBLE_SUB_COMPASS (1 << 20)
    #define ELMC_PEBBLE_SUB_DICTATION (1 << 21)
    #define ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA (1 << 22)
    #define ELMC_PEBBLE_SUB_HEALTH (1LL << 31)

    #ifndef ELMC_PEBBLE_ACCEL_SAMPLES_PER_UPDATE
    #define ELMC_PEBBLE_ACCEL_SAMPLES_PER_UPDATE #{Map.get(accel_config, :samples_per_update, 1)}
    #endif
    #ifndef ELMC_PEBBLE_ACCEL_SAMPLING_HZ
    #define ELMC_PEBBLE_ACCEL_SAMPLING_HZ #{Map.get(accel_config, :sampling_hz, 25)}
    #endif

    int elmc_pebble_init(ElmcPebbleApp *app, ElmcValue *flags);
    int elmc_pebble_init_with_mode(ElmcPebbleApp *app, ElmcValue *flags, int run_mode);
    int elmc_pebble_dispatch_int(ElmcPebbleApp *app, int64_t tag);
    int elmc_pebble_dispatch_tag_value(ElmcPebbleApp *app, int64_t tag, int64_t value);
    int elmc_pebble_dispatch_tag_bool(ElmcPebbleApp *app, int64_t tag, int value);
    int elmc_pebble_dispatch_tag_string(ElmcPebbleApp *app, int64_t tag, const char *value);
    int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload);
    int elmc_pebble_dispatch_tag_int_values(
        ElmcPebbleApp *app,
        int64_t outer_tag,
        int64_t inner_tag,
        int field_count,
        const int64_t *field_values);
    int elmc_pebble_dispatch_tag_record_int_fields(
        ElmcPebbleApp *app,
        int64_t tag,
        int field_count,
        const char **field_names,
        const int64_t *field_values);
    int elmc_pebble_msg_from_appmessage(int32_t key, int32_t value, int64_t *out_tag);
    int elmc_pebble_dispatch_appmessage(ElmcPebbleApp *app, int32_t key, int32_t value);
    int elmc_pebble_dispatch_button(ElmcPebbleApp *app, int32_t button_id);
    int elmc_pebble_dispatch_button_raw(ElmcPebbleApp *app, int32_t button_id, int32_t pressed);
    int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction);
    int elmc_pebble_dispatch_accel_data(ElmcPebbleApp *app, int32_t x, int32_t y, int32_t z);
    int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value);
    int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value);
    int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level);
    int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected);
    int elmc_pebble_dispatch_health(ElmcPebbleApp *app, int event);
    int elmc_pebble_dispatch_app_focus(ElmcPebbleApp *app, int in_focus);
    int elmc_pebble_dispatch_compass_heading(ElmcPebbleApp *app, double degrees, int is_valid);
    int elmc_pebble_dispatch_dictation_status(ElmcPebbleApp *app, int status);
    int elmc_pebble_dispatch_dictation_result(ElmcPebbleApp *app, int is_ok, int error_code, const char *text);
    int elmc_pebble_dispatch_unobstructed_will_change(ElmcPebbleApp *app, int x, int y, int w, int h);
    int elmc_pebble_dispatch_unobstructed_changing(ElmcPebbleApp *app, int progress);
    int elmc_pebble_dispatch_unobstructed_did_change(ElmcPebbleApp *app);
    int elmc_pebble_dispatch_frame(ElmcPebbleApp *app, int64_t dt_ms, int64_t elapsed_ms, int64_t frame);
    int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour);
    int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute);
    int elmc_pebble_dispatch_day(ElmcPebbleApp *app, int day);
    int elmc_pebble_dispatch_month(ElmcPebbleApp *app, int month);
    int elmc_pebble_dispatch_year(ElmcPebbleApp *app, int year);
    int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd);
    int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd);
    int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds);
    int elmc_pebble_view_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip);
    int elmc_pebble_scene_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip);
    void elmc_pebble_scene_reset_draw_cursor(ElmcPebbleApp *app);
    int elmc_pebble_scene_commands_next(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds);
    int elmc_pebble_ensure_scene(ElmcPebbleApp *app);
    int elmc_pebble_scene_command_count(ElmcPebbleApp *app);
    int elmc_pebble_scene_dirty_rect(ElmcPebbleApp *app, ElmcPebbleRect *out_rect, int *out_full);
    void elmc_pebble_invalidate_scene(ElmcPebbleApp *app);
    void elmc_pebble_clear_view_cache(ElmcPebbleApp *app);
    int elmc_pebble_tick(ElmcPebbleApp *app);
    int64_t elmc_pebble_active_subscriptions(ElmcPebbleApp *app);
    int64_t elmc_pebble_model_as_int(ElmcPebbleApp *app);
    int elmc_pebble_run_mode(ElmcPebbleApp *app);
    void elmc_pebble_deinit(ElmcPebbleApp *app);

    #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_HEAP_LOG
    void elmc_pebble_heap_log(const char *label);
    void elmc_pebble_render_diag_log(const char *phase, int render_seq, const ElmcPebbleApp *app);
    #else
    #define elmc_pebble_heap_log(label) do { (void)(label); } while (0)
    #define elmc_pebble_render_diag_log(phase, render_seq, app) \\
      do { \\
        (void)(phase); \\
        (void)(render_seq); \\
        (void)(app); \\
      } while (0)
    #endif

    #endif
    """
  end

  @spec pebble_source([map()], map(), boolean(), String.t(), integer()) :: String.t()
  defp pebble_source(
         msg_constructors,
         msg_constructor_arities,
         has_view,
         entry_module,
         random_generate_tag
       ) do
    value_decode_cases =
      msg_constructors
      |> Enum.map_join("\n", fn {name, tag} ->
        "      case ELMC_PEBBLE_MSG_#{Util.macro_name(name)}: *out_tag = #{tag}; return 0;"
      end)

    key_decode_cases =
      msg_constructors
      |> Enum.map_join("\n", fn {name, tag} ->
        "      case ELMC_PEBBLE_MSG_#{Util.macro_name(name)}: *out_tag = #{tag}; return 0;"
      end)

    msg_constructor_arity_cases =
      msg_constructors
      |> Enum.map_join("\n", fn {name, _tag} ->
        arity = Map.get(msg_constructor_arities, name, 0)
        "      case ELMC_PEBBLE_MSG_#{Util.macro_name(name)}: return #{arity};"
      end)

    tick_has_payload? =
      msg_constructors
      |> Enum.any?(fn {name, _} -> Map.get(msg_constructor_arities, name, 0) > 0 end)

    current_second_helper =
      if tick_has_payload? do
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

    storage_string_tag =
      IRAnalysis.pick_tag(msg_constructors, [
        "StorageStringLoaded",
        "GotStorageString",
        "GotString"
      ])

    direct_view_macro = direct_command_macro(entry_module, "view")

    entry_view_scene_append =
      "elmc_fn_#{String.replace(entry_module, ".", "_")}_view_scene_append"

    scene_writer_source = SceneWriter.source_implementation()

    """
    #include "elmc_pebble.h"
    #include <time.h>
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    #define ELMC_PEBBLE_PLATFORM 1
    #endif
    #ifdef ELMC_PEBBLE_PLATFORM
    #include <pebble.h>
    #if defined(__has_include) && __has_include("elmc_emulator_build_flags.h")
    #include "elmc_emulator_build_flags.h"
    #endif
    #ifndef ELMC_PEBBLE_DEBUG_LOGS
    #define ELMC_PEBBLE_DEBUG_LOGS 0
    #endif
    #endif
    #include <stdlib.h>
    #include <stdio.h>
    #include <string.h>

    #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_DEBUG_LOGS
    #define ELMC_PEBBLE_SCENE_LOG(...) APP_LOG(APP_LOG_LEVEL_INFO, __VA_ARGS__)
    #else
    #define ELMC_PEBBLE_SCENE_LOG(...) do { } while (0)
    #endif

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

    #ifndef ELMC_PEBBLE_HEAP_LOG
    #define ELMC_PEBBLE_HEAP_LOG 0
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

    #{current_second_helper}

    // #region agent log
    #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_AGENT_PROBES && !defined(#{direct_view_macro})
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

    #if !defined(#{direct_view_macro})
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

    #if !defined(#{direct_view_macro})
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
      cmd->text[0] = '\\0';
    }

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

    static void elmc_pebble_scene_abort_build(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_clear_view_cache(app);
      elmc_pebble_scene_discard_build(app);
      elmc_pebble_scene_buffer_free(&app->scene);
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
      if (app->scene.byte_capacity >= min_capacity) return 0;
      int next_capacity = app->scene.byte_capacity > 0 ? app->scene.byte_capacity : 0;
      while (next_capacity < min_capacity) {
        if (next_capacity == 0) {
    #if defined(PBL_PLATFORM_APLITE)
          next_capacity = ELMC_PEBBLE_SCENE_GROW_CHUNK;
    #else
          next_capacity = ELMC_PEBBLE_SCENE_INITIAL_CAPACITY;
    #endif
        } else if (next_capacity < ELMC_PEBBLE_SCENE_INITIAL_CAPACITY) {
          next_capacity += ELMC_PEBBLE_SCENE_GROW_CHUNK;
        } else {
          next_capacity *= 2;
        }
      }
      unsigned char *next = (unsigned char *)realloc(app->scene.bytes, (size_t)next_capacity);
      if (!next) return -2;
      app->scene.bytes = next;
      app->scene.byte_capacity = next_capacity;
      return 0;
    }

    static void elmc_pebble_scene_trim_capacity(ElmcPebbleApp *app) {
    #if ELMC_PEBBLE_SCENE_TRIM_SLACK > 0
      if (!app || !app->scene.bytes || app->scene.byte_count <= 0) return;
      int target = app->scene.byte_count + ELMC_PEBBLE_SCENE_TRIM_SLACK;
      if (app->scene.byte_capacity <= target) return;
      unsigned char *next = (unsigned char *)realloc(app->scene.bytes, (size_t)target);
      if (!next) return;
      app->scene.bytes = next;
      app->scene.byte_capacity = target;
    #else
      (void)app;
    #endif
    }

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
      app->scene.bytes[app->scene.byte_count++] = value;
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
      app->scene.bytes[app->scene.byte_count++] = b0;
      app->scene.bytes[app->scene.byte_count++] = b1;
      elmc_pebble_scene_hash_byte(app, b0);
      elmc_pebble_scene_hash_byte(app, b1);
      return 0;
    }

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

    static int elmc_scene_value_fits_i16(int32_t value) {
      return value >= -32768 && value <= 32767;
    }

    static int elmc_scene_value_fits_u8(int32_t value) {
      return value >= 0 && value <= 255;
    }

    static int elmc_scene_bounds_fit_i16(const ElmcPebbleDrawCmd *cmd) {
      if (!cmd) return 0;
      return elmc_scene_value_fits_i16(cmd->p0) &&
             elmc_scene_value_fits_i16(cmd->p1) &&
             elmc_scene_value_fits_i16(cmd->p2) &&
             elmc_scene_value_fits_i16(cmd->p3);
    }

    static int elmc_scene_text_len(const ElmcPebbleDrawCmd *cmd) {
      int text_len = 0;
      if (!cmd) return 0;
      while (text_len < (int)sizeof(cmd->text) && cmd->text[text_len] != '\\0') text_len++;
      return text_len;
    }

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
      int text_len = elmc_scene_text_len(cmd);

    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
      if (kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
          kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
          kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
        return ELMC_SCENE_PL_FULL + elmc_scene_path_extra_size(cmd);
      }
    #endif

      switch (kind) {
      case ELMC_PEBBLE_DRAW_PUSH_CONTEXT:
      case ELMC_PEBBLE_DRAW_POP_CONTEXT:
        return ELMC_SCENE_PL_EMPTY;
      case ELMC_PEBBLE_DRAW_STROKE_WIDTH:
      case ELMC_PEBBLE_DRAW_ANTIALIASED:
        return elmc_scene_value_fits_u8(cmd->p0) ? ELMC_SCENE_PL_U8 : ELMC_SCENE_PL_I32;
      case ELMC_PEBBLE_DRAW_STROKE_COLOR:
      case ELMC_PEBBLE_DRAW_FILL_COLOR:
      case ELMC_PEBBLE_DRAW_TEXT_COLOR:
      case ELMC_PEBBLE_DRAW_CLEAR:
      case ELMC_PEBBLE_DRAW_COMPOSITING_MODE:
        return elmc_scene_value_fits_u8(cmd->p0) ? ELMC_SCENE_PL_U8 : ELMC_SCENE_PL_I32;
      case ELMC_PEBBLE_DRAW_PIXEL:
        if (elmc_scene_value_fits_i16(cmd->p0) &&
            elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_u8(cmd->p2)) {
          return ELMC_SCENE_PL_PIXEL;
        }
        return ELMC_SCENE_PL_FULL;
      case ELMC_PEBBLE_DRAW_LINE:
      case ELMC_PEBBLE_DRAW_RECT:
      case ELMC_PEBBLE_DRAW_FILL_RECT:
        if (!elmc_scene_bounds_fit_i16(cmd) || cmd->p5 != 0) return ELMC_SCENE_PL_FULL;
        return elmc_scene_value_fits_u8(cmd->p4) ? ELMC_SCENE_PL_COORDS_COLOR_U8 : ELMC_SCENE_PL_COORDS_COLOR_I32;
      case ELMC_PEBBLE_DRAW_CIRCLE:
      case ELMC_PEBBLE_DRAW_FILL_CIRCLE:
        if (elmc_scene_value_fits_i16(cmd->p0) &&
            elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_i16(cmd->p2) &&
            cmd->p4 == 0 && cmd->p5 == 0) {
          return elmc_scene_value_fits_u8(cmd->p3) ? ELMC_SCENE_PL_CIRCLE_U8 : ELMC_SCENE_PL_CIRCLE_I32;
        }
        return ELMC_SCENE_PL_FULL;
      case ELMC_PEBBLE_DRAW_ROUND_RECT:
        if (elmc_scene_bounds_fit_i16(cmd) && elmc_scene_value_fits_i16(cmd->p4)) {
          return elmc_scene_value_fits_u8(cmd->p5) ? ELMC_SCENE_PL_ROUND_U8 : ELMC_SCENE_PL_ROUND_I32;
        }
        return ELMC_SCENE_PL_FULL;
      case ELMC_PEBBLE_DRAW_TEXT:
        if (elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_i16(cmd->p2) &&
            elmc_scene_value_fits_i16(cmd->p3) &&
            elmc_scene_value_fits_i16(cmd->p4)) {
          return ELMC_SCENE_PL_TEXT_BASE + 1 + text_len;
        }
        return ELMC_SCENE_PL_FULL + 1 + text_len;
      case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT:
        if (elmc_scene_value_fits_i16(cmd->p1) && elmc_scene_value_fits_i16(cmd->p2)) {
          return ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 + text_len;
        }
        return ELMC_SCENE_PL_FULL + 1 + text_len;
      case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT:
        if (elmc_scene_value_fits_i16(cmd->p1) && elmc_scene_value_fits_i16(cmd->p2)) {
          return ELMC_SCENE_PL_COORDS_COLOR_I32;
        }
        return ELMC_SCENE_PL_FULL;
      default:
        return ELMC_SCENE_PL_FULL;
      }
    }

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
      out_cmd->text[text_len] = '\\0';
      *offset += text_len;
      return 0;
    }

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
      if (kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
          payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 &&
          payload_len < ELMC_SCENE_PL_TEXT_BASE) {
        out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
        return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
      }
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
      case ELMC_SCENE_PL_PIXEL:
        out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
        if (*offset >= payload_end) return -3;
        out_cmd->p2 = bytes[*offset];
        *offset += 1;
        return 0;
      case ELMC_SCENE_PL_COORDS_COLOR_U8:
        rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        if (*offset >= payload_end) return -3;
        out_cmd->p4 = bytes[*offset];
        *offset += 1;
        return 0;
      case ELMC_SCENE_PL_COORDS_COLOR_I32:
        if (kind == ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT) {
          out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
          out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
          out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
          out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
          return 0;
        }
        rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        out_cmd->p4 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        return 0;
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
      default:
        break;
      }
      if (payload_len >= ELMC_SCENE_PL_TEXT_BASE &&
          kind == ELMC_PEBBLE_DRAW_TEXT &&
          payload_len >= ELMC_SCENE_PL_TEXT_BASE + 1) {
        rc = elmc_scene_read_text_bounds_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
      }
      if (payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE &&
          kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
          payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE + 1) {
        out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
        return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
      }
      if ((payload_len == ELMC_SCENE_PL_FULL && !elmc_scene_is_path_kind(kind)) ||
          (payload_len > ELMC_SCENE_PL_FULL && elmc_scene_is_path_kind(kind))) {
        rc = elmc_scene_read_full_i32s(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        if (elmc_scene_is_path_kind(kind)) {
          rc = elmc_scene_read_path_tail(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        }
        return 0;
      }
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
      return -4;
    }

    #{scene_writer_source}

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

    #if !defined(#{direct_view_macro})
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

    #if ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN || ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES
    static int elmc_serialize_int_list(
        ElmcValue *value,
        char *out_text,
        size_t out_size,
        int32_t *out_count) {
      if (!out_text || out_size == 0 || !out_count) return -1;
      out_text[0] = '\\0';
      *out_count = 0;
      if (!value) return 0;

      size_t used = 0;
      ElmcValue *cursor = value;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) break;
        int64_t item = elmc_as_int(node->head);
        char chunk[24];
        int n = snprintf(
            chunk,
            sizeof(chunk),
            (*out_count == 0) ? "%ld" : ",%ld",
            (long)item);
        if (n <= 0 || used + (size_t)n >= out_size) return -2;
        strncat(out_text, chunk, out_size - used - 1);
        used += (size_t)n;
        *out_count += 1;
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
      out_cmd->text[0] = '\\0';
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
          out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
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
            out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
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

    #if !defined(#{direct_view_macro})
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

    #{if tick_has_payload? do
      """
      static int elmc_msg_constructor_arity(elmc_int_t tag) {
        switch (tag) {
      #{msg_constructor_arity_cases}
          default: return 0;
        }
      }
      """
    else
      ""
    end}

    static void elmc_pebble_prepare_dispatch(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_heap_log("dispatch:prepare:before");
      elmc_pebble_clear_view_cache(app);
    #if !ELMC_PEBBLE_DIRTY_REGION_ENABLED
      /* Retain scene heap capacity across dispatches; freeing here forces realloc on
         a fragmented heap after update and can fail on tight Aplite targets. */
      app->scene.byte_count = 0;
      app->scene.command_count = 0;
      app->scene.hash = 0;
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
    #if !defined(#{direct_view_macro})
      app->stream_view_result = NULL;
    #endif
      app->scene.bytes = NULL;
      app->scene.byte_count = 0;
      app->scene.byte_capacity = 0;
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
      ElmcValue *msg = elmc_new_int(tag);
      if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", -2);
      elmc_pebble_prepare_dispatch(app);
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

      elmc_pebble_prepare_dispatch(app);
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

      elmc_pebble_prepare_dispatch(app);
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

      elmc_pebble_prepare_dispatch(app);
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

      elmc_pebble_prepare_dispatch(app);
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

    int elmc_pebble_dispatch_compass_heading(ElmcPebbleApp *app, double degrees, int is_valid) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_COMPASS)) return -8;
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_COMPASS);
      if (tag <= 0) return -6;

      const char *names[] = {"degrees", "isValid"};
      ElmcValue *values[2];
      values[0] = elmc_new_float(degrees);
      values[1] = elmc_new_bool(is_valid ? 1 : 0);
      if (!values[0] || !values[1]) {
        if (values[0]) elmc_release(values[0]);
        if (values[1]) elmc_release(values[1]);
        return -2;
      }

      ElmcValue *record = elmc_record_new(2, names, values);
      elmc_release(values[0]);
      elmc_release(values[1]);
      if (!record) return -2;

      ElmcValue *tag_value = elmc_new_int(tag);
      if (!tag_value) {
        elmc_release(record);
        return -2;
      }

      ElmcValue *msg = elmc_tuple2(tag_value, record);
      elmc_release(tag_value);
      elmc_release(record);
      if (!msg) return -2;

      elmc_pebble_prepare_dispatch(app);
      int rc = elmc_worker_dispatch(&app->worker, msg);
      elmc_release(msg);
      return elmc_pebble_finish_dispatch(app, rc);
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
        result_payload = elmc_result_ok(elmc_new_string(text ? text : ""));
      } else {
        ElmcValue *error_value = NULL;
        if (error_code == 3) {
          error_value = elmc_tuple2(elmc_new_int(3), elmc_new_string(text ? text : ""));
        } else {
          error_value = elmc_new_int(error_code);
        }
        if (!error_value) return -2;
        result_payload = elmc_result_err(error_value);
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
    #if defined(#{direct_view_macro})
      (void)app;
    #else
      if (app->stream_view_result) {
        elmc_release(app->stream_view_result);
        app->stream_view_result = NULL;
      }
    #endif
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
    #if defined(#{direct_view_macro})
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
        int rc = #{entry_view_scene_append}(direct_args, 1, &writer);
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_VIEW_APPEND_EXIT);
        elmc_release(direct_model);
        ELMC_PEBBLE_SCENE_LOG("elmc-scene view append rc=%d writer_cmds=%d",
                rc, writer.command_count);
        if (rc != 0) {
          elmc_pebble_scene_abort_build(app);
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", rc);
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
      elmc_pebble_scene_trim_capacity(app);
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
      if ((app->scene.dirty || app->scene.byte_count <= 0) &&
          app->scene_draw_byte_offset == 0) {
        int build_rc = elmc_pebble_ensure_scene(app);
        if (build_rc != 0) {
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", build_rc);
        }
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
    #if !defined(#{direct_view_macro})
      int count = 0;
      ElmcValue *result = NULL;
      int result_is_cached = dedupe ? 0 : 1;
      if (!dedupe && skip == 0) {
        elmc_pebble_clear_view_cache(app);
      }
    #endif
    #{if has_view do
      """
      #if defined(#{direct_view_macro})
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
              result = elmc_fn_#{String.replace(entry_module, ".", "_")}_view(args, 1);
              elmc_pebble_heap_log("view:end");
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

      #if !defined(#{direct_view_macro})
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
    #{if tick_has_payload? do
      "  if (elmc_msg_constructor_arity(tag) > 0) return elmc_pebble_dispatch_tag_value(app, tag, elmc_current_second());"
    else
      ""
    end}
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
    """
  end

  @spec constructor_tag_macros(String.t(), [{String.t(), non_neg_integer()}]) :: String.t()
  defp constructor_tag_macros(prefix, constructors) do
    constructors
    |> Enum.map_join("\n", fn {name, tag} ->
      "#define #{prefix}_#{Util.macro_name(name)} #{tag}"
    end)
  end

  @spec c_enum(String.t(), String.t(), keyword(non_neg_integer())) :: String.t()
  defp c_enum(type_name, prefix, entries) do
    members =
      entries
      |> Enum.map_join(",\n", fn {name, value} ->
        "  #{prefix}_#{Util.macro_name(Atom.to_string(name))} = #{value}"
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
          uses_target?(targets, "Pebble.Events.onSecondChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onSecondChange"),
      hour_events:
        uses_target?(targets, "Pebble.Events.onHourChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onHourChange"),
      minute_events:
        uses_target?(targets, "Pebble.Events.onMinuteChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onMinuteChange"),
      day_events:
        uses_target?(targets, "Pebble.Events.onDayChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onDayChange"),
      month_events:
        uses_target?(targets, "Pebble.Events.onMonthChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onMonthChange"),
      year_events:
        uses_target?(targets, "Pebble.Events.onYearChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onYearChange"),
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
      app_focus_events:
        uses_target?(targets, "Pebble.AppFocus.onChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onAppFocusChange"),
      compass_events:
        uses_target?(targets, "Pebble.Compass.onChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onCompassChange"),
      dictation_events:
        uses_target?(targets, "Pebble.Dictation.onStatus") or
          uses_target?(targets, "Pebble.Dictation.onResult") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onDictationStatus") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onDictationResult"),
      unobstructed_area_events:
        uses_target?(targets, "Pebble.UnobstructedArea.onWillChange") or
          uses_target?(targets, "Pebble.UnobstructedArea.onChanging") or
          uses_target?(targets, "Pebble.UnobstructedArea.onDidChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onUnobstructedWillChange") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onUnobstructedChanging") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.onUnobstructedDidChange"),
      inbox_events: uses_target?(targets, "Companion.Watch.onPhoneToWatch")
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
      {"ELMC_PEBBLE_FEATURE_DAY_EVENTS", flags[:day_events]},
      {"ELMC_PEBBLE_FEATURE_MONTH_EVENTS", flags[:month_events]},
      {"ELMC_PEBBLE_FEATURE_YEAR_EVENTS", flags[:year_events]},
      {"ELMC_PEBBLE_FEATURE_FRAME_EVENTS", flags[:frame_events]},
      {"ELMC_PEBBLE_FEATURE_BUTTON_EVENTS", flags[:button_events]},
      {"ELMC_PEBBLE_FEATURE_RAW_BUTTON_EVENTS", flags[:raw_button_events]},
      {"ELMC_PEBBLE_FEATURE_ACCEL_EVENTS", flags[:accel_events]},
      {"ELMC_PEBBLE_FEATURE_ACCEL_DATA_EVENTS", flags[:accel_data_events]},
      {"ELMC_PEBBLE_FEATURE_BATTERY_EVENTS", flags[:battery_events]},
      {"ELMC_PEBBLE_FEATURE_CONNECTION_EVENTS", flags[:connection_events]},
      {"ELMC_PEBBLE_FEATURE_HEALTH_EVENTS", flags[:health_events]},
      {"ELMC_PEBBLE_FEATURE_APP_FOCUS_EVENTS", flags[:app_focus_events]},
      {"ELMC_PEBBLE_FEATURE_COMPASS_EVENTS", flags[:compass_events]},
      {"ELMC_PEBBLE_FEATURE_DICTATION_EVENTS", flags[:dictation_events]},
      {"ELMC_PEBBLE_FEATURE_UNOBSTRUCTED_AREA_EVENTS", flags[:unobstructed_area_events]},
      {"ELMC_PEBBLE_FEATURE_INBOX_EVENTS", flags[:inbox_events]},
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
      {"ELMC_PEBBLE_FEATURE_CMD_HEALTH_SUPPORTED", flags[:cmd_health_supported]},
      {"ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN", flags[:cmd_vibes_custom_pattern]},
      {"ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES", flags[:cmd_data_log_bytes]},
      {"ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_INT32", flags[:cmd_data_log_int32]},
      {"ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK", flags[:cmd_compass_peek]},
      {"ELMC_PEBBLE_FEATURE_CMD_DICTATION_START", flags[:cmd_dictation_start]},
      {"ELMC_PEBBLE_FEATURE_CMD_DICTATION_STOP", flags[:cmd_dictation_stop]},
      {"ELMC_PEBBLE_FEATURE_CMD_UNOBSTRUCTED_BOUNDS_PEEK", flags[:cmd_unobstructed_bounds_peek]},
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
      {"ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL", flags[:draw_fill_radial]},
      {"ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE", flags[:draw_compositing_mode]},
      {"ELMC_PEBBLE_FEATURE_DRAW_BITMAP_IN_RECT", flags[:draw_bitmap_in_rect]},
      {"ELMC_PEBBLE_FEATURE_DRAW_VECTOR_AT", flags[:draw_vector_at]},
      {"ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT", flags[:draw_vector_sequence_at]},
      {"ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT", flags[:draw_bitmap_sequence_at]},
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

  @spec collect_targets(CCodegenTypes.ir_expr() | list() | nil | String.t() | number() | atom()) ::
          [String.t()]
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
      cmd_health_accessible: uses_target?(targets, "Elm.Kernel.PebbleWatch.healthAccessible"),
      cmd_health_supported:
        uses_target?(targets, "Pebble.Health.supported") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.healthSupported"),
      cmd_vibes_custom_pattern:
        uses_target?(targets, "Pebble.Vibes.pattern") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.vibesCustomPattern"),
      cmd_data_log_bytes:
        uses_target?(targets, "Pebble.DataLog.logBytes") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.dataLogBytes"),
      cmd_data_log_int32:
        uses_target?(targets, "Pebble.DataLog.logInt32") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.dataLogInt32"),
      cmd_compass_peek:
        uses_target?(targets, "Pebble.Compass.current") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.compassCurrent"),
      cmd_dictation_start:
        uses_target?(targets, "Pebble.Dictation.start") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.dictationStart"),
      cmd_dictation_stop:
        uses_target?(targets, "Pebble.Dictation.stop") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.dictationStop"),
      cmd_unobstructed_bounds_peek:
        uses_target?(targets, "Pebble.UnobstructedArea.currentBounds") or
          uses_target?(targets, "Elm.Kernel.PebbleWatch.unobstructedCurrentBounds")
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
      draw_vector_at: uses_target?(targets, "Pebble.Ui.drawVectorAt"),
      draw_vector_sequence_at: uses_target?(targets, "Pebble.Ui.drawVectorSequenceAt"),
      draw_bitmap_sequence_at: uses_target?(targets, "Pebble.Ui.drawBitmapSequenceAt"),
      draw_rotated_bitmap: uses_target?(targets, "Pebble.Ui.drawRotatedBitmap"),
      draw_text: uses_target?(targets, "Pebble.Ui.text"),
      draw_text_any: text_int or text_label or uses_target?(targets, "Pebble.Ui.text")
    }
  end

  @spec uses_target?(MapSet.t(String.t()), String.t()) :: boolean()
  defp uses_target?(targets, target), do: MapSet.member?(targets, target)

  @spec direct_command_macro(String.t(), String.t()) :: String.t()
  defp direct_command_macro(module_name, decl_name) do
    safe =
      "#{module_name}_#{decl_name}"
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> String.upcase()

    "ELMC_HAVE_DIRECT_COMMANDS_#{safe}"
  end
end
