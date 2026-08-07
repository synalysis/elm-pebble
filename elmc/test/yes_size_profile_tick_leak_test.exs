defmodule Elmc.YesSizeProfileTickLeakTest do
  @moduledoc """
  Alloc-track gate for the size-profile boxed worker path on watchface_yes.

  Complements `yes_watchface_tick_leak_test` (non-size behavioral ticks) by
  compiling with `codegen_profile: :size` and asserting quiet SecondChanged
  dispatches do not grow live malloc counts.

  Companion floods use `Companion.Types.PhoneToWatch` constructor tags in
  declaration order (ProvideSun=1 … SetCornerUpdateInterval=9). Optional model
  fields (`moonriseMin`, `stepsToday`, …) are warmed once before the flood gate
  so Nothing→Just first-touch reshapes are not mistaken for steady-state leaks.
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.TemplateCompile

  @compile_opts [
    codegen_profile: :size,
    direct_render_only: true,
    # Keep full runtime so ELMC_ALLOC_TRACK can compile (see heap_budget_smoke).
    prune_runtime: false,
    prune_native_wrappers: true,
    # Match device IDE compiles: heap-backed owned_slots arrays.
    pebble_int32: true,
    strip_dead_code: true,
    prod: true,
    plan_ir_mode: :primary,
    plan_ir_strict: true
  ]

  test "size-profile yes boxed worker stays alloc-balanced across SecondChanged and MinuteChanged" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for yes size profile tick leak harness")

    out_dir =
      Path.join(System.tmp_dir!(), "yes-size-tick-leak-#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template(
               "watchface_yes",
               Keyword.merge(@compile_opts, out_dir: out_dir, ir_cache: false)
             )

    worker_h = File.read!(Path.join(out_dir, "c/elmc_worker.h"))
    refute worker_h =~ "ELMC_WORKER_NATIVE_MODEL"
    refute worker_h =~ "ElmcWorkerModelNative"

    worker_c = File.read!(Path.join(out_dir, "c/elmc_worker.c"))
    assert worker_c =~ "next_model != prev_model"
    refute worker_c =~ "elmc_worker_model_native_box"
    refute worker_c =~ "elmc_worker_model_native_unpack"

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated =~ "elmc_owned_slots_acquire(ELMC_OWNED_SLOT_COUNT)"
    assert generated =~ "elmc_owned_slots_release(owned, ELMC_OWNED_SLOT_COUNT)"
    refute generated =~ ~r/elmc_calloc\(ELMC_OWNED_SLOT_COUNT,\s*sizeof\(ElmcValue \*\),\s*"owned_slots"\)/
    refute generated =~ "elmc_free(owned);"

    runtime = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))
    assert runtime =~ "elmc_owned_slots_acquire"
    assert runtime =~ "elmc_owned_slots_pool_state"

    RcTrackHarness.write_trig_stubs!(out_dir)
    harness_path = Path.join(out_dir, "c/yes_size_profile_tick_leak_harness.c")
    File.write!(harness_path, tick_harness_c())

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        "yes_size_profile_tick_leak",
        sources: pebble_harness_sources(out_dir, harness_path),
        extra_flags: ["-DPBL_ROUND", "-include", Path.join(out_dir, "c/pebble_trig_host_stubs.h")],
        alloc_probe: false,
        rc_track: false,
        alloc_track: true
      )

    assert out =~ "first_minute_alloc_delta=0"
    assert out =~ "companion_flood_alloc_delta=0"
    assert out =~ "yes_size_tick_probe ticks="
    assert out =~ "alloc_delta=0"
    assert out =~ "owned_slots_heap_allocs=0"
    assert out =~ "rc_ok yes size profile tick leak"
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

    #{RcTrackHarness.harness_rc_helpers()}

    /* Field order must match Pebble.Time.CurrentDateTime's declared layout
     * (year, month, day, dayOfWeek, hour, minute, second, utcOffsetMinutes):
     * elmc assigns field indices from Elm declaration order, and
     * elmc_record_get_index in the generated update() reads positionally, not
     * by name. A mismatched harness order previously aliased the compiler's
     * "minute" index onto this record's "second" slot, which always started
     * at the immortal small-int 0 (ELMC_SMALL_INT_MIN..MAX) -- masking the
     * real minute field and making the first MinuteChanged's minute-int box
     * look like a spurious +1 in elmc_alloc_track (see
     * yes_size_profile_tick_leak_test comment below). */
    static ElmcValue *current_datetime(int second) {
      const char *names[] = {"year", "month", "day", "dayOfWeek", "hour", "minute", "second", "utcOffsetMinutes"};
      ElmcValue *values[] = {
        elmc_harness_new_int(2026), elmc_harness_new_int(7), elmc_harness_new_int(1),
        elmc_harness_new_int(0), elmc_harness_new_int(3), elmc_harness_new_int(10), elmc_harness_new_int(second),
        elmc_harness_new_int(0)
      };
      return elmc_harness_record_new_take(8, names, values);
    }

    static ElmcValue *gabbro_launch_context(void) {
      ElmcValue *reason = elmc_harness_new_int(2);
      ElmcValue *watch_model = elmc_harness_new_string("");
      ElmcValue *watch_profile_id = elmc_harness_new_string("gabbro");
      ElmcValue *width = elmc_harness_new_int(260);
      ElmcValue *height = elmc_harness_new_int(260);
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

    /* PhoneToWatch tags = Companion.Types declaration order (also
     * ELMC_UNION_COMPANION_TYPES_PROVIDE* in generated C). */
    enum {
      PHONE_PROVIDE_SUN = 1,
      PHONE_PROVIDE_MOON = 2,
      PHONE_PROVIDE_MOON_PHASE = 3,
      PHONE_PROVIDE_WEATHER = 4,
      PHONE_PROVIDE_WIND = 5,
      PHONE_PROVIDE_TIDE = 6,
      PHONE_CLEAR_TIDE = 7,
      PHONE_PROVIDE_ALTITUDE = 8
    };

    static ElmcValue *phone_union(int tag, ElmcValue *payload) {
      return elmc_harness_tuple2_take(elmc_harness_new_int(tag), payload);
    }

    static ElmcValue *provide_sun(void) {
      ElmcValue *payload = elmc_harness_tuple2_take(
          elmc_harness_new_int(360),
          elmc_harness_tuple2_take(elmc_harness_new_int(1080), elmc_harness_new_int(1)));
      return phone_union(PHONE_PROVIDE_SUN, payload);
    }

    static ElmcValue *provide_weather(void) {
      ElmcValue *payload = elmc_harness_tuple2_take(
          elmc_harness_tuple2_take(elmc_harness_new_int(1), elmc_harness_new_int(210)),
          elmc_harness_tuple2_take(
              elmc_harness_new_int(1),
              elmc_harness_tuple2_take(
                  elmc_harness_new_int(0),
                  elmc_harness_tuple2_take(elmc_harness_new_int(0), elmc_harness_new_int(1013)))));
      return phone_union(PHONE_PROVIDE_WEATHER, payload);
    }

    static ElmcValue *provide_moon_phase(int phase_e6) {
      return phone_union(PHONE_PROVIDE_MOON_PHASE, elmc_harness_new_int(phase_e6));
    }

    static ElmcValue *provide_moon(int moonrise, int moonset, int phase_e6) {
      ElmcValue *payload = elmc_harness_tuple2_take(
          elmc_harness_new_int(moonrise),
          elmc_harness_tuple2_take(elmc_harness_new_int(moonset), elmc_harness_new_int(phase_e6)));
      return phone_union(PHONE_PROVIDE_MOON, payload);
    }

    static ElmcValue *provide_wind(int speed) {
      /* WindDirection.North=1, WindSpeed.MetersPerSecond=1 + speed */
      ElmcValue *payload = elmc_harness_tuple2_take(
          elmc_harness_new_int(1),
          elmc_harness_tuple2_take(elmc_harness_new_int(1), elmc_harness_new_int(speed)));
      return phone_union(PHONE_PROVIDE_WIND, payload);
    }

    static ElmcValue *provide_tide(int next_min) {
      ElmcValue *payload = elmc_harness_tuple2_take(
          elmc_harness_new_int(next_min),
          elmc_harness_tuple2_take(
              elmc_harness_new_int(50),
              elmc_harness_tuple2_take(elmc_harness_new_int(500), elmc_harness_new_int(1))));
      return phone_union(PHONE_PROVIDE_TIDE, payload);
    }

    static ElmcValue *provide_altitude(int meters) {
      return phone_union(
          PHONE_PROVIDE_ALTITUDE,
          elmc_harness_tuple2_take(elmc_harness_new_int(1), elmc_harness_new_int(meters)));
    }

    static ElmcValue *clear_tide(void) {
      return elmc_harness_new_int(PHONE_CLEAR_TIDE);
    }

    static int drain_view(ElmcPebbleApp *app) {
      ElmcPebbleDrawCmd cmds[64] = {0};
      return elmc_pebble_view_commands(app, cmds, 64);
    }

    static void drain_cmds(ElmcPebbleApp *app, int max_cmds) {
      for (int j = 0; j < max_cmds; j++) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_pebble_take_cmd(app, &cmd) != 0 || cmd.kind == ELMC_PEBBLE_CMD_NONE) break;
      }
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
            ElmcValue *dt = current_datetime(0);
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
      enum { TICK_COUNT = 120 };

    #if ELMC_ALLOC_TRACK
      elmc_alloc_track_reset();
    #endif

      ElmcPebbleApp app = {0};
      ElmcValue *flags = gabbro_launch_context();
      if (!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 2;
      elmc_release(flags);

      drain_init_cmds(&app);

      {
        ElmcValue *dt = current_datetime(0);
        if (!dt) return 3;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_CURRENTDATETIME, dt) != 0) {
          elmc_release(dt);
          return 3;
        }
        elmc_release(dt);
      }
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_BATTERYLEVELCHANGED, 80) != 0) return 4;
      if (elmc_pebble_dispatch_tag_bool(&app, ELMC_PEBBLE_MSG_CONNECTIONCHANGED, 1) != 0) return 5;
      if (drain_view(&app) < 1) return 10;

      {
        ElmcValue *sun = provide_sun();
        if (!sun) return 7;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, sun) != 0) {
          elmc_release(sun);
          return 7;
        }
        elmc_release(sun);
      }
      {
        ElmcValue *weather = provide_weather();
        if (!weather) return 8;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, weather) != 0) {
          elmc_release(weather);
          return 8;
        }
        elmc_release(weather);
      }
      /* Warm optional companion/health fields once (Nothing→Just reshape) before
       * the steady-state flood gate. First-touch growth is legitimate model
       * population, not a leak; measuring across it previously false-failed. */
      {
        ElmcValue *moon = provide_moon(60, 1200, 100000);
        if (!moon) return 14;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, moon) != 0) {
          elmc_release(moon);
          return 14;
        }
        elmc_release(moon);
      }
      {
        ElmcValue *phase = provide_moon_phase(250000);
        if (!phase) return 15;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, phase) != 0) {
          elmc_release(phase);
          return 15;
        }
        elmc_release(phase);
      }
      {
        ElmcValue *wind = provide_wind(5);
        if (!wind) return 16;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, wind) != 0) {
          elmc_release(wind);
          return 16;
        }
        elmc_release(wind);
      }
      {
        ElmcValue *tide = provide_tide(100);
        if (!tide) return 17;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, tide) != 0) {
          elmc_release(tide);
          return 17;
        }
        elmc_release(tide);
      }
      {
        ElmcValue *altitude = provide_altitude(100);
        if (!altitude) return 18;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, altitude) != 0) {
          elmc_release(altitude);
          return 18;
        }
        elmc_release(altitude);
      }
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_GOTSTEPSTODAY, 1000) != 0) {
        return 19;
      }
      if (drain_view(&app) < 1) return 11;

      /* Drain any commands queued by the setup above (battery/connection/
       * health/phone dispatches) before snapshotting, so the first
       * MinuteChanged measurement below isn't contaminated by unrelated
       * pending-cmd-queue frees that have nothing to do with the minute COW. */
      drain_cmds(&app, 16);

      /* First MinuteChanged dispatch: the nested now/Maybe COW reshapes heap
       * layout here (fresh model + now + Just copies), so this used to be
       * treated as an untracked "warm up" before the steady-state gate below.
       * It must be alloc-balanced too -- a real ownership bug on this exact
       * transition would otherwise hide as a one-time +1 absorbed into the
       * baseline instead of failing the test (see current_datetime comment
       * above for why a previous version of this harness masked such a bug
       * with an immortal small-int coincidence). */
    #if ELMC_ALLOC_TRACK
      uint32_t live_before_first_minute = elmc_alloc_track_live_count();
    #else
      uint32_t live_before_first_minute = 0;
    #endif
      if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_MINUTECHANGED, 11) != 0) return 12;
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

      /* Companion/hour/health soak: device gray-screens after "some while" often
       * track these richer paths, not quiet SecondChanged identity ticks.
       * All optional fields were warmed above; this loop must stay alloc-flat. */
      for (int flood = 0; flood < 24; flood++) {
        ElmcValue *sun = provide_sun();
        if (!sun) return 30;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, sun) != 0) {
          elmc_release(sun);
          return 31;
        }
        elmc_release(sun);

        ElmcValue *weather = provide_weather();
        if (!weather) return 32;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, weather) != 0) {
          elmc_release(weather);
          return 33;
        }
        elmc_release(weather);

        ElmcValue *moon = provide_moon(60 + flood, 1200 + flood, 100000 + flood * 17);
        if (!moon) return 34;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, moon) != 0) {
          elmc_release(moon);
          return 35;
        }
        elmc_release(moon);

        ElmcValue *phase = provide_moon_phase(250000 + flood * 13);
        if (!phase) return 36;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, phase) != 0) {
          elmc_release(phase);
          return 37;
        }
        elmc_release(phase);

        ElmcValue *wind = provide_wind(5 + (flood % 10));
        if (!wind) return 42;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, wind) != 0) {
          elmc_release(wind);
          return 43;
        }
        elmc_release(wind);

        if (flood % 5 == 0) {
          ElmcValue *cleared = clear_tide();
          if (!cleared) return 44;
          if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, cleared) != 0) {
            elmc_release(cleared);
            return 45;
          }
          elmc_release(cleared);
        } else {
          ElmcValue *tide = provide_tide(100 + flood);
          if (!tide) return 46;
          if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, tide) != 0) {
            elmc_release(tide);
            return 47;
          }
          elmc_release(tide);
        }

        ElmcValue *altitude = provide_altitude(100 + flood);
        if (!altitude) return 48;
        if (elmc_pebble_dispatch_tag_payload(&app, ELMC_PEBBLE_MSG_FROMPHONE, altitude) != 0) {
          elmc_release(altitude);
          return 49;
        }
        elmc_release(altitude);

        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_HOURCHANGED, flood % 24) != 0) {
          return 38;
        }
        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_GOTSTEPSTODAY, 1000 + flood * 37) != 0) {
          return 39;
        }
        if (flood % 7 == 0) {
          if (elmc_pebble_dispatch_tag_bool(&app, ELMC_PEBBLE_MSG_CONNECTIONCHANGED, flood % 2) != 0) {
            return 50;
          }
        }
        if (drain_view(&app) < 0) return 40;
        drain_cmds(&app, 16);
      }

    #if ELMC_ALLOC_TRACK
      uint32_t live_after_flood = elmc_alloc_track_live_count();
      int32_t flood_alloc_delta = (int32_t)live_after_flood - (int32_t)live_before;
      if (flood_alloc_delta != 0) {
        fprintf(stderr, "alloc leak/growth across companion/hour/steps flood: delta=%d\\n",
                (int)flood_alloc_delta);
        elmc_alloc_track_dump_live(stderr);
      }
      printf("companion_flood_alloc_delta=%d\\n", (int)flood_alloc_delta);
      if (flood_alloc_delta != 0) return 41;
      live_before = live_after_flood;
    #endif

      int failures = 0;
      int ticks = 0;
      for (int i = 0; i < TICK_COUNT; i++) {
        int second = (i % 58) + 1;
        ticks += 1;
        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_SECONDCHANGED, second) != 0) {
          fprintf(stderr, "dispatch failed second=%d\\n", second);
          failures += 1;
          break;
        }
        /* Include corner-refresh seconds (every 5s) so view rebuild + model
         * update ownership is covered, not only quiet identity ticks. */
        if (drain_view(&app) < 0) {
          fprintf(stderr, "view drain failed second=%d\\n", second);
          failures += 1;
          break;
        }

        /* Device also fires MinuteChanged; exercise COW minute update ownership. */
        if (second == 30 || second == 58) {
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
          drain_cmds(&app, 8);
        }
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

      printf("yes_size_tick_probe ticks=%d failures=%d live_before=%u live_after=%u alloc_delta=%d live_deinited=%u\\n",
             ticks, failures, live_before, live_after, (int)alloc_delta, live_deinited);

    #if ELMC_ALLOC_TRACK
      uint32_t owned_slots_heap_allocs = elmc_alloc_track_owned_slots_alloc_count();
      printf("owned_slots_heap_allocs=%u\\n", owned_slots_heap_allocs);
      if (owned_slots_heap_allocs != 0) {
        fprintf(stderr, "owned_slots heap fallback used during soak: %u\\n", owned_slots_heap_allocs);
        return 24;
      }
    #else
      printf("owned_slots_heap_allocs=0\\n");
    #endif

      if (failures != 0) return 20;
      if (alloc_delta != 0) {
        return 21;
      }
      if (live_deinited != 0) {
        fprintf(stderr, "allocs still live after deinit: %u\\n", live_deinited);
        return 22;
      }

      printf("rc_ok yes size profile tick leak\\n");
      return 0;
    }
    """
  end
end
