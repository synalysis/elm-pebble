defmodule Elmc.Backend.Plan.Fusion do
  @moduledoc """
  Fusion providers may return `%FunctionPlan{}` with `fusion_c` instead of SSA blocks.

  Plan-native providers implement `try_plan/4`. C-emit fusion providers are registered
  in `CEmit` and wrap the shared IR matchers under `Elmc.Backend.CCodegen.*`.
  """

  alias Elmc.Backend.Plan.Fusion.{CEmit, ListIndexedReplace, ListIntSearch}
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @type provider :: module()

  @plan_providers [
    ListIndexedReplace,
    ListIntSearch
  ]

  @spec try_plan(String.t(), map(), map(), keyword()) :: {:ok, FunctionPlan.t()} | :error
  def try_plan(module_name, decl, decl_map, opts \\ []) do
    case try_plan_modules(@plan_providers, module_name, decl, decl_map, opts) do
      {:ok, _} = ok ->
        ok

      :error ->
        Enum.find_value(CEmit.providers(), :error, fn provider ->
          case CEmit.try_plan(module_name, decl, decl_map, opts, provider) do
            {:ok, _} = ok -> ok
            :error -> nil
          end
        end)
    end
  end

  @spec providers() :: [provider()]
  def providers, do: @plan_providers ++ Enum.map(CEmit.providers(), fn {mod, _} -> mod end)

  defp try_plan_modules(modules, module_name, decl, decl_map, opts) do
    Enum.find_value(modules, :error, fn mod ->
      case mod.try_plan(module_name, decl, decl_map, opts) do
        {:ok, _} = ok -> ok
        :error -> nil
      end
    end)
  end
end
