defmodule Elmc.Backend.CCodegen.ListConcatReversedRowSlices do
  @moduledoc """
  Fuses `List.concat` of `List.reverse (rowAt n board)` for each row in a flat buffer.

  Verifies `rowAt` as `List.take w (List.drop (row * w) board)` from `decl_map`.
  """

  alias Elmc.Backend.CCodegen.{FusionSupport, Util}

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]}
          | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native}
          | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, row_at_target, cells_var, row_indices} <- parse(expr),
         {:ok, width} <- row_slice_width(decl_map, module_name, row_at_target),
         rows = length(row_indices),
         true <- rows > 0,
         expected = Enum.to_list(0..(rows - 1)),
         true <- row_indices == expected do
      FusionSupport.ok_rc(emit(module_name, name, cells_var, width, rows), [])
    else
      _ -> :error
    end
  end

  defp parse(%{op: :qualified_call, target: "List.concat", args: [list_expr]}) do
    parse_list_literal(list_expr)
  end

  defp parse(%{op: :call, name: op, args: [_list_expr]}) when op in ["++", "__append__"] do
    :error
  end

  defp parse(%{
         op: :pipe,
         left: list_expr,
         right: %{op: :qualified_call, target: "List.concat", args: []}
       }) do
    parse_list_literal(list_expr)
  end

  defp parse(%{
         op: :pipe,
         left: list_expr,
         right: %{op: :call, target: {_, "concat"}, args: []}
       }) do
    parse_list_literal(list_expr)
  end

  defp parse(_), do: :error

  defp parse_list_literal(%{op: :list_literal, items: items}) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, nil, nil, []}, fn item, {:ok, row_at, cells_var, indices} ->
      case parse_row_reverse(item) do
        {:ok, ^row_at, ^cells_var, row_index} when is_integer(row_index) ->
          {:cont, {:ok, row_at, cells_var, indices ++ [row_index]}}

        {:ok, new_row_at, new_cells, row_index} when row_at in [nil, new_row_at] and
                                                     cells_var in [nil, new_cells] ->
          {:cont, {:ok, new_row_at, new_cells, indices ++ [row_index]}}

        _ ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, row_at, cells_var, indices} when is_binary(row_at) and is_binary(cells_var) ->
        {:ok, row_at, cells_var, indices}

      _ ->
        :error
    end
  end

  defp parse_list_literal(_), do: :error

  defp parse_row_reverse(%{
         op: :qualified_call,
         target: "List.reverse",
         args: [row_at_call]
       }) do
    parse_row_at_call(row_at_call)
  end

  defp parse_row_reverse(_), do: :error

  defp parse_row_at_call(%{
         op: :qualified_call,
         target: row_at,
         args: [%{op: :int_literal, value: row_index}, %{op: :var, name: cells_var}]
       })
       when is_integer(row_index) and is_binary(cells_var) and is_binary(row_at) do
    {:ok, row_at, cells_var, row_index}
  end

  defp parse_row_at_call(%{
         op: :call,
         target: {_, row_at},
         args: [%{op: :int_literal, value: row_index}, %{op: :var, name: cells_var}]
       })
       when is_integer(row_index) and is_binary(cells_var) and is_binary(row_at) do
    {:ok, row_at, cells_var, row_index}
  end

  defp parse_row_at_call(_), do: :error

  defp row_slice_width(decl_map, module_name, row_at_target) do
    case Map.get(decl_map, FusionSupport.callee_key(module_name, row_at_target)) do
      %{
        expr: %{
          op: :qualified_call,
          target: "List.take",
          args: [%{op: :int_literal, value: width}, drop_expr]
        }
      }
      when is_integer(width) ->
        if row_drop_stride?(drop_expr, width), do: {:ok, width}, else: :error

      _ ->
        :error
    end
  end

  defp row_drop_stride?(
         %{
           op: :qualified_call,
           target: "List.drop",
           args: [index_expr, %{op: :var, name: _cells}]
         },
         width
       ),
       do: row_mul_width?(index_expr, width)

  defp row_drop_stride?(_, _), do: false

  defp row_mul_width?(
         %{op: :call, name: op, args: [%{op: :var, name: "row"}, %{op: :int_literal, value: width}]},
         width
       )
       when op in ["__mul__", "*"],
       do: true

  defp row_mul_width?(
         %{
           op: :qualified_call,
           target: op,
           args: [%{op: :var, name: "row"}, %{op: :int_literal, value: width}]
         },
         width
       )
       when op in ["Basics.mul", "*"],
       do: true

  defp row_mul_width?(_, _), do: false

  defp emit(module_name, name, cells_var, width, rows) do
    c_prefix = Util.module_fn_name(module_name, name)
    count = rows * width

    """
    static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *#{cells_var}) {
      RC Rc = RC_SUCCESS;
      CATCH_BEGIN
        elmc_int_t flat[#{count}];
        for (elmc_int_t row = 0; row < #{rows}; row++) {
          for (elmc_int_t col = 0; col < #{width}; col++) {
            flat[(row * #{width}) + col] =
              elmc_list_nth_int_default(#{cells_var}, (row * #{width}) + (#{width} - 1 - col), 0);
          }
        }
        Rc = elmc_list_from_int_array(out, flat, #{count});
        CHECK_RC(Rc);
      CATCH_END;
      return Rc;
    }
    """
  end
end
