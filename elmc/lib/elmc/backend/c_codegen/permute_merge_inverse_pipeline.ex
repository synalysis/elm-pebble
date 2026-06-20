defmodule Elmc.Backend.CCodegen.PermuteMergeInversePipeline do
  @moduledoc """
  Fuses permute → row merge → inverse-permute pipelines with compare, spawn, score, and model update.

  Verifies permute/inverse helpers, row merge, spawn, score merge, best save, and model
  record updates from IR — not from app-specific function names.
  """

  alias Elmc.Backend.CCodegen.{
    FusionSupport,
    RowMajorLayout,
    RowSliceAdjacentMerge,
    UnionCaseFourPerm,
    Util
  }

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]} | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error

  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    with {:ok, pipeline} <- parse_pipeline(expr),
         {:ok, width, rows} <- merge_dims(decl_map, module_name, pipeline.merge_fn),
         true <- permute_inverse_shape?(decl_map, module_name, pipeline.permute_fn, pipeline.inverse_fn),
         {:ok, else_info} <- parse_else_branch(pipeline.else_expr, pipeline),
         {:ok, model_type} <- model_type_name(decl_map, module_name, name),
         true <- model_field_macros?(module_name, model_type, pipeline, else_info),
         code when is_binary(code) and code != "" <-
           emit(module_name, name, pipeline, else_info, width, rows, model_type, decl_map) do
      FusionSupport.ok_rc(code, [{module_name, else_info.spawn}])
    else
      _ -> :error
    end
  end

  defp parse_pipeline(expr) do
    with {:ok, permute_call, merge_call, inverse_call, if_expr} <- three_lets(expr),
         {:ok, permute_fn, tag_var, cells_access} <- parse_permute_call(permute_call),
         {:ok, merge_fn, perm_buf_var} <- parse_unary_call(merge_call),
         {:ok, inverse_fn, tag_var2, merge_buf_var, merge_cells_field} <-
           parse_inverse_call(inverse_call),
         true <- tag_var == tag_var2,
         {model_var, model_cells_field} = cells_access,
         {:ok, else_expr} <- if_else(if_expr) do
      {:ok,
       %{
         permute_fn: permute_fn,
         merge_fn: merge_fn,
         inverse_fn: inverse_fn,
         tag_var: tag_var,
         perm_buf_var: perm_buf_var,
         model_var: model_var,
         cells_field: model_cells_field,
         merge_buf_var: merge_buf_var,
         merge_cells_field: merge_cells_field,
         else_expr: else_expr,
         output_var: pipeline_output_var(if_expr)
       }}
    end
  end

  defp three_lets(%{
         op: :let_in,
         value_expr: e1,
         in_expr: %{op: :let_in, value_expr: e2, in_expr: %{op: :let_in, value_expr: e3, in_expr: body}}
       }),
       do: {:ok, e1, e2, e3, body}

  defp three_lets(_), do: :error

  defp pipeline_output_var(%{
         op: :if,
         cond: %{op: :compare, left: %{op: :var, name: left}, right: %{op: :var, name: _right}}
       }),
       do: left

  defp pipeline_output_var(%{
         op: :if,
         cond: %{op: :compare, left: %{op: :var, name: name}}
       }),
       do: name

  defp pipeline_output_var(_), do: "out_buf"

  defp parse_permute_call(%{
         op: :qualified_call,
         target: permute_fn,
         args: [%{op: :var, name: tag_var}, %{op: :field_access, arg: model, field: cells}]
       })
       when is_binary(tag_var) and is_binary(model) and is_binary(cells) and is_binary(permute_fn) do
    {:ok, FusionSupport.local_name(permute_fn), tag_var, {model, cells}}
  end

  defp parse_permute_call(_), do: :error

  defp parse_unary_call(%{op: :qualified_call, target: target, args: [%{op: :var, name: arg}]})
       when is_binary(target) and is_binary(arg) do
    {:ok, FusionSupport.local_name(target), arg}
  end

  defp parse_unary_call(_), do: :error

  defp parse_inverse_call(%{
         op: :qualified_call,
         target: inverse_fn,
         args: [
           %{op: :var, name: tag_var},
           %{op: :field_access, arg: merge_buf, field: cells_field}
         ]
       })
       when is_binary(inverse_fn) and is_binary(tag_var) and is_binary(merge_buf) and
              is_binary(cells_field) do
    {:ok, FusionSupport.local_name(inverse_fn), tag_var, merge_buf, cells_field}
  end

  defp parse_inverse_call(_), do: :error

  defp if_else(%{op: :if, else_expr: else_expr}), do: {:ok, else_expr}
  defp if_else(_), do: :error

  defp merge_dims(decl_map, module_name, merge_fn) do
    case Map.get(decl_map, {module_name, merge_fn}) do
      %{expr: expr} ->
        case RowSliceAdjacentMerge.try_emit(module_name, merge_fn, expr, decl_map) do
          :error -> :error
          {:ok, _, _} -> merge_fn_dims(expr, decl_map, module_name)
        end

      _ ->
        :error
    end
  end

  defp merge_fn_dims(expr, decl_map, module_name) do
    with {:ok, row_calls} <- merge_row_calls(expr, []),
         {:ok, width} <- row_width(row_calls, decl_map, module_name) do
      {:ok, width, length(row_calls)}
    end
  end

  defp merge_row_calls(%{op: :let_in, value_expr: call, in_expr: rest}, acc),
    do: merge_row_calls(rest, acc ++ [call])

  defp merge_row_calls(%{op: :record_literal}, acc) when acc != [], do: {:ok, acc}

  defp merge_row_calls(_, _), do: :error

  defp row_width([first | _], decl_map, module_name) do
    case first do
      %{
        op: :qualified_call,
        args: [
          %{op: :qualified_call, target: row_at, args: [%{op: :int_literal, value: 0}, _]}
        ]
      } ->
        row_at_name = FusionSupport.local_name(row_at)
        row_slice_width(decl_map, module_name, row_at_name)

      _ ->
        :error
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

  defp permute_inverse_shape?(decl_map, module_name, permute_fn, inverse_fn) do
    permute_ok?(decl_map, module_name, permute_fn) and
      permute_ok?(decl_map, module_name, inverse_fn)
  end

  defp permute_ok?(decl_map, module_name, fn_name) do
    case Map.get(decl_map, {module_name, fn_name}) do
      %{expr: expr} ->
        case UnionCaseFourPerm.try_emit(module_name, fn_name, expr, decl_map) do
          {:ok, _, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp permute_case_tags(decl_map, module_name, permute_fn) do
    case Map.get(decl_map, {module_name, permute_fn}) do
      %{expr: %{op: :case, branches: branches}} -> UnionCaseFourPerm.ordered_branch_tags(branches)
      _ -> :error
    end
  end

  defp parse_else_branch(expr, pipeline) do
    with {:ok, spawn, seed_field, output_var} <- parse_spawn(expr, pipeline.output_var),
         {:ok, score_field, merge_buf_var} <- parse_score_add(expr),
         true <- merge_buf_var == pipeline.merge_buf_var,
         {:ok, best_field} <- parse_best(expr),
         {:ok, storage_key} <- parse_storage(expr),
         {:ok, update_fields} <- parse_record_update(expr),
         turn_field = parse_turn_field(expr) |> turn_field_or_default(),
         else_info = %{
           spawn: spawn,
           seed_field: seed_field,
           output_var: output_var,
           score_field: score_field,
           best_field: best_field,
           storage_key: storage_key,
           turn_field: turn_field,
           update_fields: update_fields
         },
         true <- record_updates_match?(update_fields, pipeline, else_info) do
      {:ok, else_info}
    end
  end

  defp parse_spawn(%{op: :let_in, value_expr: spawn_call, in_expr: rest}, output_var) do
    case spawn_call do
      %{
        op: :qualified_call,
        target: spawn,
        args: [%{op: :field_access, field: seed}, %{op: :var, name: ^output_var}]
      }
      when is_binary(spawn) and is_binary(seed) ->
        {:ok, FusionSupport.local_name(spawn), seed, output_var}

      _ ->
        parse_spawn(rest, output_var)
    end
  end

  defp parse_spawn(_, _), do: :error

  defp parse_score_add(expr) do
    find_let_value(expr, fn
      %{
        op: :call,
        name: op,
        args: [
          %{op: :field_access, field: model_score_field},
          %{op: :field_access, arg: merge_buf, field: _merge_score_field}
        ]
      }
      when op in ["__add__", "+"] and is_binary(merge_buf) and is_binary(model_score_field) ->
        {:ok, model_score_field, merge_buf}

      %{
        op: :qualified_call,
        target: "Basics.add",
        args: [
          %{op: :field_access, field: model_score_field},
          %{op: :field_access, arg: merge_buf, field: _merge_score_field}
        ]
      }
      when is_binary(merge_buf) and is_binary(model_score_field) ->
        {:ok, model_score_field, merge_buf}

      _ ->
        :error
    end)
  end

  defp parse_best(expr) do
    find_let_value(expr, fn
      %{
        op: :qualified_call,
        target: "Basics.max",
        args: [%{op: :field_access, field: best}, %{op: :var, name: next_score}]
      }
      when is_binary(best) and is_binary(next_score) ->
        {:ok, best}

      _ ->
        :error
    end)
  end

  defp parse_storage(expr) do
    find_let_value(expr, fn
      %{
        op: :if,
        then_expr: %{
          op: :qualified_call,
          target: target,
          args: [%{op: :int_literal, value: key}, _]
        }
      }
      when target in ["Pebble.Storage.writeString", "Storage.writeString"] and is_integer(key) ->
        {:ok, key}

      _ ->
        :error
    end)
  end

  defp parse_turn_field(expr) do
    case find_record_update(expr) do
      %{op: :record_update, fields: fields} ->
        case Enum.find(fields, fn
               %{
                 name: field,
                 expr: %{
                   op: :call,
                   name: op,
                   args: [
                     %{op: :field_access, arg: %{op: :var, name: _model}, field: field},
                     %{op: :int_literal, value: 1}
                   ]
                 }
               }
               when op in ["__add__", "+"] ->
                 true

               %{
                 name: field,
                 expr: %{
                   op: :qualified_call,
                   target: "Basics.add",
                   args: [
                     %{op: :field_access, arg: %{op: :var, name: _model}, field: field},
                     %{op: :int_literal, value: 1}
                   ]
                 }
               } ->
                 true

               _ ->
                 false
             end) do
          %{name: field} -> {:ok, field}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp turn_field_or_default({:ok, field}), do: field
  defp turn_field_or_default(:error), do: "turn"

  defp parse_record_update(expr) do
    case find_record_update(expr) do
      %{op: :record_update, fields: fields} when is_list(fields) ->
        record_field_map(fields)

      _ ->
        :error
    end
  end

  defp find_record_update(%{op: :record_update, fields: _} = expr), do: expr

  defp find_record_update(%{op: :let_in, in_expr: rest}), do: find_record_update(rest)

  defp find_record_update(%{op: :tuple2, left: left}), do: find_record_update(left)

  defp find_record_update(_), do: nil

  defp record_field_map(fields) do
    field_map =
      fields
      |> Enum.filter(&match?(%{expr: %{op: :var, name: _}}, &1))
      |> Map.new(fn %{name: name, expr: %{name: var}} -> {name, var} end)

    if map_size(field_map) >= 4, do: {:ok, field_map}, else: :error
  end

  defp record_updates_match?(field_map, pipeline, else_info) do
    Enum.all?(
      [pipeline.cells_field, else_info.score_field, else_info.best_field, else_info.seed_field],
      &Map.has_key?(field_map, &1)
    )
  end

  defp find_let_value(%{op: :let_in, value_expr: value, in_expr: rest}, matcher) do
    case matcher.(value) do
      :error -> find_let_value(rest, matcher)
      result when is_tuple(result) and elem(result, 0) == :ok -> result
      _ -> find_let_value(rest, matcher)
    end
  end

  defp find_let_value(%{op: :let_in, in_expr: rest}, matcher), do: find_let_value(rest, matcher)
  defp find_let_value(_, _), do: :error

  defp model_type_name(decl_map, module_name, name) do
    case Map.get(decl_map, {module_name, name}) do
      %{type: type} when is_binary(type) ->
        parts = String.split(type, " -> ")

        case length(parts) do
          n when n >= 2 -> {:ok, parts |> Enum.at(-2) |> type_basename()}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp model_field_macros?(module_name, model_type, pipeline, else_info) do
    fields = [
      {pipeline.cells_field, model_type},
      {else_info.seed_field, model_type},
      {else_info.score_field, model_type},
      {else_info.best_field, model_type},
      {else_info.turn_field, model_type}
    ]

    Enum.all?(fields, fn {field, type} ->
      is_binary(FusionSupport.field_macro(module_name, type, field))
    end)
  end

  defp type_basename(type) do
    type |> String.trim() |> String.split(".") |> List.last()
  end

  defp emit(module_name, name, pipeline, else_info, width, rows, model_type, decl_map) do
    c_prefix = Util.module_fn_name(module_name, name)
    count = rows * width

    with {:ok, tags} <- permute_case_tags(decl_map, module_name, pipeline.permute_fn) do
      cells_macro = FusionSupport.field_macro(module_name, model_type, pipeline.cells_field)
      seed_macro = FusionSupport.field_macro(module_name, model_type, else_info.seed_field)
      score_macro = FusionSupport.field_macro(module_name, model_type, else_info.score_field)
      best_macro = FusionSupport.field_macro(module_name, model_type, else_info.best_field)
      turn_macro = FusionSupport.field_macro(module_name, model_type, else_info.turn_field)
      tag_expr = RowMajorLayout.union_tag_expr("tag_arg")
      perm_case_index = RowMajorLayout.case_tag_perm_index_expr("case_tag", tags) |> String.trim()

      if [cells_macro, seed_macro, score_macro, best_macro, turn_macro]
         |> Enum.any?(&is_nil/1) do
        ""
      else
        emit_body(
          c_prefix,
          count,
          cells_macro,
          seed_macro,
          score_macro,
          best_macro,
          turn_macro,
          else_info,
          width,
          rows,
          tag_expr,
          perm_case_index,
          module_name
        )
      end
    else
      _ -> ""
    end
  end

  defp emit_body(
         c_prefix,
         count,
         cells_macro,
         seed_macro,
         score_macro,
         best_macro,
         turn_macro,
         else_info,
         width,
         rows,
         tag_expr,
         perm_case_index,
         module_name
       ) do
    """
    #{RowMajorLayout.emit_perm_src_index_fn(width)}
    static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *tag_arg, ElmcValue *model) {
      RC Rc = RC_SUCCESS;
      CATCH_BEGIN
      elmc_int_t src[#{count}];
      elmc_int_t perm_buf[#{count}];
      elmc_int_t merge_buf[#{count}];
      elmc_int_t out_buf[#{count}];
      ElmcValue *model_cells = ELMC_RECORD_GET_INDEX(model, #{cells_macro});
      for (elmc_int_t i = 0; i < #{count}; i++) {
        src[i] = elmc_list_nth_int_default(model_cells, i, 0);
      }
      const int case_tag = #{tag_expr};
      const int perm_case = #{perm_case_index};
      #{RowMajorLayout.emit_apply_row_major_perm_via_helper("src", "perm_buf", "perm_case", false, count)}
      elmc_int_t merge_score = 0;
      #{RowMajorLayout.emit_adjacent_pair_merge_rows(width, rows, "perm_buf", "merge_buf", "merge_score")}
      #{RowMajorLayout.emit_apply_row_major_perm_via_helper("merge_buf", "out_buf", "perm_case", true, count)}
      bool unchanged = true;
      for (elmc_int_t cmp_i = 0; cmp_i < #{count}; cmp_i++) {
        if (out_buf[cmp_i] != elmc_list_nth_int_default(model_cells, cmp_i, 0)) {
          unchanged = false;
          break;
        }
      }
      if (unchanged) {
        ElmcValue *no_cmd = elmc_int_zero();
        ElmcValue *same_out = NULL;
        Rc = elmc_tuple2_take(&same_out, model, no_cmd);
        CHECK_RC(Rc);
        *out = same_out;
      } else {
        #{emit_inline_spawn_tile(module_name, seed_macro, count)}
        const elmc_int_t model_score = ELMC_RECORD_GET_INDEX_INT(model, #{score_macro});
        const elmc_int_t model_best = ELMC_RECORD_GET_INDEX_INT(model, #{best_macro});
        const elmc_int_t model_turn = ELMC_RECORD_GET_INDEX_INT(model, #{turn_macro});
        const elmc_int_t next_score = model_score + merge_score;
        const elmc_int_t next_best = (model_best >= next_score) ? model_best : next_score;
        ElmcValue *next_best_val = NULL;
        Rc = elmc_new_int(&next_best_val, next_best);
        CHECK_RC(Rc);
        ElmcValue *save_cmd = NULL;
        if (next_best > model_best) {
          char best_buf[32];
          snprintf(best_buf, sizeof(best_buf), "%lld", (long long)next_best);
          save_cmd = elmc_cmd1_string(ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING, #{else_info.storage_key}, best_buf);
        } else {
          save_cmd = elmc_int_zero();
        }
        ElmcValue *turn_val = NULL;
        Rc = elmc_new_int(&turn_val, model_turn + 1);
        CHECK_RC(Rc);
        ElmcValue *next_model = elmc_record_update_index_cow_drop(model, #{best_macro}, next_best_val);
        next_model = elmc_record_update_index_cow_drop(next_model, #{cells_macro}, next_cells);
        next_model = elmc_record_update_index_cow_drop(next_model, #{score_macro}, elmc_new_int_take(next_score));
        next_model = elmc_record_update_index_cow_drop(next_model, #{seed_macro}, next_seed);
        next_model = elmc_record_update_index_cow_drop(next_model, #{turn_macro}, turn_val);
        elmc_release(next_cells);
        elmc_release(next_seed);
        elmc_release(turn_val);
        elmc_release(next_best_val);
        ElmcValue *cmd_copy = save_cmd ? elmc_retain(save_cmd) : elmc_int_zero();
        ElmcValue *result = NULL;
        Rc = elmc_tuple2_take(&result, next_model, cmd_copy);
        CHECK_RC(Rc);
        elmc_release(save_cmd);
        *out = result;
      }
      CATCH_END;
      return Rc;
    }
    """
  end

  defp emit_inline_spawn_tile(_module_name, seed_macro, count) do
    """
    elmc_int_t spawn_empty_count = 0;
    for (elmc_int_t spawn_scan_i = 0; spawn_scan_i < #{count}; spawn_scan_i++) {
      if (out_buf[spawn_scan_i] == 0) spawn_empty_count++;
    }
    const elmc_int_t spawn_model_seed = ELMC_RECORD_GET_INDEX_INT(model, #{seed_macro});
    elmc_int_t spawn_seed_after_choice = ((spawn_model_seed * 16807) + 11) % 2147483647;
    if (spawn_seed_after_choice < 0) spawn_seed_after_choice += 2147483647;
    elmc_int_t spawn_seed_after_tile = ((spawn_seed_after_choice * 16807) + 11) % 2147483647;
    if (spawn_seed_after_tile < 0) spawn_seed_after_tile += 2147483647;
    ElmcValue *next_seed = NULL;
    Rc = elmc_new_int(&next_seed, spawn_seed_after_tile);
    CHECK_RC(Rc);
    if (spawn_empty_count > 0) {
      elmc_int_t spawn_pick = spawn_seed_after_choice % spawn_empty_count;
      if (spawn_pick < 0) spawn_pick += spawn_empty_count;
      elmc_int_t spawn_seen_empty = 0;
      elmc_int_t spawn_tile_index = 0;
      for (elmc_int_t spawn_scan_i = 0; spawn_scan_i < #{count}; spawn_scan_i++) {
        if (out_buf[spawn_scan_i] != 0) continue;
        if (spawn_seen_empty == spawn_pick) {
          spawn_tile_index = spawn_scan_i;
          break;
        }
        spawn_seen_empty++;
      }
      elmc_int_t spawn_tile_roll = spawn_seed_after_tile % 10;
      if (spawn_tile_roll < 0) spawn_tile_roll += 10;
      out_buf[spawn_tile_index] = spawn_tile_roll == 0 ? 4 : 2;
    }
    ElmcValue *next_cells = NULL;
    if (elmc_list_from_int_array(&next_cells, out_buf, #{count}) != RC_SUCCESS)
      next_cells = elmc_list_nil();
    """
    |> String.trim()
  end
end
