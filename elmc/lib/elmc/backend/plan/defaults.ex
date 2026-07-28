defmodule Elmc.Backend.Plan.Defaults do
  @moduledoc false

  alias Elmc.Types

  @type compile_options :: Types.compile_options()

  @spec plan_ir_mode() :: :shadow | :primary
  def plan_ir_mode do
    (Process.get(:elmc_plan_ir_mode) || Application.get_env(:elmc, :default_plan_ir_mode, :primary))
    |> normalize()
  end

  @spec plan_ir_strict(:shadow | :primary) :: boolean()
  def plan_ir_strict(:primary) do
    Application.get_env(:elmc, :default_plan_ir_strict, true)
  end

  def plan_ir_strict(_mode), do: false

  @spec apply_defaults(compile_options()) :: compile_options()
  def apply_defaults(opts) when is_map(opts) do
    mode =
      case Map.get(opts, :plan_ir_mode) do
        nil -> plan_ir_mode()
        other -> normalize(other)
      end

    opts
    |> then(fn normalized ->
      case Map.get(opts, :plan_ir_mode) do
        nil -> Map.put_new(normalized, :plan_ir_mode, mode)
        _ -> Map.put(normalized, :plan_ir_mode, mode)
      end
    end)
    |> Map.put_new(:plan_ir_strict, plan_ir_strict(mode))
    |> Map.put_new(:targets, [:c])
  end

  defp normalize(:primary), do: :primary
  defp normalize(:shadow), do: :shadow
  defp normalize("primary"), do: :primary
  defp normalize("shadow"), do: :shadow
  defp normalize(_), do: :primary
end
