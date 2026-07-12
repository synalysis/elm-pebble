defmodule Elmc.GeneratedRcTrackFusionAllocProbeTest do
  use Elmc.TestSupport.PrimaryCodegenCase, async: false

  alias Elmc.Test.RcTrackHarness

  @project_dir Path.expand("fixtures/permute_merge_inverse_alloc_probe_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_fusion_alloc_probe_out", __DIR__)

  @move_count 24

  setup do
    File.rm_rf!(@out_dir)

    RcTrackHarness.compile!(@project_dir, @out_dir,
      entry_module: "Main",
      strip_dead_code: true
    )

    :ok
  end

  @tag :rc_track
  @tag :rc_track_fusion
  @tag :alloc_probe
  test "permute merge inverse fusion fixture reports balanced per-move update rc" do
    harness_path = Path.join(@out_dir, "c/rc_track_fusion_alloc_probe_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *launch_context(void) {
        ElmcValue *reason = elmc_new_int_take(1);
        ElmcValue *width = elmc_new_int_take(144);
        ElmcValue *height = elmc_new_int_take(168);
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *color_mode = elmc_new_int_take(1);
        ElmcValue *screen_values[] = {width, height, shape, color_mode};
        ElmcValue *screen = elmc_record_new_values_take_value(4, screen_values);
        ElmcValue *context_values[] = {reason, screen};
        return elmc_record_new_values_take_value(2, context_values);
      }

      static void drain_cmds(ElmcPebbleApp *app) {
        for (int j = 0; j < 8; j++) {
          ElmcPebbleCmd cmd = {0};
          if (elmc_pebble_take_cmd(app, &cmd) != 0) return;
          if (cmd.kind == ELMC_PEBBLE_CMD_NONE) return;
        }
      }

      static int drain_view(ElmcPebbleApp *app) {
        app->scene.dirty = 1;
        if (elmc_pebble_ensure_scene(app) != 0) return -1;
        ElmcPebbleDrawCmd cmds[16] = {0};
        int skip = 0;
        int total = 0;
        for (;;) {
          int n = elmc_pebble_view_commands_from(app, cmds, 16, skip);
          if (n <= 0) break;
          total += n;
          skip += n;
        }
        return total;
      }

      static int probe_update(ElmcPebbleApp *app, elmc_int_t msg, int move_idx) {
        char label[64];
        ElmcAllocProbeSnap snap = {0};
        elmc_alloc_probe_snap(&snap);
        if (elmc_pebble_dispatch_int(app, msg) != 0) return 1;
        drain_cmds(app);
        snprintf(label, sizeof(label), "move%d update", move_idx);
        if (!elmc_alloc_probe_diff_balanced(&snap, label, stderr)) return 2;
        return 0;
      }

      static int probe_view(ElmcPebbleApp *app, int move_idx) {
        char label[64];
        ElmcAllocProbeSnap snap = {0};
        app->scene.dirty = 1;
        elmc_alloc_probe_snap(&snap);
        if (elmc_pebble_ensure_scene(app) != 0) return 1;
        if (drain_view(app) < 0) return 2;
        snprintf(label, sizeof(label), "move%d view", move_idx);
        if (!elmc_alloc_probe_diff_balanced(&snap, label, stderr)) return 3;
        return 0;
      }

      int main(void) {
        static const elmc_int_t dir_msgs[4] = {
          ELMC_PEBBLE_MSG_GOLEFT,
          ELMC_PEBBLE_MSG_GORIGHT,
          ELMC_PEBBLE_MSG_GOUP,
          ELMC_PEBBLE_MSG_GODOWN
        };

        elmc_rc_track_reset();
      #if ELMC_ALLOC_TRACK
        elmc_alloc_track_reset();
      #endif

        ElmcPebbleApp app = {0};
        ElmcValue *context = launch_context();
        if (elmc_pebble_init(&app, context) != 0) return 10;
        elmc_release(context);
        drain_cmds(&app);

        for (int warm = 0; warm < 4; warm++) {
          if (elmc_pebble_dispatch_int(&app, dir_msgs[warm % 4]) != 0) return 11;
          drain_cmds(&app);
        }

        int leaks = 0;
        for (int i = 0; i < #{@move_count}; i++) {
          int rc = probe_update(&app, dir_msgs[i % 4], i);
          if (rc != 0) {
            fprintf(stderr, "alloc probe failed during update move=%d code=%d\\n", i, rc);
            leaks += 1;
          }
          rc = probe_view(&app, i);
          if (rc != 0) {
            fprintf(stderr, "alloc probe failed during view move=%d code=%d\\n", i, rc);
            leaks += 1;
          }
        }

        elmc_pebble_deinit(&app);

        if (leaks > 0) {
          fprintf(stderr, "alloc_probe_summary: leaks=%d (see probe lines above)\\n", leaks);
        }

        printf("alloc_probe_done moves=%d leaks=%d\\n", #{@move_count}, leaks);
        return 0;
      }
      
      
      """
    )

    {out, 0} =
      RcTrackHarness.run_harness_capture(
        @out_dir,
        harness_path,
        "rc_track_fusion_alloc_probe",
        sources: RcTrackHarness.worker_sources(@out_dir) ++ [harness_path],
        alloc_probe: true,
        rc_track: true,
        alloc_track: true
      )

    assert out =~ "alloc_probe_done"
    RcTrackHarness.assert_alloc_probe_thresholds!(out, early_strict_moves: 10)
  end
end
