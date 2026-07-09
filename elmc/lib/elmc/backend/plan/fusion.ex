defmodule Elmc.Backend.Plan.Fusion do
  @moduledoc """
  Fusion providers may return `%FunctionPlan{}` with `fusion_c` instead of SSA blocks.

  During migration, `Elmc.Backend.CCodegen.Fusion.try_emit/4` remains the
  legacy entry; providers here implement `try_plan/4`.
  """

  alias Elmc.Backend.Plan.Fusion.{LegacyBridge, ListIndexedReplace, ListIntSearch, ListMapStaticIndexAt,
                                Tuple2CaseTable}
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @type provider :: module()

  # Shape-specific providers first; LegacyBridge delegates to CCodegen.Fusion for the rest.
  @providers [
    Tuple2CaseTable,
    ListIndexedReplace,
    ListIntSearch,
    ListMapStaticIndexAt,
    LegacyBridge
  ]

  @spec try_plan(String.t(), map(), map(), keyword()) :: {:ok, FunctionPlan.t()} | :error
  def try_plan(module_name, decl, decl_map, opts \\ []) do
    Enum.find_value(@providers, :error, fn mod ->
      case mod.try_plan(module_name, decl, decl_map, opts) do
        {:ok, _} = ok -> ok
        :error -> nil
      end
    end)
  end

  @spec providers() :: [provider()]
  def providers, do: @providers
end
