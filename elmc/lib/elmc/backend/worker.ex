defmodule Elmc.Backend.Worker do
  @moduledoc """
  Generates a minimal C worker adapter for Elm-like init/update loops.
  """

  alias ElmEx.IR

  @spec write_worker_adapter(IR.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def write_worker_adapter(%IR{} = ir, out_dir, entry_module) do
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_worker.h"), worker_header()),
         :ok <- File.write(Path.join(c_dir, "elmc_worker.c"), worker_source(ir, entry_module)) do
      :ok
    end
  end

  @spec worker_header() :: String.t()
  defp worker_header do
    """
    #ifndef ELMC_WORKER_H
    #define ELMC_WORKER_H

    #include "elmc_generated.h"

    typedef struct {
      ElmcValue *model;
      ElmcValue *pending_cmd;
      int64_t subscriptions;
    } ElmcWorkerState;

    int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags);
    int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg);
    ElmcValue *elmc_worker_model(ElmcWorkerState *state);
    ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state);
    int64_t elmc_worker_subscriptions(ElmcWorkerState *state);
    void elmc_worker_deinit(ElmcWorkerState *state);

    #endif
    """
  end

  @spec worker_source(ElmEx.IR.t(), String.t()) :: String.t()
  defp worker_source(ir, entry_module) do
    module =
      Enum.find(ir.modules, fn mod ->
        mod.name == entry_module
      end)

    declarations = if module, do: module.declarations, else: []
    has_init = Enum.any?(declarations, &(&1.kind == :function and &1.name == "init"))
    has_update = Enum.any?(declarations, &(&1.kind == :function and &1.name == "update"))

    has_subscriptions =
      Enum.any?(declarations, &(&1.kind == :function and &1.name == "subscriptions"))

    safe_module = entry_module |> String.replace(".", "_")

    init_call =
      if has_init do
        """
        ElmcValue *args[] = { flags };
          ElmcValue *result = elmc_fn_#{safe_module}_init(args, 1);
        """
      else
        """
        (void)flags;
          ElmcValue *result = elmc_new_int(0);
        """
      end

    init_missing_guard = if has_init, do: "", else: "  return -3;\n"

    update_call =
      if has_update do
        """
        ElmcValue *args[] = { msg, state->model };
          ElmcValue *result = elmc_fn_#{safe_module}_update(args, 2);
        """
      else
        """
        (void)msg;
          ElmcValue *result = elmc_new_int(0);
        """
      end

    update_missing_guard = if has_update, do: "", else: "  return -4;\n"

    subscriptions_call =
      if has_subscriptions do
        """
        ElmcValue *args[] = { state->model };
          ElmcValue *result = elmc_fn_#{safe_module}_subscriptions(args, 1);
        """
      else
        """
        ElmcValue *result = elmc_new_int(0);
        """
      end

    """
    #include "elmc_worker.h"

    static ElmcValue *extract_model(ElmcValue *value) {
      if (!value) return elmc_new_int(0);
      if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_retain(value);
      ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
      if (!pair->first) return elmc_new_int(0);
      return elmc_retain(pair->first);
    }

    static ElmcValue *extract_cmd(ElmcValue *value) {
      if (!value) return elmc_new_int(0);
      if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_new_int(0);
      ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
      if (!pair->second) return elmc_new_int(0);
      return elmc_retain(pair->second);
    }

    static int elmc_cmd_is_none(ElmcValue *value) {
      return !value || ((value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) && elmc_as_int(value) == 0);
    }

    static ElmcValue *elmc_cmd_singleton(ElmcValue *cmd) {
      ElmcValue *empty = elmc_list_nil();
      ElmcValue *list = elmc_list_cons(cmd, empty);
      elmc_release(empty);
      return list;
    }

    static ElmcValue *elmc_cmd_queue_append(ElmcValue *existing, ElmcValue *next) {
      if (elmc_cmd_is_none(existing) && elmc_cmd_is_none(next)) return elmc_new_int(0);
      if (elmc_cmd_is_none(existing)) return elmc_retain(next);
      if (elmc_cmd_is_none(next)) return elmc_retain(existing);

      if (existing->tag == ELMC_TAG_LIST && next->tag == ELMC_TAG_LIST) {
        return elmc_list_append(existing, next);
      }

      if (existing->tag == ELMC_TAG_LIST) {
        ElmcValue *next_list = elmc_cmd_singleton(next);
        ElmcValue *merged = elmc_list_append(existing, next_list);
        elmc_release(next_list);
        return merged;
      }

      ElmcValue *existing_list = elmc_cmd_singleton(existing);

      if (next->tag == ELMC_TAG_LIST) {
        ElmcValue *merged = elmc_list_append(existing_list, next);
        elmc_release(existing_list);
        return merged;
      }

      ElmcValue *next_list = elmc_cmd_singleton(next);
      ElmcValue *merged = elmc_list_append(existing_list, next_list);
      elmc_release(existing_list);
      elmc_release(next_list);
      return merged;
    }

    static int64_t compute_subscriptions(ElmcWorkerState *state) {
      if (!state || !state->model) return 0;
    #{subscriptions_call}
      int64_t value = result ? elmc_as_int(result) : 0;
      elmc_release(result);
      return value;
    }

    int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags) {
      if (!state) return -1;
      state->subscriptions = 0;
    #{init_missing_guard}#{init_call}
      ElmcValue *next_model = extract_model(result);
      if (!next_model) {
        elmc_release(result);
        return -2;
      }
      state->model = next_model;
      state->pending_cmd = extract_cmd(result);
      elmc_release(result);
      state->subscriptions = compute_subscriptions(state);
      return 0;
    }

    int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg) {
      if (!state || !state->model) return -1;
    #{update_missing_guard}#{update_call}
      ElmcValue *next_model = extract_model(result);
      if (!next_model) {
        elmc_release(result);
        return -2;
      }
      elmc_release(state->model);
      state->model = next_model;
      ElmcValue *next_cmd = extract_cmd(result);
      ElmcValue *merged_cmd = elmc_cmd_queue_append(state->pending_cmd, next_cmd);
      if (state->pending_cmd) {
        elmc_release(state->pending_cmd);
      }
      elmc_release(next_cmd);
      state->pending_cmd = merged_cmd;
      elmc_release(result);
      state->subscriptions = compute_subscriptions(state);
      return 0;
    }

    ElmcValue *elmc_worker_model(ElmcWorkerState *state) {
      if (!state || !state->model) return NULL;
      return elmc_retain(state->model);
    }

    ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state) {
      if (!state) return NULL;
      if (!state->pending_cmd) {
        return elmc_new_int(0);
      }

      while (state->pending_cmd && state->pending_cmd->tag == ELMC_TAG_LIST) {
        if (state->pending_cmd->payload == NULL) {
          elmc_release(state->pending_cmd);
          state->pending_cmd = elmc_new_int(0);
          return elmc_new_int(0);
        }

        ElmcCons *node = (ElmcCons *)state->pending_cmd->payload;
        ElmcValue *head = node->head ? elmc_retain(node->head) : elmc_new_int(0);
        ElmcValue *next_pending = node->tail ? elmc_retain(node->tail) : elmc_new_int(0);
        elmc_release(state->pending_cmd);
        state->pending_cmd = next_pending;

        if (head->tag == ELMC_TAG_LIST) {
          ElmcValue *merged_pending = elmc_cmd_queue_append(head, state->pending_cmd);
          elmc_release(state->pending_cmd);
          state->pending_cmd = merged_pending;
          elmc_release(head);
          continue;
        }

        if (elmc_cmd_is_none(head)) {
          elmc_release(head);
          continue;
        }

        return head;
      }

      if (elmc_cmd_is_none(state->pending_cmd)) {
        elmc_release(state->pending_cmd);
        state->pending_cmd = elmc_new_int(0);
        return elmc_new_int(0);
      }

      ElmcValue *cmd = state->pending_cmd;
      state->pending_cmd = elmc_new_int(0);
      return cmd;
    }

    int64_t elmc_worker_subscriptions(ElmcWorkerState *state) {
      if (!state) return 0;
      return state->subscriptions;
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
      state->subscriptions = 0;
    }
    """
  end
end
