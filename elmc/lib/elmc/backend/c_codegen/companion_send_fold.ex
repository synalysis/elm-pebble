defmodule Elmc.Backend.CCodegen.CompanionSendFold do
  @moduledoc false

  @spec fold_wire_params(map()) :: {:ok, integer(), integer()} | :error
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

  defp lookup_constructor_tag(target) do
    tags = Process.get(:elmc_constructor_tags, %{})

    case Map.get(tags, target) || Map.get(tags, short_constructor_name(target)) do
      tag when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  defp short_constructor_name(target) do
    target |> String.split(".") |> List.last()
  end

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

  defp parse_case(%{op: :case, branches: branches}), do: {:ok, branches}
  defp parse_case(%{op: :let_in, in_expr: body}), do: parse_case(body)
  defp parse_case(_), do: :error

  defp int_literal_branches?(branches) when is_list(branches) do
    length(branches) >= 1 and
      Enum.all?(branches, fn
        %{expr: %{op: :int_literal, value: value}} -> is_integer(value)
        _ -> false
      end)
  end

  defp int_literal_branches?(_), do: false
end
