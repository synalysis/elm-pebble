defmodule Elmc.Backend.CCodegen.CanPlaceLoop do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Util

  @offsets_fn "pieceOffsets"

  @spec try_emit(String.t(), String.t(), map() | nil, map()) :: {:ok, String.t()} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with true <- name == "canPlace",
         {:ok, _x, _y, _board, offsets_call} <- parse_list_all(expr),
         {:ok, "kind", "rot"} <- piece_offsets_args(offsets_call),
         true <- offsets_table_available?(module_name, decl_map) do
      {:ok, emit(module_name, decl_map)}
    else
      _ -> :error
    end
  end

  defp offsets_table_available?(module_name, decl_map) do
    case Map.get(decl_map, {module_name, @offsets_fn}) do
      %{expr: expr} -> match?({:ok, _}, Tuple2CaseTable.try_emit(module_name, @offsets_fn, expr))
      _ -> false
    end
  end

  defp parse_list_all(%{op: :qualified_call, target: target, args: [lambda, list]})
       when target in ["List.all", "Basics.all"],
       do: parse_list_all_args(lambda, list)

  defp parse_list_all(%{
         op: :runtime_call,
         function: "elmc_list_all",
         args: [lambda, list]
       }),
       do: parse_list_all_args(lambda, list)

  defp parse_list_all(_), do: :error

  defp parse_list_all_args(lambda, list) do
    with {:ok, dx, dy, body} <- lambda_xy(lambda),
         {:ok, x, y, board} <- offset_fits_call(body, dx, dy) do
      {:ok, x, y, board, list}
    end
  end

  defp lambda_xy(%{op: :lambda, args: [left, right], body: body})
       when is_binary(left) and is_binary(right),
       do: {:ok, left, right, body}

  defp lambda_xy(%{op: :lambda, args: [tuple_arg], body: body}) when is_binary(tuple_arg) do
    case unwrap_tuple_destructure(body, tuple_arg) do
      {:ok, dx, dy, fit_body} -> {:ok, dx, dy, fit_body}
      :error -> :error
    end
  end

  defp lambda_xy(_), do: :error

  defp unwrap_tuple_destructure(
         %{
           op: :let_in,
           name: dx,
           value_expr: %{op: :tuple_first_expr, arg: %{op: :var, name: tuple}},
           in_expr: %{
             op: :let_in,
             name: dy,
             value_expr: %{op: :tuple_second_expr, arg: %{op: :var, name: tuple2}},
             in_expr: body
           }
         },
         tuple
       )
       when tuple2 == tuple,
       do: {:ok, dx, dy, body}

  defp unwrap_tuple_destructure(_, _), do: :error

  defp offset_fits_call(
         %{op: :qualified_call, target: target, args: [x, y, _dx, _dy, board]},
         dx_name,
         dy_name
       )
       when target in ["Main.offsetFits", "offsetFits"] do
    offset_fits_args(dx_name, dy_name, x, y, board)
  end

  defp offset_fits_call(
         %{op: :call, name: "offsetFits", args: [x, y, _dx, _dy, board]},
         dx_name,
         dy_name
       ) do
    offset_fits_args(dx_name, dy_name, x, y, board)
  end

  defp offset_fits_call(_, _, _), do: :error

  defp offset_fits_args(_dx_name, _dy_name, x, y, board) do
    case {x, y, board} do
      {%{op: :var, name: "x"}, %{op: :var, name: "y"}, %{op: :var, name: "board"}} ->
        {:ok, x, y, board}

      _ ->
        :error
    end
  end

  defp piece_offsets_args(%{op: :qualified_call, target: target, args: [kind, rot]})
       when target in ["Main.pieceOffsets", "pieceOffsets"] do
    case {kind, rot} do
      {%{op: :var, name: "kind"}, %{op: :var, name: "rot"}} -> {:ok, "kind", "rot"}
      _ -> :error
    end
  end

  defp piece_offsets_args(%{op: :call, name: @offsets_fn, args: [kind, rot]}) do
    case {kind, rot} do
      {%{op: :var, name: "kind"}, %{op: :var, name: "rot"}} -> {:ok, "kind", "rot"}
      _ -> :error
    end
  end

  defp piece_offsets_args(_), do: :error

  defp emit(module_name, decl_map) do
    c_name = Util.module_fn_name(module_name, "canPlace")
    table = "#{Util.safe_c_suffix(@offsets_fn)}_table"
    entry_t = "#{Util.safe_c_suffix(@offsets_fn)}_entry_t"
    cols = board_dimension(decl_map, module_name, "boardCols")
    rows = board_dimension(decl_map, module_name, "boardRows")
    fits = "#{Util.safe_c_suffix(c_name)}_offset_fits"

    """
    static elmc_int_t #{fits}(
        const elmc_int_t x,
        const elmc_int_t y,
        const elmc_int_t dx,
        const elmc_int_t dy,
        const elmc_int_t cols,
        const elmc_int_t rows,
        ElmcValue * const board
    ) {
      const elmc_int_t cellX = x + dx;
      const elmc_int_t cellY = y + dy;
      if (cellX < 0) return 0;
      if (cellX >= cols) return 0;
      if (cellY >= rows) return 0;
      if (cellY < 0) return 1;
      const elmc_int_t index = cellY * cols + cellX;
      return elmc_list_nth_int_default(board, index, 0) == 0;
    }

    static ElmcValue *#{c_name}_native(
        const elmc_int_t kind,
        const elmc_int_t rot,
        const elmc_int_t x,
        const elmc_int_t y,
        ElmcValue * const board
    ) {
      const elmc_int_t cols = #{cols};
      const elmc_int_t rows = #{rows};
      elmc_int_t k = kind % 7;
      if (k < 0) k += 7;
      elmc_int_t r = rot % 4;
      if (r < 0) r += 4;
      const #{entry_t} *entry = &#{table}[k][r];
      for (int i = 0; i < entry->count; i++) {
        if (!#{fits}(x, y, entry->cells[i][0], entry->cells[i][1], cols, rows, board)) {
          return elmc_new_bool(0);
        }
      }
      return elmc_new_bool(1);
    }
    """
  end

  defp board_dimension(decl_map, module_name, name) do
    case Map.get(decl_map, {module_name, name}) do
      %{expr: %{op: :int_literal, value: value}} when is_integer(value) ->
        Integer.to_string(value)

      _ ->
        fn_name = Util.module_fn_name(module_name, name)
        "elmc_as_int(#{fn_name}(NULL, 0))"
    end
  end
end
