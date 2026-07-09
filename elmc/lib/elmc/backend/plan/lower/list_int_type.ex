defmodule Elmc.Backend.Plan.Lower.ListIntType do
  @moduledoc false

  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.Plan.Context

  @spec list_int_subject?(Context.t(), map()) :: boolean()
  def list_int_subject?(%Context{} = ctx, %{op: :var, name: name}) when is_binary(name),
    do: list_int_var?(ctx, name)

  def list_int_subject?(_, _), do: false

  @spec list_int_var?(Context.t(), String.t()) :: boolean()
  def list_int_var?(%Context{} = ctx, name) when is_binary(name) do
    case var_type_name(ctx, name) do
      "List Int" -> true
      _ -> false
    end
  end

  defp var_type_name(%Context{module: mod, function_name: fun, decl_map: decl_map}, name)
       when is_binary(mod) and is_binary(fun) and is_binary(name) do
    with decl when is_map(decl) <- Map.get(decl_map, {mod, fun}),
         args when is_list(args) <- Map.get(decl, :args, []),
         idx when is_integer(idx) <- Enum.find_index(args, &(&1 == name)),
         types when is_list(types) <- TypeParsing.function_arg_types(Map.get(decl, :type, "")),
         type when is_binary(type) <- Enum.at(types, idx) do
      TypeParsing.normalize_type_name(type)
    else
      _ -> nil
    end
  end

  defp var_type_name(_, _), do: nil
end
