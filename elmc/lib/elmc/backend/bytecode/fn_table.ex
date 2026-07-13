defmodule Elmc.Backend.Bytecode.FnTable do
  @moduledoc false

  alias Elmc.Backend.Bytecode.Lower
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @type entry :: {String.t(), String.t()}
  @type t :: [entry()]

  @spec collect(FunctionPlan.t()) :: t()
  def collect(%FunctionPlan{} = plan) do
    direct = collect_blocks(plan.blocks)

    nested =
      (Map.get(plan, :lambdas) || [])
      |> Enum.flat_map(&collect/1)

    Enum.uniq(direct ++ nested)
  end

  @spec collect_section(Lower.section()) :: t()
  def collect_section(section) when is_map(section) do
    direct = Map.get(section, :fn_table, [])

    nested =
      (Map.get(section, :lambdas) || [])
      |> Enum.flat_map(&collect_section/1)

    Enum.uniq(direct ++ nested)
  end

  @spec index(t(), entry()) :: non_neg_integer() | nil
  def index(table, {mod, name}) do
    Enum.find_index(table, fn entry -> entry == {mod, name} end)
  end

  defp block_instrs(%Block{instrs: instrs}), do: instrs

  defp collect_blocks(blocks) do
    blocks
    |> Enum.flat_map(&block_instrs/1)
    |> Enum.filter(&(&1.op == :call_fn))
    |> Enum.map(fn %{args: %{module: mod, name: name}} -> {mod, name} end)
  end
end
