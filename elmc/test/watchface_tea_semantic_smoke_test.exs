defmodule Elmc.WatchfaceTeaSemanticSmokeTest do
  @moduledoc """
  Host TEA semantic smoke for watchfaces: init → drain time cmds → view asserts.

  Catches silent failures such as dead `update` (`--:--` forever) or degenerate
  draw geometry. One template per BEAM process (`:slow`); run via
  `./scripts/mix-test-per-template.sh test/watchface_tea_semantic_smoke_test.exs`.
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.{HostSmoke, PlanStrictTemplates, TemplateCompile}

  @moduletag :slow
  @moduletag :tea_semantic

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  @tea_profiles HostSmoke.tea_profiles(HostSmoke.templates(PlanStrictTemplates.host_smoke_names()))

  for template <- Map.keys(@tea_profiles) do
    profile = Map.fetch!(@tea_profiles, template)
    @tag template: template

    test "TEA host smoke: #{template} shows time after init cmd drain" do
      run_tea_semantic_smoke!(unquote(template), unquote(Macro.escape(profile)))
    end
  end

  defp run_tea_semantic_smoke!(template, profile) do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for watchface TEA semantic smoke")

    out_dir = Path.join(System.tmp_dir!(), "tea-smoke-#{template}-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    compile_opts = Keyword.merge(@compile_opts, out_dir: out_dir)

    assert {:ok, _result} = TemplateCompile.compile_watch_template(template, compile_opts)

    binary_name = "tea_smoke_#{template}"
    harness_path = Path.join(out_dir, "c/#{binary_name}_harness.c")
    File.write!(harness_path, tea_harness_c(template, profile))

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        binary_name,
        sources: pebble_harness_sources(out_dir, harness_path),
        rc_track: false,
        alloc_track: false
      )

    assert out =~ "rc_ok tea_semantic #{template}"
    refute out =~ "placeholder_time=1"

    if profile[:require_time?] do
      assert out =~ "time_text_ok=1"
    end

    if profile[:require_circles?] do
      assert out =~ "circle_ok=1"
    end

    if profile[:require_fill_rects?] do
      assert out =~ "fill_rect_ok=1"
    end
  end

  defp pebble_harness_sources(out_dir, harness_path) do
    [
      Path.join(out_dir, "runtime/elmc_runtime.c"),
      Path.join(out_dir, "ports/elmc_ports.c"),
      Path.join(out_dir, "c/elmc_generated.c"),
      Path.join(out_dir, "c/elmc_worker.c"),
      Path.join(out_dir, "c/elmc_pebble.c"),
      harness_path
    ]
  end

  defp tea_harness_c(template, profile) do
    require_circles? = profile[:require_circles?]
    require_fill_rects? = profile[:require_fill_rects?]
    require_time? = profile[:require_time?]

    circle_loop =
      if require_circles? do
        """
            if (cmd.kind == ELMC_PEBBLE_DRAW_FILL_CIRCLE || cmd.kind == ELMC_PEBBLE_DRAW_CIRCLE) {
              saw_circle = 1;
              if (cmd.p2 > 0) circle_ok = 1;
            }
        """
      else
        ""
      end

    fill_rect_loop =
      if require_fill_rects? do
        """
            if (cmd.kind == ELMC_PEBBLE_DRAW_FILL_RECT) {
              saw_fill_rect = 1;
              /* FILL_RECT layout: p0=x p1=y p2=w p3=h */
              if (cmd.p2 > 0 && cmd.p3 > 0) fill_rect_ok = 1;
            }
        """
      else
        ""
      end

    circle_report =
      if require_circles? do
        ~s|printf("circle_ok=%d\\n", saw_circle && circle_ok);\n|
      else
        ""
      end

    fill_rect_report =
      if require_fill_rects? do
        ~s|printf("fill_rect_ok=%d\\n", saw_fill_rect && fill_rect_ok);\n|
      else
        ""
      end

    circle_fail =
      if require_circles? do
        "if (require_circles && (!saw_circle || !circle_ok)) return 31;"
      else
        ""
      end

    fill_rect_fail =
      if require_fill_rects? do
        "if (require_fill_rects && (!saw_fill_rect || !fill_rect_ok)) return 32;"
      else
        ""
      end

    time_fail =
      if require_time? do
        "if (!time_text_ok) return 23;"
      else
        ""
      end

    """
    #include <stdio.h>
    #include <string.h>
    #include "elmc_pebble.h"

    static ElmcValue *harness_int(elmc_int_t v) {
      ElmcValue *out = NULL;
      if (elmc_new_int(&out, v) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_string(const char *s) {
      ElmcValue *out = NULL;
      if (elmc_new_string(&out, s) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *current_datetime(void) {
      ElmcValue *fields[8] = {
          harness_int(2026), harness_int(7), harness_int(1), harness_int(3),
          harness_int(10), harness_int(30), harness_int(0), harness_int(0)};
      ElmcValue *rec = NULL;
      if (elmc_record_new_values(&rec, 8, fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 8; i++) elmc_release(fields[i]);
      return rec;
    }

    static ElmcValue *launch_context(void) {
      ElmcValue *screen_width = harness_int(144);
      ElmcValue *screen_height = harness_int(168);
      ElmcValue *screen_shape = harness_int(1);
      ElmcValue *screen_color_mode = harness_int(2);
      ElmcValue *screen_values[] = {screen_width, screen_height, screen_shape, screen_color_mode};
      ElmcValue *screen = NULL;
      if (elmc_record_new_values(&screen, 4, screen_values) != RC_SUCCESS) return NULL;
      elmc_release(screen_width);
      elmc_release(screen_height);
      elmc_release(screen_shape);
      elmc_release(screen_color_mode);

      ElmcValue *reason = harness_int(2);
      ElmcValue *watch_model = harness_string("");
      ElmcValue *watch_profile_id = harness_string("flint");
      ElmcValue *has_microphone = harness_int(0);
      ElmcValue *has_compass = harness_int(0);
      ElmcValue *supports_health = harness_int(1);
      ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen,
                                      has_microphone, has_compass, supports_health};
      ElmcValue *context = NULL;
      if (elmc_record_new_values(&context, 7, context_values) != RC_SUCCESS) return NULL;
      elmc_release(reason);
      elmc_release(watch_model);
      elmc_release(watch_profile_id);
      elmc_release(has_microphone);
      elmc_release(has_compass);
      elmc_release(supports_health);
      elmc_release(screen);
      return context;
    }

    static int drain_time_cmds(ElmcPebbleApp *app) {
      for (int round = 0; round < 4; round++) {
        int progressed = 0;
        for (int j = 0; j < 16; j++) {
          ElmcPebbleCmd cmd = {0};
          if (elmc_pebble_take_cmd(app, &cmd) != 0) return 10;
          if (cmd.kind == ELMC_PEBBLE_CMD_NONE) return 0;
          progressed = 1;
    #if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_DATE_TIME
          if (cmd.kind == ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME) {
            ElmcValue *dt = current_datetime();
            if (!dt) return 11;
            if (elmc_pebble_dispatch_tag_payload(app, cmd.p0, dt) != 0) return 12;
            elmc_release(dt);
            continue;
          }
    #endif
    #if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_TIME_STRING
          if (cmd.kind == ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING) {
            if (elmc_pebble_dispatch_tag_string(app, cmd.p0, "10:30") != 0) return 13;
            continue;
          }
    #endif
        }
        if (!progressed) break;
      }
      return 0;
    }

    static int scene_semantics_ok(ElmcPebbleApp *app, int require_circles, int require_fill_rects) {
      if (elmc_pebble_ensure_scene(app) != 0) return 20;
      int placeholder_time = 0;
      int time_text_ok = 0;
      int saw_circle = 0;
      int circle_ok = 0;
      int saw_fill_rect = 0;
      int fill_rect_ok = 0;
      int byte_offset = 0;
      while (byte_offset < app->scene.byte_count) {
        ElmcPebbleDrawCmd cmd = {0};
        if (elmc_pebble_scene_decode_record(app->scene.bytes, app->scene.byte_count, &byte_offset, &cmd) != 0) {
          return 21;
        }
        if (cmd.kind == ELMC_PEBBLE_DRAW_TEXT || cmd.kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT) {
          if (strncmp(cmd.text, "--:--", sizeof(cmd.text)) == 0) placeholder_time = 1;
          if (strstr(cmd.text, "10:30") != NULL) time_text_ok = 1;
        }
    #{circle_loop}
    #{fill_rect_loop}
      }
      printf("placeholder_time=%d\\n", placeholder_time);
      printf("time_text_ok=%d\\n", time_text_ok);
    #{circle_report}
    #{fill_rect_report}
      if (placeholder_time) return 22;
    #{time_fail}
    #{circle_fail}
    #{fill_rect_fail}
      return 0;
    }

    int main(void) {
      const int require_circles = #{if require_circles?, do: 1, else: 0};
      const int require_fill_rects = #{if require_fill_rects?, do: 1, else: 0};
      ElmcPebbleApp app = {0};
      ElmcValue *flags = launch_context();
      if (!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 2;
      elmc_release(flags);

      int drain_rc = drain_time_cmds(&app);
      if (drain_rc != 0) return drain_rc;

      ElmcPebbleDrawCmd view_cmds[8] = {0};
      if (elmc_pebble_view_commands(&app, view_cmds, 8) < 1) return 24;

      int sem_rc = scene_semantics_ok(&app, require_circles, require_fill_rects);
      if (sem_rc != 0) return sem_rc;

      elmc_pebble_deinit(&app);
      printf("rc_ok tea_semantic #{template}\\n");
      return 0;
    }
    """
  end
end
