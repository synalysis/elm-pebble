defmodule Elmc.GeneratedRcTrackGame2048TemplateTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackHarness

  @source_fixture Path.expand("fixtures/simple_project", __DIR__)
  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)
  @project_dir Path.expand("tmp/rc_track_game_2048_template", __DIR__)
  @out_dir Path.expand("tmp/rc_track_game_2048_template_out", __DIR__)

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
  test "game-2048 template survives 100 moves and view renders without rc leaks" do
    harness_path = Path.join(@out_dir, "c/rc_track_game_2048_template_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *aplite_launch_context(void) {
        ElmcValue *reason = elmc_new_int(2);
        ElmcValue *watch_model = elmc_new_string("");
        ElmcValue *watch_profile_id = elmc_new_string("aplite");
        ElmcValue *width = elmc_new_int(144);
        ElmcValue *height = elmc_new_int(168);
        ElmcValue *shape = elmc_new_int(1);
        ElmcValue *color_mode = elmc_new_string("BlackWhite");
        const char *screen_names[] = {"color_mode", "height", "shape", "width"};
        ElmcValue *screen_values[] = {color_mode, height, shape, width};
        ElmcValue *screen = elmc_record_new_take(4, screen_names, screen_values);
        ElmcValue *has_microphone = elmc_new_int(0);
        ElmcValue *has_compass = elmc_new_int(0);
        ElmcValue *supports_health = elmc_new_int(0);
        const char *names[] = {
          "has_compass", "has_microphone", "reason", "screen",
          "supports_health", "watchModel", "watchProfileId"
        };
        ElmcValue *values[] = {
          has_compass, has_microphone, reason, screen,
          supports_health, watch_model, watch_profile_id
        };
        return elmc_record_new_take(7, names, values);
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

      static int scene_rect_cmds(ElmcPebbleApp *app) {
        if (elmc_pebble_ensure_scene(app) != 0) return -1;
        int rects = 0;
        int offset = 0;
        while (offset < app->scene.byte_count) {
          ElmcPebbleDrawCmd cmd = {0};
          if (elmc_pebble_scene_decode_record(app->scene.bytes, app->scene.byte_count, &offset, &cmd) != 0) {
            break;
          }
          if (cmd.kind == ELMC_PEBBLE_DRAW_RECT) rects += 1;
        }
        elmc_pebble_scene_reset_draw_cursor(app);
        return rects;
      }

      static int scene_text_cmds(ElmcPebbleApp *app) {
        if (elmc_pebble_ensure_scene(app) != 0) return -1;
        int texts = 0;
        int offset = 0;
        while (offset < app->scene.byte_count) {
          ElmcPebbleDrawCmd cmd = {0};
          if (elmc_pebble_scene_decode_record(app->scene.bytes, app->scene.byte_count, &offset, &cmd) != 0) {
            break;
          }
          if (cmd.kind == ELMC_PEBBLE_DRAW_TEXT) texts += 1;
        }
        elmc_pebble_scene_reset_draw_cursor(app);
        return texts;
      }

      static int model_nonzero_cells(ElmcPebbleApp *app) {
        ElmcValue *model = elmc_worker_model(&app->worker);
        if (!model) return -1;
        ElmcValue *cells = elmc_record_get(model, "cells");
        int count = 0;
        ElmcValue *cursor = cells;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && elmc_as_int(node->head) != 0) count += 1;
          cursor = node->tail;
        }
        if (cells) elmc_release(cells);
        elmc_release(model);
        return count;
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

      static int model_cells_len(ElmcPebbleApp *app) {
        ElmcValue *model = elmc_worker_model(&app->worker);
        if (!model) return -1;
        ElmcValue *cells = elmc_record_get(model, "cells");
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

      static int model_turn(ElmcPebbleApp *app) {
        ElmcValue *model = elmc_worker_model(&app->worker);
        if (!model) return -1;
        ElmcValue *turn_val = elmc_record_get(model, "turn");
        int turn = turn_val ? (int)elmc_as_int(turn_val) : -1;
        if (turn_val) elmc_release(turn_val);
        elmc_release(model);
        return turn;
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
        ElmcValue *context = aplite_launch_context();
        if (elmc_pebble_init(&app, context) != 0) return 2;
        elmc_release(context);

        if (model_cells_len(&app) != 16) return 8;
        if (drain_init_cmds(&app) != 0) return 16;
        if (model_nonzero_cells(&app) != 2) return 17;
        app.scene.dirty = 1;
        if (elmc_pebble_ensure_scene(&app) != 0) return 13;
        if (scene_rect_cmds(&app) != 16) return 19;
        if (scene_text_cmds(&app) < 2) return 21;
        void *scene_bytes = app.scene.bytes;
        int scene_capacity = app.scene.byte_capacity;
        if (!scene_bytes || scene_capacity <= 0) return 14;

        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_RANDOMGENERATED, 12345) != 0) return 3;
        if (app.scene.bytes != scene_bytes || app.scene.byte_capacity < scene_capacity) return 15;
        drain_cmds(&app);
        if (model_cells_len(&app) != 16) return 9;
        if (drain_view(&app) < 17) return 4;
        app.scene.dirty = 1;
        if (elmc_pebble_ensure_scene(&app) != 0) return 10;
        if (app.scene.command_count < 20) return 11;
        if (app.scene.byte_count <= 0 || app.scene.byte_count > 512) return 12;

        for (int i = 0; i < 100; i++) {
          if (elmc_pebble_dispatch_int(&app, dir_msgs[i % 4]) != 0) return 5;
          drain_cmds(&app);
          if (drain_view(&app) < 17) return 6;
        }

        int turns = model_turn(&app);
        elmc_pebble_deinit(&app);

        if (turns <= 0) {
          fprintf(stderr, "template board never moved after 100 presses (turns=%d)\\n", turns);
          return 7;
        }

        if (!elmc_rc_track_check_balanced()) {
          fprintf(stderr, "rc leak after game-2048 template soak (turns=%d)\\n", turns);
          elmc_rc_track_dump_live(stderr);
          return 1;
        }

        printf("rc_ok game_2048_template turns=%d\\n", turns);
        return 0;
      }
      """
    )

    out =
      RcTrackHarness.run_harness!(
        @out_dir,
        harness_path,
        "rc_track_game_2048_template",
        sources: RcTrackHarness.worker_sources(@out_dir) ++ [harness_path]
      )

    RcTrackHarness.assert_balanced!(out)

    assert Regex.run(~r/turns=(\d+)/, out)
           |> Enum.at(1)
           |> String.to_integer() > 0
  end
end
