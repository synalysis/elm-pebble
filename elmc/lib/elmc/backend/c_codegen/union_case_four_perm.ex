defmodule Elmc.Backend.CCodegen.UnionCaseFourPerm do
  @moduledoc """
  Fuses four-branch union `case` row-major permutes: identity, reverse rows, transpose,
  and a composed fourth branch.

  The fourth branch distinguishes forward (`reverseRows (transpose cells)`) from inverse
  (`transpose (reverseRows cells)`). Callee targets come from IR, not app names.
  """

  alias Elmc.Backend.CCodegen.{FusionSupport, ListMapStaticIndexAt, RowMajorLayout, Util}

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    case expr do
      %{op: :case, branches: case_branches} ->
        case parse(expr) do
          {:ok, cells_var, branches, mode} ->
            case callee_targets(branches, module_name) do
              {:ok, reverse_rows, transpose} ->
                case row_major_dims(decl_map, module_name, reverse_rows, transpose) do
                  {:ok, width, rows} ->
                    case ordered_branch_tags(case_branches) do
                      {:ok, tags} ->
                        FusionSupport.ok(
                          emit(module_name, name, cells_var, width, rows, mode, tags),
                          []
                        )

                      _ ->
                        :error
                    end

                  _ ->
                    :error
                end

              _ ->
                :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  @spec ordered_branch_tags([map()]) :: {:ok, [integer()]} | :error
  def ordered_branch_tags(branches) when is_list(branches) and length(branches) == 4 do
    tags =
      Enum.map(branches, fn %{pattern: pattern} ->
        pattern[:tag] || pattern[:union_tag] || ctor_tag_fallback(pattern)
      end)

    if Enum.all?(tags, &is_integer/1), do: {:ok, tags}, else: :error
  end

  def ordered_branch_tags(_), do: :error

  defp parse(%{op: :case, subject: subject, branches: branches})
       when is_list(branches) and length(branches) == 4 do
    with true <- case_subject?(subject),
         [b0, b1, b2, b3] <- branches,
         {:ok, cells_var} <- identity_cells_var(b0.expr),
         true <- cells_call?(b1.expr, cells_var),
         true <- cells_call?(b2.expr, cells_var),
         {:ok, mode} <- fourth_branch_mode(b3.expr, cells_var) do
      {:ok, cells_var, [b0.expr, b1.expr, b2.expr, b3.expr], mode}
    else
      _ -> :error
    end
  end

  defp parse(_), do: :error

  defp case_subject?(%{op: :var, name: _}), do: true
  defp case_subject?(name) when is_binary(name), do: true
  defp case_subject?(_), do: false

  defp identity_cells_var(%{op: :var, name: cells_var}) when is_binary(cells_var),
    do: {:ok, cells_var}

  defp identity_cells_var(_), do: :error

  defp cells_call?(%{op: :var, name: cells_var}, cells_var), do: true

  defp cells_call?(
         %{op: :qualified_call, args: [%{op: :var, name: cells_var}]},
         cells_var
       ),
       do: true

  defp cells_call?(
         %{op: :call, target: {_, _}, args: [%{op: :var, name: cells_var}]},
         cells_var
       ),
       do: true

  defp cells_call?(_, _), do: false

  defp fourth_branch_mode(
         %{
           op: :qualified_call,
           target: reverse_rows,
           args: [%{op: :qualified_call, target: transpose, args: [%{op: :var, name: cells}]}]
         },
         cells_var
       )
       when is_binary(reverse_rows) and is_binary(transpose) and cells == cells_var do
    {:ok, {:forward, reverse_rows, transpose}}
  end

  defp fourth_branch_mode(
         %{
           op: :qualified_call,
           target: transpose,
           args: [%{op: :qualified_call, target: reverse_rows, args: [%{op: :var, name: cells}]}]
         },
         cells_var
       )
       when is_binary(reverse_rows) and is_binary(transpose) and cells == cells_var do
    {:ok, {:inverse, reverse_rows, transpose}}
  end

  defp fourth_branch_mode(
         %{
           op: :call,
           target: {_, reverse_rows},
           args: [%{op: :call, target: {_, transpose}, args: [%{op: :var, name: cells}]}]
         },
         cells_var
       )
       when is_binary(reverse_rows) and is_binary(transpose) and cells == cells_var do
    {:ok, {:forward, reverse_rows, transpose}}
  end

  defp fourth_branch_mode(
         %{
           op: :call,
           target: {_, transpose},
           args: [%{op: :call, target: {_, reverse_rows}, args: [%{op: :var, name: cells}]}]
         },
         cells_var
       )
       when is_binary(reverse_rows) and is_binary(transpose) and cells == cells_var do
    {:ok, {:inverse, reverse_rows, transpose}}
  end

  defp fourth_branch_mode(_, _), do: :error

  defp callee_targets(branches, module_name) do
    with [_, right, up, down] <- branches,
         {:ok, reverse_rows} <- reverse_rows_target(right, module_name),
         {:ok, transpose} <- transpose_target(up, module_name),
         true <- fourth_branch_uses?(down, reverse_rows, transpose) do
      {:ok, reverse_rows, transpose}
    else
      _ -> :error
    end
  end

  defp reverse_rows_target(
         %{op: :qualified_call, target: target, args: [%{op: :var, name: _}]},
         module_name
       ),
       do: {:ok, local_callee(module_name, target)}

  defp reverse_rows_target(
         %{op: :call, target: {_, target}, args: [%{op: :var, name: _}]},
         module_name
       ),
       do: {:ok, local_callee(module_name, target)}

  defp reverse_rows_target(_, _), do: :error

  defp transpose_target(
         %{op: :qualified_call, target: target, args: [%{op: :var, name: _}]},
         module_name
       ),
       do: {:ok, local_callee(module_name, target)}

  defp transpose_target(
         %{op: :call, target: {_, target}, args: [%{op: :var, name: _}]},
         module_name
       ),
       do: {:ok, local_callee(module_name, target)}

  defp transpose_target(_, _), do: :error

  defp local_callee(module_name, target) do
    qualified_local(module_name, FusionSupport.local_name(target))
  end

  defp qualified_local(module_name, name) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [^module_name, local] -> local
      [_other, local] -> local
      [local] -> local
    end
  end

  defp fourth_branch_uses?(down, rr, tr) do
    forward_compose?(down, rr, tr) or inverse_compose?(down, rr, tr)
  end

  defp forward_compose?(
         %{op: :qualified_call, target: t1, args: [%{op: :qualified_call, target: t2}]},
         rr,
         tr
       ),
       do: targets_match?(t1, rr) and targets_match?(t2, tr)

  defp forward_compose?(
         %{op: :call, target: {_, t1}, args: [%{op: :call, target: {_, t2}}]},
         rr,
         tr
       ),
       do: targets_match?(t1, rr) and targets_match?(t2, tr)

  defp forward_compose?(_, _, _), do: false

  defp inverse_compose?(
         %{op: :qualified_call, target: t1, args: [%{op: :qualified_call, target: t2}]},
         rr,
         tr
       ),
       do: targets_match?(t1, tr) and targets_match?(t2, rr)

  defp inverse_compose?(
         %{op: :call, target: {_, t1}, args: [%{op: :call, target: {_, t2}}]},
         rr,
         tr
       ),
       do: targets_match?(t1, tr) and targets_match?(t2, rr)

  defp inverse_compose?(_, _, _), do: false

  defp targets_match?(target, expected) do
    FusionSupport.local_name(target) == expected or target == "Main.#{expected}"
  end

  defp row_major_dims(decl_map, module_name, reverse_rows, transpose) do
    with {:ok, width, rows} <- dims_from_reverse_rows(decl_map, module_name, reverse_rows),
         true <- transpose_static_count?(decl_map, module_name, transpose, width * rows) do
      {:ok, width, rows}
    end
  end

  defp dims_from_reverse_rows(decl_map, module_name, reverse_rows) do
    case Map.get(decl_map, {module_name, reverse_rows}) do
      %{expr: expr} -> parse_dims_from_reverse_rows_expr(expr, decl_map, module_name)
      _ -> :error
    end
  end

  defp parse_dims_from_reverse_rows_expr(expr, decl_map, module_name) do
    with {:ok, row_at, _cells, indices} <- reverse_rows_list(expr),
         {:ok, width} <- row_slice_width(decl_map, module_name, row_at) do
      {:ok, width, length(indices)}
    end
  end

  defp reverse_rows_list(%{op: :qualified_call, target: "List.concat", args: [list_expr]}) do
    parse_row_indices(list_items(list_expr))
  end

  defp reverse_rows_list(%{
         op: :pipe,
         left: list_expr,
         right: %{op: :qualified_call, target: "List.concat", args: []}
       }) do
    parse_row_indices(list_items(list_expr))
  end

  defp reverse_rows_list(%{
         op: :pipe,
         left: list_expr,
         right: %{op: :call, target: {_, "concat"}, args: []}
       }) do
    parse_row_indices(list_items(list_expr))
  end

  defp reverse_rows_list(_), do: :error

  defp list_items(%{op: :list_literal, items: items}), do: items
  defp list_items(_), do: []

  defp parse_row_indices(items) do
    items
    |> Enum.reduce_while({:ok, nil, nil, []}, fn item, acc ->
      case item do
        %{
          op: :qualified_call,
          target: "List.reverse",
          args: [
            %{
              op: :qualified_call,
              target: row_at,
              args: [%{op: :int_literal, value: row_index}, %{op: :var, name: cells}]
            }
          ]
        } ->
          collect_row_index(acc, row_at, cells, row_index)

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp collect_row_index({:ok, row_at, cells_var, indices}, row_at, cells, row_index)
       when cells == cells_var,
       do: {:cont, {:ok, row_at, cells_var, indices ++ [row_index]}}

  defp collect_row_index({:ok, nil, nil, []}, row_at, cells, row_index),
    do: {:cont, {:ok, row_at, cells, [row_index]}}

  defp collect_row_index(_, _, _, _), do: {:halt, :error}

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

  defp transpose_static_count?(decl_map, module_name, transpose, count) do
    case Map.get(decl_map, {module_name, transpose}) do
      %{expr: expr} ->
        case ListMapStaticIndexAt.try_emit(module_name, transpose, expr, decl_map) do
          {:ok, _, _} -> transpose_index_count(expr) == count
          :error -> false
        end

      _ ->
        false
    end
  end

  defp transpose_index_count(%{op: :qualified_call, target: "List.map", args: [_, list_expr]}) do
    case list_expr do
      %{op: :list_literal, items: items} -> length(items)
      _ -> 0
    end
  end

  defp transpose_index_count(_), do: 0

  defp ctor_tag_fallback(%{kind: :constructor, tag: tag}) when is_integer(tag), do: tag
  defp ctor_tag_fallback(%{kind: :constructor, union_tag: tag}) when is_integer(tag), do: tag
  defp ctor_tag_fallback(_), do: nil

  defp emit(module_name, name, cells_var, width, rows, mode, tags) do
    c_prefix = Util.module_fn_name(module_name, name)
    count = rows * width
    tag_expr = RowMajorLayout.union_tag_expr("tag_arg")
    index_expr = RowMajorLayout.case_tag_perm_index_expr("case_tag", tags) |> String.trim()

    """
    static ElmcValue *#{c_prefix}_native(ElmcValue *tag_arg, ElmcValue *#{cells_var}) {
      elmc_int_t src[#{count}];
      elmc_int_t dst[#{count}];
      for (elmc_int_t i = 0; i < #{count}; i++) {
        src[i] = elmc_list_nth_int_default(#{cells_var}, i, 0);
      }
      const int case_tag = #{tag_expr};
      const int perm_case = #{index_expr};
      #{RowMajorLayout.emit_apply_row_major_perm(forward_inverse_mode(mode), width, rows, "src", "dst", "perm_case", count)}
      ElmcValue *out = NULL;
      if (elmc_list_from_int_array(&out, dst, #{count}) != RC_SUCCESS)
        out = elmc_list_nil();
      return out ? out : elmc_list_nil();
    }
    """
  end

  defp forward_inverse_mode({:forward, _, _}), do: :forward
  defp forward_inverse_mode({:inverse, _, _}), do: :inverse
end
