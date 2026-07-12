defmodule Elmc.WatchfaceColorShapesHostHarnessTest do
  use Elmc.TestSupport.PrimaryCodegenCase, async: false

  alias Elmc.Test.RcTrackHarness

  @source_template Path.expand("../../ide/priv/project_templates/watchface_color_shapes", __DIR__)

  test "color shapes watchface encodes two radial wedges in scene" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for color shapes host harness")

    project_dir = Path.expand("tmp/watchface_color_shapes_host_project", __DIR__)
    out_dir = Path.expand("tmp/watchface_color_shapes_host_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(@source_template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src", "../../../../packages/elm-pebble/elm-watch/src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    RcTrackHarness.compile!(
      project_dir,
      out_dir,
      entry_module: "Main",
      direct_render_only: false,
      prune_runtime: true,
      prune_native_wrappers: true,
      strip_dead_code: true
    )

    harness_path = Path.join(out_dir, "c/watchface_color_shapes_host_harness.c")
    File.write!(harness_path, harness_c())

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        "watchface_color_shapes_host_harness",
        sources: [
          Path.join(out_dir, "runtime/elmc_runtime.c"),
          Path.join(out_dir, "ports/elmc_ports.c"),
          Path.join(out_dir, "c/elmc_generated.c"),
          Path.join(out_dir, "c/elmc_worker.c"),
          Path.join(out_dir, "c/elmc_pebble.c"),
          harness_path
        ],
        rc_track: false,
        alloc_track: false
      )

    assert out =~ "rc_ok color shapes host harness"
    assert out =~ "scene_radial=2"
    assert out =~ "moon=32768,49152"
    assert out =~ "sun=0,32768"
    assert out =~ "moon_fill=199"
    assert out =~ "sun_fill=248"

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))
    assert header =~ "ELMC_PEBBLE_FEATURE_DRAW_PATH 0"
    assert header =~ "ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL 1"
  end

  defp harness_c do
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

    static ElmcValue *launch_context(void) {
      ElmcValue *screen_fields[4] = {harness_int(144), harness_int(168), harness_int(1), harness_int(2)};
      ElmcValue *screen = NULL;
      if (elmc_record_new_values(&screen, 4, screen_fields) != RC_SUCCESS) return NULL;
      for (int i = 0; i < 4; i++) elmc_release(screen_fields[i]);

      ElmcValue *ctx_fields[7] = {
          harness_int(2),
          harness_string(""),
          harness_string("basalt"),
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

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = launch_context();
      if (!flags) return 1;
      if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 2;
      elmc_release(flags);

      if (elmc_pebble_ensure_scene(&app) != 0) return 3;

      int radial = 0;
      int moon_start = -1;
      int moon_end = -1;
      int sun_start = -1;
      int sun_end = -1;
      int moon_fill = -1;
      int sun_fill = -1;
      int pending_fill = -1;
      int byte_offset = 0;
      while (byte_offset < app.scene.byte_count) {
        ElmcPebbleDrawCmd cmd;
        if (elmc_pebble_scene_decode_record(app.scene.bytes, app.scene.byte_count, &byte_offset, &cmd) != 0) return 4;
        if (cmd.kind == ELMC_PEBBLE_DRAW_FILL_COLOR) {
          pending_fill = (int)cmd.p0;
        }
        if (cmd.kind == ELMC_PEBBLE_DRAW_FILL_RADIAL) {
          radial++;
          if (radial == 1) {
            moon_start = (int)cmd.p4;
            moon_end = (int)cmd.p5;
            moon_fill = pending_fill;
          } else if (radial == 2) {
            sun_start = (int)cmd.p4;
            sun_end = (int)cmd.p5;
            sun_fill = pending_fill;
          }
        }
      }

      printf("scene_radial=%d scene_cmds=%d moon=%d,%d moon_fill=%d sun=%d,%d sun_fill=%d\\n",
             radial, app.scene.command_count, moon_start, moon_end, moon_fill, sun_start, sun_end, sun_fill);
      if (radial != 2) return 5;
      if (moon_start != 32768 || moon_end != 49152) return 6;
      if (sun_start != 0 || sun_end != 32768) return 7;
      if (moon_fill != 199) return 8;
      if (sun_fill != 248) return 9;

      printf("rc_ok color shapes host harness\\n");
      return 0;
    }
    """
  end
end
