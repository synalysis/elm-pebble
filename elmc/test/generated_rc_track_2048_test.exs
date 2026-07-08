defmodule Elmc.GeneratedRcTrack2048Test do
  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness

  @project_dir Path.expand("fixtures/rc_track_2048_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_2048", __DIR__)

  setup do
    File.rm_rf!(@out_dir)
    RcTrackHarness.compile!(@project_dir, @out_dir, entry_module: "RcTrack2048Probe")
    :ok
  end

  defp write_harness!(name, body) do
    harness_path = Path.join(@out_dir, "c/#{name}_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include "elmc_generated.c"
      #include <stdio.h>

      #{RcTrackHarness.harness_prelude()}

      static ElmcValue *probe_initial_model(elmc_int_t seed) {
        ElmcValue *seed_val = elmc_harness_new_int(seed);
        ElmcValue *args[] = { seed_val };
        ElmcValue *model = #{RcTrackHarness.generated_fn_call(@out_dir, "RcTrack2048Probe", "initialModel", "args", 1)};
        elmc_release(seed_val);
        return model;
      }

      static ElmcValue *probe_step(elmc_int_t dir, ElmcValue *model) {
        ElmcValue *dir_val = elmc_harness_new_int(dir);
        ElmcValue *args[] = { dir_val, model };
        ElmcValue *next = #{RcTrackHarness.generated_fn_call(@out_dir, "RcTrack2048Probe", "step", "args", 2)};
        elmc_release(dir_val);
        return next;
      }

      static int probe_model_turn(ElmcValue *model) {
        ElmcValue *args[] = { model };
        ElmcValue *turn = #{RcTrackHarness.generated_fn_call(@out_dir, "RcTrack2048Probe", "modelTurn", "args", 1)};
        int n = (int)elmc_as_int(turn);
        elmc_release(turn);
        return n;
      }

      #{body}
      
      
      """
    )

    harness_path
  end

  @tag :rc_track
  test "2048 reverseRows and transpose probes balance rc registry" do
    harness_path =
      write_harness!(
        "rc_track_2048_orient",
        """
        static int run_fn(const char *name, ElmcValue *(*fn)(ElmcValue *)) {
          static const elmc_int_t board[16] = {
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16
          };
          ElmcValue *cells = elmc_harness_list_from_int_array(board, 16);
          elmc_rc_track_reset();
          ElmcValue *out = fn(cells);
          elmc_release(cells);
          elmc_release(out);
          if (!elmc_rc_track_check_balanced()) {
            fprintf(stderr, "rc leak in %s\\n", name);
            return 1;
          }
          return 0;
        }

        static ElmcValue *call_reverse(ElmcValue *cells) {
          ElmcValue *args[] = { cells };
          return #{RcTrackHarness.generated_fn_call(@out_dir, "RcTrack2048Probe", "reverseRows", "args", 1)};
        }

        static ElmcValue *call_transpose(ElmcValue *cells) {
          ElmcValue *args[] = { cells };
          return #{RcTrackHarness.generated_fn_call(@out_dir, "RcTrack2048Probe", "transpose", "args", 1)};
        }

        int main(void) {
          if (run_fn("reverseRows", call_reverse) != 0) return 1;
          if (run_fn("transpose", call_transpose) != 0) return 2;
          printf("rc_ok orient\\n");
          return 0;
        }
        
      """
      )

    out = RcTrackHarness.run_harness!(@out_dir, harness_path, "rc_track_2048_orient")
    RcTrackHarness.assert_balanced!(out)
  end

  @tag :rc_track
  test "2048 collapseRows probe balances rc registry" do
    harness_path =
      write_harness!(
        "rc_track_2048_collapse",
        """
        int main(void) {
          static const elmc_int_t board[16] = {
            2, 0, 2, 0,
            0, 4, 0, 4,
            2, 2, 0, 0,
            0, 0, 2, 2
          };
          ElmcValue *cells = elmc_harness_list_from_int_array(board, 16);

          elmc_rc_track_reset();
          ElmcValue *args[] = { cells };
          ElmcValue *out = #{RcTrackHarness.generated_fn_call(@out_dir, "RcTrack2048Probe", "collapseRows", "args", 1)};
          elmc_release(cells);
          elmc_release(out);

          if (!elmc_rc_track_check_balanced()) return 1;
          printf("rc_ok collapseRows\\n");
          return 0;
        }
        
      """
      )

    out = RcTrackHarness.run_harness!(@out_dir, harness_path, "rc_track_2048_collapse")
    RcTrackHarness.assert_balanced!(out)
  end

  @tag :rc_track
  test "2048 step probe balances rc registry for one directional move" do
    harness_path =
      write_harness!(
        "rc_track_2048_move",
        """
        int main(void) {
          ElmcValue *model = probe_initial_model(42);

          elmc_rc_track_reset();
          ElmcValue *next = probe_step(0, model);
          elmc_release(model);
          elmc_release(next);

          if (!elmc_rc_track_check_balanced()) return 1;
          printf("rc_ok step\\n");
          return 0;
        }
        
      """
      )

    out = RcTrackHarness.run_harness!(@out_dir, harness_path, "rc_track_2048_move")
    RcTrackHarness.assert_balanced!(out)
  end

  @tag :rc_track
  test "2048 cycles left/right/up/down for 100 moves without rc leaks" do
    harness_path =
      write_harness!(
        "rc_track_2048_moves",
        """
        int main(void) {
          static const int dirs[4] = { 0, 1, 2, 3 };
          elmc_rc_track_reset();
          ElmcValue *model = probe_initial_model(99);

          for (int move = 0; move < 100; move++) {
            ElmcValue *next = probe_step(dirs[move % 4], model);
            elmc_release(model);
            model = next;
          }

          int turns = probe_model_turn(model);
          elmc_release(model);

          if (turns == 0) {
            fprintf(stderr, "board never moved after 100 directional steps\\n");
            return 2;
          }

          if (!elmc_rc_track_check_balanced()) {
            fprintf(stderr, "rc leak after 100 chained moves (turns=%d)\\n", turns);
            elmc_rc_track_dump_live(stderr);
            return 1;
          }

          printf("rc_ok round_board_x100 turns=%d\\n", turns);
          return 0;
        }
        
      """
      )

    out = RcTrackHarness.run_harness!(@out_dir, harness_path, "rc_track_2048_moves")
    RcTrackHarness.assert_balanced!(out)
    assert turns_from_output(out) > 0
  end

  @tag :rc_track
  test "2048 each isolated directional step balances rc registry" do
    harness_path =
      write_harness!(
        "rc_track_2048_move_repeat",
        """
        int main(void) {
          static const int dirs[4] = { 0, 1, 2, 3 };

          for (int move = 0; move < 100; move++) {
            ElmcValue *model = probe_initial_model(99);

            elmc_rc_track_reset();
            ElmcValue *next = probe_step(dirs[move % 4], model);
            elmc_release(model);
            elmc_release(next);

            if (!elmc_rc_track_check_balanced()) {
              fprintf(stderr, "rc leak on isolated move %d dir=%d\\n", move, dirs[move % 4]);
              elmc_rc_track_dump_live(stderr);
              return move + 1;
            }
          }

          printf("rc_ok round_board_isolated_x100\\n");
          return 0;
        }
        
      """
      )

    out = RcTrackHarness.run_harness!(@out_dir, harness_path, "rc_track_2048_move_repeat")
    RcTrackHarness.assert_balanced!(out)
  end

  defp turns_from_output(out) do
    case Regex.run(~r/turns=(\d+)/, out) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end
end

defmodule Elmc.GeneratedRcTrack2048WorkerTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness

  @project_dir Path.expand("fixtures/rc_track_2048_pebble_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_2048_worker", __DIR__)

  setup do
    File.rm_rf!(@out_dir)

    RcTrackHarness.compile!(@project_dir, @out_dir,
      entry_module: "Main",
      strip_dead_code: true,
      direct_render_only: true
    )

    :ok
  end

  @tag :rc_track
  test "2048 Pebble worker cycles directions for 100 presses without rc leaks" do
    harness_path = Path.join(@out_dir, "c/rc_track_2048_worker_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_worker.h"
      #include "elmc_pebble.h"
      #include <stdio.h>

      enum { MODEL_FIELD_TURN = 4 };

      static ElmcValue *launch_context(void) {
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *height = elmc_new_int_take(168);
        ElmcValue *width = elmc_new_int_take(144);
        ElmcValue *color_mode = elmc_new_int_take(1);
        const char *screen_names[] = {"color_mode", "height", "shape", "width"};
        ElmcValue *screen_values[] = {color_mode, height, width, shape};
        ElmcValue *screen = elmc_record_new_take_value(4, screen_names, screen_values);
        ElmcValue *reason = elmc_new_int_take(1);
        const char *names[] = {"reason", "screen"};
        ElmcValue *values[] = {reason, screen};
        return elmc_record_new_take_value(2, names, values);
      }

      static void drain_cmds(ElmcWorkerState *state) {
        for (int j = 0; j < 8; j++) {
          ElmcValue *cmd = elmc_worker_take_cmd(state);
          if (!cmd) return;
          int done = (cmd->tag == ELMC_TAG_INT || cmd->tag == ELMC_TAG_BOOL) && elmc_as_int(cmd) == 0;
          elmc_release(cmd);
          if (done) return;
        }
      }

      int main(void) {
        static const elmc_int_t dir_msgs[4] = {
          ELMC_PEBBLE_MSG_LEFTPRESSED,
          ELMC_PEBBLE_MSG_RIGHTPRESSED,
          ELMC_PEBBLE_MSG_UPPRESSED,
          ELMC_PEBBLE_MSG_DOWNPRESSED
        };

        elmc_rc_track_reset();
        ElmcWorkerState state = {0};
        ElmcValue *context = launch_context();
        if (elmc_worker_init(&state, context) != 0) return 2;
        elmc_release(context);

        for (int i = 0; i < 100; i++) {
          ElmcValue *msg = elmc_new_int_take(dir_msgs[i % 4]);
          if (elmc_worker_dispatch(&state, msg) != 0) {
            elmc_release(msg);
            return 3;
          }
          elmc_release(msg);
          drain_cmds(&state);
        }

        ElmcValue *model = elmc_worker_model(&state);
        int turns = 0;
        if (model) {
          ElmcValue *turn_val = elmc_record_get_index(model, MODEL_FIELD_TURN);
          if (turn_val) {
            turns = (int)elmc_as_int(turn_val);
            elmc_release(turn_val);
          }
          elmc_release(model);
        }

        elmc_worker_deinit(&state);

        if (turns == 0) {
          fprintf(stderr, "worker board never moved after 100 directional presses\\n");
          return 4;
        }

        if (!elmc_rc_track_check_balanced()) {
          fprintf(stderr, "rc leak after worker round (turns=%d)\\n", turns);
          elmc_rc_track_dump_live(stderr);
          return 1;
        }

        printf("rc_ok worker_round_board_x100 turns=%d\\n", turns);
        return 0;
      }
      
      
      """
    )

    out = RcTrackHarness.run_worker_harness!(@out_dir, harness_path, "rc_track_2048_worker")
    RcTrackHarness.assert_balanced!(out)

    assert Regex.run(~r/turns=(\d+)/, out)
           |> Enum.at(1)
           |> String.to_integer() > 0
  end

  @tag :rc_track
  test "2048 indexedMap view renders 20 frames without rc leaks" do
    harness_path = Path.join(@out_dir, "c/rc_track_2048_view_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include "elmc_generated.h"
      #include <stdio.h>

      static ElmcValue *launch_context(void) {
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *height = elmc_new_int_take(168);
        ElmcValue *width = elmc_new_int_take(144);
        ElmcValue *color_mode = elmc_new_int_take(1);
        const char *screen_names[] = {"color_mode", "height", "shape", "width"};
        ElmcValue *screen_values[] = {color_mode, height, width, shape};
        ElmcValue *screen = elmc_record_new_take_value(4, screen_names, screen_values);
        ElmcValue *reason = elmc_new_int_take(1);
        const char *names[] = {"reason", "screen"};
        ElmcValue *values[] = {reason, screen};
        return elmc_record_new_take_value(2, names, values);
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

      int main(void) {
        static const elmc_int_t dir_msgs[4] = {
          ELMC_PEBBLE_MSG_LEFTPRESSED,
          ELMC_PEBBLE_MSG_RIGHTPRESSED,
          ELMC_PEBBLE_MSG_UPPRESSED,
          ELMC_PEBBLE_MSG_DOWNPRESSED
        };

        elmc_rc_track_reset();
        ElmcPebbleApp app = {0};
        ElmcValue *context = launch_context();
        if (elmc_pebble_init_with_mode(&app, context, ELMC_PEBBLE_MODE_APP) != 0) return 2;
        elmc_release(context);

        for (int frame = 0; frame < 20; frame++) {
          if (elmc_pebble_dispatch_int(&app, dir_msgs[frame % 4]) != 0) return 3;
          drain_cmds(&app);
          int drawn = drain_view(&app);
          if (drawn < 17) {
            fprintf(stderr, "expected at least 17 draw cmds, got %d\\n", drawn);
            return 4;
          }
        }

        elmc_pebble_deinit(&app);

        if (!elmc_rc_track_check_balanced()) {
          fprintf(stderr, "rc leak after view frames\\n");
          elmc_rc_track_dump_live(stderr);
          return 1;
        }

        printf("rc_ok view_frames_x20\\n");
        return 0;
      }
      
      
      """
    )

    out =
      RcTrackHarness.run_harness!(
        @out_dir,
        harness_path,
        "rc_track_2048_view",
        sources: RcTrackHarness.worker_sources(@out_dir) ++ [harness_path]
      )

    RcTrackHarness.assert_balanced!(out)
  end
end
