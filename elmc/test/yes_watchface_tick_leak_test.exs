defmodule Elmc.YesWatchfaceTickLeakTest do
  use Elmc.TestSupport.PrimaryCodegenCase, async: false

  alias Elmc.Test.{CCodegenExtract, RcTrackHarness}

  @source_template Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)
  @ide_dir Path.expand("../../ide", __DIR__)
  @project_dir Path.expand("tmp/yes_watchface_tick_leak_project", __DIR__)
  @out_dir Path.expand("tmp/yes_watchface_tick_leak_codegen", __DIR__)

  @compile_opts [
    strip_dead_code: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true,
    prod: false
  ]

  test "300 no-op SecondChanged dispatches stay alloc-balanced on round gabbro" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for yes watchface tick leak harness")

    File.rm_rf!(@project_dir)
    File.rm_rf!(@out_dir)
    File.cp_r!(@source_template, @project_dir)

    File.write!(
      Path.join(@project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "protocol/src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3", "elm/time" => "1.0.0"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    types_path = Path.join(@project_dir, "protocol/src/Companion/Types.elm")
    internal_path = Path.join(@project_dir, "protocol/src/Companion/Internal.elm")

    {gen_out, gen_code} =
      System.cmd(
        "mix",
        [
          "run",
          "-e",
          "Ide.CompanionProtocolGenerator.generate_elm_internal(\"#{types_path}\", \"#{internal_path}\")"
        ],
        cd: @ide_dir,
        stderr_to_stdout: true
      )

    assert gen_code == 0, "companion Internal generation failed:\n#{gen_out}"
    assert File.exists?(internal_path)

    RcTrackHarness.compile!(@project_dir, @out_dir, Keyword.merge(@compile_opts, entry_module: "Main"))

    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    temp_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_temperatureString")

    assert temp_body =~ "case_msg_tag_"
    refute temp_body =~ "elmc_fn_Main_c10"
    refute temp_body =~ "elmc_fn_Main_f10"

    sun_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Yes_Render_defaultSunWindow")
    refute sun_body =~ "elmc_fn_Main_SunCycle"
    assert sun_body =~ "elmc_record_new_values_take"

    top_left_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_topLeftSlots")
    refute top_left_body =~ "elmc_new_bool(&tmp_"
    assert top_left_body =~ "elmc_record_new_values_take"
    assert top_left_body =~ "topLeftBatteryAvailable"

    next_event_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nextEventParts")
    refute next_event_body =~ "ELMC_RELEASE(owned["
    refute next_event_body =~ "__cmp_bool_"
    assert next_event_body =~ "plan_native_bool_"

    write_trig_stubs!(@out_dir)
    harness_path = Path.join(@out_dir, "c/yes_watchface_tick_leak_harness.c")
    File.write!(harness_path, tick_harness_c())

    out =
      RcTrackHarness.run_harness!(
        @out_dir,
        harness_path,
        "yes_watchface_tick_leak",
        sources: pebble_harness_sources(@out_dir, harness_path),
        extra_flags: ["-DPBL_ROUND", "-include", Path.join(@out_dir, "c/pebble_trig_host_stubs.h")],
        alloc_probe: false,
        rc_track: false,
        alloc_track: false
      )

    assert out =~ "yes_tick_probe ticks=300 leaks=0"
    assert out =~ "rc_ok yes watchface tick leak"
  end

  defp write_trig_stubs!(out_dir) do
    File.write!(
      Path.join(out_dir, "c/pebble_trig_host_stubs.h"),
      """
      #ifndef PEBBLE_TRIG_HOST_STUBS_H
      #define PEBBLE_TRIG_HOST_STUBS_H
      #include <stdint.h>
      #ifndef TRIG_MAX_RATIO
      #define TRIG_MAX_RATIO 16384
      #endif
      int32_t sin_lookup(int32_t angle);
      int32_t cos_lookup(int32_t angle);
      #endif
      """
    )

    File.write!(
      Path.join(out_dir, "c/pebble_trig_host_stubs.c"),
      """
      #include <math.h>
      #include "pebble_trig_host_stubs.h"
      int32_t sin_lookup(int32_t angle) {
        double rad = (double)angle * 2.0 * 3.141592653589793 / 65536.0;
        return (int32_t)(sin(rad) * (double)TRIG_MAX_RATIO);
      }
      int32_t cos_lookup(int32_t angle) {
        double rad = (double)angle * 2.0 * 3.141592653589793 / 65536.0;
        return (int32_t)(cos(rad) * (double)TRIG_MAX_RATIO);
      }
      """
    )
  end

  defp pebble_harness_sources(out_dir, harness_path) do
    [
      Path.join(out_dir, "runtime/elmc_runtime.c"),
      Path.join(out_dir, "ports/elmc_ports.c"),
      Path.join(out_dir, "c/elmc_generated.c"),
      Path.join(out_dir, "c/elmc_worker.c"),
      Path.join(out_dir, "c/elmc_pebble.c"),
      Path.join(out_dir, "c/pebble_trig_host_stubs.c"),
      harness_path
    ]
  end

  defp tick_harness_c do
    """
    #include <stdio.h>
    #include "elmc_pebble.h"

    static ElmcValue *harness_int(elmc_int_t v) {
      ElmcValue *out = NULL;
      if (elmc_new_int(&out, v) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_bool(bool v) {
      ElmcValue *out = NULL;
      if (elmc_new_bool(&out, v ? 1 : 0) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_string(const char *s) {
      ElmcValue *out = NULL;
      if (elmc_new_string(&out, s) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_tuple2_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      if (elmc_tuple2_take(&out, a, b) != RC_SUCCESS) return NULL;
      return out;
    }

    static ElmcValue *harness_union_int(elmc_int_t tag, elmc_int_t value) {
      return harness_tuple2_take(harness_int(tag), harness_int(value));
    }

    static ElmcValue *harness_phone_union(elmc_int_t tag, ElmcValue *payload) {
      return harness_tuple2_take(harness_int(tag), payload);
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

    static ElmcValue *provide_sun(void) {
      ElmcValue *payload = harness_tuple2_take(
          harness_int(360),
          harness_tuple2_take(harness_int(1080), harness_int(1)));
      return harness_phone_union(2, payload);
    }

    static ElmcValue *provide_weather(void) {
      ElmcValue *payload = harness_tuple2_take(
          harness_union_int(1, 210),
          harness_tuple2_take(
              harness_int(1),
              harness_tuple2_take(
                  harness_int(0),
                  harness_tuple2_take(harness_int(0), harness_int(1013)))));
      return harness_phone_union(5, payload);
    }

    static ElmcValue *gabbro_launch_context(void) {
      ElmcValue *screen_fields[4] = {harness_int(260), harness_int(260), harness_int(1), harness_int(2)};
      ElmcValue *screen = NULL;
      if (elmc_record_new_values(&screen, 4, screen_fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 4; i++) elmc_release(screen_fields[i]);

      ElmcValue *ctx_fields[7] = {
          harness_int(2),
          harness_string(""),
          harness_string("gabbro"),
          screen,
          harness_bool(true),
          harness_bool(false),
          harness_bool(true)
      };
      ElmcValue *ctx = NULL;
      if (elmc_record_new_values(&ctx, 7, ctx_fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 7; i++) {
        if (i != 3) elmc_release(ctx_fields[i]);
      }
      elmc_release(screen);
      return ctx;
    }

    static int drain_view(ElmcPebbleApp *app) {
      ElmcPebbleDrawCmd cmds[64] = {0};
      return elmc_pebble_view_commands(app, cmds, 64);
    }

    static int probe_second_tick(ElmcPebbleApp *app, int second, int tick_idx) {
      int was_dirty = app->scene.dirty;
      if (elmc_pebble_dispatch_tag_value(app, ELMC_PEBBLE_MSG_SECONDCHANGED, second) != 0) return 1;
      if (app->scene.dirty != was_dirty) return 4;
      if (drain_view(app) < 0) return 2;
      (void)tick_idx;
      (void)second;
      return 0;
    }

    int main(void) {
      enum { TICK_COUNT = 300 };

      ElmcPebbleApp app = {0};
      ElmcValue *flags = gabbro_launch_context();
      if (!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 2;
      elmc_release(flags);

      if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_CURRENTDATETIME, current_datetime()) != 0) return 3;
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_BATTERYLEVELCHANGED, 80) != 0) return 4;
      if (elmc_pebble_dispatch_tag_bool(&app, ELMC_PEBBLE_MSG_CONNECTIONCHANGED, 1) != 0) return 5;
      if (elmc_pebble_dispatch_tag_bool(&app, ELMC_PEBBLE_MSG_GOTHEALTHSUPPORTED, 1) != 0) return 6;
      if (drain_view(&app) < 2) return 10;
      if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, provide_sun()) != 0) return 7;
      if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, provide_weather()) != 0) return 8;
      if (drain_view(&app) < 2) return 11;

      int leaks = 0;
      for (int i = 0; i < TICK_COUNT; i++) {
        int second = (i % 58) + 1;
        if (second % 5 == 0) continue;
        int rc = probe_second_tick(&app, second, i);
        if (rc != 0) {
          fprintf(stderr, "tick probe failed idx=%d second=%d code=%d\\n", i, second, rc);
          leaks += 1;
          if (leaks >= 5) break;
        }
      }

      elmc_pebble_deinit(&app);

      if (leaks > 0) {
        fprintf(stderr, "yes_tick_probe leaks=%d\\n", leaks);
        return 1;
      }

      printf("yes_tick_probe ticks=%d leaks=%d\\n", TICK_COUNT, leaks);
      printf("rc_ok yes watchface tick leak\\n");
      return 0;
    }
    """
  end
end
