defmodule Elmc.Backend.Plan.StrictPolicy do
  @moduledoc false

  alias Elmc.Backend.Plan.Shadow

  @type opts :: keyword() | map()

  @doc """
  When true, reachable Plan IR gaps and legacy fallbacks are compile errors.

  Defaults to `true` in `:primary` mode unless `plan_ir_strict: false`.
  """
  @spec strict?(opts()) :: boolean()
  def strict?(opts) do
    case plan_ir_strict(opts) do
      true -> primary_mode?(opts)
      false -> false
      nil -> primary_mode?(opts)
    end
  end

  @spec gap_severity(opts()) :: String.t()
  def gap_severity(opts) do
    if strict?(opts), do: "error", else: gap_severity_for_mode(Shadow.plan_ir_mode(opts))
  end

  @spec fallback_severity(opts(), boolean()) :: String.t()
  def fallback_severity(opts, reachable?) do
    cond do
      not reachable? -> "warning"
      strict?(opts) -> "error"
      true -> "warning"
    end
  end

  defp gap_severity_for_mode(:primary), do: "warning"
  defp gap_severity_for_mode(_), do: "info"

  defp primary_mode?(opts), do: Shadow.plan_ir_mode(opts) == :primary

  defp plan_ir_strict(opts) when is_list(opts), do: Keyword.get(opts, :plan_ir_strict)
  defp plan_ir_strict(opts) when is_map(opts), do: Map.get(opts, :plan_ir_strict)
  defp plan_ir_strict(_), do: nil
end
