defmodule Elmc.GeneratedRcTrackGame2048AllocProbeTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness

  @source_fixture Path.expand("fixtures/simple_project", __DIR__)
  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)
  @project_dir Path.expand("tmp/rc_track_game_2048_alloc_probe", __DIR__)
  @out_dir Path.expand("tmp/rc_track_game_2048_alloc_probe_out", __DIR__)

  @move_count 48

  setup do
    File.rm_rf!(@project_dir)
    File.rm_rf!(@out_dir)
    File.cp_r!(@source_fixture, @project_dir)
    File.write!(Path.join(@project_dir, "src/Main.elm"), File.read!(@template_main))

    RcTrackHarness.compile!(@project_dir, @out_dir,
      entry_module: "Main",
      strip_dead_code: true,
      direct_render_only: true
    )

    :ok
  end

  @tag :rc_track
  @tag :rc_track_2048
  @tag :alloc_probe
  test "game-2048 clockwise moves report alloc diffs for update and view" do
    harness_path = Path.join(@out_dir, "c/rc_track_game_2048_alloc_probe_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>

      #{RcTrackHarness.harness_rc_helpers()}

      static ElmcValue *aplite_launch_context(void) {
        ElmcValue *reason = elmc_harness_new_int(2);
        ElmcValue *watch_model = elmc_harness_new_string("");
        ElmcValue *watch_profile_id = elmc_harness_new_string("aplite");
        ElmcValue *width = elmc_harness_new_int(144);
        ElmcValue *height = elmc_harness_new_int(168);
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *color_mode = elmc_harness_new_int(1);
        ElmcValue *screen_values[] = {width, height, shape, color_mode};
        ElmcValue *screen = elmc_record_new_values_take_value(4, screen_values);
        ElmcValue *has_microphone = elmc_harness_new_int(0);
        ElmcValue *has_compass = elmc_harness_new_int(0);
        ElmcValue *supports_health = elmc_harness_new_int(0);
        ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,
                                       has_compass, supports_health};
        return elmc_record_new_values_take_value(7, context_values);
      }

      static void drain_cmds(ElmcPebbleApp *app) {
        for (int j = 0; j < 16; j++) {
          ElmcPebbleCmd cmd = {0};
          if (elmc_pebble_take_cmd(app, &cmd) != 0) return;
          if (cmd.kind == ELMC_PEBBLE_CMD_NONE) return;
        }
      }

      static int drain_init_cmds(ElmcPebbleApp *app) {
        ElmcPebbleCmd cmds[8];
        int count = 0;
        int random_rc = -99;
        for (int j = 0; j < 8; j++) {
          ElmcPebbleCmd cmd = {0};
          if (elmc_pebble_take_cmd(app, &cmd) != 0) break;
          if (cmd.kind == ELMC_PEBBLE_CMD_NONE) break;
          cmds[count++] = cmd;
        }
        for (int j = 0; j < count; j++) {
          if (cmds[j].kind == ELMC_PEBBLE_CMD_RANDOM_GENERATE) {
            random_rc = elmc_pebble_dispatch_tag_value(app, cmds[j].p0, 12345);
          }
        }
        for (int j = 0; j < count; j++) {
          if (cmds[j].kind == ELMC_PEBBLE_CMD_STORAGE_READ_STRING) {
            elmc_pebble_dispatch_tag_string(app, cmds[j].p1, "");
          }
        }
        return random_rc;
      }

      static int drain_view(ElmcPebbleApp *app) {
        app->scene.dirty = 1;
        if (elmc_pebble_ensure_scene(app) != 0) return -1;
        ElmcPebbleDrawCmd cmds[32] = {0};
        int skip = 0;
        int total = 0;
        for (;;) {
          int n = elmc_pebble_view_commands_from(app, cmds, 32, skip);
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
        /* Clockwise on watch: Up, Right (select), Down, Left (back). */
        static const elmc_int_t clockwise_msgs[4] = {
          ELMC_PEBBLE_MSG_UPPRESSED,
          ELMC_PEBBLE_MSG_RIGHTPRESSED,
          ELMC_PEBBLE_MSG_DOWNPRESSED,
          ELMC_PEBBLE_MSG_LEFTPRESSED
        };

        elmc_rc_track_reset();
      #if ELMC_ALLOC_TRACK
        elmc_alloc_track_reset();
      #endif

        ElmcPebbleApp app = {0};
        ElmcValue *context = aplite_launch_context();
        if (elmc_pebble_init(&app, context) != 0) return 10;
        elmc_release(context);

        if (drain_init_cmds(&app) != 0) return 11;
        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_RANDOMGENERATED, 12345) != 0) return 12;
        drain_cmds(&app);

        int leaks = 0;
        for (int i = 0; i < #{@move_count}; i++) {
          int rc = probe_update(&app, clockwise_msgs[i % 4], i);
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
        "rc_track_game_2048_alloc_probe",
        sources: RcTrackHarness.worker_sources(@out_dir) ++ [harness_path],
        alloc_probe: true,
        rc_track: true,
        alloc_track: true
      )

    assert out =~ "alloc_probe_done"

    leaks =
      case Regex.run(~r/leaks=(\d+)/, out) do
        [_, n] -> String.to_integer(n)
        _ -> flunk("missing leaks count in:\n#{out}")
      end

    update_rc_nets = RcTrackHarness.parse_alloc_probe_update_rc_nets(out)

    update_leaks = length(update_rc_nets)

    early_strict_leaks =
      Enum.count(update_rc_nets, fn {move, net} -> move < 10 and net != 0 end)

    catastrophic_update_leaks =
      Enum.count(update_rc_nets, fn {_move, net} -> net >= 10 end)

    max_update_rc_net =
      case update_rc_nets do
        [] -> 0
        nets -> nets |> Enum.map(&elem(&1, 1)) |> Enum.max()
      end

    view_leaks = RcTrackHarness.parse_alloc_probe_view_leaks(out)

    IO.puts("""
    2048 alloc probe (clockwise Up→Right→Down→Left, #{@move_count} moves):
      total unbalanced regions: #{leaks}
      update regions with rc_net>0: #{update_leaks} (max rc_net +#{max_update_rc_net})
      early-game strict leaks (moves 0-9, rc_net!=0): #{early_strict_leaks}
      catastrophic update regions (rc_net>=10): #{catastrophic_update_leaks}
      view regions with rc_net>0: #{view_leaks}
    Run: mix test.rc_2048
    
      """)

    RcTrackHarness.assert_alloc_probe_thresholds!(out, early_strict_moves: 10, max_early_strict_leaks: 1)
  end
end
