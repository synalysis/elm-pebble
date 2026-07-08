defmodule Elmc.Backend.CCodegen.ListMapStaticIndexAt do
  @moduledoc """
  Fuses `List.map` over a static int list where each element is
  `Maybe.withDefault d (listAt index list)`.

  `listAt` must lower to flat index lookup (`List.head` + `List.drop` or
  `elmc_list_nth_maybe`). Indices and helper names come from IR, not app names.
  """

  alias Elmc.Backend.CCodegen.{FusionSupport, Util}

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]}
          | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native}
          | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, default, list_at_target, list_var, indices} <- parse(expr),
         true <- FusionSupport.indexed_list_at_reader?(decl_map, module_name, list_at_target) do
      FusionSupport.ok_rc(
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
    static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *#{list_var}) {
      RC Rc = RC_SUCCESS;
      ElmcValue *owned[2] = {0};
      CATCH_BEGIN
        static const elmc_int_t #{safe}_indices[#{count}] = { #{index_values} };
        ElmcValue **tail_slot = NULL;
        for (elmc_int_t k = 0; k < #{count}; k++) {
          const elmc_int_t cell = elmc_list_nth_int_default(#{list_var}, #{safe}_indices[k], #{default});
          Rc = elmc_new_int(&owned[1], cell);
          CHECK_RC(Rc);
          ElmcValue *cell_node = NULL;
          Rc = elmc_list_cons(&cell_node, owned[1], elmc_list_nil());
          owned[1] = NULL;
          CHECK_RC(Rc);
          if (tail_slot) {
            elmc_release(*tail_slot);
            *tail_slot = cell_node;
          } else {
            owned[0] = cell_node;
          }
          tail_slot = &((ElmcCons *)cell_node->payload)->tail;
        }
        if (owned[0] == NULL) {
          *out = elmc_list_nil();
        } else {
          *out = owned[0];
          owned[0] = NULL;
        }
      CATCH_END;
      elmc_release_array_lifo(owned, DIM(owned));
      return Rc;
    }
    """
  end
end
