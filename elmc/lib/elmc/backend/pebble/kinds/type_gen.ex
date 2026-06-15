defmodule Elmc.Backend.Pebble.Kinds.TypeGen do
  @moduledoc false

  @doc false
  defmacro def_kind_union(name, table_ast) do
    union = union_ast!(table_ast, __CALLER__)

    quote do
      @type unquote(name) :: unquote(union)
    end
  end

  defp union_ast!({{:., _, [module_ast, fun]}, _, []}, caller) when is_atom(fun) do
    module = module_ast |> Macro.expand(caller)

    module
    |> apply(fun, [])
    |> Keyword.keys()
    |> keys_to_union_ast()
  end

  defp union_ast!(table_ast, _caller) do
    raise ArgumentError,
          "def_kind_union expects Module.table/0, got: #{Macro.to_string(table_ast)}"
  end

  defp keys_to_union_ast([first | rest]) do
    Enum.reduce(rest, first, fn key, acc ->
      {:|, [], [acc, key]}
    end)
  end

  defp keys_to_union_ast([]) do
    raise ArgumentError, "def_kind_union expected a non-empty kind table"
  end
end
