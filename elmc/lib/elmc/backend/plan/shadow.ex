defmodule Elmc.Backend.Plan.Shadow do
  @moduledoc """
  Shadow-mode plan lowering alongside legacy C emission.
  """

  alias Elmc.Backend.Plan.Lower.Function

  alias Elmc.Backend.Plan.Defaults

  @stats_key :elmc_plan_shadow_stats

  @spec maybe_verify_function(map(), String.t(), map(), keyword()) :: :ok | :skipped | {:error, term()}
  def maybe_verify_function(decl, module_name, decl_map, opts) do
    case plan_ir_mode(opts) do
      :off ->
        :skipped

      mode when mode in [:shadow, :primary] ->
        result = run_shadow(decl, module_name, decl_map, opts)
        record_stat(result, module_name, Map.get(decl, :name, "anon"))
        result
    end
  end

  @spec shadow_stats() :: %{ok: non_neg_integer(), skipped: non_neg_integer(), error: non_neg_integer()}
  def shadow_stats do
    Process.get(@stats_key, %{ok: 0, skipped: 0, error: 0})
  end

  @spec reset_stats() :: :ok
  def reset_stats do
    Process.put(@stats_key, %{ok: 0, skipped: 0, error: 0})
    :ok
  end

  defp run_shadow(decl, module_name, decl_map, opts) do
    try do
      case Function.lower(decl, module_name, decl_map, opts) do
        {:ok, _plan} ->
          :ok

        :unsupported ->
          :skipped

        {:error, reason} ->
          if raise_on_failure?(opts), do: raise("plan shadow verify failed: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e in FunctionClauseError ->
        if raise_on_failure?(opts), do: reraise(e, __STACKTRACE__)
        :skipped
    end
  end

  defp record_stat(result, module, name) do
    stats = shadow_stats()

    updated =
      case result do
        :ok -> %{stats | ok: stats.ok + 1}
        :skipped -> %{stats | skipped: stats.skipped + 1}
        {:error, _} -> %{stats | error: stats.error + 1}
      end

    Process.put(@stats_key, Map.put(updated, :last, {module, name, result}))
  end

  @spec plan_ir_mode(keyword() | map()) :: :off | :shadow | :primary
  def plan_ir_mode(opts) do
    mode =
      cond do
        is_list(opts) -> Keyword.get(opts, :plan_ir_mode)
        is_map(opts) -> Map.get(opts, :plan_ir_mode)
        true -> nil
      end

    (mode || Process.get(:elmc_plan_ir_mode) || Defaults.plan_ir_mode())
    |> normalize_mode()
  end

  defp normalize_mode(:primary), do: :primary
  defp normalize_mode(:shadow), do: :shadow
  defp normalize_mode("primary"), do: :primary
  defp normalize_mode("shadow"), do: :shadow
  defp normalize_mode(_), do: :off

  defp raise_on_failure?(opts) when is_list(opts), do: Keyword.get(opts, :plan_ir_raise, false)
  defp raise_on_failure?(_), do: Application.get_env(:elmc, :plan_ir_raise, false)
end
