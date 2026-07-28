defmodule Elmc.WatchfaceRcTrackSmokeTest do
  @moduledoc """
  Host RC balance smoke for arbitrary watchface templates.

  Proves runtime reference counting across the TEA loop that apps actually run:

      init → drain init cmds (time / feature-gated) → view → deinit

  Uses `ELMC_RC_TRACK` (not absolute malloc track — scene buffers stay live).
  Cmd replies use cmd-encoded tags (`cmd.p0`), never constructor-name guessing.

  One template per BEAM (`:slow`); run via:

      ./scripts/mix-test-per-template.sh test/watchface_rc_track_smoke_test.exs
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.{HostSmoke, PlanStrictTemplates, TemplateCompile}

  @moduletag :slow
  @moduletag :rc_track
  @moduletag :watchface_rc

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    # Host RC track needs the full runtime track registry; size prune is for
    # on-device builds (which do not set `-DELMC_RC_TRACK=1`).
    prune_runtime: false,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  # Expand via `PlanStrictTemplates.rc_host_smoke_names/0` as templates become host-linkable.
  @rc_templates HostSmoke.templates(PlanStrictTemplates.rc_host_smoke_names())

  for template <- @rc_templates do
    @tag template: template

    test "RC host smoke: #{template} balances after init/drain/view/deinit" do
      run_rc_smoke!(unquote(template))
    end
  end

  defp run_rc_smoke!(template) do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for watchface RC smoke")

    out_dir =
      Path.join(System.tmp_dir!(), "rc-smoke-#{template}-#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)

    compile_opts = Keyword.merge(@compile_opts, out_dir: out_dir)
    assert {:ok, _result} = TemplateCompile.compile_watch_template(template, compile_opts)

    binary_name = "rc_smoke_#{template}"
    harness_path = Path.join(out_dir, "c/#{binary_name}_harness.c")
    File.write!(harness_path, rc_harness_c(template))

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        binary_name,
        sources: pebble_harness_sources(out_dir, harness_path),
        rc_track: true,
        alloc_track: false
      )

    RcTrackHarness.assert_balanced!(out)
    assert out =~ "rc_ok watchface_rc #{template}"
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

  defp rc_harness_c(template) do
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

    /* Capability-based drain: answer cmds by kind + encoded msg tag (cmd.p0). */
    static int drain_init_cmds(ElmcPebbleApp *app) {
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

    int main(void) {
      elmc_rc_track_reset();

      ElmcPebbleApp app = {0};
      ElmcValue *flags = launch_context();
      if (!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 2;
      elmc_release(flags);

      int drain_rc = drain_init_cmds(&app);
      if (drain_rc != 0) return drain_rc;

      ElmcPebbleDrawCmd view_cmds[8] = {0};
      if (elmc_pebble_view_commands(&app, view_cmds, 8) < 1) return 24;

      elmc_pebble_deinit(&app);

      if (!elmc_rc_track_check_balanced()) {
        fprintf(stderr, "rc leak in watchface_rc #{template}\\n");
        elmc_rc_track_dump_live(stderr);
        return 1;
      }

      printf("rc_ok watchface_rc #{template}\\n");
      return 0;
    }
    """
  end
end
