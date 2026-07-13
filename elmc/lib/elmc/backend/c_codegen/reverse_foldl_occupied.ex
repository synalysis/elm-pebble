defmodule Elmc.Backend.CCodegen.ReverseFoldlOccupied do
  @moduledoc """
  Fuses `List.reverse` of `List.foldl` over a range collecting nonzero flat-list indices.

  Cell reader and board size vars are resolved from IR/`decl_map`, not by name.
  """

  alias Elmc.Backend.CCodegen.Types

  alias Elmc.Backend.CCodegen.{FusionSupport, Util}

  @spec try_emit(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]}
          | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native}
          | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, cell_reader, cols_var, size_var} <- parse(expr),
         {:ok, count} <- FusionSupport.resolve_cell_count(decl_map, module_name, size_var),
         true <- FusionSupport.flat_list_cell_reader?(decl_map, module_name, cell_reader, cols_var) do
      FusionSupport.ok_rc(
        emit(module_name, name, count),
        [{module_name, FusionSupport.local_name(cell_reader)}]
      )
    else
      _ -> :error
    end
  end

  defp parse(%{
         op: :qualified_call,
         target: "List.reverse",
         args: [
           %{
             op: :qualified_call,
             target: "List.foldl",
             args: [lambda, %{op: :list_literal, items: []}, range_call]
           }
         ]
       }) do
    with {:ok, cell_reader, cols_var} <- parse_foldl_lambda(lambda),
         {:ok, size_var} <- range_zero_to_exclusive_upper?(range_call) do
      {:ok, cell_reader, cols_var, size_var}
    end
  end

  defp parse(_), do: :error

  defp parse_foldl_lambda(%{
         op: :lambda,
         args: ["index"],
         body: %{
           op: :lambda,
           args: ["slots"],
           body: %{
             op: :if,
             cond: %{
               op: :compare,
               left: cell_at_call,
               right: %{op: :int_literal, value: 0},
               kind: :eq
             },
             then_expr: %{op: :var, name: "slots"},
             else_expr: %{
               op: :qualified_call,
               target: "List.cons",
               args: [%{op: :var, name: "index"}, %{op: :var, name: "slots"}]
             }
           }
         }
       }) do
    flat_index_from_cell_at(cell_at_call)
  end

  defp parse_foldl_lambda(_), do: :error

  defp flat_index_from_cell_at(%{
         op: :qualified_call,
         target: cell_reader,
         args: [col_expr, row_expr, %{op: :var, name: "board"}]
       })
       when is_binary(cell_reader) do
    case mod_by_cols(col_expr) do
      {:ok, cols_var} ->
        if row_from_index_div(row_expr, cols_var),
          do: {:ok, cell_reader, cols_var},
          else: :error

      :error ->
        :error
    end
  end

  defp flat_index_from_cell_at(_), do: :error

  defp mod_by_cols(%{
         op: :qualified_call,
         target: target,
         args: [%{op: :var, name: cols_var}, %{op: :var, name: "index"}]
       })
       when target in ["Basics.modBy", "modBy"] and is_binary(cols_var),
       do: {:ok, cols_var}

  defp mod_by_cols(_), do: :error

  defp row_from_index_div(%{op: :call, name: "__idiv__", args: [%{op: :var, name: "index"}, %{op: :var, name: cols_var}]}, cols_var),
    do: cols_var

  defp row_from_index_div(%{op: :qualified_call, target: "Basics.idiv", args: [%{op: :var, name: "index"}, %{op: :var, name: cols_var}]}, cols_var),
    do: cols_var

  defp row_from_index_div(_, _), do: false

  defp range_zero_to_exclusive_upper?(%{
         op: :qualified_call,
         target: "List.range",
         args: [%{op: :int_literal, value: 0}, hi]
       }) do
    FusionSupport.rows_from_sub_one(hi)
  end

  defp range_zero_to_exclusive_upper?(_), do: :error

  defp emit(module_name, name, size) do
    c_prefix = Util.module_fn_name(module_name, name)

    """
    static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *board) {
      RC Rc = RC_SUCCESS;
      ElmcValue *owned[2] = {0};
      CATCH_BEGIN
        ElmcValue **tail_slot = NULL;
        for (elmc_int_t index = 0; index < #{size}; index++) {
          const elmc_int_t cell = elmc_list_nth_int_default(board, index, 0);
          if (cell != 0) {
            Rc = elmc_new_int(&owned[1], index);
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

  @doc false
  @spec extract_fusion_data(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
          {:ok, :reverse_foldl_occupied, Types.fusion_metadata()} | :error
  def extract_fusion_data(module_name, _name, expr, decl_map) do
    with {:ok, cell_reader, cols_var, size_var} <- parse(expr),
         {:ok, count} <- FusionSupport.resolve_cell_count(decl_map, module_name, size_var),
         true <- FusionSupport.flat_list_cell_reader?(decl_map, module_name, cell_reader, cols_var) do
      {:ok, :reverse_foldl_occupied, %{count: count}}
    else
      _ -> :error
    end
  end
end
