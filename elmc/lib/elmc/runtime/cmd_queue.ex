defmodule Elmc.Runtime.CmdQueue do
  @moduledoc """
  TEA pending-cmd queue helpers shared by the worker host.

  Ownership uses `_take` semantics (distinct from `elmc_cmd_batch_*`).
  """

  @spec header_declarations() :: String.t()
  def header_declarations do
    """
    int elmc_cmd_is_none(ElmcValue *value);
    ElmcValue *elmc_cmd_none(void);
    RC elmc_cmd_queue_cons_take(ElmcValue **out, ElmcValue *head, ElmcValue *tail);
    RC elmc_cmd_queue_push_back_take(ElmcValue **out, ElmcValue *queue, ElmcValue *cmd);
    RC elmc_cmd_queue_concat_take(ElmcValue **out, ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_cmd_queue_peel_manager(ElmcValue *value);
    RC elmc_cmd_queue_push_entry(ElmcValue **out, ElmcValue *flat, ElmcValue *entry);
    RC elmc_cmd_queue_normalize(ElmcValue **out, ElmcValue *cmd);
    """
  end

  @spec implementation() :: String.t()
  def implementation do
    """
    int elmc_cmd_is_none(ElmcValue *value) {
      if (!value) return 1;
      if ((value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) && elmc_as_int(value) == 0) {
        return 1;
      }
      if (value->tag == ELMC_TAG_CMD && value->payload != NULL) {
        ElmcCmdPayload *cmd = (ElmcCmdPayload *)value->payload;
        return cmd->kind == 0;
      }
      return 0;
    }

    ElmcValue *elmc_cmd_none(void) {
      return elmc_int_zero();
    }

    RC elmc_cmd_queue_cons_take(ElmcValue **out, ElmcValue *head, ElmcValue *tail) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_list_cons(out, head, tail);
        CHECK_RC(rc);
      CATCH_END
      return rc;
    }

    RC elmc_cmd_queue_push_back_take(ElmcValue **out, ElmcValue *queue, ElmcValue *cmd) {
      RC rc = RC_SUCCESS;
      ElmcValue *cell = NULL;
      ElmcValue *head_cell = NULL;
      CATCH_BEGIN
        if (!cmd || elmc_cmd_is_none(cmd)) {
          elmc_release(cmd);
          cmd = NULL;
          *out = queue ? queue : elmc_cmd_none();
          queue = NULL;
        } else if (!queue || elmc_cmd_is_none(queue)) {
          elmc_release(queue);
          queue = NULL;
          *out = cmd;
          cmd = NULL;
        } else {
          rc = elmc_cmd_queue_cons_take(&cell, cmd, elmc_list_nil());
          cmd = NULL;
          CHECK_RC(rc);
          if (!cell || elmc_cmd_is_none(cell)) {
            *out = queue ? queue : elmc_cmd_none();
            queue = NULL;
            cell = NULL;
          } else if (queue->tag == ELMC_TAG_CMD) {
            rc = elmc_cmd_queue_cons_take(&head_cell, queue, cell);
            queue = NULL;
            cell = NULL;
            CHECK_RC(rc);
            *out = head_cell ? head_cell : elmc_cmd_none();
            head_cell = NULL;
          } else if (queue->tag != ELMC_TAG_LIST) {
            elmc_release(cell);
            cell = NULL;
            *out = queue;
            queue = NULL;
          } else {
            ElmcValue **tail = &queue;
            ElmcValue *cursor = queue;
            while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
              ElmcCons *node = (ElmcCons *)cursor->payload;
              tail = &node->tail;
              cursor = node->tail;
            }
            *tail = cell;
            cell = NULL;
            *out = queue;
            queue = NULL;
          }
        }
      CATCH_END
      elmc_release(cmd);
      elmc_release(queue);
      elmc_release(cell);
      elmc_release(head_cell);
      return rc;
    }

    RC elmc_cmd_queue_concat_take(ElmcValue **out, ElmcValue *left, ElmcValue *right) {
      RC rc = RC_SUCCESS;
      ElmcValue *tail_cell = NULL;
      ElmcValue *pair = NULL;
      CATCH_BEGIN
        if (!left || elmc_cmd_is_none(left)) {
          elmc_release(left);
          left = NULL;
          *out = right ? right : elmc_cmd_none();
          right = NULL;
        } else if (!right || elmc_cmd_is_none(right)) {
          elmc_release(right);
          right = NULL;
          *out = left;
          left = NULL;
        } else if (left->tag == ELMC_TAG_CMD) {
          if (right->tag == ELMC_TAG_CMD) {
            rc = elmc_cmd_queue_cons_take(&tail_cell, right, elmc_list_nil());
            right = NULL;
            CHECK_RC(rc);
            rc = elmc_cmd_queue_cons_take(&pair, left, tail_cell ? tail_cell : elmc_list_nil());
            left = NULL;
            tail_cell = NULL;
            CHECK_RC(rc);
            *out = pair;
            pair = NULL;
          } else if (right->tag == ELMC_TAG_LIST) {
            rc = elmc_cmd_queue_cons_take(&pair, left, right);
            left = NULL;
            right = NULL;
            CHECK_RC(rc);
            *out = pair;
            pair = NULL;
          } else {
            elmc_release(right);
            right = NULL;
            *out = left;
            left = NULL;
          }
        } else if (right->tag == ELMC_TAG_CMD) {
          rc = elmc_cmd_queue_push_back_take(out, left, right);
          left = NULL;
          right = NULL;
          CHECK_RC(rc);
        } else if (right->tag != ELMC_TAG_LIST) {
          elmc_release(right);
          right = NULL;
          *out = left;
          left = NULL;
        } else if (left->tag != ELMC_TAG_LIST) {
          elmc_release(left);
          left = NULL;
          *out = right;
          right = NULL;
        } else {
          ElmcValue **tail = &left;
          ElmcValue *cursor = left;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            tail = &node->tail;
            cursor = node->tail;
          }
          *tail = right;
          right = NULL;
          *out = left;
          left = NULL;
        }
      CATCH_END
      elmc_release(left);
      elmc_release(right);
      elmc_release(tail_cell);
      elmc_release(pair);
      return rc;
    }

    ElmcValue *elmc_cmd_queue_peel_manager(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_RECORD) {
        return NULL;
      }

      ElmcValue *tag = elmc_record_get(value, "$");
      if (!tag) {
        return NULL;
      }

      elmc_int_t tag_num = elmc_as_int(tag);
      elmc_release(tag);

      if (tag_num == 2) {
        return elmc_record_get(value, "m");
      }

      if (tag_num == 3) {
        return elmc_record_get(value, "o");
      }

      return NULL;
    }

    RC elmc_cmd_queue_push_entry(ElmcValue **out, ElmcValue *flat, ElmcValue *entry) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        for (;;) {
          ElmcValue *peeled = elmc_cmd_queue_peel_manager(entry);
          if (!peeled) {
            break;
          }

          elmc_release(entry);
          entry = peeled;
        }

        if (!entry) {
          *out = flat ? flat : elmc_cmd_none();
          flat = NULL;
        } else if (elmc_cmd_is_none(entry)) {
          elmc_release(entry);
          entry = NULL;
          *out = flat ? flat : elmc_cmd_none();
          flat = NULL;
        } else if (entry->tag == ELMC_TAG_LIST) {
          ElmcValue *cursor = entry;
          ElmcValue *current_flat = flat;
          flat = NULL;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            ElmcValue *head = node->head;
            node->head = NULL;
            rc = elmc_cmd_queue_push_entry(&current_flat, current_flat, head);
            CHECK_RC(rc);
            ElmcValue *next = node->tail;
            node->tail = NULL;
            ElmcValue *cursor_cell = cursor;
            cursor = next;
            elmc_release(cursor_cell);
          }
          /* List spine cells were released in the loop; do not release entry again. */
          entry = NULL;
          *out = current_flat;
        } else {
          rc = elmc_cmd_queue_push_back_take(out, flat, entry);
          flat = NULL;
          entry = NULL;
          CHECK_RC(rc);
        }
      CATCH_END
      elmc_release(flat);
      elmc_release(entry);
      return rc;
    }

    RC elmc_cmd_queue_normalize(ElmcValue **out, ElmcValue *cmd) {
      RC rc = RC_SUCCESS;
      ElmcValue *flat = NULL;
      ElmcValue *materialized = NULL;
      CATCH_BEGIN
        if (!cmd || elmc_cmd_is_none(cmd)) {
          elmc_release(cmd);
          cmd = NULL;
          *out = elmc_cmd_none();
        } else {
          materialized = cmd;
          cmd = NULL;

          for (;;) {
            ElmcValue *peeled = elmc_cmd_queue_peel_manager(materialized);
            if (!peeled) {
              break;
            }

            elmc_release(materialized);
            materialized = peeled;
          }

          if (!materialized || elmc_cmd_is_none(materialized)) {
            elmc_release(materialized);
            materialized = NULL;
            *out = elmc_cmd_none();
          } else if (materialized->tag != ELMC_TAG_LIST) {
            flat = elmc_cmd_none();
            rc = elmc_cmd_queue_push_back_take(&flat, flat, materialized);
            materialized = NULL;
            CHECK_RC(rc);
            *out = flat;
            flat = NULL;
          } else {
            flat = elmc_cmd_none();
            rc = elmc_cmd_queue_push_entry(&flat, flat, materialized);
            CHECK_RC(rc);
            materialized = NULL;
            *out = flat;
            flat = NULL;
          }
        }
      CATCH_END
      elmc_release(cmd);
      elmc_release(materialized);
      elmc_release(flat);
      return rc;
    }
    """
  end
end
