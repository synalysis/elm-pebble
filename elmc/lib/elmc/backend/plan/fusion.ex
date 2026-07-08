defmodule Elmc.Backend.Plan.Fusion do
  @moduledoc """
  Fusion providers may return `%FunctionPlan{}` instead of C strings.

  During migration, `Elmc.Backend.CCodegen.Fusion.try_emit/4` remains the
  legacy entry; new providers should implement `try_plan/4` here.
  """

  alias Elmc.Backend.Plan.Types.FunctionPlan

  @type provider :: module()

  @providers []

  @spec try_plan(String.t(), map(), map(), keyword()) :: {:ok, FunctionPlan.t()} | :error
  def try_plan(_module_name, _decl, _decl_map, _opts \\ []) do
    :error
  end

  @spec providers() :: [provider()]
  def providers, do: @providers
end
