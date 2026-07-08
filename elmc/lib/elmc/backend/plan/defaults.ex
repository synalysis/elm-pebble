defmodule Elmc.Backend.Plan.Defaults do
  @moduledoc false

  @spec plan_ir_mode() :: :off | :shadow | :primary
  def plan_ir_mode do
    Application.get_env(:elmc, :default_plan_ir_mode, :primary)
    |> normalize()
  end

  @spec plan_ir_strict(:off | :shadow | :primary) :: boolean()
  def plan_ir_strict(mode) do
    mode == :primary
  end

  @spec apply_defaults(map()) :: map()
  def apply_defaults(opts) when is_map(opts) do
    explicit_mode = Map.get(opts, :plan_ir_mode)
    mode = explicit_mode || plan_ir_mode()

    opts
    |> Map.put_new(:plan_ir_mode, mode)
    |> Map.put_new(:plan_ir_strict, plan_ir_strict(mode))
    |> then(fn normalized ->
      if explicit_mode == :off do
        Map.put(normalized, :plan_ir_mode_explicit_off, true)
      else
        normalized
      end
    end)
  end

  defp normalize(:primary), do: :primary
  defp normalize(:shadow), do: :shadow
  defp normalize(:off), do: :off
  defp normalize("primary"), do: :primary
  defp normalize("shadow"), do: :shadow
  defp normalize(_), do: :off
end
