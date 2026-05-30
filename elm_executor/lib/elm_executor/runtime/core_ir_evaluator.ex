defmodule ElmExecutor.Runtime.CoreIREvaluator do
  @moduledoc """
  Deterministic CoreIR expression evaluator used by runtime semantics.
  """

  import ElmExecutor.Runtime.CoreIREvaluator.Value.MaybeResult,
    only: [
      result_ctor: 1,
      maybe_head_ctor: 1,
      maybe_tail_ctor: 1,
      maybe_map_get_ctor: 2,
      maybe_extreme_ctor: 2,
      maybe_value: 1,
      maybe_ctor_like: 2,
      result_value: 1,
      with_default_maybe_or_result: 2
    ]

  import ElmExecutor.Runtime.CoreIREvaluator.Value.Dict,
    only: [
      dict_pair_list?: 1,
      dict_from_pair_list: 1,
      dict_to_list: 1,
      dict_keys: 1,
      dict_values: 1
    ]

  import ElmExecutor.Runtime.CoreIREvaluator.Value.String,
    only: [
      char_from_code: 1,
      char_predicate: 2,
      char_alpha?: 1,
      char_alphanum?: 1,
      char_digit?: 1,
      char_octal_digit?: 1,
      char_lower?: 1,
      char_upper?: 1,
      normalize_char_binary: 1,
      char_to_code: 1,
      string_left: 2,
      string_right: 2,
      string_drop_left: 2,
      string_drop_right: 2,
      string_pad_center: 3,
      string_pad_left: 3,
      string_pad_right: 3,
      string_slice: 3,
      string_indexes: 2,
      string_uncons_ctor: 1,
      maybe_int_from_string: 1,
      maybe_float_from_string: 1,
      float_to_elm_string: 1
    ]

  import ElmExecutor.Runtime.CoreIREvaluator.Value.DebugString,
    only: [
      elm_debug_to_string: 1
    ]

  alias ElmExecutor.Runtime.CoreIREvaluator.Eval
  alias ElmExecutor.Runtime.CoreIREvaluator.Index
  alias ElmExecutor.Runtime.CoreIREvaluator.Value.HigherOrder
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes

  @max_function_recursion_depth 128

  @type context :: EvalTypes.ops_context()

  @spec build_eval_context(EvalTypes.core_ir() | nil, String.t()) :: context()
  def build_eval_context(core_ir, module_name) when is_binary(module_name) do
    %{
      module: module_name,
      source_module: module_name,
      functions: index_functions(core_ir),
      record_aliases: index_record_aliases(core_ir),
      record_alias_field_types: index_record_alias_field_types(core_ir),
      constructor_tags: index_constructor_tags(core_ir)
    }
  end

  @spec entry_module(EvalTypes.core_ir() | nil) :: String.t()
  def entry_module(core_ir) when is_map(core_ir) do
    modules = generic_map_value(core_ir, "modules") || generic_map_value(core_ir, :modules)

    modules
    |> List.wrap()
    |> Enum.find_value(&module_name_with_decl(&1, "init"))
    |> case do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        modules
        |> List.wrap()
        |> Enum.find_value(&evaluator_module_name/1)
        |> case do
          name when is_binary(name) and name != "" -> name
          _ -> "Main"
        end
    end
  end

  def entry_module(_), do: "Main"

  @spec module_name_with_decl(map(), String.t()) :: String.t() | nil
  defp module_name_with_decl(module, declaration_name) when is_map(module) do
    declarations = generic_map_value(module, "declarations") || []

    if Enum.any?(declarations, &(generic_map_value(&1, "name") == declaration_name)) do
      evaluator_module_name(module)
    end
  end

  defp module_name_with_decl(_module, _declaration_name), do: nil

  @spec evaluator_module_name(map()) :: String.t() | nil
  defp evaluator_module_name(module) when is_map(module) do
    case generic_map_value(module, "name") do
      name when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  @spec evaluate(EvalTypes.expr(), EvalTypes.env(), context()) :: EvalTypes.eval_result()
  def evaluate(expr, env \\ %{}, context \\ %{})
      when is_map(expr) and is_map(env) and is_map(context) do
    do_evaluate(expr, env, context, [])
  end

  @spec decode_http_response(map(), map(), context()) :: EvalTypes.eval_result()
  def decode_http_response(command, response, context \\ %{}) when is_map(context) do
    ElmExecutor.Runtime.CoreIREvaluator.Builtins.HttpResponse.decode(
      command,
      response,
      http_response_ops(context)
    )
  end

  @spec index_functions(EvalTypes.core_ir() | nil) :: EvalTypes.function_index()
  defdelegate index_functions(core_ir), to: Index

  @spec index_record_aliases(EvalTypes.core_ir() | nil) :: EvalTypes.record_aliases()
  defdelegate index_record_aliases(core_ir), to: Index

  @spec index_record_alias_field_types(EvalTypes.core_ir() | nil) :: EvalTypes.record_alias_field_types()
  defdelegate index_record_alias_field_types(core_ir), to: Index

  @spec index_constructor_tags(EvalTypes.core_ir() | nil) :: EvalTypes.constructor_tags()
  defdelegate index_constructor_tags(core_ir), to: Index

  @spec generic_map_value(map(), String.t() | atom()) :: EvalTypes.runtime_value() | nil
  defp generic_map_value(map, key) when is_map(map) and is_binary(key) do
    map = if Map.has_key?(map, :__struct__), do: Map.from_struct(map), else: map

    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(map, fn
          {atom_key, value} when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: {:ok, value}, else: nil

          _ ->
            nil
        end)
        |> case do
          {:ok, value} -> value
          nil -> nil
        end
    end
  end

  defp generic_map_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  @spec normalize_params(list() | map() | nil) :: [String.t()]
  defp normalize_params(params) when is_list(params) do
    params
    |> Enum.map(fn p ->
      cond do
        is_binary(p) ->
          p

        is_map(p) ->
          case p["name"] || p[:name] || p["var"] || p[:var] || p["target"] || p[:target] do
            name when is_binary(name) -> name
            _ -> ""
          end

        true ->
          ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_params(_), do: []

  @spec do_evaluate(EvalTypes.expr(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.eval_result()
  defp do_evaluate(expr, env, context, stack)
       when is_map(expr) and is_map(env) and is_map(context) do
    op = expr |> generic_map_value("op") |> normalize_op()
    host = %{
      evaluate: &maybe_evaluate/4,
      compare: &compare/3,
      normalize_params: &normalize_params/1,
      collect_ok: &collect_ok/1,
      resolve_zero_arity_value: &resolve_zero_arity_value/3,
      tuple_first: &tuple_first/1,
      tuple_second: &tuple_second/1,
      char_from_code: &char_from_code/1,
      evaluate_with_env_lookup: &maybe_evaluate_with_env_lookup/4,
      normalize_record_fields: &normalize_record_fields/1,
      field_access: &field_access/2,
      numeric_operand_from_var: &numeric_operand_from_var/4,
      short_ctor_name: &short_ctor_name/1,
      record_alias_fields: &record_alias_fields/2,
      record_alias_field_types: &record_alias_field_types/2,
      record_alias_value: &record_alias_value/4,
      call_function: &call_function/5,
      call_callable: &call_callable/5,
      evaluate_case_branches: &evaluate_case_branches/5
    }

    case Eval.try_dispatch(op, expr, env, context, stack, host) do
      {:ok, value} ->
        {:ok, value}

      {:error, _} = err ->
        err

      :unsupported ->
        value = generic_map_value(expr, "value")

        cond do
          is_integer(value) or is_float(value) or is_boolean(value) or is_binary(value) ->
            {:ok, value}

          true ->
            {:error, {:unsupported_op, op}}
        end
    end
  end

  defp do_evaluate(_expr, _env, _context, _stack), do: {:error, :invalid_expr}

  @spec normalize_op(String.t() | atom()) :: atom() | String.t()
  defp normalize_op(op) when is_binary(op) do
    String.to_existing_atom(op)
  rescue
    ArgumentError -> op
  end

  defp normalize_op(op), do: op

  @spec maybe_evaluate(EvalTypes.expr() | EvalTypes.runtime_value(), EvalTypes.env(), context(), list()) ::
          EvalTypes.eval_result()
  defp maybe_evaluate(expr, env, context, stack) when is_map(expr) do
    if Map.has_key?(expr, "op") or Map.has_key?(expr, :op) do
      do_evaluate(expr, env, context, stack)
    else
      {:ok, expr}
    end
  end

  defp maybe_evaluate(value, _env, _context, _stack), do: {:ok, value}

  @spec maybe_evaluate_with_env_lookup(EvalTypes.runtime_value() | String.t(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.eval_result()
  defp maybe_evaluate_with_env_lookup(expr, env, context, stack)
       when is_binary(expr) and is_map(env) do
    case Map.fetch(env, expr) do
      {:ok, value} -> {:ok, value}
      :error -> maybe_evaluate(expr, env, context, stack)
    end
  end

  defp maybe_evaluate_with_env_lookup(expr, env, context, stack),
    do: maybe_evaluate(expr, env, context, stack)

  @spec collect_ok([EvalTypes.eval_result()]) :: EvalTypes.eval_result()
  defp collect_ok(rows) when is_list(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn
      {:ok, v}, {:ok, acc} -> {:cont, {:ok, [v | acc]}}
      {:error, reason}, _ -> {:halt, {:error, reason}}
      _, _ -> {:halt, {:error, :invalid_row}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      err -> err
    end
  end

  @spec call_function(String.t(), list(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.eval_result()
  defp call_function(name, args, env, context, stack) when is_binary(name) and is_list(args) do
    with {:ok, values} <-
           args |> Enum.map(&maybe_evaluate(&1, env, context, stack)) |> collect_ok() do
      case eval_builtin(name, values, env, context, stack) do
        {:ok, value} ->
          {:ok, value}

        {:error, reason} ->
          {:error, reason}

        :no_builtin ->
          case Map.get(env, name) do
            {:closure, params, body, closure_env} when is_list(params) and is_map(closure_env) ->
              apply_closure(name, params, body, closure_env, values, context, stack)

            bound when is_tuple(bound) or is_binary(bound) ->
              case call_callable(bound, values, env, context, stack) do
                {:error, {:not_callable, _}} ->
                  apply_indexed_function(name, values, context, stack)

                other ->
                  other
              end

            _ ->
              case apply_indexed_function(name, values, context, stack) do
                {:error, {:unknown_function, _}} when values == [] ->
                  {:ok, {:function_ref, name}}

                other ->
                  other
              end
          end
      end
    end
  end

  @spec apply_closure(String.t(), [String.t()], EvalTypes.expr(), EvalTypes.env(), EvalTypes.runtime_values(), map(), EvalTypes.eval_stack()) :: EvalTypes.eval_result()
  defp apply_closure(name, params, body, closure_env, values, context, stack)
       when is_binary(name) and is_list(params) and is_map(closure_env) and is_list(values) do
    param_count = length(params)
    value_count = length(values)

    cond do
      value_count == 0 ->
        {:ok, {:closure, params, body, closure_env}}

      value_count < param_count ->
        {bound_params, remaining_params} = Enum.split(params, value_count)

        next_env =
          Enum.zip(bound_params, values)
          |> Enum.reduce(closure_env, fn {param, value}, acc ->
            if is_binary(param), do: Map.put(acc, param, value), else: acc
          end)

        {:ok, {:closure, remaining_params, body, next_env}}

      value_count == param_count ->
        next_env =
          Enum.zip(params, values)
          |> Enum.reduce(closure_env, fn {param, value}, acc ->
            if is_binary(param), do: Map.put(acc, param, value), else: acc
          end)

        maybe_evaluate(body, next_env, context, stack)

      true ->
        {first_values, rest_values} = Enum.split(values, param_count)

        with {:ok, head_result} <-
               apply_closure(name, params, body, closure_env, first_values, context, stack) do
          call_callable(head_result, rest_values, closure_env, context, stack)
        end
    end
  end

  @spec eval_ui_builtin(String.t(), EvalTypes.runtime_values(), map()) :: EvalTypes.builtin_eval_result()
  defp eval_ui_builtin(name, values, context) when is_binary(name) and is_list(values) do
    normalized = normalize_builtin_name(name)

    case {normalized, values} do
      {"pebble.ui.clear", [color]} ->
        with {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("clear", [expr_node(resolved_color)])}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.roundrect", [x, y, w, h, radius, color]} ->
        with true <- Enum.all?([x, y, w, h, radius], &is_integer/1),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok,
           ui_node(
             "roundRect",
             Enum.map([x, y, w, h, radius, resolved_color], &expr_node/1)
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.roundrect", [bounds, radius, color]} ->
        with {:ok, {x, y, w, h}} <- normalize_rect(bounds),
             true <- is_integer(radius),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok,
           ui_node(
             "roundRect",
             Enum.map([x, y, w, h, radius, resolved_color], &expr_node/1)
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.rect", [x, y, w, h, color]} ->
        with true <- Enum.all?([x, y, w, h], &is_integer/1),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("rect", Enum.map([x, y, w, h, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.rect", [bounds, color]} ->
        with {:ok, {x, y, w, h}} <- normalize_rect(bounds),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("rect", Enum.map([x, y, w, h, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.fillrect", [x, y, w, h, color]} ->
        with true <- Enum.all?([x, y, w, h], &is_integer/1),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("fillRect", Enum.map([x, y, w, h, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.fillrect", [bounds, color]} ->
        with {:ok, {x, y, w, h}} <- normalize_rect(bounds),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("fillRect", Enum.map([x, y, w, h, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.arc", [x, y, w, h, start_angle, end_angle]} ->
        with true <- Enum.all?([x, y, w, h, start_angle, end_angle], &is_integer/1) do
          {:ok, ui_node("arc", Enum.map([x, y, w, h, start_angle, end_angle], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.arc", [bounds, start_angle, end_angle]} ->
        with {:ok, {x, y, w, h}} <- normalize_rect(bounds),
             true <- Enum.all?([start_angle, end_angle], &is_integer/1) do
          {:ok, ui_node("arc", Enum.map([x, y, w, h, start_angle, end_angle], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.fillradial", [x, y, w, h, start_angle, end_angle]} ->
        with true <- Enum.all?([x, y, w, h, start_angle, end_angle], &is_integer/1) do
          {:ok,
           ui_node(
             "fillRadial",
             Enum.map([x, y, w, h, start_angle, end_angle], &expr_node/1)
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.fillradial", [bounds, start_angle, end_angle]} ->
        with {:ok, {x, y, w, h}} <- normalize_rect(bounds),
             true <- Enum.all?([start_angle, end_angle], &is_integer/1) do
          {:ok,
           ui_node(
             "fillRadial",
             Enum.map([x, y, w, h, start_angle, end_angle], &expr_node/1)
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.pathfilled", [path_value]} ->
        with {:ok, {points, offset_x, offset_y, rotation}} <- normalize_path(path_value) do
          {:ok,
           ui_node(
             "pathFilled",
             [
               path_points_node(points),
               expr_node(offset_x),
               expr_node(offset_y),
               expr_node(rotation)
             ]
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.pathoutline", [path_value]} ->
        with {:ok, {points, offset_x, offset_y, rotation}} <- normalize_path(path_value) do
          {:ok,
           ui_node(
             "pathOutline",
             [
               path_points_node(points),
               expr_node(offset_x),
               expr_node(offset_y),
               expr_node(rotation)
             ]
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.pathoutlineopen", [path_value]} ->
        with {:ok, {points, offset_x, offset_y, rotation}} <- normalize_path(path_value) do
          {:ok,
           ui_node(
             "pathOutlineOpen",
             [
               path_points_node(points),
               expr_node(offset_x),
               expr_node(offset_y),
               expr_node(rotation)
             ]
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.circle", [cx, cy, r, color]} ->
        with true <- Enum.all?([cx, cy, r], &is_integer/1),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("circle", Enum.map([cx, cy, r, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.circle", [center, r, color]} ->
        with {:ok, {cx, cy}} <- normalize_point(center),
             true <- is_integer(r),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("circle", Enum.map([cx, cy, r, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.fillcircle", [cx, cy, r, color]} ->
        with true <- Enum.all?([cx, cy, r], &is_integer/1),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("fillCircle", Enum.map([cx, cy, r, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.fillcircle", [center, r, color]} ->
        with {:ok, {cx, cy}} <- normalize_point(center),
             true <- is_integer(r),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("fillCircle", Enum.map([cx, cy, r, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawbitmapinrect", [bitmap_id, bounds]} ->
        with {:ok, normalized_bitmap_id} <- normalize_bitmap_id(bitmap_id, context),
             {:ok, {x, y, w, h}} <- normalize_rect(bounds) do
          {:ok,
           ui_node("bitmapInRect", Enum.map([normalized_bitmap_id, x, y, w, h], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawbitmapinrect", [bitmap_id, x, y, w, h]} ->
        with {:ok, normalized_bitmap_id} <- normalize_bitmap_id(bitmap_id, context),
             true <- Enum.all?([x, y, w, h], &is_integer/1) do
          {:ok,
           ui_node("bitmapInRect", Enum.map([normalized_bitmap_id, x, y, w, h], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawrotatedbitmap", [bitmap_id, src_rect, angle, center]} ->
        with {:ok, normalized_bitmap_id} <- normalize_bitmap_id(bitmap_id, context),
             {:ok, {_src_x, _src_y, src_w, src_h}} <- normalize_rect(src_rect),
             {:ok, normalized_angle} <- normalize_rotation_angle(angle),
             {:ok, {center_x, center_y}} <- normalize_point(center) do
          {:ok,
           ui_node(
             "rotatedBitmap",
             Enum.map(
               [normalized_bitmap_id, src_w, src_h, normalized_angle, center_x, center_y],
               &expr_node/1
             )
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawrotatedbitmap", [bitmap_id, src_w, src_h, angle, center_x, center_y]} ->
        with {:ok, normalized_bitmap_id} <- normalize_bitmap_id(bitmap_id, context),
             {:ok, normalized_angle} <- normalize_rotation_angle(angle),
             true <- Enum.all?([src_w, src_h, center_x, center_y], &is_integer/1) do
          {:ok,
           ui_node(
             "rotatedBitmap",
             Enum.map(
               [normalized_bitmap_id, src_w, src_h, normalized_angle, center_x, center_y],
               &expr_node/1
             )
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawvectorat", [vector, origin]} ->
        with {:ok, normalized_vector_id} <- normalize_vector_id(vector, context),
             {:ok, {x, y}} <- normalize_point(origin) do
          {:ok,
           ui_node("drawVectorAt", Enum.map([normalized_vector_id, x, y], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawvectorat", [vector, x, y]} ->
        with {:ok, normalized_vector_id} <- normalize_vector_id(vector, context),
             true <- is_integer(x) and is_integer(y) do
          {:ok,
           ui_node("drawVectorAt", Enum.map([normalized_vector_id, x, y], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawvectorsequenceat", [vector, origin]} ->
        with {:ok, normalized_vector_id} <- normalize_vector_id(vector, context),
             {:ok, {x, y}} <- normalize_point(origin) do
          {:ok,
           ui_node("drawVectorSequenceAt", Enum.map([normalized_vector_id, x, y], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawbitmapsequenceat", [animation, origin]} ->
        with {:ok, normalized_animation_id} <- normalize_animation_id(animation, context),
             {:ok, {x, y}} <- normalize_point(origin) do
          {:ok,
           ui_node(
             "drawBitmapSequenceAt",
             Enum.map([normalized_animation_id, x, y], &expr_node/1)
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawvectorsequenceat", [vector, x, y]} ->
        with {:ok, normalized_vector_id} <- normalize_vector_id(vector, context),
             true <- is_integer(x) and is_integer(y) do
          {:ok,
           ui_node("drawVectorSequenceAt", Enum.map([normalized_vector_id, x, y], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"Pebble.Ui.drawBitmapSequenceAt", [animation, origin]} ->
        with {:ok, normalized_animation_id} <- normalize_animation_id(animation, context),
             {:ok, {x, y}} <- normalize_point(origin) do
          {:ok,
           ui_node(
             "drawBitmapSequenceAt",
             Enum.map([normalized_animation_id, x, y], &expr_node/1)
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawbitmapsequenceat", [animation, x, y]} ->
        with {:ok, normalized_animation_id} <- normalize_animation_id(animation, context),
             true <- is_integer(x) and is_integer(y) do
          {:ok,
           ui_node(
             "drawBitmapSequenceAt",
             Enum.map([normalized_animation_id, x, y], &expr_node/1)
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.line", [x1, y1, x2, y2, color]} ->
        with true <- Enum.all?([x1, y1, x2, y2], &is_integer/1),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("line", Enum.map([x1, y1, x2, y2, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.line", [start_pos, end_pos, color]} ->
        with {:ok, {x1, y1}} <- normalize_point(start_pos),
             {:ok, {x2, y2}} <- normalize_point(end_pos),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("line", Enum.map([x1, y1, x2, y2, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.pixel", [x, y, color]} ->
        with true <- Enum.all?([x, y], &is_integer/1),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("pixel", Enum.map([x, y, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.pixel", [pos, color]} ->
        with {:ok, {x, y}} <- normalize_point(pos),
             {:ok, resolved_color} <- normalize_color(color) do
          {:ok, ui_node("pixel", Enum.map([x, y, resolved_color], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.textint", [font_id, pos, value]} ->
        with {:ok, normalized_font_id} <- normalize_font_id(font_id),
             {:ok, {x, y}} <- normalize_point(pos) do
          {:ok, ui_node("textInt", Enum.map([normalized_font_id, x, y, value], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.textlabel", [font_id, pos, text]} ->
        with {:ok, normalized_font_id} <- normalize_font_id(font_id),
             {:ok, {x, y}} <- normalize_point(pos),
             {:ok, normalized_text} <- normalize_text_value(text) do
          {:ok,
           ui_node(
             "textLabel",
             [
               expr_node(normalized_font_id),
               expr_node(x),
               expr_node(y),
               expr_node(normalized_text)
             ]
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.defaulttextoptions", []} ->
        {:ok, %{"alignment" => 1, "overflow" => 0}}

      {"pebble.ui.alignleft", [options]} ->
        update_text_option(options, "alignment", 0)

      {"pebble.ui.aligncenter", [options]} ->
        update_text_option(options, "alignment", 1)

      {"pebble.ui.alignright", [options]} ->
        update_text_option(options, "alignment", 2)

      {"pebble.ui.wordwrap", [options]} ->
        update_text_option(options, "overflow", 0)

      {"pebble.ui.trailingellipsis", [options]} ->
        update_text_option(options, "overflow", 1)

      {"pebble.ui.filloverflow", [options]} ->
        update_text_option(options, "overflow", 2)

      {"pebble.ui.text", [font_id, options, bounds, value]} ->
        normalized_font_id = normalize_font_id_or_default(font_id)
        {alignment, overflow} = normalize_text_options_or_default(options)
        {x, y, w, h} = normalize_rect_or_default(bounds)
        normalized_text = normalize_text_value_or_default(value)

        {:ok,
         ui_node(
           "text",
           Enum.map(
             [normalized_font_id, x, y, w, h, alignment, overflow, normalized_text],
             &expr_node/1
           )
         )}

      {"pebble.ui.text", [font_id, bounds, value]} ->
        normalized_font_id = normalize_font_id_or_default(font_id)
        {x, y, w, h} = normalize_rect_or_default(bounds)
        normalized_text = normalize_text_value_or_default(value)

        {:ok,
         ui_node(
           "text",
           Enum.map([normalized_font_id, x, y, w, h, normalized_text], &expr_node/1)
         )}

      {"pebble.ui.strokewidth", [value]} when is_integer(value) ->
        {:ok, {:ui_context_setting, "stroke_width", max(value, 1)}}

      {"pebble.ui.antialiased", [value]} when is_boolean(value) ->
        {:ok, {:ui_context_setting, "antialiased", value}}

      {"pebble.ui.antialiased", [value]} when is_integer(value) ->
        {:ok, {:ui_context_setting, "antialiased", value != 0}}

      {"pebble.ui.strokecolor", [color]} ->
        with {:ok, resolved_color} <- normalize_color(color) do
          {:ok, {:ui_context_setting, "stroke_color", resolved_color}}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.fillcolor", [color]} ->
        with {:ok, resolved_color} <- normalize_color(color) do
          {:ok, {:ui_context_setting, "fill_color", resolved_color}}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.textcolor", [color]} ->
        with {:ok, resolved_color} <- normalize_color(color) do
          {:ok, {:ui_context_setting, "text_color", resolved_color}}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.compositingmode", [value]} when is_integer(value) ->
        {:ok, {:ui_context_setting, "compositing_mode", value}}

      {"pebble.ui.context", [settings, ops]} when is_list(settings) and is_list(ops) ->
        {:ok, {:ui_context, ui_context_style(settings), ops}}

      {"pebble.ui.group", [{:ui_context, style, ops}]} ->
        {:ok, ui_group_node(style, ops)}

      {"pebble.ui.canvaslayer", [z, ops]} ->
        {:ok, ui_node("canvasLayer", [expr_node(z)] ++ ui_children_from_value(ops))}

      {"pebble.ui.window", [z, layers]} ->
        {:ok, ui_node("window", [expr_node(z)] ++ ui_children_from_value(layers))}

      {"pebble.ui.windowstack", [windows]} ->
        {:ok, ui_node("windowStack", ui_children_from_value(windows))}

      _ ->
        :no_builtin
    end
  end

  @spec eval_ui_color_builtin(String.t(), EvalTypes.runtime_values()) :: EvalTypes.builtin_eval_result()
  defp eval_ui_color_builtin(function_name, values)
       when is_binary(function_name) and is_list(values) do
    case {function_name, values} do
      {"argb8", [code]} ->
        normalize_indexed_color(code)

      {"indexed", [code]} ->
        normalize_indexed_color(code)

      {"rgb", [r, g, b]} ->
        normalize_rgba_color(r, g, b, 255)

      {"rgba", [r, g, b, a]} ->
        normalize_rgba_color(r, g, b, a)

      {"toint", [color]} ->
        normalize_color_result(color)

      {name, []} ->
        color_constant(name)

      _ ->
        :no_builtin
    end
  end

  @spec eval_builtin(String.t(), EvalTypes.runtime_values(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp eval_builtin(name, values, env, context, stack)
       when is_binary(name) and is_list(values) and is_map(env) and is_map(context) and
              is_list(stack) do
    normalized_full = normalize_builtin_name(name)
    {module_name, function_name} = split_builtin_name(normalized_full)
    allow_legacy_fallback = legacy_fallback_allowed_module?(module_name)
    force_legacy_operator_fallback = String.starts_with?(function_name, "__")

    if String.starts_with?(normalized_full, "elm.kernel.json.") do
      json_name = String.replace_prefix(normalized_full, "elm.kernel.json.", "")

      ElmExecutor.Runtime.CoreIREvaluator.Builtins.JsonKernel.eval(
        json_name,
        values,
        json_kernel_ops(env, context, stack)
      )
    else
      case eval_builtin_by_module(normalized_full, values, env, context, stack) do
        {:ok, _} = ok ->
          ok

        {:error, _} = err ->
          if force_legacy_operator_fallback do
            case eval_builtin_legacy(name, values, env, context, stack) do
              {:ok, value} -> {:ok, value}
              _ -> err
            end
          else
            err
          end

        :skip_legacy_fallback ->
          :no_builtin

        :no_builtin ->
          if allow_legacy_fallback or force_legacy_operator_fallback do
            eval_builtin_legacy(name, values, env, context, stack)
          else
            :no_builtin
          end
      end
    end
  end

  defp eval_builtin(_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_builtin_by_module(String.t(), EvalTypes.runtime_values(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result() | :skip_legacy_fallback
  defp eval_builtin_by_module(normalized_full, values, env, context, stack)
       when is_binary(normalized_full) and is_list(values) and is_map(env) and is_map(context) and
              is_list(stack) do
    {module_name, function_name} = split_builtin_name(normalized_full)

    case module_name do
      "list" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.List.eval(
          function_name,
          values,
          list_builtin_ops(env, context, stack)
        )

      "result" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Result.eval(
          function_name,
          values,
          result_builtin_ops(env, context, stack)
        )

      "maybe" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Maybe.eval(
          function_name,
          values,
          maybe_builtin_ops(env, context, stack)
        )

      "task" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Task.eval(
          function_name,
          values,
          task_builtin_ops(env, context, stack)
        )

      "random" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Random.eval(
          function_name,
          values,
          random_builtin_ops(env, context, stack)
        )

      "elm.kernel.random" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Random.eval(
          function_name,
          values,
          random_builtin_ops(env, context, stack)
        )

      "cmd" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Cmd.eval(function_name, values)

      "sub" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Cmd.eval(function_name, values)

      "platform.cmd" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Cmd.eval(function_name, values)

      "platform.sub" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Cmd.eval(function_name, values)

      "http" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Http.eval(function_name, values)

      "pebble.storage" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package.eval(
          module_name,
          function_name,
          values,
          package_builtin_ops(env, context, stack)
        )

      "pebble.time" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package.eval(
          module_name,
          function_name,
          values,
          package_builtin_ops(env, context, stack)
        )

      "pebble.watchinfo" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package.eval(
          module_name,
          function_name,
          values,
          package_builtin_ops(env, context, stack)
        )

      "pebble.health" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package.eval(
          module_name,
          function_name,
          values,
          package_builtin_ops(env, context, stack)
        )

      "pebble.cmd" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package.eval(
          module_name,
          function_name,
          values,
          package_builtin_ops(env, context, stack)
        )

      "elm.kernel.pebblewatch" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package.eval(
          module_name,
          function_name,
          values,
          package_builtin_ops(env, context, stack)
        )

      "companion.phone" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package.eval(
          module_name,
          function_name,
          values,
          package_builtin_ops(env, context, stack)
        )

      "companion.watch" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package.eval(
          module_name,
          function_name,
          values,
          package_builtin_ops(env, context, stack)
        )

      "companion.generatedpreferences" ->
        eval_generated_preferences_builtin(function_name, values)

      "basics" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Basics.eval(
          function_name,
          values,
          basics_builtin_ops(env, context, stack)
        )

      "bitwise" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Bitwise.eval(function_name, values)

      "bit" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Bitwise.eval(function_name, values)

      "string" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.String.eval(
          function_name,
          values,
          string_builtin_ops(env, context, stack)
        )

      "dict" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Dict.eval(
          function_name,
          values,
          dict_builtin_ops(env, context, stack)
        )

      "array" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Array.eval(
          function_name,
          values,
          array_builtin_ops(env, context, stack)
        )

      "set" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Set.eval(
          function_name,
          values,
          set_builtin_ops(env, context, stack)
        )

      "char" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Char.eval(function_name, values)

      "url" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Url.eval(function_name, values)

      "time" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Time.eval(function_name, values)

      "elm.kernel.time" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Time.eval_kernel(function_name, values)

      "debug" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Debug.eval(
          function_name,
          values,
          debug_builtin_ops()
        )

      "parser" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Parser.eval(
          function_name,
          values,
          parser_builtin_ops(env, context, stack)
        )

      "parser.advanced" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Parser.eval(
          function_name,
          values,
          parser_builtin_ops(env, context, stack)
        )

      "tuple" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.Tuple.eval(
          function_name,
          values,
          tuple_builtin_ops(env, context, stack)
        )

      "pebble.ui" ->
        case eval_ui_builtin(normalized_full, values, context) do
          :no_builtin ->
            cond do
              indexed_pebble_ui_function?(context, function_name, length(values)) ->
                :no_builtin

              true ->
                maybe_wrap_render_ops_as_ui_node(function_name, values, context)
            end

          other ->
            other
        end

      "pebble.ui.color" ->
        eval_ui_color_builtin(function_name, values)

      "json.decode" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.JsonDecode.eval(
          function_name,
          values,
          json_decode_builtin_ops(env, context, stack)
        )

      "json.encode" ->
        ElmExecutor.Runtime.CoreIREvaluator.Builtins.JsonEncode.eval(
          function_name,
          values,
          json_encode_builtin_ops(env, context, stack)
        )

      "" ->
        if function_name in ["map", "map2", "andthen", "withdefault"] do
          :skip_legacy_fallback
        else
          :no_builtin
        end

      _ ->
        :no_builtin
    end
  end

  @spec eval_generated_preferences_builtin(String.t(), EvalTypes.runtime_values()) :: EvalTypes.builtin_eval_result()
  defp eval_generated_preferences_builtin("decodeconfigurationflags", [flags]) do
    response =
      case flags do
        %{} -> Map.get(flags, "configurationResponse") || Map.get(flags, :configurationResponse)
        _ -> nil
      end

    case response do
      value when is_binary(value) and value != "" ->
        :no_builtin

      _ ->
        {:ok, %{"ctor" => "Ok", "args" => [%{"ctor" => "Nothing", "args" => []}]}}
    end
  end

  defp eval_generated_preferences_builtin(_function_name, _values), do: :no_builtin

  @spec indexed_pebble_ui_function?(map(), String.t(), non_neg_integer()) :: boolean()
  defp indexed_pebble_ui_function?(context, function_name, arity)
       when is_map(context) and is_binary(function_name) and is_integer(arity) do
    context
    |> Map.get(:functions, %{})
    |> Enum.any?(fn
      {{module_name, name, ^arity}, _def} when is_binary(module_name) and is_binary(name) ->
        compact_module_name(module_name) == "pebbleui" and
          normalize_builtin_name(name) == function_name

      _ ->
        false
    end)
  end

  @spec maybe_wrap_render_ops_as_ui_node(String.t(), EvalTypes.runtime_values(), map()) ::
          EvalTypes.builtin_eval_result()
  defp maybe_wrap_render_ops_as_ui_node(function_name, values, context)
       when is_binary(function_name) and is_list(values) and is_map(context) do
    with [ops] <- values,
         true <- is_list(ops),
         type when is_binary(type) <-
           function_type_signature(context, "Pebble.Ui", function_name, 1),
         true <- render_ops_to_ui_node_signature?(type) do
      wrap_render_ops_list_as_ui_node(ops)
    else
      _ -> :no_builtin
    end
  end

  @spec function_type_signature(map(), String.t(), String.t(), non_neg_integer()) ::
          String.t() | nil
  defp function_type_signature(context, module_name, function_name, arity)
       when is_map(context) and is_binary(module_name) and is_binary(function_name) and
              is_integer(arity) do
    target_compact = compact_module_name(module_name)
    target_name = normalize_builtin_name(function_name)

    context
    |> Map.get(:functions, %{})
    |> Enum.find_value(fn
      {{candidate_module, name, ^arity}, defn} when is_binary(candidate_module) and is_binary(name) ->
        if compact_module_name(candidate_module) == target_compact and
             normalize_builtin_name(name) == target_name do
          case defn do
            %{type: type} when is_binary(type) and type != "" -> type
            _ -> nil
          end
        end

      _ ->
        nil
    end)
  end

  @spec render_ops_to_ui_node_signature?(String.t()) :: boolean()
  defp render_ops_to_ui_node_signature?(type) when is_binary(type) do
    type
    |> String.replace(~r/\s+/, "")
    |> String.downcase()
    |> then(fn normalized ->
      String.match?(normalized, ~r/listrenderop->.*uinode$/) or
        String.match?(normalized, ~r/\(.*listrenderop.*\)->.*uinode$/)
    end)
  end

  @spec wrap_render_ops_list_as_ui_node(list()) :: {:ok, EvalTypes.ui_node_map()}
  defp wrap_render_ops_list_as_ui_node(ops) when is_list(ops) do
    canvas = ui_node("canvasLayer", [expr_node(1) | ui_children_from_value(ops)])
    window = ui_node("window", [expr_node(1), canvas])
    {:ok, ui_node("windowStack", [window])}
  end

  @spec list_builtin_ops(map(), map(), list()) :: map()
  defp list_builtin_ops(env, context, stack) do
    %{
      map_dispatch: &map_dispatch(&1, &2, env, context, stack),
      list_map2: &list_map2_with_callable(&1, &2, &3, env, context, stack),
      indexed_map: &indexed_map_with_callable(&1, &2, env, context, stack),
      concat_map: &concat_map_with_callable(&1, &2, env, context, stack),
      filter_map: &filter_map_with_callable(&1, &2, env, context, stack),
      foldl: &foldl_with_callable(&1, &2, &3, env, context, stack),
      foldr: &foldr_with_callable(&1, &2, &3, env, context, stack),
      filter: &filter_with_callable(&1, &2, env, context, stack),
      all: &all_with_callable(&1, &2, env, context, stack),
      any: &any_with_callable(&1, &2, env, context, stack),
      partition: &partition_with_callable(&1, &2, env, context, stack),
      sort_by: &sort_by_with_callable(&1, &2, env, context, stack),
      sort_with: &sort_with_callable(&1, &2, env, context, stack),
      head: &{:ok, maybe_head_ctor(&1)},
      tail: &{:ok, maybe_tail_ctor(&1)},
      maximum: &{:ok, maybe_extreme_ctor(&1, :max)},
      minimum: &{:ok, maybe_extreme_ctor(&1, :min)},
      call: &call_callable(&1, &2, env, context, stack)
    }
  end

  @spec string_builtin_ops(map(), map(), list()) :: map()
  defp string_builtin_ops(env, context, stack) do
    call = callable_runner(env, context, stack)

    %{
      string_map: &HigherOrder.string_map_with_callable(&1, &2, call),
      string_filter: &HigherOrder.string_filter_with_callable(&1, &2, call),
      string_foldl: &HigherOrder.string_foldl_with_callable(&1, &2, &3, call),
      string_foldr: &HigherOrder.string_foldr_with_callable(&1, &2, &3, call),
      string_any: &HigherOrder.string_any_with_callable(&1, &2, call),
      string_all: &HigherOrder.string_all_with_callable(&1, &2, call)
    }
  end

  @spec dict_builtin_ops(map(), map(), list()) :: map()
  defp dict_builtin_ops(env, context, stack) do
    %{
      call: &call_callable(&1, &2, env, context, stack)
    }
  end

  @spec set_builtin_ops(map(), map(), list()) :: map()
  defp set_builtin_ops(env, context, stack) do
    %{
      call: &call_callable(&1, &2, env, context, stack)
    }
  end

  @spec tuple_builtin_ops(map(), map(), list()) :: map()
  defp tuple_builtin_ops(env, context, stack) do
    %{
      call: &call_callable(&1, &2, env, context, stack)
    }
  end

  @spec result_builtin_ops(map(), map(), list()) :: map()
  defp result_builtin_ops(env, context, stack) do
    %{
      map: &HigherOrder.result_map_with_callable(&1, &2, callable_runner(env, context, stack)),
      and_then:
        &HigherOrder.result_and_then_with_callable(&1, &2, callable_runner(env, context, stack)),
      map2_dispatch: &map2_dispatch(&1, &2, &3, env, context, stack),
      call: &call_callable(&1, &2, env, context, stack)
    }
  end

  @spec maybe_builtin_ops(map(), map(), list()) :: map()
  defp maybe_builtin_ops(env, context, stack) do
    %{
      map: &HigherOrder.maybe_map_with_callable(&1, &2, callable_runner(env, context, stack)),
      and_then: &maybe_and_then_with_callable(&1, &2, env, context, stack),
      map2_dispatch: &map2_dispatch(&1, &2, &3, env, context, stack)
    }
  end

  @spec task_builtin_ops(map(), map(), list()) :: map()
  defp task_builtin_ops(env, context, stack) do
    %{
      map: &task_map_with_callable(&1, &2, env, context, stack),
      map2_dispatch: &map2_dispatch(&1, &2, &3, env, context, stack),
      sequence: &task_sequence/1,
      call: &call_callable(&1, &2, env, context, stack)
    }
  end

  @spec random_builtin_ops(map(), map(), list()) :: map()
  defp random_builtin_ops(env, context, stack) do
    %{
      call: &call_callable(&1, &2, env, context, stack)
    }
  end

  @spec package_builtin_ops(map(), map(), list()) :: map()
  defp package_builtin_ops(env, context, stack) do
    %{
      call: &call_callable(&1, &2, env, context, stack),
      debug_to_string: &elm_debug_to_string/1,
      normalize_union_value: &normalize_union_value(&1, &2, context),
      launch_context: Map.get(context, :launch_context) || Map.get(context, "launch_context") || %{}
    }
  end

  @spec basics_builtin_ops(map(), map(), list()) :: map()
  defp basics_builtin_ops(env, context, stack) do
    %{
      map2_dispatch: &map2_dispatch(&1, &2, &3, env, context, stack),
      compare: &compare_ctor/2
    }
  end

  @spec array_builtin_ops(map(), map(), list()) :: map()
  defp array_builtin_ops(env, context, stack) do
    %{
      slice: &list_slice/3,
      map: &map_with_callable(&1, &2, env, context, stack),
      indexed_map: &indexed_map_with_callable(&1, &2, env, context, stack),
      foldl: &foldl_with_callable(&1, &2, &3, env, context, stack),
      foldr: &foldr_with_callable(&1, &2, &3, env, context, stack),
      initialize: &initialize_with_callable(&1, &2, env, context, stack),
      get: &maybe_get_ctor/2,
      set: &list_set/3
    }
  end

  @spec debug_builtin_ops() :: map()
  defp debug_builtin_ops, do: %{to_string: &elm_debug_to_string/1}

  @spec parser_builtin_ops(map(), map(), list()) :: map()
  defp parser_builtin_ops(env, context, stack) do
    %{call: &call_callable(&1, &2, env, context, stack)}
  end

  @spec json_decode_builtin_ops(map(), map(), list()) :: map()
  defp json_decode_builtin_ops(env, context, stack) do
    %{
      kernel:
        &ElmExecutor.Runtime.CoreIREvaluator.Builtins.JsonKernel.eval(
          &1,
          &2,
          json_kernel_ops(env, context, stack)
        )
    }
  end

  @spec json_encode_builtin_ops(map(), map(), list()) :: map()
  defp json_encode_builtin_ops(env, context, stack) do
    %{
      call_encoder: &call_callable(&1, [&2], env, context, stack),
      collect_ok: &collect_ok/1
    }
  end

  @spec json_kernel_ops(map(), map(), list()) :: map()
  defp json_kernel_ops(env, context, stack) do
    %{
      call: &call_callable(&1, &2, env, context, stack),
      collect_ok: &collect_ok/1,
      result_ctor: &result_ctor/1
    }
  end

  @spec http_response_ops(context()) :: context()
  defp http_response_ops(context) do
    %{
      call: &call_callable(&1, &2, %{}, context, []),
      collect_ok: &collect_ok/1,
      constructor_value: &tagged_constructor_value(&1, &2, context),
      result_ctor: &result_ctor/1
    }
  end

  @spec split_builtin_name(String.t()) :: {String.t(), String.t()}
  defp split_builtin_name(normalized_full) when is_binary(normalized_full) do
    case String.split(normalized_full, ".", trim: true) do
      [] ->
        {"", ""}

      [function_name] ->
        {"", function_name}

      parts ->
        function_name = List.last(parts)
        module_name = parts |> Enum.drop(-1) |> Enum.join(".")
        {module_name, function_name}
    end
  end

  @spec legacy_fallback_allowed_module?(String.t()) :: boolean()
  defp legacy_fallback_allowed_module?(module_name) when is_binary(module_name) do
    module_name in [
      "",
      "list",
      "result",
      "maybe",
      "task",
      "basics",
      "bitwise",
      "string",
      "dict",
      "array",
      "char",
      "url",
      "time",
      "debug",
      "parser",
      "parser.advanced",
      "tuple",
      "json.decode",
      "json.encode"
    ]
  end

  @spec eval_builtin_legacy(String.t(), EvalTypes.runtime_values(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp eval_builtin_legacy(name, values, env, context, stack)
       when is_binary(name) and is_list(values) and is_map(env) and is_map(context) and
              is_list(stack) do
    normalized = normalize_builtin_short_name(name)
    call = callable_runner(env, context, stack)

    case {normalized, values} do
      {"__add__", [a, b]} when is_number(a) and is_number(b) ->
        {:ok, a + b}

      {"__sub__", [a, b]} when is_number(a) and is_number(b) ->
        {:ok, a - b}

      {"__mul__", [a, b]} when is_number(a) and is_number(b) ->
        {:ok, a * b}

      {"__append__", [a, b]} when is_binary(a) and is_binary(b) ->
        {:ok, a <> b}

      {"__append__", [a, b]} when is_list(a) and is_list(b) ->
        {:ok, a ++ b}

      {"__pow__", [a, b]} when is_number(a) and is_integer(b) ->
        {:ok, pow_number(a, b)}

      {op, [left, right]}
      when op in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] ->
        {:ok, compare(comparison_operator_kind(op), left, right)}

      {op, [left]} when op in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] ->
        {:ok, {:builtin_partial, op, [left]}}

      {"__fdiv__", [a, b]} when is_number(a) and is_number(b) and a == 0 and b == 0 ->
        {:ok, :nan}

      {"__fdiv__", [a, b]} when is_number(a) and is_number(b) and b == 0 ->
        {:ok, if(a < 0, do: :neg_infinity, else: :infinity)}

      {"__fdiv__", [a, b]} when is_number(a) and is_number(b) ->
        {:ok, a / b}

      {"__idiv__", [_a, 0]} ->
        {:ok, nil}

      {"__idiv__", [a, b]} when is_integer(a) and is_integer(b) ->
        {:ok, div(a, b)}

      {"__idiv__", [a, b]} when is_number(a) and is_number(b) ->
        divisor = trunc(b)
        if divisor == 0, do: {:ok, nil}, else: {:ok, div(trunc(a), divisor)}

      {"compare", [a, b]} ->
        {:ok, compare_ctor(a, b)}

      {"modby", [by, value]} when is_integer(by) and by > 0 and is_integer(value) ->
        {:ok, Integer.mod(value, by)}

      {"modby", [by]} when is_integer(by) and by > 0 ->
        {:ok, {:builtin_partial, "modBy", [by]}}

      {"remainderby", [by, value]} when is_integer(by) and by > 0 and is_integer(value) ->
        {:ok, rem(value, by)}

      {"remainderby", [by]} when is_integer(by) and by > 0 ->
        {:ok, {:builtin_partial, "remainderBy", [by]}}

      {"max", [a, b]} ->
        {:ok, if(a >= b, do: a, else: b)}

      {"min", [a, b]} ->
        {:ok, if(a <= b, do: a, else: b)}

      {"clamp", [low, high, value]} ->
        {:ok, value |> max(low) |> min(high)}

      {"not", [a]} when is_boolean(a) ->
        {:ok, !a}

      {"and", [a, b]} when is_boolean(a) and is_boolean(b) ->
        {:ok, a and b}

      {"or", [a, b]} when is_boolean(a) and is_boolean(b) ->
        {:ok, a or b}

      {"identity", [x]} ->
        {:ok, x}

      {"always", [x]} ->
        {:ok, {:builtin_partial, "always", [x]}}

      {"always", [x, _]} ->
        {:ok, x}

      {"abs", [a]} when is_number(a) ->
        {:ok, abs(a)}

      {"negate", [a]} when is_number(a) ->
        {:ok, -a}

      {"tofloat", [a]} when is_integer(a) ->
        {:ok, a * 1.0}

      {"tofloat", [a]} when is_float(a) ->
        {:ok, a}

      {"round", [a]} when is_number(a) ->
        {:ok, round(a)}

      {"floor", [a]} when is_number(a) ->
        {:ok, floor(a)}

      {"ceiling", [a]} when is_number(a) ->
        {:ok, ceil(a)}

      {"truncate", [a]} when is_number(a) ->
        {:ok, trunc(a)}

      {"sqrt", [a]} when is_number(a) ->
        safe_math_unary(&:math.sqrt/1, a)

      {"cos", [a]} when is_number(a) ->
        safe_math_unary(&:math.cos/1, a)

      {"sin", [a]} when is_number(a) ->
        safe_math_unary(&:math.sin/1, a)

      {"tan", [a]} when is_number(a) ->
        safe_math_unary(&:math.tan/1, a)

      {"acos", [a]} when is_number(a) ->
        safe_math_unary(&:math.acos/1, a)

      {"asin", [a]} when is_number(a) ->
        safe_math_unary(&:math.asin/1, a)

      {"atan", [a]} when is_number(a) ->
        safe_math_unary(&:math.atan/1, a)

      {"atan2", [y, x]} when is_number(y) and is_number(x) ->
        safe_math_binary(&:math.atan2/2, y, x)

      {"logbase", [base, n]} when is_number(base) and is_number(n) ->
        safe_log_base(base, n)

      {"degrees", [deg]} when is_number(deg) ->
        {:ok, deg * :math.pi() / 180.0}

      {"radians", [rad]} when is_number(rad) ->
        {:ok, rad}

      {"turns", [turn]} when is_number(turn) ->
        {:ok, turn * 2.0 * :math.pi()}

      {"frompolar", [{radius, theta}]} when is_number(radius) and is_number(theta) ->
        {:ok, {radius * :math.cos(theta), radius * :math.sin(theta)}}

      {"topolar", [{x, y}]} when is_number(x) and is_number(y) ->
        {:ok, {:math.sqrt(x * x + y * y), :math.atan2(y, x)}}

      {"isnan", [x]} ->
        {:ok, nan_value?(x)}

      {"isinfinite", [x]} ->
        {:ok, infinite_value?(x)}

      {"xor", [a, b]} when is_boolean(a) and is_boolean(b) ->
        {:ok, a != b}

      {"shiftleftby", [by, value]} when is_integer(by) and is_integer(value) ->
        {:ok, Bitwise.bsl(value, by)}

      {"shiftrightby", [by, value]} when is_integer(by) and is_integer(value) ->
        {:ok, Bitwise.bsr(value, by)}

      {"shiftrightzfby", [by, value]} when is_integer(by) and is_integer(value) ->
        {:ok, Bitwise.bsr(Bitwise.band(value, 0xFFFFFFFF), by)}

      {"empty", []} ->
        {:ok, %{}}

      {"fromlist", [xs]} when is_list(xs) ->
        if dict_pair_list?(xs), do: {:ok, dict_from_pair_list(xs)}, else: {:ok, xs}

      {"repeat", [n, value]} when is_integer(n) and n >= 0 ->
        {:ok, List.duplicate(value, n)}

      {"tolist", [xs]} when is_list(xs) ->
        {:ok, xs}

      {"tolist", [dict]} when is_map(dict) ->
        {:ok, dict_to_list(dict)}

      {"length", [xs]} when is_list(xs) ->
        {:ok, length(xs)}

      {"length", [text]} when is_binary(text) ->
        {:ok, String.length(text)}

      {"isempty", [xs]} when is_list(xs) ->
        {:ok, xs == []}

      {"isempty", [text]} when is_binary(text) ->
        {:ok, text == ""}

      {"keys", [dict]} when is_map(dict) ->
        {:ok, dict_keys(dict)}

      {"values", [dict]} when is_map(dict) ->
        {:ok, dict_values(dict)}

      {"singleton", [value]} ->
        {:ok, [value]}

      {"singleton", [key, value]} ->
        {:ok, %{key => value}}

      {"head", [xs]} when is_list(xs) ->
        {:ok, maybe_head_ctor(xs)}

      {"tail", [xs]} when is_list(xs) ->
        {:ok, maybe_tail_ctor(xs)}

      {"take", [n, xs]} when is_integer(n) and is_list(xs) ->
        {:ok, Enum.take(xs, max(n, 0))}

      {"drop", [n, xs]} when is_integer(n) and is_list(xs) ->
        {:ok, Enum.drop(xs, max(n, 0))}

      {"reverse", [xs]} when is_list(xs) ->
        {:ok, Enum.reverse(xs)}

      {"concat", [xss]} when is_list(xss) ->
        {:ok, Enum.flat_map(xss, fn x -> if is_list(x), do: x, else: [] end)}

      {"concatmap", [fun, xs]} when is_list(xs) ->
        concat_map_with_callable(fun, xs, env, context, stack)

      {"filtermap", [fun, xs]} when is_list(xs) ->
        filter_map_with_callable(fun, xs, env, context, stack)

      {"member", [x, xs]} when is_list(xs) ->
        {:ok, Enum.member?(xs, x)}

      {"all", [fun, xs]} when is_list(xs) ->
        all_with_callable(fun, xs, env, context, stack)

      {"any", [fun, xs]} when is_list(xs) ->
        any_with_callable(fun, xs, env, context, stack)

      {"partition", [fun, xs]} when is_list(xs) ->
        partition_with_callable(fun, xs, env, context, stack)

      {"sum", [xs]} when is_list(xs) ->
        {:ok, Enum.reduce(xs, 0, fn x, acc -> if is_number(x), do: acc + x, else: acc end)}

      {"product", [xs]} when is_list(xs) ->
        {:ok, Enum.reduce(xs, 1, fn x, acc -> if is_number(x), do: acc * x, else: acc end)}

      {"maximum", [xs]} when is_list(xs) ->
        {:ok, maybe_extreme_ctor(xs, :max)}

      {"minimum", [xs]} when is_list(xs) ->
        {:ok, maybe_extreme_ctor(xs, :min)}

      {"range", [start, stop]} when is_integer(start) and is_integer(stop) ->
        {:ok, if(start > stop, do: [], else: Enum.to_list(start..stop))}

      {"sort", [xs]} when is_list(xs) ->
        {:ok, Enum.sort(xs)}

      {"sortby", [fun, xs]} when is_list(xs) ->
        sort_by_with_callable(fun, xs, env, context, stack)

      {"sortwith", [fun, xs]} when is_list(xs) ->
        sort_with_callable(fun, xs, env, context, stack)

      {"intersperse", [sep, xs]} when is_list(xs) ->
        {:ok, list_intersperse(xs, sep)}

      {"unzip", [pairs]} when is_list(pairs) ->
        {:ok, list_unzip(pairs)}

      {"map", [fun, subject]} ->
        map_dispatch(fun, subject, env, context, stack)

      {"filter", [fun, xs]} when is_list(xs) ->
        filter_with_callable(fun, xs, env, context, stack)

      {"filter", [fun, text]} when is_binary(text) ->
        HigherOrder.string_filter_with_callable(fun, text, call)

      {"foldl", [fun, init, xs]} when is_list(xs) ->
        foldl_with_callable(fun, init, xs, env, context, stack)

      {"foldl", [fun, init, text]} when is_binary(text) ->
        HigherOrder.string_foldl_with_callable(fun, init, text, call)

      {"foldr", [fun, init, xs]} when is_list(xs) ->
        foldr_with_callable(fun, init, xs, env, context, stack)

      {"foldr", [fun, init, text]} when is_binary(text) ->
        HigherOrder.string_foldr_with_callable(fun, init, text, call)

      {"indexedmap", [fun, xs]} when is_list(xs) ->
        indexed_map_with_callable(fun, xs, env, context, stack)

      {"initialize", [n, fun]} when is_integer(n) and n >= 0 ->
        initialize_with_callable(n, fun, env, context, stack)

      {"get", [idx, xs]} when is_integer(idx) and is_list(xs) ->
        {:ok, maybe_get_ctor(xs, idx)}

      {"get", [key, dict]} when is_map(dict) ->
        {:ok, maybe_map_get_ctor(dict, key)}

      {"set", [idx, value, xs]} when is_integer(idx) and is_list(xs) ->
        {:ok, list_set(xs, idx, value)}

      {"push", [value, xs]} when is_list(xs) ->
        {:ok, xs ++ [value]}

      {"insert", [key, value, dict]} when is_map(dict) ->
        {:ok, Map.put(dict, key, value)}

      {"remove", [key, dict]} when is_map(dict) ->
        {:ok, Map.delete(dict, key)}

      {"member", [key, dict]} when is_map(dict) ->
        {:ok, Map.has_key?(dict, key)}

      {"append", [left, right]} when is_list(left) and is_list(right) ->
        {:ok, left ++ right}

      {"append", [left, right]} when is_binary(left) and is_binary(right) ->
        {:ok, left <> right}

      {"slice", [start, stop, xs]}
      when is_integer(start) and is_integer(stop) and is_list(xs) ->
        {:ok, list_slice(xs, start, stop)}

      {"slice", [start, stop, text]}
      when is_integer(start) and is_integer(stop) and is_binary(text) ->
        {:ok, string_slice(text, start, stop)}

      {"toindexedlist", [xs]} when is_list(xs) ->
        {:ok, xs |> Enum.with_index() |> Enum.map(fn {value, idx} -> {idx, value} end)}

      {"cons", [head, tail]} when is_list(tail) ->
        {:ok, [head | tail]}

      {"cons", [head, tail]} when is_binary(tail) ->
        {:ok, normalize_char_binary(head) <> tail}

      {"fromchar", [c]} ->
        {:ok, normalize_char_binary(c)}

      {"tochar", [s]} when is_binary(s) ->
        {:ok, normalize_char_binary(s)}

      {"fromint", [value]} when is_integer(value) ->
        {:ok, Integer.to_string(value)}

      {"fromfloat", [value]} when is_number(value) ->
        {:ok, float_to_elm_string(value)}

      {"toint", [text]} when is_binary(text) ->
        {:ok, maybe_int_from_string(text)}

      {"tofloat", [text]} when is_binary(text) ->
        {:ok, maybe_float_from_string(text)}

      {"split", [sep, text]} when is_binary(sep) and is_binary(text) ->
        {:ok, String.split(text, sep)}

      {"join", [sep, parts]} when is_binary(sep) and is_list(parts) ->
        {:ok, Enum.map(parts, &to_string/1) |> Enum.join(sep)}

      {"words", [text]} when is_binary(text) ->
        {:ok, String.split(text, ~r/\s+/, trim: true)}

      {"lines", [text]} when is_binary(text) ->
        {:ok, String.split(text, ~r/\r\n|\r|\n/, trim: false)}

      {"trim", [text]} when is_binary(text) ->
        {:ok, String.trim(text)}

      {"trimleft", [text]} when is_binary(text) ->
        {:ok, String.trim_leading(text)}

      {"trimright", [text]} when is_binary(text) ->
        {:ok, String.trim_trailing(text)}

      {"contains", [needle, haystack]} when is_binary(needle) and is_binary(haystack) ->
        {:ok, String.contains?(haystack, needle)}

      {"startswith", [prefix, text]} when is_binary(prefix) and is_binary(text) ->
        {:ok, String.starts_with?(text, prefix)}

      {"endswith", [suffix, text]} when is_binary(suffix) and is_binary(text) ->
        {:ok, String.ends_with?(text, suffix)}

      {"replace", [before, replacement, text]}
      when is_binary(before) and is_binary(replacement) and is_binary(text) ->
        {:ok, String.replace(text, before, replacement)}

      {"left", [n, text]} when is_integer(n) and is_binary(text) ->
        {:ok, string_left(text, n)}

      {"right", [n, text]} when is_integer(n) and is_binary(text) ->
        {:ok, string_right(text, n)}

      {"dropleft", [n, text]} when is_integer(n) and is_binary(text) ->
        {:ok, string_drop_left(text, n)}

      {"dropright", [n, text]} when is_integer(n) and is_binary(text) ->
        {:ok, string_drop_right(text, n)}

      {"pad", [n, fill, text]} when is_integer(n) and is_binary(text) ->
        {:ok, string_pad_center(text, n, fill)}

      {"padleft", [n, fill, text]} when is_integer(n) and is_binary(text) ->
        {:ok, string_pad_left(text, n, fill)}

      {"padright", [n, fill, text]} when is_integer(n) and is_binary(text) ->
        {:ok, string_pad_right(text, n, fill)}

      {"reverse", [text]} when is_binary(text) ->
        {:ok, text |> String.graphemes() |> Enum.reverse() |> Enum.join()}

      {"all", [fun, text]} when is_binary(text) ->
        HigherOrder.string_all_with_callable(fun, text, call)

      {"any", [fun, text]} when is_binary(text) ->
        HigherOrder.string_any_with_callable(fun, text, call)

      {"indexes", [needle, haystack]} when is_binary(needle) and is_binary(haystack) ->
        {:ok, string_indexes(needle, haystack)}

      {"indices", [needle, haystack]} when is_binary(needle) and is_binary(haystack) ->
        {:ok, string_indexes(needle, haystack)}

      {"tolist", [text]} when is_binary(text) ->
        {:ok, String.graphemes(text)}

      {"tolower", [text]} when is_binary(text) ->
        {:ok, String.downcase(text)}

      {"toupper", [text]} when is_binary(text) ->
        {:ok, String.upcase(text)}

      {"uncons", [text]} when is_binary(text) ->
        {:ok, string_uncons_ctor(text)}

      {"tocode", [c]} ->
        {:ok, char_to_code(c)}

      {"isalpha", [c]} ->
        {:ok, char_predicate(c, &char_alpha?/1)}

      {"isalphanum", [c]} ->
        {:ok, char_predicate(c, &char_alphanum?/1)}

      {"isdigit", [c]} ->
        {:ok, char_predicate(c, &char_digit?/1)}

      {"isoctdigit", [c]} ->
        {:ok, char_predicate(c, &char_octal_digit?/1)}

      {"islower", [c]} ->
        {:ok, char_predicate(c, &char_lower?/1)}

      {"isupper", [c]} ->
        {:ok, char_predicate(c, &char_upper?/1)}

      {"tostring", [value]} ->
        {:ok, elm_debug_to_string(value)}

      {"pair", [a, b]} ->
        {:ok, {a, b}}

      {"mapfirst", [fun, pair]} ->
        tuple_map_first_with_callable(fun, pair, env, context, stack)

      {"mapsecond", [fun, pair]} ->
        tuple_map_second_with_callable(fun, pair, env, context, stack)

      {"mapboth", [f1, f2, pair]} ->
        tuple_map_both_with_callable(f1, f2, pair, env, context, stack)

      {"withdefault", [default, maybe_or_result]} ->
        {:ok, with_default_maybe_or_result(default, maybe_or_result)}

      {"andthen", [fun, result]} ->
        HigherOrder.result_and_then_with_callable(fun, result, call)

      {"succeed", [value]} ->
        {:ok, {:task, :ok, value}}

      {"fail", [error]} ->
        {:ok, {:task, :err, error}}

      {"sequence", [tasks]} when is_list(tasks) ->
        task_sequence(tasks)

      {"map2", [fun, xs, ys]} when is_list(xs) and is_list(ys) ->
        list_map2_with_callable(fun, xs, ys, env, context, stack)

      {"map2", [a, b, c]} ->
        map2_dispatch(a, b, c, env, context, stack)

      _ ->
        eval_ui_builtin(name, values, context)
    end
  end

  defp eval_builtin_legacy(_name, _values, _env, _context, _stack), do: :no_builtin

  @spec pow_number(number(), integer()) :: number()
  defp pow_number(base, exponent) when is_integer(base) and exponent >= 0 do
    :math.pow(base * 1.0, exponent) |> round()
  end

  defp pow_number(base, exponent) when is_number(base) and is_integer(exponent) do
    :math.pow(base * 1.0, exponent)
  end

  @spec normalize_builtin_name(String.t() | EvalTypes.runtime_value()) :: String.t()
  defp normalize_builtin_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> normalize_module_alias_name()
  end

  @spec normalize_module_alias_name(String.t()) :: String.t()
  defp normalize_module_alias_name("pebbleui." <> rest), do: "pebble.ui." <> rest
  defp normalize_module_alias_name("pebblecolor." <> rest), do: "pebble.ui.color." <> rest
  defp normalize_module_alias_name("uicolor." <> rest), do: "pebble.ui.color." <> rest
  defp normalize_module_alias_name(name), do: name

  @spec normalize_builtin_short_name(String.t() | EvalTypes.runtime_value()) :: String.t()
  defp normalize_builtin_short_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.downcase()
  end

  @spec infinite_float?(number()) :: boolean()
  defp infinite_float?(x) when is_float(x) do
    rendered = :erlang.float_to_binary(x, [:compact]) |> String.downcase()
    String.contains?(rendered, "inf")
  end

  @spec nan_value?(EvalTypes.runtime_value()) :: boolean()
  defp nan_value?(:nan), do: true
  defp nan_value?(x) when is_float(x), do: x != x
  defp nan_value?(_), do: false

  @spec infinite_value?(EvalTypes.runtime_value()) :: boolean()
  defp infinite_value?(:nan), do: false
  defp infinite_value?(x) when is_float(x), do: infinite_float?(x)
  defp infinite_value?(_), do: false

  @spec safe_math_unary((number() -> number()), number()) :: {:ok, number() | :nan}
  defp safe_math_unary(fun, value) when is_function(fun, 1) do
    try do
      {:ok, fun.(value)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  @spec safe_math_binary((number(), number() -> number()), number(), number()) :: {:ok, number() | :nan}
  defp safe_math_binary(fun, left, right) when is_function(fun, 2) do
    try do
      {:ok, fun.(left, right)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  @spec safe_log_base(number(), number()) :: {:ok, number() | :nan}
  defp safe_log_base(base, n) do
    try do
      {:ok, :math.log(n) / :math.log(base)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  @spec short_ctor_name(EvalTypes.ctor_name() | atom()) :: String.t()
  defp short_ctor_name(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
  end

  @spec compare_ctor(EvalTypes.runtime_value(), EvalTypes.runtime_value()) :: EvalTypes.command_map()
  defp compare_ctor(left, right) do
    cond do
      left < right -> %{"ctor" => "LT", "args" => []}
      left > right -> %{"ctor" => "GT", "args" => []}
      true -> %{"ctor" => "EQ", "args" => []}
    end
  end

  @spec maybe_get_ctor(list(), integer()) :: EvalTypes.command_map()
  defp maybe_get_ctor(xs, idx) when is_list(xs) and is_integer(idx) do
    if idx < 0 or idx >= length(xs) do
      %{"ctor" => "Nothing", "args" => []}
    else
      %{"ctor" => "Just", "args" => [Enum.at(xs, idx)]}
    end
  end

  @spec list_set(list(), integer(), EvalTypes.runtime_value()) :: list()
  defp list_set(xs, idx, value) when is_list(xs) and is_integer(idx) do
    if idx < 0 or idx >= length(xs) do
      xs
    else
      List.replace_at(xs, idx, value)
    end
  end

  @spec list_slice(list(), integer(), integer()) :: list()
  defp list_slice(xs, start, stop) when is_list(xs) and is_integer(start) and is_integer(stop) do
    len = length(xs)
    from = normalize_slice_index(start, len)
    to = normalize_slice_index(stop, len)
    count = max(to - from, 0)
    xs |> Enum.drop(from) |> Enum.take(count)
  end

  @spec normalize_slice_index(integer(), non_neg_integer()) :: non_neg_integer()
  defp normalize_slice_index(index, len) when is_integer(index) and is_integer(len) do
    normalized = if index < 0, do: len + index, else: index
    normalized |> max(0) |> min(len)
  end

  @spec callable_runner(map(), map(), list()) :: function()
  defp callable_runner(env, context, stack) do
    fn fun, args -> call_callable(fun, args, env, context, stack) end
  end

  @spec list_intersperse(list(), EvalTypes.runtime_value()) :: list()
  defp list_intersperse([], _sep), do: []
  defp list_intersperse([x], _sep), do: [x]
  defp list_intersperse([x | rest], sep), do: [x, sep | list_intersperse(rest, sep)]

  @spec list_unzip(list()) :: {list(), list()}
  defp list_unzip(pairs) do
    pairs
    |> Enum.reduce({[], []}, fn pair, {left, right} ->
      case pair do
        {a, b} -> {[a | left], [b | right]}
        [a, b] -> {[a | left], [b | right]}
        _ -> {left, right}
      end
    end)
    |> then(fn {left, right} -> {Enum.reverse(left), Enum.reverse(right)} end)
  end

  @spec map_dispatch(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp map_dispatch(fun, subject, env, context, stack) do
    call = callable_runner(env, context, stack)

    cond do
      is_list(subject) ->
        map_with_callable(fun, subject, env, context, stack)

      is_binary(subject) ->
        HigherOrder.string_map_with_callable(fun, subject, call)

      true ->
        case HigherOrder.maybe_map_with_callable(fun, subject, call) do
          :no_builtin ->
            case HigherOrder.result_map_with_callable(fun, subject, call) do
              :no_builtin -> task_map_with_callable(fun, subject, env, context, stack)
              result -> result
            end

          result ->
            result
        end
    end
    |> case do
      :no_builtin ->
        if is_callable_like(subject),
          do: map_dispatch(subject, fun, env, context, stack),
          else: :no_builtin

      other ->
        other
    end
  end

  @spec map2_dispatch(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp map2_dispatch(a, b, c, env, context, stack) do
    candidates = [{a, b, c}, {c, a, b}, {b, c, a}, {c, b, a}]
    call = callable_runner(env, context, stack)

    Enum.reduce_while(candidates, :no_builtin, fn {fun, left, right}, _acc ->
      result =
        case HigherOrder.maybe_map2_with_callable(fun, left, right, call) do
          :no_builtin -> HigherOrder.result_map2_with_callable(fun, left, right, call)
          other -> other
        end

      if result == :no_builtin, do: {:cont, :no_builtin}, else: {:halt, result}
    end)
  end

  @spec is_callable_like(EvalTypes.runtime_value()) :: boolean()
  defp is_callable_like({:closure, _params, _body, _env}), do: true
  defp is_callable_like({:builtin_partial, _name, _bound}), do: true
  defp is_callable_like({:function_ref, _name}), do: true
  defp is_callable_like(name) when is_binary(name), do: true
  defp is_callable_like(_), do: false

  @spec task_map_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp task_map_with_callable(fun, {:task, :ok, value}, env, context, stack) do
    case call_callable(fun, [value], env, context, stack) do
      {:ok, mapped} -> {:ok, {:task, :ok, mapped}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp task_map_with_callable(_fun, {:task, :err, error}, _env, _context, _stack),
    do: {:ok, {:task, :err, error}}

  defp task_map_with_callable(_fun, _task, _env, _context, _stack), do: :no_builtin

  defp maybe_and_then_with_callable(fun, maybe, env, context, stack) do
    case maybe_value(maybe) do
      {:just, value} -> call_callable(fun, [value], env, context, stack)
      :nothing -> {:ok, maybe_ctor_like(maybe, :nothing)}
      :invalid -> :no_builtin
    end
  end

  @spec task_sequence(list()) :: EvalTypes.builtin_eval_result()
  defp task_sequence(tasks) when is_list(tasks) do
    Enum.reduce_while(tasks, {:ok, []}, fn task, {:ok, acc} ->
      case task do
        {:task, :ok, value} -> {:cont, {:ok, [value | acc]}}
        {:task, :err, error} -> {:halt, {:ok, {:task, :err, error}}}
        _ -> {:halt, :no_builtin}
      end
    end)
    |> case do
      {:ok, {:task, :err, _} = err_task} -> {:ok, err_task}
      {:ok, values} when is_list(values) -> {:ok, {:task, :ok, Enum.reverse(values)}}
      other -> other
    end
  end

  @spec concat_map_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp concat_map_with_callable(fun, xs, env, context, stack) do
    xs
    |> Enum.map(fn x -> call_callable(fun, [x], env, context, stack) end)
    |> collect_ok()
    |> case do
      {:ok, lists} -> {:ok, Enum.flat_map(lists, fn x -> if is_list(x), do: x, else: [] end)}
      err -> err
    end
  end

  @spec filter_map_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp filter_map_with_callable(fun, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, []}, fn x, {:ok, acc} ->
      case call_callable(fun, [x], env, context, stack) do
        {:ok, maybe} ->
          case maybe_value(maybe) do
            {:just, value} -> {:cont, {:ok, [value | acc]}}
            :nothing -> {:cont, {:ok, acc}}
            :invalid -> {:halt, {:error, {:expected_maybe, maybe}}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, kept} -> {:ok, Enum.reverse(kept)}
      err -> err
    end
  end

  @spec list_map2_with_callable(EvalTypes.runtime_value(), list(), list(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp list_map2_with_callable(fun, xs, ys, env, context, stack) do
    xs
    |> Enum.zip(ys)
    |> Enum.map(fn {x, y} -> call_callable(fun, [x, y], env, context, stack) end)
    |> collect_ok()
  end

  @spec all_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp all_with_callable(fun, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, true}, fn x, _ ->
      case call_callable(fun, [x], env, context, stack) do
        {:ok, true} -> {:cont, {:ok, true}}
        {:ok, _} -> {:halt, {:ok, false}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec any_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp any_with_callable(fun, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, false}, fn x, _ ->
      case call_callable(fun, [x], env, context, stack) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, _} -> {:cont, {:ok, false}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec partition_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp partition_with_callable(fun, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, {[], []}}, fn x, {:ok, {yes, no}} ->
      case call_callable(fun, [x], env, context, stack) do
        {:ok, true} -> {:cont, {:ok, {[x | yes], no}}}
        {:ok, _} -> {:cont, {:ok, {yes, [x | no]}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {yes, no}} -> {:ok, {Enum.reverse(yes), Enum.reverse(no)}}
      err -> err
    end
  end

  @spec sort_by_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp sort_by_with_callable(fun, xs, env, context, stack) do
    xs
    |> Enum.map(fn x ->
      case call_callable(fun, [x], env, context, stack) do
        {:ok, key} -> {:ok, {x, key}}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> collect_ok()
    |> case do
      {:ok, keyed} ->
        {:ok, keyed |> Enum.sort_by(fn {_x, key} -> key end) |> Enum.map(fn {x, _} -> x end)}

      err ->
        err
    end
  end

  @spec sort_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp sort_with_callable(fun, xs, env, context, stack) do
    try do
      {:ok,
       Enum.sort(xs, fn a, b ->
         case call_callable(fun, [a, b], env, context, stack) do
           {:ok, value} ->
             compare_order_value(value) != :gt

           _ ->
             a <= b
         end
       end)}
    rescue
      _ -> {:ok, Enum.sort(xs)}
    end
  end

  @spec compare_order_value(EvalTypes.runtime_value()) :: :lt | :eq | :gt
  defp compare_order_value(%{"ctor" => ctor}) when is_binary(ctor),
    do: compare_order_value(%{ctor: short_ctor_name(ctor)})

  defp compare_order_value(%{ctor: ctor}) when is_binary(ctor) do
    case String.upcase(short_ctor_name(ctor)) do
      "LT" -> :lt
      "EQ" -> :eq
      "GT" -> :gt
      _ -> :eq
    end
  end

  defp compare_order_value(_), do: :eq

  @spec tuple_to_pair(EvalTypes.runtime_value()) :: {:ok, tuple() | EvalTypes.runtime_value()} | :error
  defp tuple_to_pair({a, b}), do: {:ok, {a, b}}
  defp tuple_to_pair([a, b]), do: {:ok, {a, b}}
  defp tuple_to_pair(_), do: :error

  @spec tuple_map_first_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp tuple_map_first_with_callable(fun, pair, env, context, stack) do
    with {:ok, {a, b}} <- tuple_to_pair(pair),
         {:ok, mapped} <- call_callable(fun, [a], env, context, stack) do
      {:ok, {mapped, b}}
    else
      :error -> :no_builtin
      err -> err
    end
  end

  @spec tuple_map_second_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp tuple_map_second_with_callable(fun, pair, env, context, stack) do
    with {:ok, {a, b}} <- tuple_to_pair(pair),
         {:ok, mapped} <- call_callable(fun, [b], env, context, stack) do
      {:ok, {a, mapped}}
    else
      :error -> :no_builtin
      err -> err
    end
  end

  @spec tuple_map_both_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp tuple_map_both_with_callable(f1, f2, pair, env, context, stack) do
    with {:ok, {a, b}} <- tuple_to_pair(pair),
         {:ok, left} <- call_callable(f1, [a], env, context, stack),
         {:ok, right} <- call_callable(f2, [b], env, context, stack) do
      {:ok, {left, right}}
    else
      :error -> :no_builtin
      err -> err
    end
  end

  @spec map_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp map_with_callable(fun, xs, env, context, stack) do
    xs
    |> Enum.map(fn x -> call_callable(fun, [x], env, context, stack) end)
    |> collect_ok()
  end

  @spec filter_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp filter_with_callable(fun, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, []}, fn x, {:ok, acc} ->
      case call_callable(fun, [x], env, context, stack) do
        {:ok, true} -> {:cont, {:ok, [x | acc]}}
        {:ok, _} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, kept} -> {:ok, Enum.reverse(kept)}
      err -> err
    end
  end

  @spec foldl_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp foldl_with_callable(fun, init, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, init}, fn x, {:ok, acc} ->
      case call_callable(fun, [x, acc], env, context, stack) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec foldr_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp foldr_with_callable(fun, init, xs, env, context, stack) do
    xs
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, init}, fn x, {:ok, acc} ->
      case call_callable(fun, [x, acc], env, context, stack) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec indexed_map_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp indexed_map_with_callable(fun, xs, env, context, stack) do
    xs
    |> Enum.with_index()
    |> Enum.map(fn {x, idx} -> call_callable(fun, [idx, x], env, context, stack) end)
    |> collect_ok()
  end

  @spec initialize_with_callable(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.builtin_eval_result()
  defp initialize_with_callable(n, fun, env, context, stack) do
    if n <= 0 do
      {:ok, []}
    else
      0..(n - 1)
      |> Enum.to_list()
      |> Enum.map(fn idx -> call_callable(fun, [idx], env, context, stack) end)
      |> collect_ok()
    end
  end

  @spec call_callable(EvalTypes.runtime_value(), EvalTypes.runtime_values(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.eval_result()
  defp call_callable(fun, args, env, context, stack) when is_list(args) do
    case fun do
      {:closure, params, body, closure_env} when is_list(params) and is_map(closure_env) ->
        apply_closure("<closure>", params, body, closure_env, args, context, stack)

      {:builtin_partial, name, bound} when is_binary(name) and is_list(bound) ->
        case eval_builtin(name, bound ++ args, env, context, stack) do
          {:ok, value} -> {:ok, value}
          :no_builtin -> {:error, {:unknown_function, {"<builtin>", name, length(bound ++ args)}}}
        end

      {:record_alias_constructor, _name, fields, field_types} when is_list(fields) ->
        {:ok, record_alias_value(fields, field_types, args, context)}

      {:function_ref, name} when is_binary(name) ->
        case call_function(name, Enum.map(args, &literal_or_expr/1), env, context, stack) do
          {:error, {:unknown_function, _}} = error ->
            if constructor_name?(name),
              do: {:ok, constructor_value(name, args, constructor_tag_for_ctor(name, context))},
              else: error

          other ->
            other
        end

      name when is_binary(name) ->
        case call_function(name, Enum.map(args, &literal_or_expr/1), env, context, stack) do
          {:error, {:unknown_function, _}} = error ->
            if constructor_name?(name),
              do: {:ok, constructor_value(name, args, constructor_tag_for_ctor(name, context))},
              else: error

          other ->
            other
        end

      tag when is_integer(tag) ->
        {:ok, tagged_constructor_value(tag, args, context)}

      _ ->
        {:error, {:not_callable, fun}}
    end
  end

  @spec constructor_name?(String.t()) :: boolean()
  defp constructor_name?(name) when is_binary(name) do
    name
    |> short_ctor_name()
    |> String.match?(~r/^[A-Z]/)
  end

  @spec constructor_value(String.t(), list(), integer() | nil) :: map()
  defp constructor_value(name, args, tag \\ nil) when is_list(args) do
    ctor_label =
      cond do
        is_binary(name) ->
          short_ctor_name(name)

        is_atom(name) ->
          short_ctor_name(Atom.to_string(name))

        true ->
          inspect(name)
      end

    value = %{"ctor" => ctor_label, "args" => args}

    if is_integer(tag), do: Map.put(value, "tag", tag), else: value
  end

  @spec tagged_constructor_value(integer(), EvalTypes.runtime_values(), map()) :: EvalTypes.runtime_value()
  defp tagged_constructor_value(tag, args, context)
       when is_integer(tag) and is_list(args) and is_map(context) do
    case constructor_name_for_tag(tag, context) do
      name when is_binary(name) -> constructor_value(name, args, tag)
      _ -> {tag, constructor_payload(args)}
    end
  end

  defp tagged_constructor_value({tag, payload}, args, context)
       when is_integer(tag) and is_list(args) and is_map(context) do
    case constructor_name_for_tag(tag, context) do
      name when is_binary(name) ->
        constructor_value(name, [payload | args], tag)

      _ ->
        {tag, constructor_payload([payload | args])}
    end
  end

  defp tagged_constructor_value(name, args, _context) when is_list(args),
    do: constructor_value(name, args)

  @spec constructor_payload(EvalTypes.runtime_values()) :: EvalTypes.runtime_value() | EvalTypes.runtime_values()
  defp constructor_payload([]), do: nil
  defp constructor_payload([one]), do: one

  defp constructor_payload([left | rest]), do: {left, constructor_payload(rest)}

  @spec constructor_name_for_tag(integer(), map()) :: String.t() | nil
  defp constructor_name_for_tag(tag, context) when is_integer(tag) and is_map(context) do
    candidates =
      context
      |> Map.get(:constructor_tags, [])
      |> Enum.filter(&(Map.get(&1, :tag) == tag))

    candidates
    |> Enum.find(&Map.get(&1, :update_module?))
    |> case do
      %{ctor: ctor} ->
        ctor

      _ ->
        case candidates do
          [%{ctor: ctor}] -> ctor
          _ -> nil
        end
    end
  end

  @spec normalize_union_value(EvalTypes.runtime_value(), String.t(), map()) :: EvalTypes.runtime_value()
  defp normalize_union_value(%{"ctor" => _ctor} = value, _union, _context), do: value
  defp normalize_union_value(%{ctor: _ctor} = value, _union, _context), do: value

  defp normalize_union_value({tag, payload}, union, context)
       when is_integer(tag) and is_binary(union) and is_map(context) do
    case constructor_entry_for_union_tag(union, tag, context) do
      %{ctor: ctor, payload_spec: payload_spec} ->
        args =
          case normalize_constructor_payload(payload, payload_spec, context) do
            nil -> []
            value -> [value]
          end

        %{"ctor" => ctor, "args" => args, "tag" => tag}

      _ ->
        {tag, payload}
    end
  end

  defp normalize_union_value(tag, union, context)
       when is_integer(tag) and is_binary(union) and is_map(context) do
    case constructor_entry_for_union_tag(union, tag, context) do
      %{ctor: ctor} -> %{"ctor" => ctor, "args" => [], "tag" => tag}
      _ -> tag
    end
  end

  defp normalize_union_value(value, _union, _context), do: value

  @spec normalize_constructor_payload(EvalTypes.runtime_value(), String.t() | nil, map()) :: EvalTypes.runtime_value()
  defp normalize_constructor_payload(nil, _payload_spec, _context), do: nil

  defp normalize_constructor_payload(payload, payload_spec, context)
       when is_binary(payload_spec) and is_map(context) do
    cond do
      union_known?(payload_spec, context) ->
        normalize_union_value(payload, payload_spec, context)

      true ->
        payload
    end
  end

  defp normalize_constructor_payload(payload, _payload_spec, _context), do: payload

  @spec normalize_value_by_type(EvalTypes.runtime_value(), String.t() | nil, map()) :: EvalTypes.runtime_value()
  def normalize_value_by_type(value, type, context)
      when is_binary(type) and is_map(context) do
    normalized_type = normalize_type_name(type)

    cond do
      maybe_type?(normalized_type) ->
        normalize_maybe_value(value, maybe_inner_type(normalized_type), context)

      union_known?(normalized_type, context) ->
        normalize_union_value(value, normalized_type, context)

      is_list(record_alias_fields(context, normalized_type)) ->
        normalize_record_alias_runtime_value(value, normalized_type, context)

      true ->
        value
    end
  end

  def normalize_value_by_type(value, _type, _context), do: value

  @spec constructor_entry_for_union_tag(String.t(), integer(), map()) :: map() | nil
  defp constructor_entry_for_union_tag(union, tag, context)
       when is_binary(union) and is_integer(tag) and is_map(context) do
    context
    |> Map.get(:constructor_tags, [])
    |> Enum.find(fn entry ->
      entry_union = Map.get(entry, :union) || Map.get(entry, "union")
      entry_tag = Map.get(entry, :tag) || Map.get(entry, "tag")
      entry_tag == tag and union_names_match?(entry_union, union)
    end)
  end

  @spec union_known?(String.t(), map()) :: boolean()
  defp union_known?(union, context) when is_binary(union) and is_map(context) do
    context
    |> Map.get(:constructor_tags, [])
    |> Enum.any?(fn entry ->
      entry_union = Map.get(entry, :union) || Map.get(entry, "union")
      union_names_match?(entry_union, union)
    end)
  end

  @spec union_names_match?(String.t() | nil, String.t()) :: boolean()
  defp union_names_match?(entry_union, type_name)
       when is_binary(entry_union) and is_binary(type_name) do
    entry_union == type_name or
      union_short_name(entry_union) == union_short_name(type_name)
  end

  defp union_names_match?(_entry_union, _type_name), do: false

  @spec union_short_name(String.t()) :: String.t()
  defp union_short_name(name) when is_binary(name) do
    name
    |> String.split(".")
    |> List.last()
    |> Kernel.||(name)
  end

  @spec record_alias_fields(map(), String.t()) :: [String.t()] | nil
  defp record_alias_fields(context, target) when is_map(context) and is_binary(target) do
    aliases = Map.get(context, :record_aliases, %{})
    short = short_ctor_name(target)
    {module_name, name} = parse_function_name(target, context)

    aliases[{module_name, name}] ||
      Enum.find_value(aliases, fn
        {{_module, ^short}, fields} -> fields
        _ -> nil
      end)
  end

  defp record_alias_fields(_context, _target), do: nil

  @spec record_alias_field_types(map(), String.t()) :: map()
  defp record_alias_field_types(context, target) when is_map(context) and is_binary(target) do
    aliases = Map.get(context, :record_alias_field_types, %{})
    short = short_ctor_name(target)
    {module_name, name} = parse_function_name(target, context)

    aliases[{module_name, name}] ||
      Enum.find_value(aliases, %{}, fn
        {{_module, ^short}, field_types} -> field_types
        _ -> nil
      end)
  end

  defp record_alias_field_types(_context, _target), do: %{}

  @spec record_alias_value([String.t()], map(), list(), map()) :: map()
  defp record_alias_value(fields, field_types, values, context)
       when is_list(fields) and is_map(field_types) and is_list(values) and is_map(context) do
    fields
    |> Enum.zip(values)
    |> Map.new(fn {field, value} ->
      {field, normalize_value_by_type(value, Map.get(field_types, field), context)}
    end)
  end

  @spec normalize_record_alias_runtime_value(EvalTypes.runtime_value(), String.t(), map()) :: EvalTypes.runtime_value()
  defp normalize_record_alias_runtime_value(value, type, context)
       when is_binary(type) and is_map(context) do
    fields = record_alias_fields(context, type)
    field_types = record_alias_field_types(context, type)

    cond do
      legacy_tuple_constructor_map?(value) and is_list(fields) ->
        values = flatten_legacy_tuple_constructor_map(value, length(fields))
        record_alias_value(fields, field_types, values, context)

      is_map(value) and is_list(fields) ->
        Map.new(value, fn {field, nested} ->
          field = to_string(field)
          {field, normalize_value_by_type(nested, Map.get(field_types, field), context)}
        end)

      is_tuple(value) and is_list(fields) ->
        values = flatten_tuple_chain(value, length(fields))
        record_alias_value(fields, field_types, values, context)

      true ->
        value
    end
  end

  @spec normalize_maybe_value(EvalTypes.runtime_value(), String.t() | nil, map()) :: EvalTypes.runtime_value()
  defp normalize_maybe_value(0, _inner_type, _context), do: %{"ctor" => "Nothing", "args" => []}
  defp normalize_maybe_value(nil, _inner_type, _context), do: %{"ctor" => "Nothing", "args" => []}

  defp normalize_maybe_value({1, payload}, inner_type, context),
    do: %{"ctor" => "Just", "args" => [normalize_value_by_type(payload, inner_type, context)]}

  defp normalize_maybe_value(%{"ctor" => "Just", "args" => [payload]}, inner_type, context),
    do: %{"ctor" => "Just", "args" => [normalize_value_by_type(payload, inner_type, context)]}

  defp normalize_maybe_value(%{"ctor" => "Nothing", "args" => []}, _inner_type, _context),
    do: %{"ctor" => "Nothing", "args" => []}

  defp normalize_maybe_value(%{ctor: "Just", args: [payload]}, inner_type, context),
    do: %{"ctor" => "Just", "args" => [normalize_value_by_type(payload, inner_type, context)]}

  defp normalize_maybe_value(%{ctor: "Nothing", args: []}, _inner_type, _context),
    do: %{"ctor" => "Nothing", "args" => []}

  defp normalize_maybe_value(value, _inner_type, _context), do: value

  @spec flatten_tuple_chain(EvalTypes.runtime_value(), non_neg_integer()) :: [EvalTypes.runtime_value()]
  defp flatten_tuple_chain(value, count) when is_integer(count) and count > 0 do
    do_flatten_tuple_chain(value, count, [])
  end

  defp flatten_tuple_chain(_value, _count), do: []

  defp do_flatten_tuple_chain(value, 1, acc), do: Enum.reverse([value | acc])

  defp do_flatten_tuple_chain({left, right}, remaining, acc) when remaining > 1,
    do: do_flatten_tuple_chain(right, remaining - 1, [left | acc])

  defp do_flatten_tuple_chain(value, _remaining, acc), do: Enum.reverse([value | acc])

  @spec legacy_tuple_constructor_map?(EvalTypes.runtime_value()) :: boolean()
  defp legacy_tuple_constructor_map?(%{"ctor" => ctor, "args" => args})
       when is_binary(ctor) and is_list(args),
       do: legacy_tuple_integer_token(ctor) != nil

  defp legacy_tuple_constructor_map?(_value), do: false

  @spec flatten_legacy_tuple_constructor_map(EvalTypes.runtime_value(), non_neg_integer()) :: [EvalTypes.runtime_value()]
  defp flatten_legacy_tuple_constructor_map(value, count) when is_integer(count) and count > 0 do
    do_flatten_legacy_tuple_constructor_map(value, count, [])
  end

  defp flatten_legacy_tuple_constructor_map(_value, _count), do: []

  defp do_flatten_legacy_tuple_constructor_map(value, 1, acc) do
    Enum.reverse([legacy_tuple_scalar_value(value) | acc])
  end

  defp do_flatten_legacy_tuple_constructor_map(
         %{"ctor" => ctor, "args" => [next | _]},
         remaining,
         acc
       )
       when is_binary(ctor) and remaining > 1 do
    case legacy_tuple_integer_token(ctor) do
      nil -> Enum.reverse([%{"ctor" => ctor, "args" => [next]} | acc])
      integer -> do_flatten_legacy_tuple_constructor_map(next, remaining - 1, [integer | acc])
    end
  end

  defp do_flatten_legacy_tuple_constructor_map(value, _remaining, acc),
    do: Enum.reverse([legacy_tuple_scalar_value(value) | acc])

  @spec legacy_tuple_scalar_value(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
  defp legacy_tuple_scalar_value(%{"ctor" => ctor, "args" => []}) when is_binary(ctor) do
    legacy_tuple_integer_token(ctor) || %{"ctor" => ctor, "args" => []}
  end

  defp legacy_tuple_scalar_value(value), do: value

  @spec legacy_tuple_integer_token(String.t()) :: integer() | nil
  defp legacy_tuple_integer_token(token) when is_binary(token) do
    normalized =
      token
      |> String.trim()
      |> String.trim_leading("(")
      |> String.trim_trailing(",")
      |> String.trim_trailing(")")
      |> String.trim()

    case Integer.parse(normalized) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  @spec maybe_type?(String.t()) :: boolean()
  defp maybe_type?(type), do: type == "Maybe" or String.starts_with?(type, "Maybe ")

  @spec maybe_inner_type(String.t()) :: String.t() | nil
  defp maybe_inner_type("Maybe"), do: nil

  defp maybe_inner_type(type) when is_binary(type) do
    type
    |> String.replace_prefix("Maybe", "")
    |> String.trim()
    |> unwrap_parens()
  end

  @spec normalize_type_name(String.t()) :: String.t()
  defp normalize_type_name(type) when is_binary(type) do
    type
    |> String.trim()
    |> unwrap_parens()
  end

  @spec unwrap_parens(String.t()) :: String.t()
  defp unwrap_parens(type) when is_binary(type) do
    trimmed = String.trim(type)

    if String.starts_with?(trimmed, "(") and String.ends_with?(trimmed, ")") do
      trimmed
      |> String.slice(1, String.length(trimmed) - 2)
      |> String.trim()
    else
      trimmed
    end
  end

  @spec literal_or_expr(EvalTypes.runtime_value()) :: EvalTypes.expr() | EvalTypes.runtime_value()
  defp literal_or_expr(value) when is_map(value), do: value
  defp literal_or_expr(value), do: value

  @spec tuple_first(EvalTypes.runtime_value()) :: EvalTypes.runtime_value() | nil
  defp tuple_first({left, _right}), do: left
  defp tuple_first([left, _right]), do: left
  defp tuple_first(_), do: nil

  @spec tuple_second(EvalTypes.runtime_value()) :: EvalTypes.runtime_value() | nil
  defp tuple_second({_left, right}), do: right
  defp tuple_second([_left, right]), do: right
  defp tuple_second(_), do: nil

  @spec normalize_indexed_color(EvalTypes.runtime_value()) :: EvalTypes.color_result()
  defp normalize_indexed_color(code) when is_integer(code), do: {:ok, clamp_int(code, 0, 255)}
  defp normalize_indexed_color(_code), do: :no_builtin

  @spec normalize_rgba_color(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.runtime_value()) :: EvalTypes.color_result()
  defp normalize_rgba_color(r, g, b, a)
       when is_integer(r) and is_integer(g) and is_integer(b) and is_integer(a),
       do: {:ok, color_rgba_to_int(r, g, b, a)}

  defp normalize_rgba_color(_r, _g, _b, _a), do: :no_builtin

  @spec normalize_color_result(EvalTypes.runtime_value()) :: EvalTypes.color_result()
  defp normalize_color_result(color) do
    case normalize_color(color) do
      {:ok, value} -> {:ok, value}
      :error -> :no_builtin
    end
  end

  @spec color_constant(String.t()) :: {:ok, integer()} | :no_builtin
  defp color_constant(name) when is_binary(name) do
    case name do
      "clearcolor" -> {:ok, 0x00}
      "black" -> {:ok, 0xC0}
      "oxfordblue" -> {:ok, 0xC1}
      "dukeblue" -> {:ok, 0xC2}
      "blue" -> {:ok, 0xC3}
      "darkgreen" -> {:ok, 0xC4}
      "midnightgreen" -> {:ok, 0xC5}
      "cobaltblue" -> {:ok, 0xC6}
      "bluemoon" -> {:ok, 0xC7}
      "islamicgreen" -> {:ok, 0xC8}
      "jaegergreen" -> {:ok, 0xC9}
      "tiffanyblue" -> {:ok, 0xCA}
      "vividcerulean" -> {:ok, 0xCB}
      "green" -> {:ok, 0xCC}
      "malachite" -> {:ok, 0xCD}
      "mediumspringgreen" -> {:ok, 0xCE}
      "cyan" -> {:ok, 0xCF}
      "bulgarianrose" -> {:ok, 0xD0}
      "imperialpurple" -> {:ok, 0xD1}
      "indigo" -> {:ok, 0xD2}
      "electricultramarine" -> {:ok, 0xD3}
      "armygreen" -> {:ok, 0xD4}
      "darkgray" -> {:ok, 0xD5}
      "liberty" -> {:ok, 0xD6}
      "verylightblue" -> {:ok, 0xD7}
      "kellygreen" -> {:ok, 0xD8}
      "maygreen" -> {:ok, 0xD9}
      "cadetblue" -> {:ok, 0xDA}
      "pictonblue" -> {:ok, 0xDB}
      "brightgreen" -> {:ok, 0xDC}
      "screamingreen" -> {:ok, 0xDD}
      "mediumaquamarine" -> {:ok, 0xDE}
      "electricblue" -> {:ok, 0xDF}
      "darkcandyapplered" -> {:ok, 0xE0}
      "jazzberryjam" -> {:ok, 0xE1}
      "purple" -> {:ok, 0xE2}
      "vividviolet" -> {:ok, 0xE3}
      "windsortan" -> {:ok, 0xE4}
      "rosevale" -> {:ok, 0xE5}
      "purpureus" -> {:ok, 0xE6}
      "lavenderindigo" -> {:ok, 0xE7}
      "limerick" -> {:ok, 0xE8}
      "brass" -> {:ok, 0xE9}
      "lightgray" -> {:ok, 0xEA}
      "babyblueeyes" -> {:ok, 0xEB}
      "springbud" -> {:ok, 0xEC}
      "inchworm" -> {:ok, 0xED}
      "mintgreen" -> {:ok, 0xEE}
      "celeste" -> {:ok, 0xEF}
      "red" -> {:ok, 0xF0}
      "folly" -> {:ok, 0xF1}
      "fashionmagenta" -> {:ok, 0xF2}
      "magenta" -> {:ok, 0xF3}
      "orange" -> {:ok, 0xF4}
      "sunsetorange" -> {:ok, 0xF5}
      "brilliantrose" -> {:ok, 0xF6}
      "shockingpink" -> {:ok, 0xF7}
      "chromeyellow" -> {:ok, 0xF8}
      "rajah" -> {:ok, 0xF9}
      "melon" -> {:ok, 0xFA}
      "richbrilliantlavender" -> {:ok, 0xFB}
      "yellow" -> {:ok, 0xFC}
      "icterine" -> {:ok, 0xFD}
      "pastelyellow" -> {:ok, 0xFE}
      "white" -> {:ok, 0xFF}
      _ -> :no_builtin
    end
  end

  @spec normalize_color(EvalTypes.runtime_value()) :: {:ok, non_neg_integer()} | :error
  defp normalize_color(value) when is_integer(value), do: {:ok, clamp_int(value, 0, 255)}

  defp normalize_color(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args),
    do: normalize_color_ctor(ctor, args)

  defp normalize_color(%{ctor: ctor, args: args}) when is_binary(ctor) and is_list(args),
    do: normalize_color_ctor(ctor, args)

  defp normalize_color(_), do: :error

  @spec normalize_point(EvalTypes.runtime_value()) :: {:ok, {integer(), integer()}} | :error
  defp normalize_point(value) when is_map(value) do
    x = Map.get(value, "x") || Map.get(value, :x)
    y = Map.get(value, "y") || Map.get(value, :y)

    if is_integer(x) and is_integer(y), do: {:ok, {x, y}}, else: :error
  end

  defp normalize_point(_), do: :error

  @spec normalize_rect(EvalTypes.runtime_value()) :: {:ok, {integer(), integer(), integer(), integer()}} | :error
  defp normalize_rect({x, {y, {w, h}}})
       when is_integer(x) and is_integer(y) and is_integer(w) and is_integer(h),
       do: {:ok, {x, y, w, h}}

  defp normalize_rect(value) when is_map(value) do
    x = Map.get(value, "x") || Map.get(value, :x)
    y = Map.get(value, "y") || Map.get(value, :y)
    w = Map.get(value, "w") || Map.get(value, :w)
    h = Map.get(value, "h") || Map.get(value, :h)

    if is_integer(x) and is_integer(y) and is_integer(w) and is_integer(h),
      do: {:ok, {x, y, w, h}},
      else: :error
  end

  defp normalize_rect(_), do: :error

  @spec normalize_rect_or_default(EvalTypes.runtime_value()) :: {integer(), integer(), integer(), integer()}
  defp normalize_rect_or_default(value) do
    case normalize_rect(value) do
      {:ok, rect} -> rect
      :error -> {0, 0, 0, 0}
    end
  end

  @spec normalize_text_options(EvalTypes.runtime_value()) :: {:ok, {integer(), integer()}} | :error
  defp normalize_text_options({:function_ref, "Pebble.Ui.defaultTextOptions"}), do: {:ok, {1, 0}}
  defp normalize_text_options({:function_ref, "Ui.defaultTextOptions"}), do: {:ok, {1, 0}}

  defp normalize_text_options(value) when is_map(value) do
    alignment = Map.get(value, "alignment") || Map.get(value, :alignment)
    overflow = Map.get(value, "overflow") || Map.get(value, :overflow)

    with {:ok, normalized_alignment} <- normalize_text_alignment(alignment),
         {:ok, normalized_overflow} <- normalize_text_overflow(overflow) do
      {:ok, {normalized_alignment, normalized_overflow}}
    end
  end

  defp normalize_text_options(_), do: :error

  @spec normalize_text_options_or_default(EvalTypes.runtime_value()) :: {integer(), integer()}
  defp normalize_text_options_or_default(value) do
    case normalize_text_options(value) do
      {:ok, options} -> options
      :error -> {1, 0}
    end
  end

  defp update_text_option(options, field, value) when is_binary(field) and is_integer(value) do
    case normalize_text_options(options) do
      {:ok, {alignment, overflow}} ->
        next =
          %{
            "alignment" => alignment,
            "overflow" => overflow
          }
          |> Map.put(field, value)

        {:ok, next}

      :error ->
        :no_builtin
    end
  end

  defp normalize_text_alignment(0), do: {:ok, 0}
  defp normalize_text_alignment(1), do: {:ok, 1}
  defp normalize_text_alignment(2), do: {:ok, 2}
  defp normalize_text_alignment(%{"ctor" => "AlignLeft"}), do: {:ok, 0}
  defp normalize_text_alignment(%{"ctor" => "AlignCenter"}), do: {:ok, 1}
  defp normalize_text_alignment(%{"ctor" => "AlignRight"}), do: {:ok, 2}
  defp normalize_text_alignment(%{ctor: "AlignLeft"}), do: {:ok, 0}
  defp normalize_text_alignment(%{ctor: "AlignCenter"}), do: {:ok, 1}
  defp normalize_text_alignment(%{ctor: "AlignRight"}), do: {:ok, 2}
  defp normalize_text_alignment(_), do: :error

  defp normalize_text_overflow(0), do: {:ok, 0}
  defp normalize_text_overflow(1), do: {:ok, 1}
  defp normalize_text_overflow(2), do: {:ok, 2}
  defp normalize_text_overflow(%{"ctor" => "WordWrap"}), do: {:ok, 0}
  defp normalize_text_overflow(%{"ctor" => "TrailingEllipsis"}), do: {:ok, 1}
  defp normalize_text_overflow(%{"ctor" => "Fill"}), do: {:ok, 2}
  defp normalize_text_overflow(%{ctor: "WordWrap"}), do: {:ok, 0}
  defp normalize_text_overflow(%{ctor: "TrailingEllipsis"}), do: {:ok, 1}
  defp normalize_text_overflow(%{ctor: "Fill"}), do: {:ok, 2}
  defp normalize_text_overflow(_), do: :error

  @spec normalize_path(EvalTypes.runtime_value()) ::
          {:ok, {[{integer(), integer()}], integer(), integer(), integer()}} | :error
  defp normalize_path({points, {offset_x, offset_y}, rotation})
       when is_list(points) and is_integer(offset_x) and is_integer(offset_y) and
              is_integer(rotation) do
    with {:ok, normalized_points} <- normalize_points(points) do
      {:ok, {normalized_points, offset_x, offset_y, rotation}}
    end
  end

  defp normalize_path(value) when is_list(value) do
    case value do
      [points, {offset_x, offset_y}, rotation]
      when is_list(points) and is_integer(offset_x) and is_integer(offset_y) and
             is_integer(rotation) ->
        with {:ok, normalized_points} <- normalize_points(points) do
          {:ok, {normalized_points, offset_x, offset_y, rotation}}
        end

      _ ->
        :error
    end
  end

  defp normalize_path(_), do: :error

  @spec normalize_points(EvalTypes.runtime_value()) :: {:ok, [{integer(), integer()}]} | :error
  defp normalize_points(points) when is_list(points) do
    normalized =
      points
      |> Enum.map(&normalize_point_tuple/1)

    if Enum.all?(normalized, &match?({:ok, {_x, _y}}, &1)) do
      {:ok, Enum.map(normalized, fn {:ok, pair} -> pair end)}
    else
      :error
    end
  end

  defp normalize_points(_), do: :error

  @spec normalize_point_tuple(EvalTypes.runtime_value()) :: {:ok, {integer(), integer()}} | :error
  defp normalize_point_tuple({x, y}) when is_integer(x) and is_integer(y), do: {:ok, {x, y}}
  defp normalize_point_tuple([x, y]) when is_integer(x) and is_integer(y), do: {:ok, {x, y}}

  defp normalize_point_tuple(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y),
    do: {:ok, {x, y}}

  defp normalize_point_tuple(%{x: x, y: y}) when is_integer(x) and is_integer(y),
    do: {:ok, {x, y}}

  defp normalize_point_tuple(_), do: :error

  @spec normalize_color_ctor(EvalTypes.runtime_value(), EvalTypes.runtime_value()) :: {:ok, non_neg_integer()} | :error
  defp normalize_color_ctor(ctor, args) when is_binary(ctor) and is_list(args) do
    short =
      ctor
      |> String.split(".")
      |> List.last()
      |> to_string()

    case {short, args} do
      {"Indexed", [code]} when is_integer(code) ->
        {:ok, clamp_int(code, 0, 255)}

      {"RGBA", [r, g, b, a]}
      when is_integer(r) and is_integer(g) and is_integer(b) and is_integer(a) ->
        {:ok, color_rgba_to_int(r, g, b, a)}

      _ ->
        :error
    end
  end

  @spec bitmap_resource_id_from_value(EvalTypes.runtime_value(), map()) ::
          {:ok, non_neg_integer()} | :error
  def bitmap_resource_id_from_value(value, context \\ %{}), do: normalize_bitmap_id(value, context)

  @doc false
  @spec normalize_runtime_rect(EvalTypes.runtime_value()) ::
          {:ok, {integer(), integer(), integer(), integer()}} | :error
  def normalize_runtime_rect(value), do: normalize_rect(value)

  @doc false
  @spec normalize_runtime_point(EvalTypes.runtime_value()) :: {:ok, {integer(), integer()}} | :error
  def normalize_runtime_point(value), do: normalize_point(value)

  @doc false
  @spec normalize_runtime_color(EvalTypes.runtime_value()) :: {:ok, integer()} | :error
  def normalize_runtime_color(value), do: normalize_color(value)

  @doc false
  @spec normalize_runtime_rotation_angle(EvalTypes.runtime_value()) :: {:ok, integer()} | :error
  def normalize_runtime_rotation_angle(value), do: normalize_rotation_angle(value)

  @spec normalize_bitmap_id(EvalTypes.runtime_value(), map()) :: {:ok, non_neg_integer()} | :error
  defp normalize_bitmap_id(value, context)

  defp normalize_bitmap_id(value, _context) when is_integer(value), do: {:ok, value}

  defp normalize_bitmap_id(%{"tag" => tag}, _context) when is_integer(tag), do: {:ok, tag}
  defp normalize_bitmap_id(%{tag: tag}, _context) when is_integer(tag), do: {:ok, tag}

  defp normalize_bitmap_id(%{"ctor" => ctor, "args" => args} = value, context)
       when is_map(value) and is_list(args) do
    bitmap_resource_id_from_ctor(ctor, Map.get(value, "tag"), context)
  end

  defp normalize_bitmap_id(%{ctor: ctor, args: args} = value, context)
       when is_map(value) and is_list(args) do
    bitmap_resource_id_from_ctor(ctor, Map.get(value, :tag), context)
  end

  defp normalize_bitmap_id(_, _context), do: :error

  @spec bitmap_resource_id_from_ctor(String.t() | atom(), integer() | nil, map()) ::
          {:ok, non_neg_integer()} | :error
  defp bitmap_resource_id_from_ctor(ctor, tag, context) do
    ctor = to_string(ctor)

    cond do
      ctor in ["NoBitmap", "NoStaticBitmap"] ->
        {:ok, 0}

      is_integer(tag) ->
        {:ok, bitmap_id_from_union_tag(tag, context)}

      true ->
        cond do
          is_integer(id = bitmap_resource_index_for_ctor(ctor, context)) and id >= 1 ->
            {:ok, id}

          is_integer(tag = constructor_tag_for_ctor(ctor, context)) ->
            {:ok, bitmap_id_from_union_tag(tag, context)}

          true ->
            :error
        end
    end
  end

  @spec bitmap_id_from_union_tag(integer(), map()) :: non_neg_integer()
  defp bitmap_id_from_union_tag(tag, context) when is_integer(tag) and is_map(context) do
    no_bitmap_ctor =
      if is_integer(constructor_tag_for_ctor("NoStaticBitmap", context)),
        do: "NoStaticBitmap",
        else: "NoBitmap"

    if is_integer(constructor_tag_for_ctor(no_bitmap_ctor, context)) do
      max(tag - 1, 0)
    else
      max(tag, 0)
    end
  end

  @spec bitmap_resource_index_for_ctor(String.t() | atom(), map()) :: integer() | nil
  defp bitmap_resource_index_for_ctor(ctor, context) when is_map(context) do
    ctor =
      ctor
      |> to_string()
      |> String.trim()

    context
    |> Map.get(:bitmap_resource_indices, %{})
    |> Map.get(ctor)
    |> case do
      id when is_integer(id) and id >= 1 -> id
      _ -> nil
    end
  end

  defp bitmap_resource_index_for_ctor(_ctor, _context), do: nil

  @spec vector_resource_id_from_value(EvalTypes.runtime_value(), map()) ::
          {:ok, non_neg_integer()} | :error
  def vector_resource_id_from_value(value, context \\ %{}), do: normalize_vector_id(value, context)

  @spec normalize_vector_id(EvalTypes.runtime_value(), map()) :: {:ok, non_neg_integer()} | :error
  defp normalize_vector_id(value, context)

  defp normalize_vector_id(value, _context) when is_integer(value), do: {:ok, max(value, 0)}

  defp normalize_vector_id(%{"ctor" => ctor, "args" => args} = value, context)
       when is_map(value) and is_list(args) do
    vector_resource_id_from_ctor(ctor, Map.get(value, "tag"), context)
  end

  defp normalize_vector_id(%{ctor: ctor, args: args} = value, context)
       when is_map(value) and is_list(args) do
    vector_resource_id_from_ctor(ctor, Map.get(value, :tag), context)
  end

  defp normalize_vector_id(%{"tag" => tag}, _context) when is_integer(tag),
    do: {:ok, max(tag, 0)}

  defp normalize_vector_id(%{tag: tag}, _context) when is_integer(tag), do: {:ok, max(tag, 0)}

  defp normalize_vector_id(_, _context), do: :error

  @spec vector_resource_id_from_ctor(String.t() | atom(), integer() | nil, map()) ::
          {:ok, non_neg_integer()} | :error
  defp vector_resource_id_from_ctor(ctor, tag, context) do
    ctor = to_string(ctor)

    cond do
      ctor in ["NoVectorGraphic", "NoStaticVector", "NoAnimatedVector"] ->
        {:ok, 0}

      is_integer(id = vector_resource_index_for_ctor(ctor, context)) and id >= 1 ->
        {:ok, id}

      is_integer(tag) ->
        {:ok, tag + 1}

      is_integer(tag = constructor_tag_for_ctor(ctor, context)) ->
        {:ok, tag + 1}

      true ->
        :error
    end
  end

  @spec constructor_tag_for_ctor(String.t() | atom(), map()) :: integer() | nil
  defp constructor_tag_for_ctor(ctor, context) when is_map(context) do
    ctor = to_string(ctor)

    context
    |> Map.get(:constructor_tags, [])
    |> Enum.filter(fn entry -> to_string(Map.get(entry, :ctor) || "") == ctor end)
    |> prefer_resource_constructor_entry()
    |> case do
      %{tag: tag} when is_integer(tag) -> tag
      %{"tag" => tag} when is_integer(tag) -> tag
      _ -> nil
    end
  end

  defp constructor_tag_for_ctor(_ctor, _context), do: nil

  @spec prefer_resource_constructor_entry([map()]) :: map() | nil
  defp prefer_resource_constructor_entry([entry]), do: entry

  defp prefer_resource_constructor_entry(entries) when is_list(entries) and entries != [] do
    Enum.find(entries, fn entry ->
      union = to_string(Map.get(entry, :union) || Map.get(entry, "union") || "")
      union in [
        "VectorGraphic",
        "Bitmap",
        "Font",
        "Animation",
        "StaticBitmap",
        "AnimatedBitmap",
        "StaticVector",
        "AnimatedVector"
      ]
    end) || List.first(entries)
  end

  defp prefer_resource_constructor_entry(_entries), do: nil

  @spec vector_resource_index_for_ctor(String.t() | atom(), map()) :: integer() | nil
  defp vector_resource_index_for_ctor(ctor, context) when is_map(context) do
    ctor =
      case ctor do
        value when is_binary(value) -> value
        value when is_atom(value) -> Atom.to_string(value)
        _ -> ""
      end

    context
    |> Map.get(:vector_resource_indices, %{})
    |> Map.get(ctor)
  end

  defp vector_resource_index_for_ctor(_ctor, _context), do: nil

  @spec animation_resource_id_from_value(EvalTypes.runtime_value(), map()) ::
          {:ok, non_neg_integer()} | :error
  def animation_resource_id_from_value(value, context \\ %{}),
    do: normalize_animation_id(value, context)

  @spec normalize_animation_id(EvalTypes.runtime_value(), map()) :: {:ok, non_neg_integer()} | :error
  defp normalize_animation_id(value, context)

  defp normalize_animation_id(value, _context) when is_integer(value), do: {:ok, max(value, 0)}

  defp normalize_animation_id(%{"ctor" => ctor, "args" => args} = value, context)
       when is_map(value) and is_list(args) do
    animation_resource_id_from_ctor(ctor, Map.get(value, "tag"), context)
  end

  defp normalize_animation_id(%{ctor: ctor, args: args} = value, context)
       when is_map(value) and is_list(args) do
    animation_resource_id_from_ctor(ctor, Map.get(value, :tag), context)
  end

  defp normalize_animation_id(%{"tag" => tag}, _context) when is_integer(tag),
    do: {:ok, max(tag, 0)}

  defp normalize_animation_id(%{tag: tag}, _context) when is_integer(tag), do: {:ok, max(tag, 0)}

  defp normalize_animation_id(_, _context), do: :error

  @spec animation_resource_id_from_ctor(String.t() | atom(), integer() | nil, map()) ::
          {:ok, non_neg_integer()} | :error
  defp animation_resource_id_from_ctor(ctor, tag, context) do
    ctor = to_string(ctor)

    cond do
      ctor in ["NoAnimation", "NoAnimatedBitmap"] ->
        {:ok, 0}

      is_integer(id = animation_resource_index_for_ctor(ctor, context)) and id >= 1 ->
        {:ok, id}

      is_integer(tag) ->
        {:ok, tag + 1}

      is_integer(tag = constructor_tag_for_ctor(ctor, context)) ->
        {:ok, tag + 1}

      true ->
        :error
    end
  end

  @spec animation_resource_index_for_ctor(String.t() | atom(), map()) :: integer() | nil
  defp animation_resource_index_for_ctor(ctor, context) when is_map(context) do
    ctor =
      ctor
      |> to_string()
      |> String.trim()

    context
    |> Map.get(:animation_resource_indices, %{})
    |> Map.get(ctor)
    |> case do
      id when is_integer(id) and id >= 1 -> id
      _ -> nil
    end
  end

  defp animation_resource_index_for_ctor(_ctor, _context), do: nil

  @spec normalize_font_id(EvalTypes.runtime_value()) :: {:ok, non_neg_integer()} | :error
  defp normalize_font_id(value) when is_integer(value), do: {:ok, value}

  defp normalize_font_id({:function_ref, "Pebble.Ui.Resources.DefaultFont"}), do: {:ok, 1}
  defp normalize_font_id({:function_ref, "Resources.DefaultFont"}), do: {:ok, 1}
  defp normalize_font_id({:function_ref, name}) when is_binary(name), do: {:ok, 1}

  defp normalize_font_id(%{"tag" => tag}) when is_integer(tag), do: {:ok, tag}
  defp normalize_font_id(%{tag: tag}) when is_integer(tag), do: {:ok, tag}

  defp normalize_font_id(%{"ctor" => _ctor, "args" => []} = value) when is_map(value) do
    case {Map.get(value, "ctor"), Map.get(value, "tag")} do
      {"DefaultFont", _} -> {:ok, 1}
      {_ctor, tag} when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  defp normalize_font_id(%{ctor: _ctor, args: []} = value) when is_map(value) do
    case {Map.get(value, :ctor), Map.get(value, :tag)} do
      {"DefaultFont", _} -> {:ok, 1}
      {:DefaultFont, _} -> {:ok, 1}
      {_ctor, tag} when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  defp normalize_font_id(_), do: :error

  @spec normalize_font_id_or_default(EvalTypes.runtime_value()) :: non_neg_integer()
  defp normalize_font_id_or_default(value) do
    case normalize_font_id(value) do
      {:ok, font_id} -> font_id
      :error -> 1
    end
  end

  @spec normalize_text_value(EvalTypes.runtime_value()) :: {:ok, String.t()} | :error
  defp normalize_text_value(value) when is_binary(value), do: {:ok, value}

  defp normalize_text_value(value) do
    case binary_leaves(value) do
      leaves when leaves != [] -> {:ok, Enum.join(leaves)}
      _ -> :error
    end
  end

  @spec normalize_text_value_or_default(EvalTypes.runtime_value()) :: String.t()
  defp normalize_text_value_or_default(value) do
    case normalize_text_value(value) do
      {:ok, text} -> text
      :error -> ""
    end
  end

  @spec binary_leaves(EvalTypes.runtime_value()) :: [String.t()]
  defp binary_leaves(value) when is_binary(value), do: [value]

  defp binary_leaves(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.flat_map(&binary_leaves/1)
  end

  defp binary_leaves(value) when is_list(value), do: Enum.flat_map(value, &binary_leaves/1)
  defp binary_leaves(_value), do: []

  @spec normalize_rotation_angle(EvalTypes.runtime_value()) :: {:ok, integer()} | :error
  defp normalize_rotation_angle(value) when is_integer(value), do: {:ok, value}

  defp normalize_rotation_angle(%{"ctor" => ctor, "args" => [angle]})
       when is_binary(ctor) and is_integer(angle) do
    if String.ends_with?(ctor, ".Rotation") or ctor == "Rotation", do: {:ok, angle}, else: :error
  end

  defp normalize_rotation_angle(%{ctor: ctor, args: [angle]})
       when is_binary(ctor) and is_integer(angle) do
    if String.ends_with?(ctor, ".Rotation") or ctor == "Rotation", do: {:ok, angle}, else: :error
  end

  defp normalize_rotation_angle(_), do: :error

  @spec color_rgba_to_int(EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.runtime_value(), EvalTypes.runtime_value()) :: non_neg_integer()
  defp color_rgba_to_int(r, g, b, a) do
    rr = color_channel_to_2bit(r)
    gg = color_channel_to_2bit(g)
    bb = color_channel_to_2bit(b)
    aa = color_channel_to_2bit(a)

    Bitwise.bor(
      Bitwise.bsl(aa, 6),
      Bitwise.bor(Bitwise.bsl(rr, 4), Bitwise.bor(Bitwise.bsl(gg, 2), bb))
    )
  end

  @spec color_channel_to_2bit(integer()) :: non_neg_integer()
  defp color_channel_to_2bit(value) when is_integer(value) do
    div(clamp_int(value, 0, 255) * 3 + 127, 255)
  end

  @spec clamp_int(integer(), integer(), integer()) :: integer()
  defp clamp_int(value, low, high) when is_integer(value), do: max(low, min(high, value))

  @spec ui_node(String.t(), [EvalTypes.ui_node_map()]) :: EvalTypes.ui_node_map()
  defp ui_node(type, children) when is_binary(type) and is_list(children) do
    %{"type" => type, "children" => children, "label" => ""}
  end

  @spec ui_group_node(EvalTypes.command_map(), EvalTypes.runtime_value()) :: EvalTypes.ui_node_map()
  defp ui_group_node(style, ops) when is_map(style) do
    node = ui_node("group", ui_children_from_value(ops))

    if map_size(style) > 0 do
      Map.put(node, "style", style)
    else
      node
    end
  end

  defp ui_group_node(_style, ops), do: ui_node("group", ui_children_from_value(ops))

  @spec ui_context_style(list()) :: EvalTypes.command_map()
  defp ui_context_style(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn
      {:ui_context_setting, key, value}, acc when is_binary(key) ->
        Map.put(acc, key, value)

      _, acc ->
        acc
    end)
  end

  defp ui_context_style(_settings), do: %{}

  @spec expr_node(EvalTypes.runtime_value()) :: EvalTypes.ui_node_map()
  defp expr_node(value) when is_integer(value) or is_float(value),
    do: %{"type" => "expr", "value" => value, "children" => []}

  defp expr_node(value) when is_binary(value),
    do: %{"type" => "expr", "label" => value, "children" => []}

  defp expr_node(value) when is_boolean(value),
    do: %{"type" => "expr", "label" => to_string(value), "children" => []}

  defp expr_node(%{} = node), do: node
  defp expr_node(value), do: %{"type" => "expr", "label" => inspect(value), "children" => []}

  @spec path_points_node([{integer(), integer()}]) :: EvalTypes.ui_node_map()
  defp path_points_node(points) when is_list(points) do
    %{
      "type" => "List",
      "label" => "[#{length(points)}]",
      "children" =>
        Enum.map(points, fn {x, y} ->
          %{
            "type" => "tuple2",
            "label" => "",
            "children" => [expr_node(x), expr_node(y)]
          }
        end)
    }
  end

  @spec ui_children_from_value(EvalTypes.runtime_value()) :: [EvalTypes.ui_node_map()]
  defp ui_children_from_value(list) when is_list(list) do
    list
    |> Enum.flat_map(fn
      %{"type" => _} = node -> [node]
      %{type: _} = node -> [node]
      %{} = map -> [expr_node(map)]
      value -> [expr_node(value)]
    end)
  end

  defp ui_children_from_value(%{} = node), do: [node]
  defp ui_children_from_value(_), do: []

  @spec resolve_zero_arity_value(String.t(), map(), EvalTypes.eval_stack()) :: {:ok, EvalTypes.runtime_value()} | :error
  defp resolve_zero_arity_value(name, context, stack)
       when is_binary(name) and is_map(context) and is_list(stack) do
    {module_name, function_name} = parse_function_name(name, context)
    functions = Map.get(context, :functions, %{})
    allow_global_lookup = not String.contains?(name, ".")

    case find_zero_arity_function_def(functions, module_name, function_name, allow_global_lookup) do
      %{body: body} ->
        key = {module_name, function_name, 0}

        case do_evaluate(body, %{}, with_function_context(context, module_name), [key | stack]) do
          {:ok, value} -> {:ok, value}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp resolve_zero_arity_value(_name, _context, _stack), do: :error

  @spec apply_indexed_function(String.t(), EvalTypes.runtime_values(), map(), EvalTypes.eval_stack()) :: EvalTypes.eval_result()
  defp apply_indexed_function(name, values, context, stack) do
    {module_name, function_name} = parse_function_name(name, context)
    functions = Map.get(context, :functions, %{})
    allow_global_lookup = not String.contains?(name, ".")

    module_name
    |> module_name_candidates(functions)
    |> Enum.reduce_while(nil, fn candidate_module, _acc ->
      case apply_indexed_function_in_module(
             candidate_module,
             function_name,
             values,
             context,
             stack,
             allow_global_lookup
           ) do
        {:error, {:unknown_function, _}} = err -> {:cont, err}
        other -> {:halt, other}
      end
    end)
    |> case do
      nil ->
        unknown = {:error, {:unknown_function, {module_name, function_name, length(values)}}}

        case try_pebble_ui_to_ui_node_fallback(module_name, function_name, values) do
          {:ok, value} -> {:ok, value}
          :error -> unknown
        end

      {:error, {:unknown_function, {module_name, function_name, _arity}}} = unknown ->
        case try_pebble_ui_to_ui_node_fallback(module_name, function_name, values) do
          {:ok, value} -> {:ok, value}
          :error -> unknown
        end

      result ->
        result
    end
  end

  @spec try_pebble_ui_to_ui_node_fallback(String.t(), String.t(), EvalTypes.runtime_values()) ::
          {:ok, EvalTypes.ui_node_map()} | :error
  defp try_pebble_ui_to_ui_node_fallback(module_name, "toUiNode", [ops])
       when is_binary(module_name) do
    if pebble_ui_module_name?(module_name) and is_list(ops) do
      wrap_render_ops_list_as_ui_node(ops)
    else
      :error
    end
  end

  defp try_pebble_ui_to_ui_node_fallback(_module_name, _function_name, _values), do: :error

  @spec pebble_ui_module_name?(String.t()) :: boolean()
  defp pebble_ui_module_name?(module_name) when is_binary(module_name) do
    compact_module_name(module_name) in ["pebbleui", "ui"]
  end

  @spec apply_indexed_function_in_module(
          String.t(),
          String.t(),
          EvalTypes.runtime_values(),
          EvalTypes.ops_context(),
          EvalTypes.eval_stack(),
          boolean()
        ) :: EvalTypes.eval_result()
  defp apply_indexed_function_in_module(
         module_name,
         function_name,
         values,
         context,
         stack,
         allow_global_lookup
       ) do
    key = {module_name, function_name, length(values)}

    if intrinsic_operator_name?(function_name) do
      intrinsic_operator_fallback(function_name, values, context, stack, key)
    else
      apply_indexed_function_in_module_impl(
        module_name,
        function_name,
        values,
        context,
        stack,
        allow_global_lookup,
        key
      )
    end
  end

  defp apply_indexed_function_in_module_impl(
         module_name,
         function_name,
         values,
         context,
         stack,
         allow_global_lookup,
         key
       ) do
    functions = Map.get(context, :functions, %{})

    cond do
      function_recursion_depth(stack, key) >= @max_function_recursion_depth ->
        {:error, {:recursive_loop_detected, key}}

      is_map(functions[key]) ->
        %{params: params, body: body} = functions[key]
        env = Enum.zip(params, values) |> Map.new()
        do_evaluate(body, env, with_function_context(context, module_name), [key | stack])

      true ->
        fallback =
          find_function_def(
            functions,
            module_name,
            function_name,
            length(values),
            allow_global_lookup
          )

        case fallback do
          %{params: params, body: body} ->
            env = Enum.zip(params, values) |> Map.new()
            do_evaluate(body, env, with_function_context(context, module_name), [key | stack])

          _ ->
            overapplied_def =
              find_overapplied_function_def(
                functions,
                module_name,
                function_name,
                length(values),
                allow_global_lookup
              )

            if is_map(overapplied_def) do
              %{params: params, body: body} = overapplied_def
              arity = length(params)
              {first_values, rest_values} = Enum.split(values, arity)
              overapplied_key = {module_name, function_name, arity}
              env = Enum.zip(params, first_values) |> Map.new()

              with {:ok, head_result} <-
                     do_evaluate(
                       body,
                       env,
                       with_function_context(context, module_name),
                       [overapplied_key | stack]
                     ) do
                apply_overapplied_result(head_result, rest_values, env, context, stack)
              end
            else
              partial_def =
                find_partial_function_def(
                  functions,
                  module_name,
                  function_name,
                  length(values),
                  allow_global_lookup
                )

              case partial_def do
                %{params: params, body: body} ->
                  {bound_params, remaining_params} = Enum.split(params, length(values))
                  closure_env = Enum.zip(bound_params, values) |> Map.new()
                  {:ok, {:closure, remaining_params, body, closure_env}}

                _ ->
                  zero_arity_def =
                    find_zero_arity_function_def(
                      functions,
                      module_name,
                      function_name,
                      allow_global_lookup
                    )

                  zero_arity_key = {module_name, function_name, 0}

                    if is_map(zero_arity_def) and values != [] do
                      %{body: body} = zero_arity_def

                      with {:ok, callable} <-
                             do_evaluate(
                               body,
                               %{},
                               with_function_context(context, module_name),
                               [zero_arity_key | stack]
                             ),
                           {:ok, value} <-
                             call_callable(
                               callable,
                               values,
                               %{},
                               with_function_context(context, module_name),
                               [zero_arity_key | stack]
                             ) do
                        {:ok, value}
                      else
                        _ -> intrinsic_operator_fallback(function_name, values, context, stack, key)
                      end
                    else
                      intrinsic_operator_fallback(function_name, values, context, stack, key)
                    end
              end
            end
        end
    end
  end

  @spec intrinsic_operator_fallback(
          String.t(),
          EvalTypes.runtime_values(),
          EvalTypes.ops_context(),
          EvalTypes.eval_stack(),
          EvalTypes.function_index_key()
        ) :: EvalTypes.eval_result()
  defp intrinsic_operator_fallback(function_name, values, context, stack, key)
       when is_binary(function_name) and is_list(values) and is_map(context) and is_list(stack) do
    if intrinsic_operator_name?(function_name) do
      case eval_builtin(function_name, values, %{}, context, stack) do
        {:ok, value} -> {:ok, value}
        _ -> {:error, {:unknown_function, key}}
      end
    else
      {:error, {:unknown_function, key}}
    end
  end

  @spec intrinsic_operator_name?(String.t()) :: boolean()
  defp intrinsic_operator_name?(name) when is_binary(name),
    do: String.starts_with?(name, "__") and String.ends_with?(name, "__")

  defp intrinsic_operator_name?(_name), do: false

  defp apply_overapplied_result(head_result, rest_values, env, context, stack)
       when is_list(rest_values) do
    case call_callable(head_result, rest_values, env, context, stack) do
      {:error, {:not_callable, _}} when length(rest_values) == 1 ->
        [accessor] = rest_values
        call_callable(accessor, [head_result], env, context, stack)

      other ->
        other
    end
  end

  @spec module_name_candidates(String.t(), map()) :: [String.t()]
  defp module_name_candidates(module_name, functions)
       when is_binary(module_name) and is_map(functions) do
    compact = compact_module_name(module_name)

    candidates =
      functions
      |> Map.keys()
      |> Enum.flat_map(fn
        {candidate_module, _function_name, _arity} when is_binary(candidate_module) ->
          if compact_module_name(candidate_module) == compact, do: [candidate_module], else: []

        _ ->
          []
      end)
      |> Enum.uniq()

    [module_name | candidates]
    |> Enum.uniq()
  end

  defp module_name_candidates(module_name, _functions) when is_binary(module_name),
    do: [module_name]

  @spec function_recursion_depth(EvalTypes.eval_stack(), EvalTypes.runtime_value()) :: non_neg_integer()
  defp function_recursion_depth(stack, key) when is_list(stack),
    do: Enum.count(stack, &(&1 == key))

  @spec compact_module_name(String.t()) :: String.t()
  defp compact_module_name(module_name) when is_binary(module_name) do
    module_name
    |> String.replace(".", "")
    |> String.downcase()
  end

  @spec with_function_context(map(), String.t()) :: map()
  defp with_function_context(context, module_name)
       when is_map(context) and is_binary(module_name) do
    context
    |> Map.put(:module, module_name)
    |> Map.put(:source_module, module_name)
  end

  @spec find_function_def(map(), String.t(), String.t(), non_neg_integer(), boolean()) ::
          map() | nil
  defp find_function_def(functions, module_name, function_name, arity, allow_global_lookup)
       when is_map(functions) and is_binary(module_name) and is_binary(function_name) and
              is_integer(arity) and arity >= 0 and is_boolean(allow_global_lookup) do
    direct_key = {module_name, function_name, arity}

    cond do
      is_map(functions[direct_key]) ->
        functions[direct_key]

      true ->
        exact_candidates =
          functions
          |> Enum.filter(fn
            {{mod, fn_name, fn_arity}, defn}
            when mod == module_name and fn_name == function_name and fn_arity == arity and
                   is_map(defn) ->
              true

            _ ->
              false
          end)
          |> Enum.map(fn {_k, defn} -> defn end)

        case exact_candidates do
          [defn] ->
            defn

          _ ->
            normalized_target = normalize_builtin_short_name(function_name)

            normalized_candidates =
              functions
              |> Enum.filter(fn
                {{mod, fn_name, fn_arity}, defn}
                when fn_arity == arity and is_map(defn) ->
                  same_name = fn_name == function_name
                  same_normalized = normalize_builtin_short_name(fn_name) == normalized_target
                  same_module = mod == module_name
                  (same_name or same_normalized) and same_module

                _ ->
                  false
              end)
              |> Enum.map(fn {_k, defn} -> defn end)

            case normalized_candidates do
              [defn] ->
                defn

              _ when allow_global_lookup ->
                global_candidates =
                  functions
                  |> Enum.filter(fn
                    {{_mod, fn_name, fn_arity}, defn}
                    when fn_arity == arity and is_map(defn) ->
                      fn_name == function_name or
                        normalize_builtin_short_name(fn_name) == normalized_target

                    _ ->
                      false
                  end)
                  |> Enum.map(fn {_k, defn} -> defn end)

                case global_candidates do
                  [defn] -> defn
                  _ -> nil
                end

              _ ->
                nil
            end
        end
    end
  end

  @spec find_partial_function_def(map(), String.t(), String.t(), non_neg_integer(), boolean()) ::
          map() | nil
  defp find_partial_function_def(
         functions,
         module_name,
         function_name,
         bound_arity,
         allow_global_lookup
       )
       when is_map(functions) and is_binary(module_name) and is_binary(function_name) and
              is_integer(bound_arity) and bound_arity >= 0 and is_boolean(allow_global_lookup) do
    normalized_target = normalize_builtin_short_name(function_name)

    functions
    |> Enum.filter(fn
      {{mod, fn_name, fn_arity}, defn}
      when is_binary(mod) and is_binary(fn_name) and is_integer(fn_arity) and
             fn_arity > bound_arity and
             is_map(defn) ->
        same_name = fn_name == function_name
        same_normalized = normalize_builtin_short_name(fn_name) == normalized_target
        same_module = mod == module_name
        global_match = allow_global_lookup and (same_name or same_normalized)

        ((same_name or same_normalized) and same_module) or global_match

      _ ->
        false
    end)
    |> Enum.sort_by(fn {{mod, _fn_name, fn_arity}, _defn} ->
      module_rank = if mod == module_name, do: 0, else: 1
      {module_rank, fn_arity}
    end)
    |> case do
      [{_key, defn} | _] -> defn
      [] -> nil
    end
  end

  @spec find_overapplied_function_def(map(), String.t(), String.t(), pos_integer(), boolean()) ::
          map() | nil
  defp find_overapplied_function_def(
         functions,
         module_name,
         function_name,
         value_count,
         allow_global_lookup
       )
       when is_map(functions) and is_binary(module_name) and is_binary(function_name) and
              is_integer(value_count) and value_count > 0 and is_boolean(allow_global_lookup) do
    normalized_target = normalize_builtin_short_name(function_name)

    functions
    |> Enum.filter(fn
      {{mod, fn_name, fn_arity}, defn}
      when is_binary(mod) and is_binary(fn_name) and is_integer(fn_arity) and
             fn_arity > 0 and fn_arity < value_count and is_map(defn) ->
        same_name = fn_name == function_name
        same_normalized = normalize_builtin_short_name(fn_name) == normalized_target
        same_module = mod == module_name
        global_match = allow_global_lookup and (same_name or same_normalized)

        ((same_name or same_normalized) and same_module) or global_match

      _ ->
        false
    end)
    |> Enum.sort_by(fn {{mod, _fn_name, fn_arity}, _defn} ->
      module_rank = if mod == module_name, do: 0, else: 1
      {module_rank, -fn_arity}
    end)
    |> case do
      [{_key, defn} | _] -> defn
      [] -> nil
    end
  end

  defp find_overapplied_function_def(
         _functions,
         _module_name,
         _function_name,
         _value_count,
         _allow
       ),
       do: nil

  @spec find_zero_arity_function_def(map(), String.t(), String.t(), boolean()) :: map() | nil
  defp find_zero_arity_function_def(functions, module_name, function_name, allow_global_lookup)
       when is_map(functions) and is_binary(module_name) and is_binary(function_name) and
              is_boolean(allow_global_lookup) do
    case find_function_def(functions, module_name, function_name, 0, allow_global_lookup) do
      %{body: _body} = defn ->
        defn

      _ when allow_global_lookup ->
        normalized_target = normalize_builtin_short_name(function_name)

        global_zero_arity =
          functions
          |> Enum.filter(fn
            {{_mod, fn_name, 0}, defn} when is_map(defn) ->
              fn_name == function_name or
                normalize_builtin_short_name(fn_name) == normalized_target

            _ ->
              false
          end)
          |> Enum.map(fn {_k, defn} -> defn end)

        case global_zero_arity do
          [defn] -> defn
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec parse_function_name(EvalTypes.runtime_value(), map()) :: {String.t(), String.t()}
  defp parse_function_name(name, context) when is_binary(name) do
    parts = String.split(name, ".", trim: true)

    case parts do
      [one] ->
        module_name =
          to_string(Map.get(context, :module) || Map.get(context, :source_module) || "Main")

        {module_name, one}

      many ->
        function_name = List.last(many)
        module_name = many |> Enum.drop(-1) |> Enum.join(".")
        {module_name, function_name}
    end
  end

  @spec evaluate_case_branches(list(), EvalTypes.runtime_value(), EvalTypes.env(), map(), EvalTypes.eval_stack()) :: EvalTypes.eval_result()
  defp evaluate_case_branches(branches, subject, env, context, stack) when is_list(branches) do
    Enum.find_value(branches, {:error, :no_case_branch_match}, fn branch ->
      pattern = branch["pattern"] || branch[:pattern] || %{}
      expr = branch["expr"] || branch[:expr]

      case match_pattern(pattern, subject, context) do
        {:ok, pattern_bindings} ->
          next_env = Map.merge(env, pattern_bindings)

          case maybe_evaluate(expr, next_env, context, stack) do
            {:ok, value} -> {:ok, value}
            {:error, reason} -> {:error, reason}
          end

        :nomatch ->
          nil
      end
    end)
  end

  defp evaluate_case_branches(_branches, _subject, _env, _context, _stack),
    do: {:error, :invalid_case_branches}

  @spec match_pattern(map(), EvalTypes.runtime_value(), map()) :: EvalTypes.pattern_match_result()
  defp match_pattern(pattern, value, context)

  defp match_pattern(pattern, value, context) when is_map(pattern) do
    kind = normalize_pattern_kind(pattern["kind"] || pattern[:kind])

    case kind do
      :wildcard ->
        {:ok, %{}}

      :var ->
        name = pattern["name"] || pattern[:name]
        if is_binary(name), do: {:ok, %{name => value}}, else: {:ok, %{}}

      :literal ->
        expected = pattern["value"] || pattern[:value]
        if literal_pattern_match?(expected, value), do: {:ok, %{}}, else: :nomatch

      :int ->
        expected = pattern["value"] || pattern[:value]
        if expected == value, do: {:ok, %{}}, else: :nomatch

      :float ->
        expected = pattern["value"] || pattern[:value]
        if expected == value, do: {:ok, %{}}, else: :nomatch

      :string ->
        expected = pattern["value"] || pattern[:value]
        if expected == value, do: {:ok, %{}}, else: :nomatch

      :constructor ->
        tag = pattern["tag"] || pattern[:tag]
        arg_pattern = pattern["arg_pattern"] || pattern[:arg_pattern]
        bind_name = pattern["bind"] || pattern[:bind]
        name = to_string(pattern["name"] || pattern[:name] || "")

        match_result =
          cond do
            is_integer(tag) and is_map(arg_pattern) ->
              case value do
                {^tag, payload} -> match_pattern(arg_pattern, payload, context)
                _ -> match_constructor_by_name(name, arg_pattern, bind_name, pattern, value, context)
              end

            is_integer(tag) ->
              case value do
                {^tag, payload} ->
                  if is_binary(bind_name) and bind_name != "" do
                    {:ok, %{bind_name => payload}}
                  else
                    {:ok, %{}}
                  end

                ^tag ->
                  {:ok, %{}}

                _ ->
                  match_constructor_by_name(name, arg_pattern, bind_name, pattern, value, context)
              end

            true ->
              match_constructor_by_name(name, arg_pattern, bind_name, pattern, value, context)
          end

        case match_result do
          {:ok, bindings} when is_binary(bind_name) and bind_name != "" ->
            if Map.has_key?(bindings, bind_name) do
              {:ok, bindings}
            else
              {:ok, Map.put(bindings, bind_name, value)}
            end

          {:ok, _bindings} ->
            match_result

          :nomatch ->
            :nomatch
        end

      :tuple2 ->
        left = pattern["left"] || pattern[:left] || %{}
        right = pattern["right"] || pattern[:right] || %{}

        case value do
          {l, r} ->
            with {:ok, lb} <- match_pattern(left, l, context),
                 {:ok, rb} <- match_pattern(right, r, context) do
              {:ok, Map.merge(lb, rb)}
            end

          _ ->
            :nomatch
        end

      :tuple ->
        elements = pattern["elements"] || pattern[:elements] || []

        cond do
          is_tuple(value) and tuple_size(value) == length(elements) ->
            match_pattern_list(elements, Tuple.to_list(value), context)

          length(elements) == 2 ->
            case value do
              {l, r} ->
                match_pattern_list(elements, [l, r], context)

              _ ->
                :nomatch
            end

          true ->
            :nomatch
        end

      :alias ->
        alias_name = pattern["name"] || pattern[:name]
        inner = pattern["pattern"] || pattern[:pattern]

        case match_pattern(inner, value, context) do
          {:ok, bindings} when is_binary(alias_name) and alias_name != "" ->
            {:ok, Map.put(bindings, alias_name, value)}

          {:ok, bindings} ->
            {:ok, bindings}

          :nomatch ->
            :nomatch
        end

      _ ->
        :nomatch
    end
  end

  defp match_pattern(_pattern, _value, _context), do: :nomatch

  @spec normalize_pattern_kind(EvalTypes.runtime_value()) :: atom() | String.t() | nil
  defp normalize_pattern_kind("wildcard"), do: :wildcard
  defp normalize_pattern_kind("var"), do: :var
  defp normalize_pattern_kind("literal"), do: :literal
  defp normalize_pattern_kind("int"), do: :int
  defp normalize_pattern_kind("float"), do: :float
  defp normalize_pattern_kind("string"), do: :string
  defp normalize_pattern_kind("constructor"), do: :constructor
  defp normalize_pattern_kind("tuple2"), do: :tuple2
  defp normalize_pattern_kind("tuple"), do: :tuple
  defp normalize_pattern_kind("alias"), do: :alias
  defp normalize_pattern_kind(kind), do: kind

  @spec literal_pattern_match?(EvalTypes.runtime_value(), EvalTypes.runtime_value()) :: boolean()
  defp literal_pattern_match?("True", true), do: true
  defp literal_pattern_match?("False", false), do: true
  defp literal_pattern_match?(expected, value), do: expected == value

  @spec match_constructor_by_name(
          String.t(),
          map() | nil,
          String.t() | nil,
          map(),
          EvalTypes.runtime_value(),
          map()
        ) :: EvalTypes.pattern_match_result()
  defp match_constructor_by_name(name, arg_pattern, bind_name, pattern, value, context)
       when is_binary(name) do
    short_name = short_ctor_name(name)

    case value do
      true when name == "True" ->
        {:ok, %{}}

      false when name == "False" ->
        {:ok, %{}}

      [] when short_name == "[]" ->
        {:ok, %{}}

      [head | tail] when short_name == "::" ->
        match_constructor_args(pattern, arg_pattern, bind_name, [head, tail], context)

      0 when short_name == "Nothing" ->
        {:ok, %{}}

      nil when short_name == "Nothing" ->
        {:ok, %{}}

      scalar
      when short_name == "Just" and
             (is_integer(scalar) or is_float(scalar) or is_boolean(scalar) or is_binary(scalar)) and
             scalar != 0 ->
        match_constructor_args(pattern, arg_pattern, bind_name, [scalar], context)

      {1, payload} when short_name in ["Just", "Ok"] ->
        match_constructor_args(pattern, arg_pattern, bind_name, [payload], context)

      {0, payload} when short_name == "Err" ->
        match_constructor_args(pattern, arg_pattern, bind_name, [payload], context)

      {tag, payload} when is_integer(tag) ->
        case constructor_tag_for_name(short_name, context) do
          ^tag -> match_constructor_args(pattern, arg_pattern, bind_name, [payload], context)
          _ -> :nomatch
        end

      %{"ctor" => ^name, "args" => args} when is_list(args) ->
        match_constructor_args(pattern, arg_pattern, bind_name, args, context)

      %{ctor: ^name, args: args} when is_list(args) ->
        match_constructor_args(pattern, arg_pattern, bind_name, args, context)

      %{"ctor" => ^short_name, "args" => args} when is_list(args) ->
        match_constructor_args(pattern, arg_pattern, bind_name, args, context)

      %{ctor: ^short_name, args: args} when is_list(args) ->
        match_constructor_args(pattern, arg_pattern, bind_name, args, context)

      _ ->
        :nomatch
    end
  end

  @spec constructor_tag_for_name(String.t(), map()) :: integer() | nil
  defp constructor_tag_for_name(short_name, context) when is_binary(short_name) and is_map(context) do
    context
    |> Map.get(:constructor_tags, [])
    |> Enum.find_value(fn
      %{ctor: ctor, tag: tag} when is_integer(tag) ->
        if short_ctor_name(to_string(ctor)) == short_name, do: tag, else: nil

      %{"ctor" => ctor, "tag" => tag} when is_integer(tag) ->
        if short_ctor_name(to_string(ctor)) == short_name, do: tag, else: nil

      _ ->
        nil
    end)
  end

  defp constructor_tag_for_name(_short_name, _context), do: nil

  @spec match_constructor_args(
          map(),
          map() | nil,
          String.t() | nil,
          list(),
          map()
        ) :: EvalTypes.pattern_match_result()
  defp match_constructor_args(pattern, arg_pattern, bind_name, args, context) when is_list(args) do
    cond do
      is_map(arg_pattern) and length(args) == 1 ->
        with {:ok, bindings} <- match_pattern(arg_pattern, hd(args), context) do
          if is_binary(bind_name) and bind_name != "" do
            {:ok, Map.put(bindings, bind_name, hd(args))}
          else
            {:ok, bindings}
          end
        end

      is_map(arg_pattern) and length(args) > 1 ->
        with {:ok, bindings} <- match_pattern(arg_pattern, List.to_tuple(args), context) do
          if is_binary(bind_name) and bind_name != "" do
            {:ok, Map.put(bindings, bind_name, List.to_tuple(args))}
          else
            {:ok, bindings}
          end
        end

      is_binary(bind_name) and bind_name != "" and length(args) == 1 ->
        {:ok, %{bind_name => hd(args)}}

      is_binary(bind_name) and bind_name != "" ->
        :nomatch

      true ->
        arg_patterns = pattern["args"] || pattern[:args] || []
        match_pattern_list(arg_patterns, args, context)
    end
  end

  @spec match_pattern_list(list(), list(), map()) :: EvalTypes.pattern_match_result()
  defp match_pattern_list(patterns, values, context)
       when is_list(patterns) and is_list(values) and length(patterns) == length(values) do
    Enum.zip(patterns, values)
    |> Enum.reduce_while({:ok, %{}}, fn {pat, val}, {:ok, acc} ->
      case match_pattern(pat, val, context) do
        {:ok, b} -> {:cont, {:ok, Map.merge(acc, b)}}
        :nomatch -> {:halt, :nomatch}
      end
    end)
  end

  defp match_pattern_list(_patterns, _values, _context), do: :nomatch

  @spec field_access(EvalTypes.runtime_value(), String.t()) :: EvalTypes.runtime_value()
  defp field_access(base, field) when is_map(base) and is_binary(field) do
    generic_map_value(base, field)
  end

  defp field_access(base, field) when is_map(base) and is_atom(field),
    do: generic_map_value(base, field)

  defp field_access(_base, _field), do: nil

  @spec numeric_operand_from_var(
          String.t() | atom() | nil,
          EvalTypes.env(),
          map(),
          EvalTypes.eval_stack()
        ) :: {:ok, number()} | {:error, EvalTypes.eval_error()}
  defp numeric_operand_from_var(name, env, context, stack)
       when is_binary(name) and is_map(env) and is_map(context) and is_list(stack) do
    cond do
      is_number(value = numeric_env_value(env, name)) ->
        {:ok, value}

      true ->
        case resolve_zero_arity_value(name, context, stack) do
          {:ok, value} when is_number(value) ->
            {:ok, value}

          _ ->
            case maybe_evaluate(%{"op" => :var, "name" => name}, env, context, stack) do
              {:ok, value} when is_number(value) -> {:ok, value}
              other -> other
            end
        end
    end
  end

  defp numeric_operand_from_var(_name, _env, _context, _stack), do: {:error, :invalid_operand}

  @spec numeric_env_value(EvalTypes.env(), String.t() | atom()) :: number() | nil
  defp numeric_env_value(env, name) when is_map(env) and is_binary(name) do
    value =
      case Map.fetch(env, name) do
        {:ok, value} ->
          value

        :error ->
          Enum.find_value(env, fn
            {key, value} when is_atom(key) ->
              if Atom.to_string(key) == name, do: value, else: nil

            _ ->
              nil
          end)
      end

    case value do
      value when is_number(value) -> value
      _ -> nil
    end
  end

  defp numeric_env_value(_env, _name), do: nil

  @spec normalize_record_fields(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
  defp normalize_record_fields(fields) when is_map(fields), do: Map.to_list(fields)

  defp normalize_record_fields(fields) when is_list(fields) do
    fields
    |> Enum.reduce([], fn
      {k, v}, acc ->
        [{k, v} | acc]

      %{"name" => name, "expr" => expr}, acc when is_binary(name) ->
        [{name, expr} | acc]

      %{name: name, expr: expr}, acc when is_binary(name) ->
        [{name, expr} | acc]

      %{"field" => name, "expr" => expr}, acc when is_binary(name) ->
        [{name, expr} | acc]

      %{field: name, expr: expr}, acc when is_binary(name) ->
        [{name, expr} | acc]

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp normalize_record_fields(_), do: []

  @spec compare(atom(), EvalTypes.runtime_value(), EvalTypes.runtime_value()) :: boolean()
  defp compare(kind, left, right) do
    normalized = kind |> to_string() |> String.downcase()

    case normalized do
      "eq" -> values_equal?(left, right)
      "neq" -> not values_equal?(left, right)
      "lt" -> left < right
      "lte" -> left <= right
      "gt" -> left > right
      "gte" -> left >= right
      _ -> false
    end
  end

  defp values_equal?(left, right) do
    case {maybe_value(left), maybe_value(right)} do
      {:invalid, :invalid} ->
        result_values_equal?(left, right)

      {left_maybe, right_maybe} ->
        left_maybe == right_maybe
    end
  end

  defp result_values_equal?(left, right) do
    case {result_value(left), result_value(right)} do
      {:invalid, :invalid} -> left == right
      {left_result, right_result} -> left_result == right_result
    end
  end

  @spec comparison_operator_kind(String.t()) :: atom()
  defp comparison_operator_kind("__eq__"), do: :eq
  defp comparison_operator_kind("__neq__"), do: :neq
  defp comparison_operator_kind("__lt__"), do: :lt
  defp comparison_operator_kind("__lte__"), do: :lte
  defp comparison_operator_kind("__gt__"), do: :gt
  defp comparison_operator_kind("__gte__"), do: :gte
  defp comparison_operator_kind(_), do: :eq
end
