defmodule Elmc.Backend.Plan.Worker.Host.Verify do
  @moduledoc """
  Structural / ABI checks for `%Plan.Worker.HostPlan{}`.

  This is not `Plan.Verify` (owned-reg / `:fn_out` FunctionPlan SSA). It only
  validates HostPlan entry metadata before C emit.
  """
  alias Elmc.Backend.Plan.Worker.HostPlan

  @type error :: {:host_plan, atom(), term()}

  @spec verify(HostPlan.t()) :: :ok | {:error, error()}
  def verify(%HostPlan{} = plan) do
    with :ok <- verify_entry(:init, plan.init),
         :ok <- verify_entry(:update, plan.update),
         :ok <- verify_entry(:subscriptions, plan.subscriptions),
         :ok <- verify_model_dependent(plan),
         :ok <- verify_cmd_cap(plan) do
      :ok
    end
  end

  defp verify_entry(role, %{present?: true, call: call}) when is_map(call) do
    required = [:safe_module, :fun, :abi, :arg_exprs, :rc_var, :fail_kind]

    missing =
      Enum.reject(required, fn key ->
        Map.has_key?(call, key) and present_value?(Map.get(call, key))
      end)

    cond do
      missing != [] ->
        {:error, {:host_plan, :incomplete_entry_call, {role, missing}}}

      call.abi not in [:direct, :argc] ->
        {:error, {:host_plan, :bad_entry_abi, {role, call.abi}}}

      call.fail_kind not in [:init_fail, :update_fail, :sub_fail, :generic_fail] ->
        {:error, {:host_plan, :bad_fail_kind, {role, call.fail_kind}}}

      not is_list(call.arg_exprs) ->
        {:error, {:host_plan, :bad_arg_exprs, role}}

      true ->
        :ok
    end
  end

  defp verify_entry(role, %{present?: false} = entry) do
    cond do
      not is_binary(Map.get(entry, :stub_c)) or entry.stub_c == "" ->
        {:error, {:host_plan, :missing_stub, role}}

      role in [:init, :update] and not is_integer(Map.get(entry, :missing_return)) ->
        {:error, {:host_plan, :missing_return_code, role}}

      true ->
        :ok
    end
  end

  defp verify_entry(role, other) do
    {:error, {:host_plan, :bad_entry, {role, other}}}
  end

  defp verify_model_dependent(%{model_dependent_subs?: true, subscriptions: %{present?: false}}) do
    {:error, {:host_plan, :model_dependent_without_subscriptions, nil}}
  end

  defp verify_model_dependent(_), do: :ok

  defp verify_cmd_cap(%{last_dispatch_cmd_cap: cap}) when is_integer(cap) and cap >= 0, do: :ok

  defp verify_cmd_cap(%{last_dispatch_cmd_cap: cap}) do
    {:error, {:host_plan, :bad_last_dispatch_cmd_cap, cap}}
  end

  defp present_value?(value) when is_binary(value), do: value != ""
  defp present_value?(value) when is_atom(value), do: true
  defp present_value?(value) when is_list(value), do: true
  defp present_value?(_), do: false
end
