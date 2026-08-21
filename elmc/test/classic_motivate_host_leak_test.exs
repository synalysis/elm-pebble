defmodule Elmc.ClassicMotivateHostLeakTest do
  @moduledoc """
  Alloc/RC soak for Classic Motivate: init, time, storage, companion settings,
  phase ticks, and deinit must stay alloc-flat and empty after teardown.
  """

  use Elmc.TestSupport.PrimaryCodegenCase, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.TemplateCompile

  @compile_opts [
    codegen_profile: :size,
    direct_render_only: true,
    prune_runtime: false,
    prune_native_wrappers: true,
    pebble_int32: true,
    strip_dead_code: true,
    prod: true,
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    entry_module: "Main"
  ]

  @moduletag timeout: 300_000

  test "classic motivate stays alloc-balanced across time, storage, and phone settings" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for classic motivate leak harness")

    out_dir =
      Path.join(System.tmp_dir!(), "classic-motivate-leak-#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)

    assert {:ok, _} =
             TemplateCompile.compile_watch_template(
               "watchface_classic_motivate",
               Keyword.merge(@compile_opts, out_dir: out_dir)
             )

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated =~ "elmc_as_int(fallback)"
    refute generated =~ ~r/\? fallback :/

    RcTrackHarness.write_trig_stubs!(out_dir)
    harness_path = Path.join(out_dir, "c/classic_motivate_host_leak_harness.c")
    File.write!(harness_path, leak_harness_c())

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        "classic_motivate_host_leak",
        sources: [
          Path.join(out_dir, "runtime/elmc_runtime.c"),
          Path.join(out_dir, "ports/elmc_ports.c"),
          Path.join(out_dir, "c/elmc_generated.c"),
          Path.join(out_dir, "c/elmc_worker.c"),
          Path.join(out_dir, "c/elmc_pebble.c"),
          Path.join(out_dir, "c/pebble_trig_host_stubs.c"),
          harness_path
        ],
        extra_flags: ["-include", Path.join(out_dir, "c/pebble_trig_host_stubs.h")],
        alloc_probe: false,
        rc_track: true,
        alloc_track: true
      )

    assert out =~ "first_minute_alloc_delta=0"
    assert out =~ "settings_flood_alloc_delta=0"
    assert out =~ "classic_motivate_leak_probe ticks="
    assert out =~ "alloc_delta=0"
    assert out =~ "live_deinited=0"
    assert out =~ "rc_ok classic motivate host leak"
  end

  defp leak_harness_c do
    """
    #include <stdio.h>
    #include "elmc_pebble.h"

    #{RcTrackHarness.harness_rc_helpers()}

    static ElmcValue *current_datetime(int hour, int minute, int second) {
      const char *names[] = {"year", "month", "day", "dayOfWeek", "hour", "minute", "second", "utcOffsetMinutes"};
      ElmcValue *values[] = {
        elmc_harness_new_int(2026), elmc_harness_new_int(8), elmc_harness_new_int(19),
        elmc_harness_new_int(3), elmc_harness_new_int(hour), elmc_harness_new_int(minute),
        elmc_harness_new_int(second), elmc_harness_new_int(0)
      };
      return elmc_harness_record_new_take(8, names, values);
    }

    static ElmcValue *basalt_launch_context(void) {
      ElmcValue *reason = elmc_harness_new_int(2);
      ElmcValue *watch_model = elmc_harness_new_string("");
      ElmcValue *watch_profile_id = elmc_harness_new_string("basalt");
      ElmcValue *width = elmc_harness_new_int(144);
      ElmcValue *height = elmc_harness_new_int(168);
      ElmcValue *shape = elmc_harness_new_int(1);
      ElmcValue *color_mode = elmc_harness_new_int(2);
      ElmcValue *screen_values[] = {width, height, shape, color_mode};
      ElmcValue *screen = elmc_harness_record_new_values_take(4, screen_values);
      ElmcValue *has_microphone = elmc_harness_new_bool(1);
      ElmcValue *has_compass = elmc_harness_new_bool(0);
      ElmcValue *supports_health = elmc_harness_new_bool(1);
      ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen,
                                      has_microphone, has_compass, supports_health};
      return elmc_harness_record_new_values_take(7, context_values);
    }

    /* PhoneToWatch tags = Companion.Types declaration order. */
    enum {
      PHONE_SET_MOTIVATIONAL_TEXT = 1,
      PHONE_SET_WATCH_DISPLAY_SECONDS = 2,
      PHONE_SET_QUOTE_DISPLAY_SECONDS = 3
    };

    static ElmcValue *phone_union(int tag, ElmcValue *payload) {
      return elmc_harness_tuple2_take(elmc_harness_new_int(tag), payload);
    }

    static int drain_view(ElmcPebbleApp *app) {
      ElmcPebbleDrawCmd cmds[96] = {0};
      return elmc_pebble_view_commands(app, cmds, 96);
    }

    static void drain_cmds(ElmcPebbleApp *app, int max_cmds) {
      for (int j = 0; j < max_cmds; j++) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_pebble_take_cmd(app, &cmd) != 0 || cmd.kind == ELMC_PEBBLE_CMD_NONE) break;
    #if ELMC_PEBBLE_FEATURE_CMD_GET_CURRENT_DATE_TIME
        if (cmd.kind == ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME) {
          ElmcValue *dt = current_datetime(10, 30, 0);
          if (dt) {
            elmc_pebble_dispatch_tag_payload(app, cmd.p0, dt);
            elmc_release(dt);
          }
        }
    #endif
    #if ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_INT
        if (cmd.kind == ELMC_PEBBLE_CMD_STORAGE_READ_INT) {
          elmc_pebble_dispatch_tag_value(app, cmd.p1, 7);
        }
    #endif
    #if ELMC_PEBBLE_FEATURE_CMD_STORAGE_READ_STRING
        if (cmd.kind == ELMC_PEBBLE_CMD_STORAGE_READ_STRING) {
          elmc_pebble_dispatch_tag_string(app, cmd.p1, "Stay the course.");
        }
    #endif
        elmc_pebble_cmd_release_value(&cmd);
      }
    }

    static int dispatch_phone(ElmcPebbleApp *app, ElmcValue *msg) {
      if (!msg) return 1;
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_FROMPHONE, msg);
      elmc_release(msg);
      return rc;
    }

    int main(void) {
      enum { TICK_COUNT = 120 };

    #if ELMC_ALLOC_TRACK
      elmc_alloc_track_reset();
    #endif
    #if ELMC_RC_TRACK
      elmc_rc_track_reset();
    #endif

      ElmcPebbleApp app = {0};
      ElmcValue *flags = basalt_launch_context();
      if (!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 2;
      elmc_release(flags);

      drain_cmds(&app, 16);

      {
        ElmcValue *dt = current_datetime(10, 30, 0);
        if (!dt) return 3;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_CURRENTDATETIME, dt) != 0) {
          elmc_release(dt);
          return 3;
        }
        elmc_release(dt);
      }
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_LOADEDWATCHSECONDS, 8) != 0) return 4;
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_LOADEDQUOTESECONDS, 4) != 0) return 5;
      if (elmc_pebble_dispatch_tag_string(&app, ELMC_PEBBLE_MSG_LOADEDQUOTETEXT, "Make today count.") != 0) {
        return 6;
      }
      if (drain_view(&app) < 1) return 10;
      drain_cmds(&app, 16);

      if (dispatch_phone(&app, phone_union(PHONE_SET_MOTIVATIONAL_TEXT,
                                          elmc_harness_new_string("Keep going."))) != 0) {
        return 7;
      }
      if (dispatch_phone(&app, phone_union(PHONE_SET_WATCH_DISPLAY_SECONDS,
                                          elmc_harness_new_int(6))) != 0) {
        return 8;
      }
      if (dispatch_phone(&app, phone_union(PHONE_SET_QUOTE_DISPLAY_SECONDS,
                                          elmc_harness_new_int(3))) != 0) {
        return 9;
      }
      if (drain_view(&app) < 1) return 11;
      drain_cmds(&app, 16);

    #if ELMC_ALLOC_TRACK
      uint32_t live_before_first_minute = elmc_alloc_track_live_count();
    #else
      uint32_t live_before_first_minute = 0;
    #endif
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_MINUTECHANGED, 31) != 0) return 12;
      if (drain_view(&app) < 0) return 13;
      drain_cmds(&app, 16);

    #if ELMC_ALLOC_TRACK
      uint32_t live_before = elmc_alloc_track_live_count();
    #else
      uint32_t live_before = 0;
    #endif
      int32_t first_minute_alloc_delta = (int32_t)live_before - (int32_t)live_before_first_minute;
      if (first_minute_alloc_delta != 0) {
        fprintf(stderr, "alloc leak/growth on first MinuteChanged: delta=%d\\n", (int)first_minute_alloc_delta);
        elmc_alloc_track_dump_live(stderr);
      }
      printf("first_minute_alloc_delta=%d\\n", (int)first_minute_alloc_delta);
      if (first_minute_alloc_delta != 0) return 23;

      /* Same settings each pass: quote/wrap reshape is not a leak, but a
       * repeated identity update must stay alloc-flat. */
      for (int flood = 0; flood < 12; flood++) {
        if (dispatch_phone(&app, phone_union(PHONE_SET_MOTIVATIONAL_TEXT,
                                            elmc_harness_new_string("Keep going."))) != 0) {
          return 30;
        }
        if (dispatch_phone(&app, phone_union(PHONE_SET_WATCH_DISPLAY_SECONDS,
                                            elmc_harness_new_int(6))) != 0) {
          return 31;
        }
        if (dispatch_phone(&app, phone_union(PHONE_SET_QUOTE_DISPLAY_SECONDS,
                                            elmc_harness_new_int(3))) != 0) {
          return 32;
        }
        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_HOURCHANGED, 10) != 0) {
          return 33;
        }
        drain_cmds(&app, 8);
        if (drain_view(&app) < 0) return 34;
        drain_cmds(&app, 8);
      }

    #if ELMC_ALLOC_TRACK
      uint32_t live_after_flood = elmc_alloc_track_live_count();
      int32_t flood_alloc_delta = (int32_t)live_after_flood - (int32_t)live_before;
      if (flood_alloc_delta != 0) {
        fprintf(stderr, "alloc leak/growth across settings/hour flood: delta=%d\\n",
                (int)flood_alloc_delta);
        elmc_alloc_track_dump_live(stderr);
      }
      printf("settings_flood_alloc_delta=%d\\n", (int)flood_alloc_delta);
      if (flood_alloc_delta != 0) return 41;
      live_before = live_after_flood;
    #endif

      int failures = 0;
      int ticks = 0;
      for (int i = 0; i < TICK_COUNT; i++) {
        int second = i % 60;
        ticks += 1;
        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_SECONDCHANGED, second) != 0) {
          fprintf(stderr, "dispatch failed second=%d\\n", second);
          failures += 1;
          break;
        }
        if (drain_view(&app) < 0) {
          fprintf(stderr, "view drain failed second=%d\\n", second);
          failures += 1;
          break;
        }
        if (second == 0 || second == 30) {
          int minute = 12 + (i % 7);
          if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_MINUTECHANGED, minute) != 0) {
            fprintf(stderr, "minute dispatch failed minute=%d\\n", minute);
            failures += 1;
            break;
          }
          if (drain_view(&app) < 0) {
            fprintf(stderr, "view drain failed after minute=%d\\n", minute);
            failures += 1;
            break;
          }
        }
        drain_cmds(&app, 8);
      }

    #if ELMC_ALLOC_TRACK
      uint32_t live_after = elmc_alloc_track_live_count();
      int32_t alloc_delta = (int32_t)live_after - (int32_t)live_before;
      if (alloc_delta != 0) {
        fprintf(stderr, "alloc leak/growth across steady-state ticks: delta=%d\\n", (int)alloc_delta);
        elmc_alloc_track_dump_live(stderr);
      }
    #else
      uint32_t live_after = 0;
      int32_t alloc_delta = 0;
    #endif

      elmc_pebble_deinit(&app);

    #if ELMC_ALLOC_TRACK
      uint32_t live_deinited = elmc_alloc_track_live_count();
    #else
      uint32_t live_deinited = 0;
    #endif

      printf("classic_motivate_leak_probe ticks=%d failures=%d live_before=%u live_after=%u alloc_delta=%d live_deinited=%u\\n",
             ticks, failures, live_before, live_after, (int)alloc_delta, live_deinited);

      if (failures != 0) return 20;
      if (alloc_delta != 0) return 21;
      if (live_deinited != 0) {
        fprintf(stderr, "allocs still live after deinit: %u\\n", live_deinited);
    #if ELMC_ALLOC_TRACK
        elmc_alloc_track_dump_live(stderr);
    #endif
        return 22;
      }
    #if ELMC_RC_TRACK
      if (!elmc_rc_track_check_balanced()) {
        fprintf(stderr, "rc track unbalanced after deinit\\n");
        return 25;
      }
    #endif

      printf("rc_ok classic motivate host leak\\n");
      return 0;
    }
    """
  end
end
