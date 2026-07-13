defmodule Elmc.Backend.CCodegen.RowSliceAdjacentMerge do
  @moduledoc """
  Fuses row-slice adjacent-pair merge pipeline: `collapseRow (rowAt n board)` per row, concat cells, sum scores.

  Verifies `rowAt` (`List.take`/`List.drop`), `collapseRow` (filter nonzero + slide merge + pad),
  and `merge` (adjacent equal pair collapse into a two-field record) from `decl_map`.
  """

  alias Elmc.Backend.CCodegen.Types

  alias Elmc.Backend.CCodegen.{FusionSupport, Util}

  @spec try_emit(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]}
          | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native}
          | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, row_calls, cells_field, score_field, cells_var} <- parse_collapse_rows(expr),
         {:ok, width} <- row_width_from_calls(decl_map, module_name, row_calls),
         rows = length(row_calls),
         true <- rows > 0,
         {:ok, collapse_row, row_at, merge} <- call_targets_from(decl_map, module_name, row_calls),
         {:ok, ^width} <- row_slice_width(decl_map, module_name, row_at),
         {:ok, ^merge, ^cells_field, ^score_field} <-
           collapse_row_shape(decl_map, module_name, collapse_row, width),
         true <- adjacent_pair_merge_record?(decl_map, module_name, merge, cells_field, score_field),
         {:ok, _record_type} <- result_record_type(decl_map, module_name, name) do
      callees = [
        FusionSupport.callee_key(module_name, collapse_row),
        FusionSupport.callee_key(module_name, row_at),
        FusionSupport.callee_key(module_name, merge)
      ]

      FusionSupport.ok_rc(
        emit(module_name, name, cells_var, rows, width),
        callees
      )
    else
      _ -> :error
    end
  end

  defp parse_collapse_rows(expr) do
    with {:ok, row_calls, cells_var} <- parse_row_lets(expr, []),
         {:ok, cells_field, score_field} <- parse_result_record(expr) do
      {:ok, row_calls, cells_field, score_field, cells_var}
    end
  end

  defp parse_row_lets(%{op: :let_in, value_expr: row_call, in_expr: rest}, acc) do
    parse_row_lets(rest, acc ++ [row_call])
  end

  defp parse_row_lets(%{op: :record_literal, fields: _fields}, acc) when acc != [] do
    with {:ok, cells_var} <- cells_var_from_row_calls(acc) do
      {:ok, acc, cells_var}
    end
  end

  defp parse_row_lets(_, _), do: :error

  defp cells_var_from_row_calls([first | _]) do
    case row_at_call(first) do
      {:ok, _collapse_row, _row_at, _row_index, cells_var} -> {:ok, cells_var}
      :error -> :error
    end
  end

  defp row_at_call(%{
         op: :qualified_call,
         target: collapse_row,
         args: [row_at_call]
       }) do
    case row_at_call do
      %{
        op: :qualified_call,
        target: row_at,
        args: [%{op: :int_literal, value: row_index}, %{op: :var, name: cells_var}]
      }
      when is_integer(row_index) and is_binary(cells_var) ->
        {:ok, collapse_row, row_at, row_index, cells_var}

      _ ->
        :error
    end
  end

  defp row_at_call(_), do: :error

  defp parse_result_record(expr), do: unwrap_result_record(expr) |> parse_result_fields()

  defp unwrap_result_record(expr) do
    case expr do
      %{op: :let_in, in_expr: rest} ->
        unwrap_result_record(rest)

      %{
        op: :record_literal,
        fields: fields
      }
      when is_list(fields) ->
        with {:ok, cells_field, cells_expr} <- find_append_field(fields),
             {:ok, score_field, score_expr} <- find_add_field(fields) do
          {:ok, cells_field, score_field, cells_expr, score_expr}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_result_fields({:ok, cells_field, score_field, cells_expr, score_expr}) do
    with true <- append_chain_fields?(cells_expr),
         true <- add_chain_fields?(score_expr) do
      {:ok, cells_field, score_field}
    else
      _ -> :error
    end
  end

  defp parse_result_fields(:error), do: :error

  defp find_padded_cells_field(fields, width) do
    Enum.find_value(fields, :error, fn
      %{name: name, expr: expr} when is_binary(name) ->
        if padded_row_cells?(expr, name, width), do: {:ok, name, expr}, else: nil

      _ ->
        nil
    end)
  end

  defp padded_row_cells?(
         %{op: :call, name: op, args: [left, right]},
         cells_field,
         width
       )
       when op in ["__append__", "++"] do
    field_access_field(left) == cells_field and repeat_pad?(right, cells_field, width)
  end

  defp padded_row_cells?(
         %{op: :qualified_call, target: "Basics.append", args: [left, right]},
         cells_field,
         width
       ) do
    padded_row_cells?(%{op: :call, name: "__append__", args: [left, right]}, cells_field, width)
  end

  defp padded_row_cells?(_, _, _), do: false

  defp find_append_field(fields) do
    Enum.find_value(fields, :error, fn
      %{name: name, expr: expr} when is_binary(name) ->
        if append_chain_root?(expr) and append_chain_fields?(expr),
          do: {:ok, name, expr},
          else: nil

      _ ->
        nil
    end)
  end

  defp append_chain_root?(%{op: :call, name: op, args: [_left, _right]})
       when op in ["__append__", "++"],
       do: true

  defp append_chain_root?(%{op: :qualified_call, target: "Basics.append", args: [_left, _right]}),
    do: true

  defp append_chain_root?(_), do: false

  defp find_add_field(fields) do
    Enum.find_value(fields, :error, fn
      %{name: name, expr: expr} when is_binary(name) ->
        if add_chain_fields?(expr), do: {:ok, name, expr}, else: nil

      _ ->
        nil
    end)
  end

  defp find_score_field(fields) do
    Enum.find_value(fields, :error, fn
      %{name: name, expr: expr} when is_binary(name) ->
        if field_access?(expr), do: {:ok, name, expr}, else: nil

      _ ->
        nil
    end)
  end

  defp append_chain_fields?(%{op: :call, name: op, args: [left, right]})
       when op in ["__append__", "++"],
       do: append_side?(left) and append_side?(right)

  defp append_chain_fields?(%{
         op: :qualified_call,
         target: "Basics.append",
         args: [left, right]
       }),
       do: append_chain_fields?(%{op: :call, name: "__append__", args: [left, right]})

  defp append_chain_fields?(%{op: :field_access, field: field}) when is_binary(field), do: true
  defp append_chain_fields?(_), do: false

  defp append_side?(expr), do: field_access?(expr) or append_chain_fields?(expr)

  defp field_access?(%{op: :field_access, field: field}) when is_binary(field), do: true
  defp field_access?(_), do: false

  defp field_access_field(%{op: :field_access, field: field}) when is_binary(field), do: field
  defp field_access_field(_), do: nil

  defp add_chain_fields?(%{op: :call, name: op, args: [left, right]})
       when op in ["__add__", "+"],
       do: sum_side?(left) and sum_side?(right)

  defp add_chain_fields?(%{
         op: :qualified_call,
         target: "Basics.add",
         args: [left, right]
       }),
       do: add_chain_fields?(%{op: :call, name: "__add__", args: [left, right]})

  defp add_chain_fields?(%{op: :field_access, field: field}) when is_binary(field), do: true
  defp add_chain_fields?(_), do: false

  defp sum_side?(expr), do: field_access?(expr) or add_chain_fields?(expr)

  defp row_width_from_calls(decl_map, module_name, row_calls) do
    with [first | _] <- row_calls,
         {:ok, collapse_row, row_at, 0, _} <- row_at_call(first),
         {:ok, width} <- row_slice_width(decl_map, module_name, row_at) do
      expected = Enum.map(0..(length(row_calls) - 1), & &1)

      actual =
        Enum.map(row_calls, fn call ->
          case row_at_call(call) do
            {:ok, ^collapse_row, ^row_at, row_index, _} -> row_index
            _ -> :error
          end
        end)

      if actual == expected, do: {:ok, width}, else: :error
    else
      _ -> :error
    end
  end

  defp call_targets_from(decl_map, module_name, row_calls) do
    with [first | _] <- row_calls,
         {:ok, collapse_row, row_at, _, _} <- row_at_call(first),
         {:ok, merge} <- collapse_row_merge(decl_map, module_name, collapse_row) do
      {:ok, collapse_row, row_at, merge}
    end
  end

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
       ) do
    row_mul_width?(index_expr, width)
  end

  defp row_drop_stride?(_, _), do: false

  defp row_mul_width?(%{op: :call, name: op, args: [%{op: :var, name: "row"}, %{op: :int_literal, value: width}]}, width)
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

  defp collapse_row_merge(decl_map, module_name, collapse_row_target) do
    case Map.get(decl_map, FusionSupport.callee_key(module_name, collapse_row_target)) do
      %{
        expr: %{
          op: :let_in,
          value_expr: %{
            op: :qualified_call,
            target: merge_target,
            args: [filter_expr]
          }
        }
      } ->
        if nonzero_filter?(filter_expr),
          do: {:ok, merge_target},
          else: :error

      _ ->
        :error
    end
  end

  defp nonzero_filter?(%{
         op: :qualified_call,
         target: "List.filter",
         args: [predicate, %{op: :var, name: "row"}]
       }) do
    case predicate do
      %{op: :call, name: op, args: [%{op: :int_literal, value: 0}]}
      when op in ["__neq__", "/="] ->
        true

      %{
        op: :qualified_call,
        target: target,
        args: [%{op: :int_literal, value: 0}]
      }
      when target in ["Basics.neq", "/="] ->
        true

      _ ->
        false
    end
  end

  defp nonzero_filter?(_), do: false

  defp collapse_row_shape(decl_map, module_name, collapse_row_target, width) do
    case Map.get(decl_map, FusionSupport.callee_key(module_name, collapse_row_target)) do
      %{
        expr: %{
          op: :let_in,
          value_expr: %{op: :qualified_call, target: merge_target},
          in_expr: %{op: :record_literal, fields: fields}
        }
      } ->
        with {:ok, cells_field, _cells_expr} <- find_padded_cells_field(fields, width),
             {:ok, score_field, score_expr} <- find_score_field(fields),
             true <- field_access_field(score_expr) == score_field do
          {:ok, merge_target, cells_field, score_field}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp repeat_pad?(
         %{
           op: :qualified_call,
           target: "List.repeat",
           args: [count_expr, %{op: :int_literal, value: 0}]
         },
         cells_field,
         width
       ) do
    case count_expr do
      %{
        op: :call,
        name: op,
        args: [
          %{op: :int_literal, value: ^width},
          %{
            op: :qualified_call,
            target: "List.length",
            args: [length_arg]
          }
        ]
      }
      when op in ["__sub__", "-"] ->
        field_access_field(length_arg) == cells_field

      %{
        op: :qualified_call,
        target: sub,
        args: [
          %{op: :int_literal, value: ^width},
          %{
            op: :qualified_call,
            target: "List.length",
            args: [length_arg]
          }
        ]
      }
      when sub in ["Basics.sub", "-"] ->
        field_access_field(length_arg) == cells_field

      _ ->
        false
    end
  end

  defp repeat_pad?(_, _, _), do: false

  defp adjacent_pair_merge_record?(decl_map, module_name, merge_target, cells_field, score_field) do
    case Map.get(decl_map, FusionSupport.callee_key(module_name, merge_target)) do
      %{expr: %{op: :case, subject: "values", branches: branches}} ->
        adjacent_pair_merge_branches?(branches, module_name, merge_target, cells_field, score_field)

      _ ->
        false
    end
  end

  defp adjacent_pair_merge_branches?(
         [
           %{pattern: %{kind: :constructor, resolved_name: "List.::"}, expr: cons_expr},
           %{pattern: %{kind: :wildcard}, expr: default_expr}
         ],
         module_name,
         merge_target,
         cells_field,
         score_field
       ) do
    equal_merge_branch?(cons_expr, module_name, merge_target, cells_field, score_field, :equal) and
      adjacent_pair_merge_default?(default_expr, cells_field, score_field)
  end

  defp adjacent_pair_merge_branches?(_, _, _, _, _), do: false

  defp adjacent_pair_merge_default?(
         %{op: :record_literal, fields: fields},
         cells_field,
         score_field
       ) do
    with %{expr: %{op: :var, name: "values"}} <- Enum.find(fields, &(&1.name == cells_field)),
         %{expr: %{op: :int_literal, value: 0}} <- Enum.find(fields, &(&1.name == score_field)) do
      true
    else
      _ -> false
    end
  end

  defp adjacent_pair_merge_default?(_, _, _), do: false

  defp equal_merge_branch?(expr, module_name, merge_target, cells_field, score_field, _) do
    case expr do
      %{
        op: :if,
        cond: %{op: :compare, left: %{name: "a"}, right: %{name: "b"}, kind: :eq},
        then_expr: then_expr,
        else_expr: else_expr
      } ->
        adjacent_pair_merge_equal_then?(then_expr, module_name, merge_target, cells_field, score_field) and
          adjacent_pair_merge_unequal_else?(else_expr, module_name, merge_target, cells_field, score_field)

      _ ->
        false
    end
  end

  defp adjacent_pair_merge_equal_then?(
         %{
           op: :let_in,
           value_expr: merge_call,
           in_expr: %{
             op: :let_in,
             value_expr: %{op: :add_vars, left: "a", right: "b"},
             in_expr: record
           }
         },
         _module_name,
         merge_target,
         cells_field,
         score_field
       ) do
    merge_rest_call?(merge_call, merge_target, "rest") and
      adjacent_pair_merge_cons_record?(record, "value", cells_field, score_field, true)
  end

  defp adjacent_pair_merge_equal_then?(_, _, _, _, _), do: false

  defp adjacent_pair_merge_unequal_else?(
         %{
           op: :let_in,
           value_expr: merge_call,
           in_expr: record
         },
         _module_name,
         merge_target,
         cells_field,
         score_field
       ) do
    merge_cons_rest_call?(merge_call, merge_target) and
      adjacent_pair_merge_cons_record?(record, "a", cells_field, score_field, false)
  end

  defp adjacent_pair_merge_unequal_else?(_, _, _, _, _), do: false

  defp merge_rest_call?(%{op: :qualified_call, target: target, args: [%{name: "rest"}]}, merge_target, "rest") do
    target == merge_target
  end

  defp merge_rest_call?(_, _, _), do: false

  defp merge_cons_rest_call?(
         %{
           op: :qualified_call,
           target: target,
           args: [
             %{
               op: :qualified_call,
               target: "List.cons",
               args: [%{name: "b"}, %{name: "rest"}]
             }
           ]
         },
         merge_target
       ) do
    target == merge_target
  end

  defp merge_cons_rest_call?(_, _), do: false

  defp adjacent_pair_merge_cons_record?(record, head_var, cells_field, score_field, add_score?) do
    case record do
      %{op: :record_literal, fields: fields} ->
        with %{expr: cons_expr} <- Enum.find(fields, &(&1.name == cells_field)),
             %{expr: score_expr} <- Enum.find(fields, &(&1.name == score_field)),
             true <- cons_matches?(cons_expr, head_var, cells_field),
             true <- score_field_expr?(score_expr, score_field, head_var, add_score?) do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp cons_matches?(
         %{
           op: :qualified_call,
           target: "List.cons",
           args: [%{name: cons_head}, tail]
         },
         head_var,
         cells_field
       ) do
    cons_head == head_var and cons_head in ["value", "a"] and
      field_access_field(tail) == cells_field
  end

  defp cons_matches?(_, _, _), do: false

  defp score_field_expr?(expr, score_field, head_var, true) do
    case expr do
      %{op: :call, name: op, args: [%{name: ^head_var}, tail]}
      when op in ["__add__", "+"] ->
        field_access_field(tail) == score_field

      %{
        op: :qualified_call,
        target: "Basics.add",
        args: [%{name: ^head_var}, tail]
      } ->
        field_access_field(tail) == score_field

      _ ->
        false
    end
  end

  defp score_field_expr?(expr, score_field, _head_var, false) do
    field_access_field(expr) == score_field
  end

  defp result_record_type(decl_map, module_name, name) do
    case Map.get(decl_map, {module_name, name}) do
      %{type: type} when is_binary(type) ->
        case String.split(type, " -> ", parts: 2) do
          [_arg, result] -> {:ok, result_type_name(result)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp result_type_name(type) do
    type
    |> String.trim()
    |> String.split(".")
    |> List.last()
  end

  defp emit(module_name, name, cells_var, rows, width) do
    c_prefix = Util.module_fn_name(module_name, name)
    cell_count = rows * width

    """
    static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *#{cells_var}) {
      RC Rc = RC_SUCCESS;
      ElmcValue *owned[2] = {0};
      CATCH_BEGIN
        static const elmc_int_t rows = #{rows};
        static const elmc_int_t width = #{width};
        elmc_int_t flat[#{cell_count}];
        elmc_int_t total_score = 0;
        for (elmc_int_t row = 0; row < rows; row++) {
          elmc_int_t buf[#{width}];
          elmc_int_t n = 0;
          for (elmc_int_t col = 0; col < width; col++) {
            const elmc_int_t cell = elmc_list_nth_int_default(#{cells_var}, (row * width) + col, 0);
            if (cell != 0) buf[n++] = cell;
          }
          elmc_int_t merged[#{width}];
          elmc_int_t m = 0;
          elmc_int_t row_score = 0;
          elmc_int_t i = 0;
          while (i < n) {
            if (i + 1 < n && buf[i] == buf[i + 1]) {
              const elmc_int_t v = buf[i] + buf[i + 1];
              merged[m++] = v;
              row_score += v;
              i += 2;
            } else {
              merged[m++] = buf[i++];
            }
          }
          while (m < width) merged[m++] = 0;
          total_score += row_score;
          for (elmc_int_t col = 0; col < width; col++) {
            flat[(row * width) + col] = merged[col];
          }
        }
        Rc = elmc_list_from_int_array(&owned[0], flat, #{cell_count});
        CHECK_RC(Rc);
        Rc = elmc_new_int(&owned[1], total_score);
        CHECK_RC(Rc);
        {
          ElmcValue *rec_values[2] = {owned[0], owned[1]};
          Rc = elmc_record_new_values_take(out, 2, rec_values);
          CHECK_RC(Rc);
          owned[0] = NULL;
          owned[1] = NULL;
        }
      CATCH_END;
      elmc_release_array_lifo(owned, DIM(owned));
      return Rc;
    }
    """
  end

  @doc false
  @spec extract_fusion_data(String.t(), String.t(), Types.ir_expr() | nil, Types.function_decl_map()) ::
          {:ok, :row_slice_adjacent_merge, Types.fusion_metadata()} | :error
  def extract_fusion_data(module_name, _name, expr, decl_map) do
    with {:ok, row_calls, _cells_field, _score_field, _cells_var} <- parse_collapse_rows(expr),
         {:ok, width} <- row_width_from_calls(decl_map, module_name, row_calls),
         rows = length(row_calls),
         true <- rows > 0 do
      {:ok, :row_slice_adjacent_merge, %{width: width, rows: rows}}
    else
      _ -> :error
    end
  end
end
