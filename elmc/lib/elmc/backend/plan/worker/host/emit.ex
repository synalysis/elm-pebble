defmodule Elmc.Backend.Plan.Worker.Host.Emit do
  @moduledoc """
  Emit `elmc_worker.c` TEA host shells from `Plan.Worker.HostPlan`.
  """
  alias Elmc.Backend.Plan.Worker.Emit, as: SharedEmit
  alias Elmc.Backend.Plan.Worker.HostPlan

  @spec worker_source(HostPlan.t()) :: String.t()
  def worker_source(%HostPlan{} = plan) do
    """
    #{SharedEmit.tea_preamble_c()}

    #{SharedEmit.cmd_queue_runtime_c()}

    #{SharedEmit.sub_tag_slot_fn(plan.layout)}

    #{SharedEmit.subscription_runtime_c()}

    #{compute_subscriptions_fn(plan)}

    #{init_fn(plan)}

    #{dispatch_fn(plan)}

    #{SharedEmit.tea_host_api_c()}
    """
  end

  defp init_fn(%HostPlan{} = plan) do
    missing_guard = init_missing_guard(plan.init)
    init_call = entry_call_body(plan.init)

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
      state->model = next_model;
      state->dispatch_needs_render = 1;
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

    """
    static int64_t compute_subscriptions(ElmcWorkerState *state) {
      if (!state || !state->model) return 0;
      #{call}
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
      #{render_call_c(call)}
      #{String.trim(render_on_fail_c(call))}
    """
  end

  defp entry_call_body(%{present?: false, stub_c: stub}) when is_binary(stub) do
    stub
  end

  defp render_call_c(%{abi: :direct, safe_module: safe, fun: fun, rc_var: rc_var, arg_exprs: args}) do
    "RC #{rc_var} = elmc_fn_#{safe}_#{fun}(&result, #{Enum.join(args, ", ")});"
  end

  defp render_call_c(%{abi: :argc, safe_module: safe, fun: fun, rc_var: rc_var, arg_exprs: args}) do
    """
    ElmcValue *args[] = { #{Enum.join(args, ", ")} };
      RC #{rc_var} = elmc_fn_#{safe}_#{fun}(&result, args, #{length(args)});
    """
    |> String.trim()
  end

  defp render_on_fail_c(%{fail_kind: :init_fail, rc_var: rc_var}) do
    """
    if (#{rc_var} != RC_SUCCESS) {
      ELMC_WORKER_LOG_RC_FAIL("worker init", #{rc_var});
      elmc_release(result);
      return -2;
    }
    """
  end

  defp render_on_fail_c(%{fail_kind: :update_fail, rc_var: rc_var}) do
    """
    if (#{rc_var} != RC_SUCCESS) {
      ELMC_WORKER_LOG_RC_FAIL("worker update", #{rc_var});
      elmc_release(result);
      return -2;
    }
    """
  end

  defp render_on_fail_c(%{fail_kind: :sub_fail, rc_var: rc_var}) do
    """
    if (#{rc_var} != RC_SUCCESS) {
      ELMC_WORKER_LOG_RC_FAIL("worker subscriptions", #{rc_var});
      elmc_release(result);
      return 0;
    }
    """
  end

  defp render_on_fail_c(%{rc_var: rc_var, fun: fun}) do
    """
    if (#{rc_var} != RC_SUCCESS) {
      ELMC_WORKER_LOG_RC_FAIL("worker #{fun}", #{rc_var});
      elmc_release(result);
      return -2;
    }
    """
  end
end
