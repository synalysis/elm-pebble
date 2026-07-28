defmodule Elmc.Backend.Plan.Worker.Emit do
  @moduledoc """
  Shared worker subscription slot emit and TEA extract/snapshot C from
  `Plan.Worker.Layout` metadata. Pure cmd-queue helpers live in
  `Elmc.Runtime.CmdQueue`. TEA host shells (`init` / `dispatch`) emit from
  `Plan.Worker.Host.Emit`.
  """
  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.Plan.Worker.Layout

  @spec worker_slot_defines(Layout.t()) :: String.t()
  def worker_slot_defines(%{compact: false}), do: ""

  def worker_slot_defines(%{slot_map: slot_map, frame_slot: frame_slot}) do
    lines =
      Enum.map(slot_map, fn {_mask, {name, index}} ->
        "#define #{name} #{index}"
      end)

    frame_line =
      if is_integer(frame_slot) do
        ["#define ELMC_WORKER_SLOT_FRAME #{frame_slot}"]
      else
        []
      end

    (lines ++ frame_line)
    |> Enum.sort()
    |> Enum.join("\n")
    |> case do
      "" -> ""
      defines -> defines <> "\n"
    end
  end

  @spec sub_tag_slot_fn(Layout.t()) :: String.t()
  def sub_tag_slot_fn(%{compact: false}) do
    """
    static int elmc_sub_tag_slot(int64_t mask) {
      if (mask == 0) return -1;
      if ((mask & (1LL << 13)) != 0) return 13;
      if ((mask & (mask - 1)) != 0) return -1;
      int bit = 0;
      while (bit < 32 && (mask & (1LL << bit)) == 0) bit++;
      return bit < 32 ? bit : -1;
    }
    """
  end

  def sub_tag_slot_fn(%{compact: true} = layout) do
    frame_guard =
      if is_integer(layout.frame_slot) do
        "  if ((mask & (1LL << 13)) != 0) return ELMC_WORKER_SLOT_FRAME;\n"
      else
        ""
      end

    table_rows =
      layout.slot_map
      |> Enum.map(fn {mask, {_name, index}} ->
        "  { #{mask_case_label(mask)}, #{index} }"
      end)

    table_body =
      if table_rows == [] do
        ""
      else
        """
        static const struct { int64_t mask; int slot; } elmc_worker_sub_slot_table[] = {
        #{Enum.join(table_rows, ",\n")},
        };
        """
      end

    lookup_loop =
      if table_rows == [] do
        "  (void)mask;\n  return -1;"
      else
        """
        for (unsigned int i = 0; i < sizeof(elmc_worker_sub_slot_table) / sizeof(elmc_worker_sub_slot_table[0]); i++) {
          if (elmc_worker_sub_slot_table[i].mask == mask) return elmc_worker_sub_slot_table[i].slot;
        }
        return -1;
        """
      end

    """
    #{table_body}static int elmc_sub_tag_slot(int64_t mask) {
      if (mask == 0) return -1;
    #{frame_guard}#{lookup_loop}
    }
    """
  end

  @spec subscription_runtime_c() :: String.t()
  def subscription_runtime_c do
    """
    static void elmc_worker_clear_sub_tags(ElmcWorkerState *state) {
      if (!state) return;
      for (int i = 0; i < ELMC_WORKER_SUB_TAG_SLOTS; i++) state->sub_msg_tags[i] = 0;
      state->button_raw_sub_count = 0;
    }

    static int elmc_worker_mask_is_button_raw(int64_t mask) {
      return (mask & (1LL << 14)) != 0;
    }

    static void elmc_worker_apply_sub(ElmcWorkerState *state, ElmcValue *sub) {
      if (!state || !sub) return;

      if (sub->tag == ELMC_TAG_SUB && sub->payload != NULL) {
        ElmcSubPayload *payload = (ElmcSubPayload *)sub->payload;
        state->subscriptions |= payload->mask;
        if (elmc_worker_mask_is_button_raw(payload->mask) && payload->arity >= 3) {
          if (state->button_raw_sub_count < ELMC_WORKER_MAX_BUTTON_RAW_SUBS) {
            ElmcButtonRawSub *entry = &state->button_raw_subs[state->button_raw_sub_count++];
            entry->button_id = payload->p0;
            entry->event = payload->p1;
            entry->msg_tag = payload->p2;
          }
          return;
        }
        if (payload->arity > 0) {
          int slot = elmc_sub_tag_slot(payload->mask);
          if (slot >= 0 && slot < ELMC_WORKER_SUB_TAG_SLOTS) state->sub_msg_tags[slot] = payload->p0;
        }
        return;
      }

      if (sub->tag == ELMC_TAG_LIST && sub->payload != NULL) {
        ElmcValue *cursor = sub;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *cons = (ElmcCons *)cursor->payload;
          if (cons->head) elmc_worker_apply_sub(state, cons->head);
          cursor = cons->tail;
        }
      }
    }

    elmc_int_t elmc_worker_sub_msg_tag(ElmcWorkerState *state, int64_t flag) {
      if (!state || flag == 0) return 0;
      int slot = elmc_sub_tag_slot(flag);
      if (slot < 0 || slot >= ELMC_WORKER_SUB_TAG_SLOTS) return 0;
      return state->sub_msg_tags[slot];
    }

    elmc_int_t elmc_worker_button_raw_msg_tag(ElmcWorkerState *state, elmc_int_t button_id, elmc_int_t event) {
      if (!state) return 0;
      for (int i = 0; i < state->button_raw_sub_count; i++) {
        ElmcButtonRawSub *entry = &state->button_raw_subs[i];
        if (entry->button_id == button_id && entry->event == event) return entry->msg_tag;
      }
      return 0;
    }
    """
  end

  @spec tea_preamble_c() :: String.t()
  def tea_preamble_c do
    """
    #include "elmc_worker.h"
    #include <string.h>
    #if defined(__has_include)
    #if __has_include("../../elmc_emulator_build_flags.h")
    #include "../../elmc_emulator_build_flags.h"
    #elif __has_include("elmc_emulator_build_flags.h")
    #include "elmc_emulator_build_flags.h"
    #endif
    #endif

    #if defined(ELMC_PEBBLE_PLATFORM)
    #include <pebble.h>
    #define ELMC_WORKER_LOG_RC_FAIL(site, rc) \\
      do { \\
        ELMC_RC_LOG_FAIL((rc), (site), "failed"); \\
        APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC %s RC %u line %u", (site), (unsigned)(rc), (unsigned)elmc_last_fail_line); \\
      } while (0)
    #else
    #define ELMC_WORKER_LOG_RC_FAIL(site, rc) ELMC_RC_LOG_FAIL((rc), (site), "failed")
    #endif

    #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_HEAP_LOG
    static void elmc_worker_heap_log(const char *label) {
      APP_LOG(
        APP_LOG_LEVEL_INFO,
        "ELMC heap %s used=%lu free=%lu",
        label ? label : "?",
        (unsigned long)heap_bytes_used(),
        (unsigned long)heap_bytes_free());
    }
    #else
    #define elmc_worker_heap_log(label) do { (void)(label); } while (0)
    #endif
    """
  end

  @doc """
  TEA tuple extract + last-dispatch snapshot helpers.

  Pure `elmc_cmd_queue_*` helpers live in `Elmc.Runtime.CmdQueue`.
  """
  @spec cmd_queue_runtime_c() :: String.t()
  def cmd_queue_runtime_c do
    """
    /* Transfer ownership from (model, cmd) tuple without retaining or double-freeing. */
    static ElmcValue *extract_model_take(ElmcValue *value) {
      if (!value) return NULL;
      if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_retain(value);
      ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
      if (!pair->first) return NULL;
      ElmcValue *model = pair->first;
      pair->first = NULL;
      return model;
    }

    static ElmcValue *extract_cmd_take(ElmcValue *value) {
      if (!value) return elmc_int_zero();
      if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_int_zero();
      ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
      if (!pair->second) return elmc_int_zero();
      ElmcValue *cmd = pair->second;
      pair->second = NULL;
      return cmd;
    }

    #if ELMC_WORKER_LAST_DISPATCH_CMD_CAP > 0
    static void elmc_worker_dispatch_cmd_clear(ElmcWorkerDispatchCmd *out) {
      if (!out) return;
      out->kind = 0;
      out->p0 = 0;
      out->p1 = 0;
      out->p2 = 0;
      out->p3 = 0;
      out->p4 = 0;
      out->p5 = 0;
      out->text[0] = '\\0';
    }

    static int elmc_worker_dispatch_cmd_from_value(ElmcValue *value, ElmcWorkerDispatchCmd *out_cmd) {
      if (!out_cmd) return -1;
      elmc_worker_dispatch_cmd_clear(out_cmd);
      if (!value) return -2;
      if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) {
        out_cmd->kind = elmc_as_int(value);
        return 0;
      }
      if (value->tag == ELMC_TAG_CMD && value->payload != NULL) {
        ElmcCmdPayload *cmd = (ElmcCmdPayload *)value->payload;
        out_cmd->kind = cmd->kind;
        if (cmd->arity > 0) out_cmd->p0 = cmd->p0;
        if (cmd->arity > 1) out_cmd->p1 = cmd->p1;
        if (cmd->arity > 2) out_cmd->p2 = cmd->p2;
        if (cmd->arity > 3) out_cmd->p3 = cmd->p3;
        if (cmd->arity > 4) out_cmd->p4 = cmd->p4;
        if (cmd->arity > 5) out_cmd->p5 = cmd->p5;
        if (cmd->text && cmd->text->tag == ELMC_TAG_STRING && cmd->text->payload) {
          strncpy(out_cmd->text, (const char *)cmd->text->payload, sizeof(out_cmd->text) - 1);
          out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
        }
        return 0;
      }
      return -3;
    }
    static void elmc_worker_snapshot_last_dispatch_cmds(ElmcWorkerState *state, ElmcValue *queue) {
      if (!state) return;
      state->last_dispatch_cmd_count = 0;
      if (!queue || elmc_cmd_is_none(queue)) return;

      ElmcValue *cursor = queue;
      while (cursor && state->last_dispatch_cmd_count < ELMC_WORKER_LAST_DISPATCH_CMD_CAP) {
        if (cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && !elmc_cmd_is_none(node->head)) {
            if (elmc_worker_dispatch_cmd_from_value(node->head, &state->last_dispatch_cmds[state->last_dispatch_cmd_count]) == 0) {
              state->last_dispatch_cmd_count += 1;
            }
          }
          cursor = node->tail;
          continue;
        }
        if (!elmc_cmd_is_none(cursor)) {
          if (elmc_worker_dispatch_cmd_from_value(cursor, &state->last_dispatch_cmds[state->last_dispatch_cmd_count]) == 0) {
            state->last_dispatch_cmd_count += 1;
          }
        }
        break;
      }
    }
    #endif
    """
  end
  @spec tea_host_api_c() :: String.t()
  def tea_host_api_c do
    """
    int elmc_worker_dispatch_needs_render(ElmcWorkerState *state) {
      if (!state) return 0;
      return state->dispatch_needs_render;
    }

    ElmcValue *elmc_worker_model(ElmcWorkerState *state) {
      if (!state || !state->model) return NULL;
      return elmc_retain(state->model);
    }

    ElmcValue *elmc_worker_pending_cmds_borrow(ElmcWorkerState *state) {
      if (!state || !state->pending_cmd) return elmc_cmd_none();
      return elmc_retain(state->pending_cmd);
    }

    int elmc_worker_last_dispatch_cmd_count(ElmcWorkerState *state) {
      if (!state) return 0;
    #if ELMC_WORKER_LAST_DISPATCH_CMD_CAP > 0
      return state->last_dispatch_cmd_count;
    #else
      return 0;
    #endif
    }

    int elmc_worker_last_dispatch_cmd_at(ElmcWorkerState *state, int index, ElmcWorkerDispatchCmd *out_cmd) {
    #if ELMC_WORKER_LAST_DISPATCH_CMD_CAP > 0
      if (!state || !out_cmd || index < 0 || index >= state->last_dispatch_cmd_count) return -1;
      *out_cmd = state->last_dispatch_cmds[index];
      return 0;
    #else
      (void)state;
      (void)index;
      (void)out_cmd;
      return -1;
    #endif
    }

    ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state) {
      if (!state) return NULL;
      if (!state->pending_cmd) {
        return elmc_cmd_none();
      }

      while (state->pending_cmd && state->pending_cmd->tag == ELMC_TAG_LIST) {
        if (state->pending_cmd->payload == NULL) {
          elmc_release(state->pending_cmd);
          state->pending_cmd = elmc_cmd_none();
          return elmc_cmd_none();
        }

        ElmcCons *node = (ElmcCons *)state->pending_cmd->payload;
        ElmcValue *head = node->head;
        ElmcValue *rest = node->tail;
        /* Transfer ownership: detach before release (list release walks the spine). */
        node->head = NULL;
        node->tail = NULL;
        elmc_release(state->pending_cmd);
        state->pending_cmd = rest ? rest : elmc_cmd_none();

        if (elmc_cmd_is_none(head)) {
          elmc_release(head);
          continue;
        }

        return head;
      }

      if (elmc_cmd_is_none(state->pending_cmd)) {
        ElmcValue *none = elmc_cmd_none();
        elmc_release(state->pending_cmd);
        state->pending_cmd = none;
        return none;
      }

      ElmcValue *cmd = state->pending_cmd;
      state->pending_cmd = elmc_cmd_none();
      return cmd;
    }

    int64_t elmc_worker_subscriptions(ElmcWorkerState *state) {
      if (!state) return 0;
      return state->subscriptions;
    }

    elmc_int_t elmc_worker_last_fail_code(void) {
      return (elmc_int_t)elmc_rc_fail_code();
    }

    elmc_int_t elmc_worker_last_fail_line(void) {
      return (elmc_int_t)elmc_last_fail_line;
    }

    void elmc_worker_deinit(ElmcWorkerState *state) {
      if (!state) return;
      if (state->model) {
        elmc_release(state->model);
        state->model = NULL;
      }
      if (state->pending_cmd) {
        elmc_release(state->pending_cmd);
        state->pending_cmd = NULL;
      }
    #if ELMC_WORKER_LAST_DISPATCH_CMD_CAP > 0
      state->last_dispatch_cmd_count = 0;
    #endif
      state->subscriptions = 0;
    }
    """
  end

  defp mask_case_label(mask) when is_binary(mask) do
    Map.get(Emit.subscription_mask_literals(), mask, mask)
  end
end
