defmodule Elmc.Backend.CCodegen.CompanionSendFold do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.Types

  @spec fold_wire_params(Types.ir_expr()) :: {:ok, integer(), integer()} | :error
  def fold_wire_params(msg) do
    decl_map = Process.get(:elmc_program_decls, %{})

    with {:ok, union_tag} <- union_tag_from_msg(msg),
         {:ok, wire_tag} <-
           fold_union_int_lookup("Companion.Internal", "watchToPhoneTag", union_tag, decl_map),
         {:ok, wire_val} <-
           fold_union_int_lookup("Companion.Internal", "watchToPhoneValue", union_tag, decl_map) do
      {:ok, wire_tag, wire_val}
    else
      _ -> :error
    end
  end

  @spec union_tag_from_msg(map() | term()) :: Types.ir_expr()

  defp union_tag_from_msg(%{op: :int_literal, value: tag}) when is_integer(tag), do: {:ok, tag}

  defp union_tag_from_msg(%{op: :constructor_call, target: target, args: []})
       when is_binary(target),
       do: lookup_constructor_tag(target)

  defp union_tag_from_msg(%{op: :qualified_call, target: target, args: []}) when is_binary(target),
    do: lookup_constructor_tag(target)

  defp union_tag_from_msg(%{op: :qualified_ref, target: target}) when is_binary(target),
    do: lookup_constructor_tag(target)

  defp union_tag_from_msg(%{op: :qualified_var, target: target}) when is_binary(target),
    do: lookup_constructor_tag(target)

  defp union_tag_from_msg(_), do: :error

  @spec lookup_constructor_tag(String.t()) :: Types.ir_expr()

  defp lookup_constructor_tag(target) do
    tags = Process.get(:elmc_constructor_tags, %{})

    case Elmc.Backend.CCodegen.IRQueries.lookup_tag(tags, target) do
      tag when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  @spec fold_union_int_lookup(String.t(), String.t(), String.t(), Types.decl_map()) :: Types.ir_expr()

  defp fold_union_int_lookup(module, name, union_tag, decl_map) do
    with %{expr: expr} <- Map.get(decl_map, {module, name}),
         {:ok, branches} <- parse_case(expr),
         true <- int_literal_branches?(branches),
         %{expr: %{op: :int_literal, value: wire}} <-
           Enum.find(branches, fn %{pattern: %{tag: tag}} -> tag == union_tag end) do
      {:ok, wire}
    else
      _ -> :error
    end
  end

  @spec parse_case(map() | term()) :: Types.ir_expr()

  defp parse_case(%{op: :case, branches: branches}), do: {:ok, branches}
  defp parse_case(%{op: :let_in, in_expr: body}), do: parse_case(body)
  defp parse_case(_), do: :error

  @spec int_literal_branches?(list() | term()) :: boolean()

  defp int_literal_branches?(branches) when is_list(branches) do
    length(branches) >= 1 and
      Enum.all?(branches, fn
        %{expr: %{op: :int_literal, value: value}} -> is_integer(value)
        _ -> false
      end)
  end

  defp int_literal_branches?(_), do: false
end
