defmodule Elmc.Backend.CCodegen.FilterMapRowDrop do
  @moduledoc """
  Fuses `filterMap` row keep/drop + `concat` of repeated zero rows over a flat list.

  Matches when row-full and row-slice helpers are verified from `decl_map`, not by name.
  """

  alias Elmc.Backend.CCodegen.FusionSupport
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Util

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]}
          | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native}
          | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, rows_var, cols_var, row_full, row_cells} <- parse(expr),
         {:ok, rows} <- FusionSupport.resolve_int_constant(decl_map, module_name, rows_var),
         {:ok, cols} <- FusionSupport.resolve_int_constant(decl_map, module_name, cols_var),
         true <- row_full_matches?(decl_map, module_name, row_full, row_cells),
         {:ok, cell_reader} <- row_cells_matches?(decl_map, module_name, row_cells, cols_var),
         true <- FusionSupport.flat_list_cell_reader?(decl_map, module_name, cell_reader, cols_var) do
      FusionSupport.ok_rc(
        emit(module_name, name, rows, cols),
        [
          {module_name, FusionSupport.local_name(row_full)},
          {module_name, FusionSupport.local_name(row_cells)},
          {module_name, FusionSupport.local_name(cell_reader)}
        ]
      )
    else
      _ -> :error
    end
  end


  defp parse(%{op: :let_in, name: "kept", value_expr: kept_expr, in_expr: rest}) do
    with {:ok, rows_var, row_full, row_cells} <- parse_filter_map_rows(kept_expr),
         {:ok, cols_var} <- parse_cleared_concat(rest) do
      {:ok, rows_var, cols_var, row_full, row_cells}
    end
  end

  defp parse(_), do: :error

  defp parse_filter_map_rows(%{
         op: :qualified_call,
         target: "List.filterMap",
         args: [lambda, range_call]
       }) do
    with {:ok, row_full, row_cells} <- parse_filter_lambda(lambda),
         {:ok, rows_var} <- parse_range_zero_to_rows_minus_one(range_call) do
      {:ok, rows_var, row_full, row_cells}
    end
  end

  defp parse_filter_map_rows(_), do: :error

  defp parse_filter_lambda(%{
         op: :lambda,
         args: ["row"],
         body: %{
           op: :if,
           cond: %{
             op: :qualified_call,
             target: row_full,
             args: [%{op: :var, name: "row"}, %{op: :var, name: "board"}]
           },
           then_expr: %{op: :int_literal, value: 0, union_ctor: "Maybe.Nothing"},
           else_expr: %{
             op: :tuple2,
             left: %{op: :int_literal, value: 1, union_ctor: "Maybe.Just"},
             right: %{
               op: :qualified_call,
               target: row_cells,
               args: [%{op: :var, name: "row"}, %{op: :var, name: "board"}]
             }
           }
         }
       }) do
    {:ok, row_full, row_cells}
  end

  defp parse_filter_lambda(_), do: :error

  defp parse_range_zero_to_rows_minus_one(%{
         op: :qualified_call,
         target: "List.range",
         args: [%{op: :int_literal, value: 0}, %{op: :sub_const, var: rows_var, value: 1}]
       })
       when is_binary(rows_var),
       do: {:ok, rows_var}

  defp parse_range_zero_to_rows_minus_one(%{
         op: :qualified_call,
         target: "List.range",
         args: [%{op: :int_literal, value: 0}, %{op: :add_const, var: rows_var, value: -1}]
       })
       when is_binary(rows_var),
       do: {:ok, rows_var}

  defp parse_range_zero_to_rows_minus_one(_), do: :error

  defp parse_cleared_concat(%{
         op: :let_in,
         name: "cleared",
         value_expr: %{
           op: :call,
           name: "__sub__",
           args: [
             %{op: :var, name: rows_var},
             %{op: :qualified_call, target: "List.length", args: [%{op: :var, name: "kept"}]}
           ]
         },
         in_expr: %{
           op: :tuple2,
           left: concat_expr,
           right: %{op: :var, name: "cleared"}
         }
       })
       when is_binary(rows_var) do
    with {:ok, cols_var} <- parse_concat_repeat_zero_rows(concat_expr) do
      {:ok, cols_var}
    end
  end

  defp parse_cleared_concat(_), do: :error

  defp parse_concat_repeat_zero_rows(%{
         op: :qualified_call,
         target: "List.concat",
         args: [
           %{
             op: :call,
             name: "__append__",
             args: [
               %{
                 op: :qualified_call,
                 target: "List.repeat",
                 args: [%{op: :var, name: "cleared"}, zero_row_repeat]
               },
               %{op: :var, name: "kept"}
             ]
           }
         ]
       }) do
    parse_zero_row_repeat(zero_row_repeat)
  end

  defp parse_concat_repeat_zero_rows(_), do: :error

  defp parse_zero_row_repeat(%{
         op: :qualified_call,
         target: "List.repeat",
         args: [%{op: :var, name: cols_var}, %{op: :int_literal, value: 0}]
       })
       when is_binary(cols_var),
       do: {:ok, cols_var}

  defp parse_zero_row_repeat(_), do: :error

  defp row_full_matches?(decl_map, module_name, row_full, row_cells) do
    case Map.get(decl_map, FusionSupport.callee_key(module_name, row_full)) do
      %{
        expr: %{
          op: :qualified_call,
          target: "List.all",
          args: [
            %{op: :call, name: "__neq__", args: [%{op: :int_literal, value: 0}]},
            %{
              op: :qualified_call,
              target: ^row_cells,
              args: [%{op: :var, name: "row"}, %{op: :var, name: "board"}]
            }
          ]
        }
      } ->
        true

      _ ->
        false
    end
  end

  defp row_cells_matches?(decl_map, module_name, row_cells, cols_var) do
    case Map.get(decl_map, FusionSupport.callee_key(module_name, row_cells)) do
      %{
        expr: %{
          op: :qualified_call,
          target: "List.map",
          args: [
            %{
              op: :lambda,
              args: ["col"],
              body: %{
                op: :qualified_call,
                target: cell_reader,
                args: [
                  %{op: :var, name: "col"},
                  %{op: :var, name: "row"},
                  %{op: :var, name: "board"}
                ]
              }
            },
            range_expr
          ]
        }
      } ->
        if range_zero_to_cols_minus_one?(range_expr, cols_var),
          do: {:ok, cell_reader},
          else: :error

      _ ->
        :error
    end
  end

  defp range_zero_to_cols_minus_one?(%{
         op: :qualified_call,
         target: "List.range",
         args: [%{op: :int_literal, value: 0}, %{op: :sub_const, var: cols_var, value: 1}]
       }, cols_var)
       when is_binary(cols_var),
       do: true

  defp range_zero_to_cols_minus_one?(%{
         op: :qualified_call,
         target: "List.range",
         args: [%{op: :int_literal, value: 0}, %{op: :add_const, var: cols_var, value: -1}]
       }, cols_var)
       when is_binary(cols_var),
       do: true

  defp range_zero_to_cols_minus_one?(_, _), do: false

  defp emit(module_name, name, rows, cols) do
    c_prefix = Util.module_fn_name(module_name, name)
    bail = &RcRuntimeEmit.fusion_tuple2_take_int_out("out", &1, "cleared")

    """
    static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *board) {
      RC Rc = RC_SUCCESS;
      ElmcValue *owned[1] = {0};
      CATCH_BEGIN
        const elmc_int_t rows = #{rows};
        const elmc_int_t cols = #{cols};
        elmc_int_t cleared = 0;
        for (elmc_int_t row = 0; row < rows; row++) {
          bool row_full = true;
          for (elmc_int_t col = 0; col < cols; col++) {
            if (elmc_list_nth_int_default(board, (row * cols) + col, 0) == 0) {
              row_full = false;
              break;
            }
          }
          if (row_full) cleared++;
        }
        if (cleared == 0) {
          #{RcRuntimeEmit.fusion_tuple2_take_int_out("out", "elmc_retain(board)", "0")}
        } else {
          ElmcValue *built = NULL;
          ElmcValue **tail_slot = NULL;
          for (elmc_int_t z = 0; z < (cleared * cols); z++) {
            ElmcValue *cell = NULL;
            if (elmc_list_cons(&cell, elmc_int_zero(), elmc_list_nil()) != RC_SUCCESS) cell = elmc_list_nil();
            if (!cell) {
              elmc_release(built);
              #{bail.("elmc_list_nil()")}
            }
            if (tail_slot) {
              elmc_release(*tail_slot);
              *tail_slot = cell;
            } else {
              built = cell;
            }
            tail_slot = &((ElmcCons *)cell->payload)->tail;
          }
          for (elmc_int_t row = 0; row < rows; row++) {
            bool row_full = true;
            for (elmc_int_t col = 0; col < cols; col++) {
              if (elmc_list_nth_int_default(board, (row * cols) + col, 0) == 0) {
                row_full = false;
                break;
              }
            }
            if (!row_full) {
              for (elmc_int_t col = 0; col < cols; col++) {
                const elmc_int_t cell_value = elmc_list_nth_int_default(board, (row * cols) + col, 0);
                ElmcValue *head = NULL;
                if (elmc_new_int(&head, cell_value) != RC_SUCCESS) head = elmc_int_zero();
                if (!head) {
                  elmc_release(built);
                  #{bail.("elmc_list_nil()")}
                }
                ElmcValue *cell = NULL;
                if (elmc_list_cons(&cell, head, elmc_list_nil()) != RC_SUCCESS) cell = elmc_list_nil();
                elmc_release(head);
                if (!cell) {
                  elmc_release(built);
                  #{bail.("elmc_list_nil()")}
                }
                if (tail_slot) {
                  elmc_release(*tail_slot);
                  *tail_slot = cell;
                } else {
                  built = cell;
                }
                tail_slot = &((ElmcCons *)cell->payload)->tail;
              }
            }
          }
          if (!built) built = elmc_list_nil();
          #{RcRuntimeEmit.fusion_tuple2_take_int_out("out", "built", "cleared")}
        }
      CATCH_END;
      elmc_release_array_lifo(owned, DIM(owned));
      return Rc;
    }
    """
  end
end
