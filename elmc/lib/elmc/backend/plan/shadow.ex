defmodule Elmc.Backend.Plan.Shadow do
  @moduledoc """
  Plan lowering verification alongside primary C emission.
  """
  alias Elmc.Backend.Plan.Types, as: Types

  alias Elmc.Backend.Plan.Lower.Function

  alias Elmc.Backend.Plan.{Defaults, Types}

  @stats_key :elmc_plan_shadow_stats

  @spec maybe_verify_function(
          Types.function_decl(),
          String.t(),
          Types.function_decl_map(),
          keyword()
        ) ::
          :ok | :skipped | {:error, Types.lower_error()}
  def maybe_verify_function(decl, module_name, decl_map, opts) do
    result = run_shadow(decl, module_name, decl_map, opts)
    record_stat(result, module_name, Map.get(decl, :name, "anon"))
    result
  end

  @spec shadow_stats() :: %{
          ok: non_neg_integer(),
          skipped: non_neg_integer(),
          error: non_neg_integer()
        }
  def shadow_stats do
    Process.get(@stats_key, %{ok: 0, skipped: 0, error: 0})
  end

  @spec reset_stats() :: :ok
  def reset_stats do
    Process.put(@stats_key, %{ok: 0, skipped: 0, error: 0})
    :ok
  end

  @spec run_shadow(Types.decl(), String.t(), Types.decl_map(), keyword()) ::
          :ok | :skipped | {:error, Types.lower_error()}
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

  @spec record_stat(:ok | :skipped | {:error, term()}, String.t(), String.t()) :: term()
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

  @spec plan_ir_mode(keyword() | map()) :: Elmc.Types.plan_ir_mode()
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

  @spec normalize_mode(term()) :: Elmc.Types.plan_ir_mode()
  defp normalize_mode(:primary), do: :primary
  defp normalize_mode(:shadow), do: :shadow
  defp normalize_mode("primary"), do: :primary
  defp normalize_mode("shadow"), do: :shadow
  defp normalize_mode(_), do: :primary

  @spec raise_on_failure?(keyword() | term()) :: boolean()
  defp raise_on_failure?(opts) when is_list(opts), do: Keyword.get(opts, :plan_ir_raise, false)
  defp raise_on_failure?(_), do: Application.get_env(:elmc, :plan_ir_raise, false)
end
