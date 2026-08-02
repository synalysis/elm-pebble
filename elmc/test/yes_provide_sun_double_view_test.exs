defmodule Elmc.YesProvideSunDoubleViewTest do
  @moduledoc """
  Host gate: ProvideSun / MinuteChanged cycles must not double-free.

  Regressions:
  - Maybe.withDefault retain-drop on borrowed Just payloads in drawDial
  - TickSpec.minute index used for CurrentDateTime.minute (year overwrite)
  - scheduleCompanionFetches cow_drop releasing borrowed model (2nd MinuteChanged)
  - record_get into owned[] without retain → epilogue frees model fields (3rd tick / view)
  """

  use ExUnit.Case, async: false

  @moduletag :slow
  @moduletag :rc_track

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.TemplateCompile

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: false,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  test "watchface_yes ProvideSun + repeated MinuteChanged survives without double free" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc missing")

    out_dir = Path.join(System.tmp_dir!(), "yes-sun-x2-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)
    assert {:ok, _} = TemplateCompile.compile_watch_template("watchface_yes", Keyword.put(@compile_opts, :out_dir, out_dir))

    harness_path = Path.join(out_dir, "c/yes_provide_sun_x2_harness.c")
    File.write!(harness_path, harness_c())
    RcTrackHarness.write_trig_stubs!(out_dir)

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        "yes_provide_sun_x2",
        sources:
          RcTrackHarness.pebble_harness_sources(out_dir, harness_path, [
            Path.join(out_dir, "c/pebble_trig_host_stubs.c")
          ]),
        extra_flags: ["-include", Path.join(out_dir, "c/pebble_trig_host_stubs.h")],
        rc_track: true,
        alloc_track: false
      )

    assert out =~ "rc_ok yes provide sun x2"
    refute out =~ "Double free"
    refute out =~ "malloc():"
  end

  defp harness_c do
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
    static ElmcValue *harness_tuple2_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      if (elmc_tuple2_take(&out, a, b) != RC_SUCCESS) return NULL;
      return out;
    }
    static ElmcValue *harness_phone_union(elmc_int_t tag, ElmcValue *payload) {
      return harness_tuple2_take(harness_int(tag), payload);
    }
    static ElmcValue *provide_sun(elmc_int_t sunrise, elmc_int_t sunset) {
      ElmcValue *payload = harness_tuple2_take(
          harness_int(sunrise),
          harness_tuple2_take(harness_int(sunset), harness_int(1)));
      return harness_phone_union(2, payload);
    }
    static ElmcValue *current_datetime(void) {
      ElmcValue *fields[8] = {
          harness_int(2026), harness_int(8), harness_int(2), harness_int(3),
          harness_int(10), harness_int(30), harness_int(0), harness_int(0)};
      ElmcValue *rec = NULL;
      if (elmc_record_new_values(&rec, 8, fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 8; i++) elmc_release(fields[i]);
      return rec;
    }
    static ElmcValue *launch_context(void) {
      ElmcValue *screen_fields[4] = {harness_int(200), harness_int(228), harness_int(1), harness_int(2)};
      ElmcValue *screen = NULL;
      if (elmc_record_new_values(&screen, 4, screen_fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 4; i++) elmc_release(screen_fields[i]);
      ElmcValue *ctx_fields[7] = {
          harness_int(2), harness_string(""), harness_string("emery"),
          screen, harness_int(1), harness_int(0), harness_int(1)
      };
      ElmcValue *ctx = NULL;
      if (elmc_record_new_values(&ctx, 7, ctx_fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 7; i++) if (i != 3) elmc_release(ctx_fields[i]);
      elmc_release(screen);
      return ctx;
    }
    static int view_once(ElmcPebbleApp *app) {
      ElmcPebbleDrawCmd cmds[64] = {0};
      return elmc_pebble_view_commands(app, cmds, 64);
    }
    static int drain(ElmcPebbleApp *app) {
      for (int round=0; round<8; round++) {
        int progressed=0;
        for (int j=0;j<32;j++) {
          ElmcPebbleCmd cmd={0};
          if (elmc_pebble_take_cmd(app,&cmd)!=0) return 10;
          if (cmd.kind==ELMC_PEBBLE_CMD_NONE) return 0;
          progressed=1;
    #if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_DATE_TIME
          if (cmd.kind==ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME) {
            ElmcValue *dt=current_datetime();
            if(!dt) return 11;
            if (elmc_pebble_dispatch_tag_payload(app, cmd.p0, dt)!=0) {
              elmc_release(dt);
              return 12;
            }
            elmc_release(dt);
            continue;
          }
    #endif
        }
        if(!progressed) break;
      }
      return 0;
    }
    int main(void) {

      ElmcPebbleApp app = {0};
      ElmcValue *flags = launch_context();
      if (!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 2;
      elmc_release(flags);
      int dr = drain(&app); if (dr) return dr;
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_MINUTECHANGED, 31) != 0) return 40;
      if (view_once(&app) < 1) return 50;
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_MINUTECHANGED, 32) != 0) return 41;
      if (view_once(&app) < 1) return 51;
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_MINUTECHANGED, 33) != 0) return 42;
      if (view_once(&app) < 1) return 52;

      elmc_pebble_deinit(&app);
      printf("rc_ok yes provide sun x2\\n");
      return 0;
    }
    """
  end
end
