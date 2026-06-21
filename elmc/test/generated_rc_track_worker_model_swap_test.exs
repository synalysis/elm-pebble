defmodule Elmc.GeneratedRcTrackWorkerModelSwapTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness

  @source_fixture Path.expand("fixtures/simple_project", __DIR__)
  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)
  @out_dir Path.expand("tmp/rc_track_worker_model_swap_out", __DIR__)
  @project_dir Path.expand("tmp/rc_track_worker_model_swap", __DIR__)

  @dispatch_count 20

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
  test "game-2048 worker keeps cells list and turn across in-place model returns" do
    harness_path = Path.join(@out_dir, "c/rc_track_worker_model_swap_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_worker.h"
      #include "elmc_pebble.h"
      #include <stdio.h>

      enum {
        MODEL_FIELD_CELLS = 0,
        MODEL_FIELD_TURN = 4
      };

      static ElmcValue *launch_context(void) {
        ElmcValue *reason = elmc_new_int_take(2);
        ElmcValue *watch_model = elmc_new_string_take("");
        ElmcValue *watch_profile_id = elmc_new_string_take("aplite");
        ElmcValue *width = elmc_new_int_take(144);
        ElmcValue *height = elmc_new_int_take(168);
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *color_mode = elmc_new_int_take(1);
        ElmcValue *screen_values[] = {width, height, shape, color_mode};
        ElmcValue *screen = elmc_record_new_values_take_value(4, screen_values);
        ElmcValue *has_microphone = elmc_new_int_take(0);
        ElmcValue *has_compass = elmc_new_int_take(0);
        ElmcValue *supports_health = elmc_new_int_take(0);
        ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,
                                       has_compass, supports_health};
        return elmc_record_new_values_take_value(7, context_values);
      }

      static void drain_cmds(ElmcWorkerState *state) {
        for (int j = 0; j < 16; j++) {
          ElmcValue *cmd = elmc_worker_take_cmd(state);
          if (!cmd) return;
          int done = (cmd->tag == ELMC_TAG_INT || cmd->tag == ELMC_TAG_BOOL) && elmc_as_int(cmd) == 0;
          elmc_release(cmd);
          if (done) return;
        }
      }

      static int dispatch_tag_string(ElmcWorkerState *state, elmc_int_t tag, const char *value) {
        ElmcValue *tag_val = elmc_new_int_take(tag);
        ElmcValue *payload = elmc_new_string_take(value ? value : "");
        ElmcValue *msg = elmc_tuple2_take_value(tag_val, payload);
        if (!msg) return -1;
        int rc = elmc_worker_dispatch(state, msg);
        elmc_release(msg);
        return rc;
      }

      static int dispatch_tag_value(ElmcWorkerState *state, elmc_int_t tag, elmc_int_t value) {
        ElmcValue *tag_val = elmc_new_int_take(tag);
        ElmcValue *payload = elmc_new_int_take(value);
        ElmcValue *msg = elmc_tuple2_take_value(tag_val, payload);
        if (!msg) return -1;
        int rc = elmc_worker_dispatch(state, msg);
        elmc_release(msg);
        return rc;
      }

      static int dispatch_int(ElmcWorkerState *state, elmc_int_t msg) {
        ElmcValue *wrapped = elmc_new_int_take(msg);
        int rc = elmc_worker_dispatch(state, wrapped);
        elmc_release(wrapped);
        return rc;
      }

      static void drain_pending_cmds(ElmcWorkerState *state) {
        for (int j = 0; j < 32; j++) {
          ElmcValue *cmd = elmc_worker_take_cmd(state);
          if (!cmd) return;
          if ((cmd->tag == ELMC_TAG_INT || cmd->tag == ELMC_TAG_BOOL) && elmc_as_int(cmd) == 0) {
            elmc_release(cmd);
            return;
          }
          if (cmd->tag == ELMC_TAG_CMD && cmd->payload) {
            ElmcCmdPayload *payload = (ElmcCmdPayload *)cmd->payload;
            if (payload->kind == ELMC_PEBBLE_CMD_RANDOM_GENERATE) {
              dispatch_tag_value(state, payload->p0, 12345);
            } else if (payload->kind == ELMC_PEBBLE_CMD_STORAGE_READ_STRING) {
              dispatch_tag_string(state, payload->p1, "");
            }
          }
          elmc_release(cmd);
        }
      }

      static int drain_init_cmds(ElmcWorkerState *state) {
        drain_pending_cmds(state);
        return 0;
      }

      static int model_cells_len(ElmcWorkerState *state) {
        ElmcValue *model = elmc_worker_model(state);
        if (!model) return -1;
        ElmcValue *cells = elmc_record_get_index(model, MODEL_FIELD_CELLS);
        int len = 0;
        ElmcValue *cursor = cells;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          len += 1;
          cursor = ((ElmcCons *)cursor->payload)->tail;
        }
        if (cells) elmc_release(cells);
        elmc_release(model);
        return len;
      }

      static int model_turn(ElmcWorkerState *state) {
        ElmcValue *model = elmc_worker_model(state);
        if (!model) return -1;
        ElmcValue *turn_val = elmc_record_get_index(model, MODEL_FIELD_TURN);
        int turn = turn_val ? (int)elmc_as_int(turn_val) : -1;
        if (turn_val) elmc_release(turn_val);
        elmc_release(model);
        return turn;
      }

      int main(void) {
        static const elmc_int_t dir_msgs[4] = {
          ELMC_PEBBLE_MSG_UPPRESSED,
          ELMC_PEBBLE_MSG_RIGHTPRESSED,
          ELMC_PEBBLE_MSG_DOWNPRESSED,
          ELMC_PEBBLE_MSG_LEFTPRESSED
        };

        elmc_rc_track_reset();
        ElmcWorkerState state = {0};
        ElmcValue *context = launch_context();
        if (elmc_worker_init(&state, context) != 0) return 2;
        elmc_release(context);

        if (model_cells_len(&state) != 16) return 8;
        drain_init_cmds(&state);
        if (dispatch_tag_value(&state, ELMC_PEBBLE_MSG_RANDOMGENERATED, 12345) != 0) return 10;
        drain_cmds(&state);

        int prev_turn = model_turn(&state);

        for (int i = 0; i < #{@dispatch_count}; i++) {
          if (dispatch_int(&state, dir_msgs[i % 4]) != 0) return 3;
          drain_cmds(&state);

          int cells_len = model_cells_len(&state);
          int turn = model_turn(&state);
          if (cells_len != 16) {
            fprintf(stderr, "worker cells len=%d after dispatch %d (expected 16)\\n", cells_len, i);
            return 4;
          }
          if (turn < prev_turn) {
            fprintf(stderr, "worker turn regressed to %d after dispatch %d (was %d)\\n", turn, i, prev_turn);
            return 5;
          }
          prev_turn = turn;
        }

        int turns = model_turn(&state);
        drain_cmds(&state);
        elmc_worker_deinit(&state);

        if (turns <= 0) {
          fprintf(stderr, "worker board never moved after #{@dispatch_count} directional presses\\n");
          return 6;
        }

        printf("rc_ok worker_model_swap turns=%d\\n", turns);
        return 0;
      }
      """
    )

    out = RcTrackHarness.run_worker_harness!(@out_dir, harness_path, "rc_track_worker_model_swap")
    RcTrackHarness.assert_balanced!(out)

    turns =
      Regex.run(~r/turns=(\d+)/, out)
      |> Enum.at(1)
      |> String.to_integer()

    assert turns > 0
  end
end
