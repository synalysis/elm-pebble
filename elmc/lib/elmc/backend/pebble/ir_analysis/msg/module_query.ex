defmodule Elmc.Backend.Pebble.IRAnalysis.Msg.ModuleQuery do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.Types

  @spec has_view?(IR.t(), Types.entry_module()) :: boolean()
  def has_view?(%IR{} = ir, entry_module) do
    ir.modules
    |> Enum.find(&(&1.name == entry_module))
    |> case do
      nil -> false
      mod -> Enum.any?(mod.declarations, &(&1.kind == :function and &1.name == "view"))
    end
  end

  @spec union_constructors(
          IR.t(),
          Types.union_module(),
          Types.decl_name()
        ) :: Types.msg_constructor_list()
  def union_constructors(%IR{} = ir, module_name, union_name) do
    ir.modules
    |> Enum.find(&(&1.name == module_name))
    |> case do
      nil ->
        []

      mod ->
        mod.unions
        |> Map.get(union_name, %{tags: %{}})
        |> Map.get(:tags, %{})
        |> Map.to_list()
        |> Enum.sort_by(fn {_ctor, tag} -> tag end)
    end
  end

  @spec entry_msg_union(IR.t(), Types.entry_module()) :: Types.msg_union()
  def entry_msg_union(%IR{} = ir, entry_module) do
    ir.modules
    |> Enum.find(&(&1.name == entry_module))
    |> case do
      nil -> nil
      mod -> Map.get(mod.unions, "Msg")
    end
  end
end
