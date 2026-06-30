defmodule Elmc.Backend.CCodegen.FoldlOffsetPatch do
  @moduledoc """
  Fuses `List.foldl` over tuple offsets that patch a flat list via a bounds-checked setter.

  Offsets table and setter targets are resolved from IR/`decl_map`, not by name.
  """

  alias Elmc.Backend.CCodegen.{FusionSupport, Tuple2CaseTable, Util}

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, piece_var, piece_type} <- parse_function(decl_map, module_name, name),
         {:ok, ^piece_var, offsets_target, set_cell_target} <- parse(expr),
         {:ok, cols_var, rows_var} <- grid_dims_from_set_cell(decl_map, module_name, set_cell_target),
         {:ok, cols} <- FusionSupport.resolve_int_constant(decl_map, module_name, cols_var),
         {:ok, rows} <- FusionSupport.resolve_int_constant(decl_map, module_name, rows_var),
         true <- flat_set_cell?(decl_map, module_name, set_cell_target, cols_var),
         true <- piece_offsets_table?(decl_map, module_name, offsets_target) do
      offsets_name = FusionSupport.local_name(offsets_target)
      set_cell_name = FusionSupport.local_name(set_cell_target)

      FusionSupport.ok(
        emit(module_name, name, piece_type, cols, rows, offsets_name),
        [{module_name, offsets_name}, {module_name, set_cell_name}]
      )
    else
      _ -> :error
    end
  end

  defp parse_function(decl_map, module_name, name) do
    case Map.get(decl_map, {module_name, name}) do
      %{type: type, args: [piece_var, _board_var | _]} when is_binary(type) ->
        case String.split(type, " -> ", trim: true) do
          [piece_type | _] -> {:ok, piece_var, piece_type}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse(%{op: :qualified_call, target: "List.foldl", args: [lambda, %{op: :var, name: _board}, offsets]}) do
    with {:ok, piece_var, set_cell_target} <- parse_foldl_lambda(lambda),
         {:ok, offsets_target} <- piece_offsets_call(offsets, piece_var) do
      {:ok, piece_var, offsets_target, set_cell_target}
    end
  end

  defp parse(_), do: :error

  defp parse_foldl_lambda(%{
         op: :lambda,
         args: ["tupleArg"],
         body: %{
           op: :let_in,
           name: "dx",
           value_expr: %{op: :tuple_first_expr, arg: %{op: :var, name: "tupleArg"}},
           in_expr: %{
             op: :let_in,
             name: "dy",
             value_expr: %{op: :tuple_second_expr, arg: %{op: :var, name: "tupleArg"}},
             in_expr: %{
               op: :lambda,
               args: ["acc"],
               body: set_cell_call
             }
           }
         }
       }) do
    parse_set_cell_call(set_cell_call)
  end

  defp parse_foldl_lambda(_), do: :error

  defp parse_set_cell_call(%{
         op: :let_in,
         name: "value",
         value_expr: %{
           op: :call,
           name: "__add__",
           args: [%{op: :field_access, arg: piece_var, field: "kind"}, %{op: :int_literal, value: 1}]
         },
         in_expr: %{
           op: :qualified_call,
           target: set_cell_target,
           args: [
             %{
               op: :call,
               name: "__add__",
               args: [%{op: :field_access, arg: piece_x, field: "x"}, %{op: :var, name: "dx"}]
             },
             %{
               op: :call,
               name: "__add__",
               args: [%{op: :field_access, arg: piece_y, field: "y"}, %{op: :var, name: "dy"}]
             },
             %{op: :var, name: "value"},
             %{op: :var, name: "acc"}
           ]
         }
       })
       when is_binary(piece_var) and piece_x == piece_var and piece_y == piece_var and
              is_binary(set_cell_target) do
    {:ok, piece_var, set_cell_target}
  end

  defp parse_set_cell_call(_), do: :error

  defp piece_offsets_call(
         %{
           op: :qualified_call,
           target: offsets_target,
           args: [
             %{op: :field_access, arg: piece_var, field: "kind"},
             %{op: :field_access, arg: piece_var, field: "rot"}
           ]
         },
         piece_var
       )
       when is_binary(offsets_target) and is_binary(piece_var),
       do: {:ok, offsets_target}

  defp piece_offsets_call(_, _), do: :error

  defp grid_dims_from_set_cell(decl_map, module_name, set_cell_target) do
    case Map.get(decl_map, FusionSupport.callee_key(module_name, set_cell_target)) do
      %{expr: %{op: :if, else_expr: else_expr} = expr} ->
        with {cols_var, rows_var} <- axis_dim_vars_from_bounds(expr),
             true <- flat_indexed_map_update?(else_expr, cols_var) do
          {:ok, cols_var, rows_var}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp axis_dim_vars_from_bounds(expr) do
    compares = collect_compares(expr)

    with cols when is_binary(cols) <- axis_dim_var(compares, "x"),
         rows when is_binary(rows) <- axis_dim_var(compares, "y") do
      {cols, rows}
    else
      _ -> :error
    end
  end

  defp axis_dim_var(compares, axis) do
    Enum.find_value(compares, fn
      %{left: %{op: :var, name: ^axis}, right: %{op: :var, name: var}, kind: kind}
      when kind in [:gt, :gte, :eq] ->
        var

      _ ->
        nil
    end)
  end

  defp collect_compares(%{op: :compare} = expr), do: [expr]

  defp collect_compares(%{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}),
    do: collect_compares(cond) ++ collect_compares(then_expr) ++ collect_compares(else_expr)

  defp collect_compares(_), do: []

  defp flat_indexed_map_update?(expr, cols_var) do
    case expr do
      %{
        op: :qualified_call,
        target: "List.indexedMap",
        args: [%{op: :lambda, body: inner_lambda}, _board]
      } ->
        cond =
          case inner_lambda do
            %{op: :if, cond: c} -> c
            %{op: :lambda, body: %{op: :if, cond: c}} -> c
            _ -> nil
          end

        case cond do
          %{op: :compare, right: right} ->
            index_uses_cols?(right, cols_var)

          other ->
            index_uses_cols?(other, cols_var)
        end

      _ ->
        false
    end
  end

  defp index_uses_cols?(expr, cols_var) do
    case FusionSupport.cols_from_y_mul_plus_x(expr) do
      {:ok, resolved} -> resolved == cols_var
      _ -> false
    end
  end

  defp piece_offsets_table?(decl_map, module_name, offsets_target) do
    offsets_name = FusionSupport.local_name(offsets_target)

    case Map.get(decl_map, {module_name, offsets_name}) do
      %{expr: expr} ->
        Tuple2CaseTable.recognized?(module_name, offsets_name, expr)

      _ ->
        false
    end
  end

  defp flat_set_cell?(decl_map, module_name, set_cell_target, cols_var) do
    case Map.get(decl_map, FusionSupport.callee_key(module_name, set_cell_target)) do
      %{expr: %{op: :if, else_expr: else_expr}} ->
        flat_indexed_map_update?(else_expr, cols_var)

      _ ->
        false
    end
  end

  defp emit(module_name, name, piece_type, cols, rows, offsets_fn_name) do
    c_prefix = Util.module_fn_name(module_name, name)
    table_type = FusionSupport.table_type(offsets_fn_name)
    table_ref = FusionSupport.table_ref(offsets_fn_name)
    kind_field = field_macro(module_name, piece_type, "kind")
    rot_field = field_macro(module_name, piece_type, "rot")
    x_field = field_macro(module_name, piece_type, "x")
    y_field = field_macro(module_name, piece_type, "y")

    """
    static ElmcValue *#{c_prefix}_native(ElmcValue *piece, ElmcValue *board) {
      const elmc_int_t kind = ELMC_RECORD_GET_INDEX_INT(piece, #{kind_field});
      const elmc_int_t rot = ELMC_RECORD_GET_INDEX_INT(piece, #{rot_field});
      const elmc_int_t px = ELMC_RECORD_GET_INDEX_INT(piece, #{x_field});
      const elmc_int_t py = ELMC_RECORD_GET_INDEX_INT(piece, #{y_field});
      const elmc_int_t value = kind + 1;
      const elmc_int_t cols = #{cols};
      const elmc_int_t rows = #{rows};
      elmc_int_t k = kind % 7;
      if (k < 0) k += 7;
      elmc_int_t r = rot % 4;
      if (r < 0) r += 4;
      const #{table_type} *entry = &#{table_ref}[k][r];
      elmc_int_t patches[4];
      int patch_count = 0;
      for (int i = 0; i < entry->count; i++) {
        const elmc_int_t x = px + entry->cells[i][0];
        const elmc_int_t y = py + entry->cells[i][1];
        if (x >= 0 && x < cols && y >= 0 && y < rows) {
          patches[patch_count++] = (y * cols) + x;
        }
      }
      const elmc_int_t total = cols * rows;
      if (board && board->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *ilp = (ElmcIntListPayload *)board->payload;
        const int len = ilp ? ilp->length : 0;
        if (len != total) return elmc_retain(board);
        elmc_int_t buf[#{cols * rows}];
        for (int i = 0; i < len; i++) {
          buf[i] = ilp->values[i];
        }
        for (int p = 0; p < patch_count; p++) {
          const elmc_int_t patch = patches[p];
          if (patch >= 0 && patch < len) buf[patch] = value;
        }
        ElmcValue *out = NULL;
        if (elmc_list_from_int_array(&out, buf, len) != RC_SUCCESS || !out) {
          return elmc_retain(board);
        }
        return out;
      }
      ElmcValue *out = NULL;
      ElmcValue **tail_slot = NULL;
      elmc_int_t idx = 0;
      ElmcValue *cursor = board;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        elmc_int_t cell_value = elmc_as_int(node->head);
        for (int p = 0; p < patch_count; p++) {
          if (idx == patches[p]) {
            cell_value = value;
            break;
          }
        }
        ElmcValue *head = NULL;
        if (elmc_new_int(&head, cell_value) != RC_SUCCESS) head = elmc_int_zero();
        if (!head) {
          elmc_release(out);
          return elmc_retain(board);
        }
        ElmcValue *cell = NULL;
        if (elmc_list_cons(&cell, head, elmc_list_nil()) != RC_SUCCESS) cell = elmc_list_nil();
        elmc_release(head);
        if (!cell) {
          elmc_release(out);
          return elmc_retain(board);
        }
        if (tail_slot) {
          elmc_release(*tail_slot);
          *tail_slot = cell;
        } else {
          out = cell;
        }
        tail_slot = &((ElmcCons *)cell->payload)->tail;
        cursor = node->tail;
        idx++;
      }
      if (!out) out = elmc_list_nil();
      return out;
    }
    """
  end

  defp field_macro(module_name, type_name, field) do
    case Map.get(Process.get(:elmc_record_field_macros, %{}), {module_name, type_name, field}) do
      macro when is_binary(macro) -> macro
      _ -> "0 /* #{field} */"
    end
  end
end
