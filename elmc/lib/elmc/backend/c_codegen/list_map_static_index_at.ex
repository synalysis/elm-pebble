defmodule Elmc.Backend.CCodegen.ListMapStaticIndexAt do
  @moduledoc """
  Fuses `List.map` over a static int list where each element is
  `Maybe.withDefault d (listAt index list)`.

  `listAt` must lower to flat index lookup (`List.head` + `List.drop` or
  `elmc_list_nth_maybe`). Indices and helper names come from IR, not app names.
  """

  alias Elmc.Backend.CCodegen.{FusionSupport, Util}

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, default, list_at_target, list_var, indices} <- parse(expr),
         true <- FusionSupport.indexed_list_at_reader?(decl_map, module_name, list_at_target) do
      FusionSupport.ok(
        emit(module_name, name, list_var, default, indices),
        []
      )
    else
      _ -> :error
    end
  end

  defp parse(%{
         op: :qualified_call,
         target: "List.map",
         args: [lambda, list_expr]
       }) do
    with {:ok, default, list_at_target, list_var} <- parse_lambda(lambda),
         {:ok, indices} <- parse_static_int_list(list_expr) do
      {:ok, default, list_at_target, list_var, indices}
    end
  end

  defp parse(_), do: :error

  defp parse_lambda(%{op: :lambda, args: [index_var], body: body}) do
    parse_with_default_list_at(body, index_var)
  end

  defp parse_lambda(_), do: :error

  defp parse_with_default_list_at(
         %{op: :qualified_call, target: "Maybe.withDefault", args: [default_expr, list_at_call]},
         index_var
       ) do
    with %{op: :int_literal, value: default} <- default_expr,
         {:ok, list_at_target, list_var} <- parse_list_at_call(list_at_call, index_var) do
      {:ok, default, list_at_target, list_var}
    else
      _ -> :error
    end
  end

  defp parse_with_default_list_at(_, _), do: :error

  defp parse_list_at_call(
         %{op: :qualified_call, target: list_at_target, args: args},
         index_var
       )
       when is_binary(list_at_target) do
    case args do
      [%{op: :var, name: ^index_var}, %{op: :var, name: list_var}] when is_binary(list_var) ->
        {:ok, list_at_target, list_var}

      _ ->
        :error
    end
  end

  defp parse_list_at_call(
         %{op: :call, target: {_, list_at_name}, args: args},
         index_var
       )
       when is_binary(list_at_name) do
    case args do
      [%{op: :var, name: ^index_var}, %{op: :var, name: list_var}] when is_binary(list_var) ->
        {:ok, list_at_name, list_var}

      _ ->
        :error
    end
  end

  defp parse_list_at_call(_, _), do: :error

  defp parse_static_int_list(%{op: :list_literal, items: items}) when is_list(items) and items != [] do
    items
    |> Enum.reduce_while({:ok, []}, fn
      %{op: :int_literal, value: value}, {:ok, acc} ->
        {:cont, {:ok, [value | acc]}}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end

  defp parse_static_int_list(_), do: :error

  defp emit(module_name, name, list_var, default, indices) do
    c_prefix = Util.module_fn_name(module_name, name)
    safe = Util.safe_c_suffix(name)
    count = length(indices)
    index_values = Enum.join(indices, ", ")

    """
    static ElmcValue *#{c_prefix}_native(ElmcValue *#{list_var}) {
      static const elmc_int_t #{safe}_indices[#{count}] = { #{index_values} };
      ElmcValue *out = NULL;
      ElmcValue **tail_slot = NULL;
      for (elmc_int_t k = 0; k < #{count}; k++) {
        const elmc_int_t cell = elmc_list_nth_int_default(#{list_var}, #{safe}_indices[k], #{default});
        ElmcValue *head = NULL;
        if (elmc_new_int(&head, cell) != RC_SUCCESS) head = elmc_int_zero();
        if (!head) {
          elmc_release(out);
          return elmc_list_nil();
        }
        ElmcValue *cell_node = NULL;
        if (elmc_list_cons(&cell_node, head, elmc_list_nil()) != RC_SUCCESS) cell_node = elmc_list_nil();
        elmc_release(head);
        if (!cell_node) {
          elmc_release(out);
          return elmc_list_nil();
        }
        if (tail_slot) {
          elmc_release(*tail_slot);
          *tail_slot = cell_node;
        } else {
          out = cell_node;
        }
        tail_slot = &((ElmcCons *)cell_node->payload)->tail;
      }
      return out ? out : elmc_list_nil();
    }
    """
  end
end
