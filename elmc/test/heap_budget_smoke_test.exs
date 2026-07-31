defmodule Elmc.HeapBudgetSmokeTest do
  @moduledoc """
  Host heap-budget smoke for reference templates.

  Uses `ELMC_ALLOC_TRACK` live counts at init/drain/view phases as a RAM-pressure
  proxy (Pebble `heap_bytes_free` is device-only). Host builds set `pebble_int32:
  false` so heap-owned `owned[]` frames stay on the stack and compile with alloc
  track enabled.
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :heap_budget

  @templates ~w(watchface_yes game_2048)
  @compile_opts [
    codegen_profile: :size,
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: false,
    prune_native_wrappers: true,
    pebble_int32: false
  ]

  for template <- @templates do
    @tag template: template

    test "heap budget smoke reports alloc phases for #{template}" do
      template = unquote(template)
      cc = System.find_executable("cc")
      if is_nil(cc), do: flunk("cc not available for heap budget smoke")

      out_dir = Path.join(System.tmp_dir!(), "heap-budget-#{template}-#{System.unique_integer([:positive])}")
      File.rm_rf!(out_dir)

      assert {:ok, _result} =
               TemplateCompile.compile_watch_template(template, Keyword.merge(@compile_opts, out_dir: out_dir))

      binary_name = "heap_budget_#{template}"
      harness_path = Path.join(out_dir, "c/#{binary_name}_harness.c")
      File.write!(harness_path, heap_harness_c(template))

      out =
        RcTrackHarness.run_harness!(
          out_dir,
          harness_path,
          binary_name,
          sources: pebble_harness_sources(out_dir, harness_path),
          rc_track: false,
          alloc_track: true
        )

      assert out =~ "heap_budget_ok #{template}"
      assert out =~ "phase=init:end live="
      assert out =~ "phase=drain:end live="
      assert out =~ "phase=view:end live="
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

  defp heap_harness_c("game_2048") do
    """
    #include "elmc_pebble.h"
    #include <stdio.h>

    #{RcTrackHarness.harness_rc_helpers()}

    static void log_phase(const char *phase) {
    #if ELMC_ALLOC_TRACK
      printf("phase=%s live=%u\\n", phase, elmc_alloc_track_live_count());
    #else
      printf("phase=%s live=0\\n", phase);
    #endif
    }

    static ElmcValue *launch_context(void) {
      ElmcValue *reason = elmc_harness_new_int(2);
      ElmcValue *watch_model = elmc_harness_new_string("");
      ElmcValue *watch_profile_id = elmc_harness_new_string("aplite");
      ElmcValue *width = elmc_harness_new_int(144);
      ElmcValue *height = elmc_harness_new_int(168);
      ElmcValue *shape = elmc_harness_new_int(1);
      ElmcValue *color_mode = elmc_harness_new_int(1);
      ElmcValue *screen_values[] = {width, height, shape, color_mode};
      ElmcValue *screen = elmc_harness_record_new_values_take(4, screen_values);
      ElmcValue *has_microphone = elmc_harness_new_int(0);
      ElmcValue *has_compass = elmc_harness_new_int(0);
      ElmcValue *supports_health = elmc_harness_new_int(0);
      ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen,
                                      has_microphone, has_compass, supports_health};
      return elmc_harness_record_new_values_take(7, context_values);
    }

    static void drain_init_cmds(ElmcPebbleApp *app) {
      for (int j = 0; j < 8; j++) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_pebble_take_cmd(app, &cmd) != 0) break;
        if (cmd.kind == ELMC_PEBBLE_CMD_NONE) break;
        if (cmd.kind == ELMC_PEBBLE_CMD_RANDOM_GENERATE) {
          elmc_pebble_dispatch_tag_value(app, cmd.p0, 42);
        }
        if (cmd.kind == ELMC_PEBBLE_CMD_STORAGE_READ_STRING) {
          elmc_pebble_dispatch_tag_string(app, cmd.p1, "");
        }
      }
    }

    int main(void) {
    #if ELMC_ALLOC_TRACK
      elmc_alloc_track_reset();
    #endif

      ElmcPebbleApp app = {0};
      ElmcValue *context = launch_context();
      if (!context) return 1;
      if (elmc_pebble_init(&app, context) != 0) return 1;
      elmc_release(context);
      log_phase("init:end");

      drain_init_cmds(&app);
      log_phase("drain:end");

      if (elmc_pebble_dispatch_int(&app, ELMC_PEBBLE_MSG_UPPRESSED) != 0) return 2;

      app.scene.dirty = 1;
      if (elmc_pebble_ensure_scene(&app) != 0) return 3;
      ElmcPebbleDrawCmd cmds[32] = {0};
      (void)elmc_pebble_view_commands_from(&app, cmds, 32, 0);
      log_phase("view:end");

      elmc_pebble_deinit(&app);
      printf("heap_budget_ok game_2048\\n");
      return 0;
    }
    """
  end

  defp heap_harness_c("watchface_yes") do
    """
    #include "elmc_pebble.h"
    #include <stdio.h>
    #include <string.h>

    #{RcTrackHarness.harness_rc_helpers()}

    static ElmcValue *current_datetime(void) {
      const char *names[] = {"year", "month", "day", "hour", "minute", "second", "weekday", "is24h"};
      ElmcValue *values[] = {
        elmc_harness_new_int(2026), elmc_harness_new_int(7), elmc_harness_new_int(31),
        elmc_harness_new_int(10), elmc_harness_new_int(30), elmc_harness_new_int(0),
        elmc_harness_new_int(5), elmc_harness_new_int(1)
      };
      return elmc_harness_record_new_take(8, names, values);
    }

    static void log_phase(const char *phase) {
    #if ELMC_ALLOC_TRACK
      printf("phase=%s live=%u\\n", phase, elmc_alloc_track_live_count());
    #else
      printf("phase=%s live=0\\n", phase);
    #endif
    }

    static ElmcValue *launch_context(void) {
      ElmcValue *reason = elmc_harness_new_int(2);
      ElmcValue *watch_model = elmc_harness_new_string("");
      ElmcValue *watch_profile_id = elmc_harness_new_string("flint");
      ElmcValue *width = elmc_harness_new_int(144);
      ElmcValue *height = elmc_harness_new_int(168);
      ElmcValue *shape = elmc_harness_new_int(1);
      ElmcValue *color_mode = elmc_harness_new_int(1);
      ElmcValue *screen_values[] = {width, height, shape, color_mode};
      ElmcValue *screen = elmc_harness_record_new_values_take(4, screen_values);
      ElmcValue *has_microphone = elmc_harness_new_int(0);
      ElmcValue *has_compass = elmc_harness_new_int(0);
      ElmcValue *supports_health = elmc_harness_new_int(0);
      ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen,
                                      has_microphone, has_compass, supports_health};
      return elmc_harness_record_new_values_take(7, context_values);
    }

    static void drain_init_cmds(ElmcPebbleApp *app) {
      for (int round = 0; round < 4; round++) {
        int progressed = 0;
        for (int j = 0; j < 16; j++) {
          ElmcPebbleCmd cmd = {0};
          if (elmc_pebble_take_cmd(app, &cmd) != 0) return;
          if (cmd.kind == ELMC_PEBBLE_CMD_NONE) return;
          progressed = 1;
    #if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_DATE_TIME
          if (cmd.kind == ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME) {
            ElmcValue *dt = current_datetime();
            if (dt) {
              elmc_pebble_dispatch_tag_payload(app, cmd.p0, dt);
              elmc_release(dt);
            }
            continue;
          }
    #endif
    #if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_TIME_STRING
          if (cmd.kind == ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING) {
            elmc_pebble_dispatch_tag_string(app, cmd.p0, "10:30");
            continue;
          }
    #endif
        }
        if (!progressed) break;
      }
    }

    int main(void) {
    #if ELMC_ALLOC_TRACK
      elmc_alloc_track_reset();
    #endif

      ElmcPebbleApp app = {0};
      ElmcValue *context = launch_context();
      if (!context) return 1;
      if (elmc_pebble_init_with_mode(&app, context, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 1;
      elmc_release(context);
      log_phase("init:end");

      drain_init_cmds(&app);
      log_phase("drain:end");

      ElmcPebbleDrawCmd view_cmds[8] = {0};
      if (elmc_pebble_view_commands(&app, view_cmds, 8) < 1) return 2;
      log_phase("view:end");

      elmc_pebble_deinit(&app);
      printf("heap_budget_ok watchface_yes\\n");
      return 0;
    }
    """
  end

  defp heap_harness_c(template), do: raise("unsupported template #{template}")
end
