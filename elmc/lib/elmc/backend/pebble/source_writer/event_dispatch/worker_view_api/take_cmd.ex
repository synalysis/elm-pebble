defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.WorkerViewApi.TakeCmd do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd) {
      if (!app || !app->initialized || !out_cmd) return -1;
      ElmcValue *cmd = elmc_worker_take_cmd(&app->worker);
      if (!cmd) return -2;
      int rc = elmc_cmd_from_value(cmd, out_cmd);
      elmc_release(cmd);
      return rc;
    }

    static int elmc_pebble_cmd_queue_index(ElmcValue *queue, int target, ElmcPebbleCmd *out_cmd) {
      if (!out_cmd || target < 0) return -1;
      int index = 0;
      ElmcValue *cursor = queue;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcPebbleCmd cmd = {0};
        if (node->head && elmc_cmd_from_value(node->head, &cmd) == 0 &&
            cmd.kind != ELMC_PEBBLE_CMD_NONE) {
          if (index == target) {
            *out_cmd = cmd;
            return 0;
          }
          index += 1;
        }
        cursor = node->tail;
      }
      if (cursor && cursor->tag != ELMC_TAG_LIST) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_cmd_from_value(cursor, &cmd) == 0 && cmd.kind != ELMC_PEBBLE_CMD_NONE) {
          if (index == target) {
            *out_cmd = cmd;
            return 0;
          }
        }
      }
      return -2;
    }

    static int elmc_pebble_cmd_queue_count_value(ElmcValue *queue) {
      int count = 0;
      ElmcValue *cursor = queue;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcPebbleCmd cmd = {0};
        if (node->head && elmc_cmd_from_value(node->head, &cmd) == 0 &&
            cmd.kind != ELMC_PEBBLE_CMD_NONE) {
          count += 1;
        }
        cursor = node->tail;
      }
      if (cursor && cursor->tag != ELMC_TAG_LIST) {
        ElmcPebbleCmd cmd = {0};
        if (elmc_cmd_from_value(cursor, &cmd) == 0 && cmd.kind != ELMC_PEBBLE_CMD_NONE) {
          count += 1;
        }
      }
      return count;
    }

    int elmc_pebble_pending_cmd_count(ElmcPebbleApp *app) {
      if (!app || !app->initialized) return 0;
      ElmcValue *queue = elmc_worker_pending_cmds_borrow(&app->worker);
      if (!queue) return 0;
      int count = elmc_pebble_cmd_queue_count_value(queue);
      elmc_release(queue);
      return count;
    }

    int elmc_pebble_last_dispatch_cmd_count(ElmcPebbleApp *app) {
      if (!app || !app->initialized) return 0;
      return elmc_worker_last_dispatch_cmd_count(&app->worker);
    }

    int elmc_pebble_last_dispatch_cmd_at(ElmcPebbleApp *app, int index, ElmcPebbleCmd *out_cmd) {
      if (!app || !app->initialized || !out_cmd) return -1;
      ElmcWorkerDispatchCmd snap = {0};
      if (elmc_worker_last_dispatch_cmd_at(&app->worker, index, &snap) != 0) return -2;
      out_cmd->kind = snap.kind;
      out_cmd->p0 = snap.p0;
      out_cmd->p1 = snap.p1;
      out_cmd->p2 = snap.p2;
      out_cmd->p3 = snap.p3;
      out_cmd->p4 = snap.p4;
      out_cmd->p5 = snap.p5;
      strncpy(out_cmd->text, snap.text, sizeof(out_cmd->text) - 1);
      out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
      return 0;
    }

    int elmc_pebble_pending_cmd_at(ElmcPebbleApp *app, int index, ElmcPebbleCmd *out_cmd) {
      if (!app || !app->initialized || !out_cmd) return -1;
      ElmcValue *queue = elmc_worker_pending_cmds_borrow(&app->worker);
      if (!queue) return -2;
      int rc = elmc_pebble_cmd_queue_index(queue, index, out_cmd);
      elmc_release(queue);
      return rc;
    }

"""
  end
end
