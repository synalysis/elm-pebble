defmodule Elmc.Backend.Plan.Worker.Host.Emit do
  @moduledoc """
  Emit `elmc_worker.c` TEA host shells from `Plan.Worker.HostPlan`.
  """
  alias Elmc.Backend.Plan.Worker.Emit, as: SharedEmit
  alias Elmc.Backend.Plan.Worker.HostPlan
  alias Elmc.Backend.Plan.Worker.ModelNative

  @spec worker_source(HostPlan.t()) :: String.t()
  def worker_source(%HostPlan{} = plan) do
    model_native_c =
      case Map.get(plan, :model_native) do
        nil -> ""
        layout -> ModelNative.sync_helpers_c(layout) <> "\n"
      end

    """
    #{SharedEmit.tea_preamble_c()}

    #{model_native_c}#{SharedEmit.cmd_queue_runtime_c()}

    #{SharedEmit.sub_tag_slot_fn(plan.layout)}

    #{SharedEmit.subscription_runtime_c()}

    #{compute_subscriptions_fn(plan)}

    #{init_fn(plan)}

    #{dispatch_fn(plan)}

    #{tea_host_api_c(plan)}
    """
  end

  defp tea_host_api_c(%HostPlan{model_native: layout}) when not is_nil(layout) do
    SharedEmit.tea_host_api_c()
    |> String.replace(
      """
      ElmcValue *elmc_worker_model(ElmcWorkerState *state) {
        if (!state || !state->model) return NULL;
        return elmc_retain(state->model);
      }
      """,
      """
      ElmcValue *elmc_worker_model(ElmcWorkerState *state) {
        return elmc_worker_model_boxed(state);
      }
      """
    )
  end

  defp tea_host_api_c(_plan), do: SharedEmit.tea_host_api_c()

  defp init_fn(%HostPlan{} = plan) do
    missing_guard = init_missing_guard(plan.init)
    init_call = entry_call_body(plan.init)

    model_store =
      if plan.model_native do
        """
          elmc_worker_model_native_unpack(&state->model_native, next_model);
          state->model = next_model;
        """
      else
        "      state->model = next_model;\n"
      end

    """
    int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags) {
      if (!state) return -1;
      state->subscriptions = 0;
      elmc_worker_clear_sub_tags(state);
      elmc_worker_heap_log("init:start");
    #{missing_guard}#{init_call}
      ElmcValue *next_model = extract_model_take(result);
      if (!next_model) {
        elmc_release(result);
        return -2;
      }
    #{model_store}      state->dispatch_needs_render = 1;
      {
        ElmcValue *pending = NULL;
        ElmcValue *raw_cmd = extract_cmd_take(result);
        RC pending_rc = elmc_cmd_queue_normalize(&pending, raw_cmd);
        if (pending_rc != RC_SUCCESS) {
          ELMC_WORKER_LOG_RC_FAIL("worker init pending cmd", pending_rc);
          elmc_release(result);
          return -2;
        }
    #if ELMC_WORKER_LAST_DISPATCH_CMD_CAP > 0
        elmc_worker_snapshot_last_dispatch_cmds(state, pending);
    #endif
        state->pending_cmd = pending;
      }
      elmc_release(result);
      state->subscriptions = compute_subscriptions(state);
      elmc_worker_heap_log("init:end");
      return 0;
    }
    """
  end

  defp dispatch_fn(%HostPlan{} = plan) do
    missing_guard = dispatch_missing_guard(plan.update)
    update_call = entry_call_body(plan.update)
    refresh = dispatch_subscriptions_refresh(plan)

    if plan.model_native do
      native_dispatch_fn(plan, missing_guard, update_call, refresh)
    else
      boxed_dispatch_fn(plan, missing_guard, update_call, refresh)
    end
  end

  defp native_dispatch_fn(_plan, missing_guard, update_call, refresh) do
    """
    int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg) {
      if (!state) return -1;
      state->dispatch_needs_render = 0;
      elmc_worker_heap_log("update:start");
      ElmcWorkerModelNative prev_native = state->model_native;
      if (!state->model) {
        ElmcValue *boxed = NULL;
        if (elmc_worker_model_native_box(&boxed, &state->model_native) != RC_SUCCESS) {
          return -2;
        }
        state->model = boxed;
      }
      ElmcValue *prev_model = state->model;
    #{missing_guard}#{update_call}
      ElmcValue *next_model = extract_model_take(result);
      if (!next_model) {
        elmc_release(result);
        return -2;
      }
      elmc_worker_model_native_unpack(&state->model_native, next_model);
      int model_changed = (next_model != prev_model);
      if (model_changed) {
        elmc_release(state->model);
        state->model = next_model;
      } else if (next_model->rc > 1) {
        elmc_release(next_model);
      }
      if (model_changed ||
          memcmp(&prev_native, &state->model_native, sizeof(prev_native)) != 0) {
        state->dispatch_needs_render = 1;
      }
      {
        ElmcValue *next_cmd = NULL;
        ElmcValue *raw_cmd = extract_cmd_take(result);
        RC next_rc = elmc_cmd_queue_normalize(&next_cmd, raw_cmd);
        if (next_rc != RC_SUCCESS) {
          ELMC_WORKER_LOG_RC_FAIL("worker update pending cmd", next_rc);
          elmc_release(result);
          return -2;
        }
    #if ELMC_WORKER_LAST_DISPATCH_CMD_CAP > 0
        elmc_worker_snapshot_last_dispatch_cmds(state, next_cmd);
    #endif
        if (!elmc_cmd_is_none(next_cmd)) {
          state->dispatch_needs_render = 1;
        }
        ElmcValue *merged = NULL;
        RC merge_rc = elmc_cmd_queue_concat_take(&merged, state->pending_cmd, next_cmd);
        if (merge_rc != RC_SUCCESS) {
          elmc_release(next_cmd);
          ELMC_WORKER_LOG_RC_FAIL("worker update cmd concat", merge_rc);
          elmc_release(result);
          return -2;
        }
        state->pending_cmd = merged;
      }
      elmc_release(result);
    #{refresh}  elmc_worker_heap_log("update:end");
      return 0;
    }
    """
  end

  defp boxed_dispatch_fn(_plan, missing_guard, update_call, refresh) do
    """
    int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg) {
      if (!state || !state->model) return -1;
      state->dispatch_needs_render = 0;
      elmc_worker_heap_log("update:start");
      ElmcValue *prev_model = state->model;
      uint32_t prev_mut_gen = elmc_record_mutation_gen(prev_model);
    #{missing_guard}#{update_call}
      ElmcValue *next_model = extract_model_take(result);
      if (!next_model) {
        elmc_release(result);
        return -2;
      }
      int model_changed = (next_model != prev_model);
      if (model_changed) {
        elmc_release(state->model);
      } else if (next_model->rc > 1) {
        elmc_release(next_model);
      }
      state->model = next_model;
      if (model_changed || elmc_record_mutation_gen(next_model) != prev_mut_gen) {
        state->dispatch_needs_render = 1;
      }
      {
        ElmcValue *next_cmd = NULL;
        ElmcValue *raw_cmd = extract_cmd_take(result);
        RC next_rc = elmc_cmd_queue_normalize(&next_cmd, raw_cmd);
        if (next_rc != RC_SUCCESS) {
          ELMC_WORKER_LOG_RC_FAIL("worker update pending cmd", next_rc);
          elmc_release(result);
          return -2;
        }
    #if ELMC_WORKER_LAST_DISPATCH_CMD_CAP > 0
        elmc_worker_snapshot_last_dispatch_cmds(state, next_cmd);
    #endif
        if (!elmc_cmd_is_none(next_cmd)) {
          state->dispatch_needs_render = 1;
        }
        ElmcValue *merged = NULL;
        RC merge_rc = elmc_cmd_queue_concat_take(&merged, state->pending_cmd, next_cmd);
        if (merge_rc != RC_SUCCESS) {
          elmc_release(next_cmd);
          ELMC_WORKER_LOG_RC_FAIL("worker update cmd concat", merge_rc);
          elmc_release(result);
          return -2;
        }
        state->pending_cmd = merged;
      }
      elmc_release(result);
    #{refresh}  elmc_worker_heap_log("update:end");
      return 0;
    }
    """
  end

  defp compute_subscriptions_fn(%HostPlan{} = plan) do
    call = entry_call_body(plan.subscriptions)

    model_guard =
      if plan.model_native do
        "if (!state) return 0;\n"
      else
        "if (!state || !state->model) return 0;\n"
      end

    """
    static int64_t compute_subscriptions(ElmcWorkerState *state) {
      #{model_guard}    #{call}
      elmc_worker_clear_sub_tags(state);
      state->subscriptions = 0;
      if (result) elmc_worker_apply_sub(state, result);
      elmc_release(result);
      return state->subscriptions;
    }
    """
  end

  defp init_missing_guard(%{present?: true}), do: ""

  defp init_missing_guard(%{present?: false, missing_return: code}) when is_integer(code) do
    "  return #{code};\n"
  end

  defp dispatch_missing_guard(%{present?: true}), do: ""

  defp dispatch_missing_guard(%{present?: false, missing_return: code}) when is_integer(code) do
    "  return #{code};\n"
  end

  defp dispatch_subscriptions_refresh(%{model_dependent_subs?: true}) do
    "  if (state->dispatch_needs_render) {\n    state->subscriptions = compute_subscriptions(state);\n  }\n"
  end

  defp dispatch_subscriptions_refresh(_), do: ""

  defp entry_call_body(%{present?: true, call: call}) do
    """
    ElmcValue *result = NULL;
      #{call.call_c}
      #{String.trim(call.on_fail_c)}
    """
  end

  defp entry_call_body(%{present?: false, stub_c: stub}) when is_binary(stub) do
    stub
  end
end
