defmodule Elmc.TestSupport.TeaScenarioHarness do
  @moduledoc false

  alias Elmc.TestSupport.{TeaScenario, TeaScenarioProtocol}

  @spec emit(String.t(), map(), String.t()) :: String.t()
  def emit(template, scenario, header_path) do
    caps = TeaScenario.capabilities(header_path)
    protocol_c = TeaScenarioProtocol.harness_c(template) || ""

    """
    #include <stdio.h>
    #include <string.h>
    #include "elmc_pebble.h"
    #include "elmc_scene_sdk_replay.h"
    #include "pebble_sdk_spy.h"

    static ElmcValue *tea_harness_int(elmc_int_t v) {
      ElmcValue *out = NULL;
      if (elmc_new_int(&out, v) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *tea_harness_bool(bool v) {
      ElmcValue *out = NULL;
      if (elmc_new_bool(&out, v ? 1 : 0) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *tea_harness_string(const char *s) {
      ElmcValue *out = NULL;
      if (elmc_new_string(&out, s) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *tea_harness_tuple2_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      if (elmc_tuple2_take(&out, a, b) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *tea_harness_union_int(elmc_int_t tag, elmc_int_t value) {
      return tea_harness_tuple2_take(tea_harness_int(tag), tea_harness_int(value));
    }

    static ElmcValue *tea_harness_phone_union(elmc_int_t tag, ElmcValue *payload) {
      return tea_harness_tuple2_take(tea_harness_int(tag), payload);
    }

    static ElmcValue *tea_current_datetime(void) {
      ElmcValue *fields[8] = {
          tea_harness_int(2026), tea_harness_int(7), tea_harness_int(1), tea_harness_int(3),
          tea_harness_int(10), tea_harness_int(30), tea_harness_int(0), tea_harness_int(0)};
      ElmcValue *rec = NULL;
      if (elmc_record_new_values(&rec, 8, fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 8; i++) elmc_release(fields[i]);
      return rec;
    }

    static ElmcValue *tea_launch_context(void) {
      ElmcValue *screen_fields[4] = {tea_harness_int(144), tea_harness_int(168), tea_harness_int(1), tea_harness_int(2)};
      ElmcValue *screen = NULL;
      if (elmc_record_new_values(&screen, 4, screen_fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 4; i++) elmc_release(screen_fields[i]);

      ElmcValue *ctx_fields[7] = {
          tea_harness_int(2),
          tea_harness_string(""),
          tea_harness_string("gabbro"),
          screen,
          tea_harness_bool(false),
          tea_harness_bool(false),
          tea_harness_bool(true)
      };
      ElmcValue *ctx = NULL;
      if (elmc_record_new_values(&ctx, 7, ctx_fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 7; i++) {
        if (i != 3) elmc_release(ctx_fields[i]);
      }
      elmc_release(screen);
      return ctx;
    }

    #{protocol_c}

    static int tea_drain_cmds(ElmcPebbleApp *app) {
      for (int round = 0; round < 4; round++) {
        int progressed = 0;
        for (int j = 0; j < 16; j++) {
          ElmcPebbleCmd cmd = {0};
          if (elmc_pebble_take_cmd(app, &cmd) != 0) return -1;
          if (cmd.kind == ELMC_PEBBLE_CMD_NONE) {
            if (!progressed) return 0;
            break;
          }
          progressed = 1;
          switch (cmd.kind) {
    #{drain_switch_cases(caps)}
          default:
            break;
          }
        }
        if (!progressed) break;
      }
      return 0;
    }

    static int tea_run_view(ElmcPebbleApp *app, ElmcSceneSdkReplayStats *stats) {
      app->scene.dirty = 1;
      if (elmc_pebble_ensure_scene(app) != 0) return -1;
      return elmc_scene_replay_to_sdk(app, stats);
    }

    static int scene_text_is_placeholder(const ElmcPebbleApp *app) {
      int byte_offset = 0;
      while (byte_offset < app->scene.byte_count) {
        ElmcPebbleDrawCmd cmd;
        if (elmc_pebble_scene_decode_record(app->scene.bytes, app->scene.byte_count, &byte_offset, &cmd) != 0) {
          return 0;
        }
        if (cmd.kind == ELMC_PEBBLE_DRAW_TEXT && strstr(cmd.text, "--:--") != NULL) {
          return 1;
        }
      }
      return 0;
    }

    static int tea_dispatch_button(ElmcPebbleApp *app, int32_t button_id) {
      int dr = elmc_pebble_dispatch_button(app, button_id);
      if (dr != 0) return -1;
      return tea_drain_cmds(app);
    }

    static void tea_dump_spy_texts(void) {
      printf("spy_texts:");
      for (int i = 0; i < spy_count(); i++) {
        const SpyRecord *rec = spy_record(i);
        if (rec && rec->kind == SPY_OP_DRAW_TEXT && rec->text[0] != '\\0') {
          printf(" | %s", rec->text);
        }
      }
      printf("\\n");
    }

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = tea_launch_context();
      if (!flags) return 1;
      if (#{init_expr(scenario)}) return 2;
      elmc_release(flags);

    #{emit_steps(scenario, caps)}

      ElmcSceneSdkReplayStats stats = {0};
      if (tea_run_view(&app, &stats) != 0) return 90;

      printf("scene_cmds=%d scene_text=%d scene_fill_rect=%d scene_fill_circle=%d scene_circle=%d scene_radial=%d scene_text_origin=%d\\n",
             stats.scene_cmds, stats.scene_text, stats.scene_fill_rect, stats.scene_fill_circle,
             stats.scene_circle, stats.scene_fill_radial, stats.scene_text_origin);
      printf("sdk_text=%d sdk_fill_rect=%d sdk_fill_circle=%d sdk_circle=%d sdk_center_text=%d sdk_fullwidth_center=%d\\n",
             stats.sdk_text, stats.sdk_fill_rect, stats.sdk_fill_circle, stats.sdk_circle,
             spy_text_align_count(GTextAlignmentCenter),
             spy_text_full_width_center_count(#{Map.get(scenario.expects, :full_width_min, 80)}));

    #{emit_expect_checks(scenario)}

      elmc_pebble_deinit(&app);
      printf("rc_ok tea_scenario #{template}\\n");
      return 0;
    }
    """
  end

  defp init_expr(%{mode: :watchface}) do
    "elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0"
  end

  defp init_expr(_), do: "elmc_pebble_init(&app, flags) != 0"

  defp drain_switch_cases(caps) do
    lines = []

    lines =
      if caps[:has_current_datetime] do
        lines ++
          [
            """
                  case ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME:
                    {
                      ElmcValue *dt = tea_current_datetime();
                      if (!dt) return -2;
                      if (elmc_pebble_dispatch_tag_payload(app, cmd.p0, dt) == 0) progressed = 1;
                      elmc_release(dt);
                    }
                    break;
            """
          ]
      else
        lines
      end

    lines =
      if caps[:has_current_datetime] do
        lines ++
          [
            """
                  case ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING:
                    if (elmc_pebble_dispatch_tag_string(app, cmd.p0, "10:30") == 0) progressed = 1;
                    break;
            """
          ]
      else
        lines
      end

    lines =
      if caps[:has_storage] do
        lines ++
          [
            """
                  case ELMC_PEBBLE_CMD_STORAGE_READ_INT:
                    if (elmc_pebble_dispatch_tag_value(app, cmd.p0, 0) == 0) progressed = 1;
                    break;
                  case ELMC_PEBBLE_CMD_STORAGE_READ_STRING:
                    if (elmc_pebble_dispatch_tag_string(app, cmd.p1, "") == 0) progressed = 1;
                    break;
            """
          ]
      else
        lines
      end

    lines =
      if caps[:has_random] do
        lines ++
          [
            """
                  case ELMC_PEBBLE_CMD_RANDOM_GENERATE:
                    if (elmc_pebble_dispatch_tag_value(app, cmd.p0, 42) == 0) progressed = 1;
                    break;
            """
          ]
      else
        lines
      end

    lines =
      if caps[:has_health] do
        lines ++
          [
            """
                  case ELMC_PEBBLE_CMD_HEALTH_SUPPORTED:
                    if (elmc_pebble_dispatch_tag_bool(app, cmd.p0, 1) == 0) progressed = 1;
                    break;
                  case ELMC_PEBBLE_CMD_HEALTH_VALUE:
                  case ELMC_PEBBLE_CMD_HEALTH_SUM_TODAY:
                  case ELMC_PEBBLE_CMD_HEALTH_SUM:
                    if (elmc_pebble_dispatch_tag_value(app, cmd.p0, 100) == 0) progressed = 1;
                    break;
            """
          ]
      else
        lines
      end

    Enum.join(lines, "")
  end

  defp emit_steps(scenario, caps) do
    scenario.steps
    |> Enum.with_index(3)
    |> Enum.map(fn {step, code} -> emit_step(step, code, caps) end)
    |> Enum.join("\n")
  end

  defp emit_step({:drain_cmds, _kinds}, code, _caps) do
    "  if (tea_drain_cmds(&app) != 0) return #{code};"
  end

  defp emit_step({:dispatch_clock, :current_datetime}, code, _caps) do
    """
      {
        ElmcValue *dt = tea_current_datetime();
        if (!dt) return #{code};
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_CURRENTDATETIME, dt) != 0) return #{code + 1};
        elmc_release(dt);
      }
    """
  end

  defp emit_step({:dispatch_tag_value, :battery, value}, code, _caps) do
  """
    if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_BATTERYLEVELCHANGED, #{value}) != 0) return #{code};
  """
  end

  defp emit_step({:dispatch_tag_value, :random, value}, code, _caps) do
    "if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_RANDOMGENERATED, #{value}) != 0) return #{code};"
  end

  defp emit_step({:dispatch_tag_bool, :connection, value}, code, _caps) do
    bool = if value, do: 1, else: 0
    "if (elmc_pebble_dispatch_tag_bool(&app, ELMC_PEBBLE_MSG_CONNECTIONCHANGED, #{bool}) != 0) return #{code};"
  end

  defp emit_step({:dispatch_tag_bool, :health, value}, code, _caps) do
    bool = if value, do: 1, else: 0
    "if (elmc_pebble_dispatch_tag_bool(&app, ELMC_PEBBLE_MSG_GOTHEALTHSUPPORTED, #{bool}) != 0) return #{code};"
  end

  defp emit_step({:from_phone, ctor}, code, _caps) when is_binary(ctor) do
    fn_name = TeaScenarioProtocol.builder_fn_name(ctor)

    """
      {
        ElmcValue *payload = #{fn_name}();
        if (!payload) return #{code};
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, payload) != 0) return #{code + 1};
        elmc_release(payload);
      }
    """
  end

  defp emit_step({:dispatch_button, button}, code, _caps) do
    "if (tea_dispatch_button(&app, #{button_macro(button)}) != 0) return #{code};"
  end

  defp emit_step({:cycle_msgs, :direction, count}, code, _caps) do
    """
      {
        static const elmc_int_t dir_msgs[4] = {
          ELMC_PEBBLE_MSG_LEFTPRESSED,
          ELMC_PEBBLE_MSG_RIGHTPRESSED,
          ELMC_PEBBLE_MSG_UPPRESSED,
          ELMC_PEBBLE_MSG_DOWNPRESSED
        };
        for (int i = 0; i < #{count}; i++) {
          if (elmc_pebble_dispatch_int(&app, dir_msgs[i % 4]) != 0) return #{code};
          if (tea_drain_cmds(&app) != 0) return #{code + 1};
        }
      }
    """
  end

  defp emit_step({:cycle_buttons, :direction, count}, code, _caps) do
    """
      {
        static const int32_t dir_buttons[4] = {
          ELMC_PEBBLE_BUTTON_LEFT,
          ELMC_PEBBLE_BUTTON_RIGHT,
          ELMC_PEBBLE_BUTTON_UP,
          ELMC_PEBBLE_BUTTON_DOWN
        };
        for (int i = 0; i < #{count}; i++) {
          if (tea_dispatch_button(&app, dir_buttons[i % 4]) != 0) return #{code};
        }
      }
    """
  end

  defp emit_step({:dispatch_frame, count, dt_ms}, code, _caps) do
    """
      for (int frame = 0; frame < #{count}; frame++) {
        if (elmc_pebble_dispatch_frame(&app, #{dt_ms}, #{dt_ms} * (frame + 1), frame + 1) != 0) return #{code};
      }
    """
  end

  defp emit_step(:view, _code, _caps), do: ""

  defp emit_step({:assert_view_texts, texts}, code, _caps) when is_list(texts) do
    checks =
      Enum.map_join(texts, "\n", fn text ->
        escaped = String.replace(text, "\"", "\\\"")

        """
            if (!spy_find_text("#{escaped}")) {
              printf("missing_spy_text=#{escaped}\\n");
              tea_dump_spy_texts();
              return #{code};
            }
        """
      end)

    """
      {
        ElmcSceneSdkReplayStats assert_stats = {0};
        spy_reset();
        if (tea_run_view(&app, &assert_stats) != 0) return #{code};
    #{checks}
      }
    """
  end

  defp emit_step(step, code, _caps) do
    "  /* unsupported step #{inspect(step)} */ (void)0; /* code=#{code} */"
  end
  defp button_macro(:up), do: "ELMC_PEBBLE_BUTTON_UP"
  defp button_macro(:down), do: "ELMC_PEBBLE_BUTTON_DOWN"
  defp button_macro(:left), do: "ELMC_PEBBLE_BUTTON_LEFT"
  defp button_macro(:right), do: "ELMC_PEBBLE_BUTTON_RIGHT"
  defp button_macro(:select), do: "ELMC_PEBBLE_BUTTON_SELECT"
  defp button_macro(:back), do: "ELMC_PEBBLE_BUTTON_BACK"

  defp emit_expect_checks(scenario) do
    expects = scenario.expects || %{}

    checks =
      []
      |> maybe_check(expects, :min_scene_cmds, "stats.scene_cmds < #{expects[:min_scene_cmds]}", 91)
      |> maybe_check(expects, :min_scene_text, "stats.scene_text < #{expects[:min_scene_text]}", 92)
      |> maybe_check(expects, :min_scene_fill_rect, "stats.scene_fill_rect < #{expects[:min_scene_fill_rect]}", 93)
      |> maybe_check(expects, :min_scene_fill_circle, "stats.scene_fill_circle < #{expects[:min_scene_fill_circle]}", 94)
      |> maybe_check(expects, :min_scene_circle, "(stats.scene_circle + stats.scene_fill_circle) < #{expects[:min_scene_circle]}", 95)
      |> maybe_check(expects, :min_scene_radial, "stats.scene_fill_radial < #{expects[:min_scene_radial]}", 96)
      |> maybe_check(expects, :min_spy_text, "stats.sdk_text < #{expects[:min_spy_text]}", 97)
      |> maybe_check(expects, :min_spy_fill_rect, "stats.sdk_fill_rect < #{expects[:min_spy_fill_rect]}", 98)
      |> maybe_check(expects, :min_text_align_center, "spy_text_align_count(GTextAlignmentCenter) < #{expects[:min_text_align_center]}", 99)
      |> maybe_check(
        expects,
        :min_text_full_width_center,
        "spy_text_full_width_center_count(#{Map.get(expects, :full_width_min, 80)}) < #{expects[:min_text_full_width_center]}",
        100
      )

    checks =
      if expects[:no_text_at_origin?] do
        checks ++ ["if (stats.scene_text_origin > 0) return 101;"]
      else
        checks
      end

    checks =
      if expects[:no_placeholder_time?] do
        checks ++ ["if (scene_text_is_placeholder(&app)) { printf(\"placeholder_time=1\\n\"); return 102; }"]
      else
        checks
      end

    checks =
      if expects[:require_time_text?] do
        checks ++ ["printf(\"time_text_ok=%d\\n\", stats.scene_text > 0);"]
      else
        checks
      end

    checks =
      case expects[:require_spy_texts] do
        texts when is_list(texts) and texts != [] ->
          checks ++
            Enum.map(texts, fn text ->
              escaped = String.replace(text, "\"", "\\\"")

              """
              if (!spy_find_text("#{escaped}")) {
                printf("missing_spy_text=#{escaped}\\n");
                tea_dump_spy_texts();
                return 103;
              }
              """
            end)

        _ ->
          checks
      end

    Enum.join(checks, "\n  ")
  end

  defp maybe_check(checks, expects, key, condition, code) do
    if Map.has_key?(expects, key) do
      checks ++ ["if (#{condition}) return #{code};"]
    else
      checks
    end
  end
end
