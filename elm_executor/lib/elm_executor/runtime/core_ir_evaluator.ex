defmodule ElmExecutor.Runtime.CoreIREvaluator do
  @moduledoc """
  Deterministic CoreIR expression evaluator used by runtime semantics.
  """

  @type function_def :: %{
          module: String.t(),
          name: String.t(),
          params: [String.t()],
          body: map()
        }

  @type context :: %{
          optional(:functions) => %{
            optional({String.t(), String.t(), non_neg_integer()}) => function_def()
          },
          optional(:module) => String.t(),
          optional(:source_module) => String.t()
        }

  @spec evaluate(map(), map(), context()) :: {:ok, term()} | {:error, term()}
  def evaluate(expr, env \\ %{}, context \\ %{})
      when is_map(expr) and is_map(env) and is_map(context) do
    do_evaluate(expr, env, context, [])
  end

  @spec index_functions(map() | nil) :: map()
  def index_functions(%{modules: modules}) when is_list(modules),
    do: index_functions(%{"modules" => modules})

  def index_functions(%{"modules" => modules}) when is_list(modules) do
    Enum.reduce(modules, %{}, fn mod, acc ->
      module_name = to_string(mod["name"] || mod[:name] || "Main")
      decls = mod["declarations"] || mod[:declarations] || []

      Enum.reduce(decls, acc, fn decl, a ->
        if to_string(decl["kind"] || decl[:kind] || "") == "function" do
          name = to_string(decl["name"] || decl[:name] || "")
          body = decl["expr"] || decl[:expr]

          params =
            normalize_params(decl["params"] || decl[:params] || decl["args"] || decl[:args])

          Map.put(a, {module_name, name, length(params)}, %{
            module: module_name,
            name: name,
            params: params,
            body: body
          })
        else
          a
        end
      end)
    end)
  end

  def index_functions(_), do: %{}

  @spec normalize_params(term()) :: term()
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

  @spec do_evaluate(term(), term(), term(), term()) :: term()
  defp do_evaluate(expr, env, context, stack)
       when is_map(expr) and is_map(env) and is_map(context) do
    op = expr["op"] || expr[:op]

    case op do
      :int_literal ->
        {:ok, expr["value"] || expr[:value]}

      :float_literal ->
        {:ok, expr["value"] || expr[:value]}

      :bool_literal ->
        {:ok, expr["value"] || expr[:value]}

      :char_literal ->
        {:ok, expr["value"] || expr[:value]}

      :string_literal ->
        {:ok, expr["value"] || expr[:value]}

      :expr ->
        inner =
          expr["expr"] || expr[:expr] || expr["value_expr"] || expr[:value_expr] ||
            expr["in_expr"] || expr[:in_expr]

        maybe_evaluate(inner, env, context, stack)

      :var ->
        name = expr["name"] || expr[:name]

        value =
          if is_binary(name) and Map.has_key?(env, name) do
            Map.get(env, name)
          else
            case String.downcase(to_string(name || "")) do
              "pi" -> :math.pi()
              "e" -> :math.exp(1.0)
              "empty" -> []
              _ -> nil
            end
          end

        if value == nil and is_binary(name) do
          {:ok, {:function_ref, name}}
        else
          {:ok, value}
        end

      :var_resolved ->
        value_expr = expr["value_expr"] || expr[:value_expr]
        maybe_evaluate(value_expr, env, context, stack)

      :field_access ->
        field = expr["field"] || expr[:field]

        with {:ok, base} <-
               maybe_evaluate_with_env_lookup(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, field_access(base, field)}
        end

      :field_call ->
        field = expr["field"] || expr[:field]
        args = expr["args"] || expr[:args] || []

        with {:ok, base} <-
               maybe_evaluate_with_env_lookup(expr["arg"] || expr[:arg], env, context, stack),
             callable when not is_nil(callable) <- field_access(base, field),
             {:ok, values} <-
               args |> Enum.map(&maybe_evaluate(&1, env, context, stack)) |> collect_ok(),
             {:ok, value} <- call_callable(callable, values, env, context, stack) do
          {:ok, value}
        else
          nil -> {:error, {:unknown_field_call, field}}
          {:error, _} = err -> err
          _ -> {:error, {:invalid_field_call, field}}
        end

      :record_literal ->
        fields = expr["fields"] || expr[:fields] || %{}

        map =
          normalize_record_fields(fields)
          |> Enum.reduce(%{}, fn {k, v}, acc ->
            case maybe_evaluate(v, env, context, stack) do
              {:ok, value} -> Map.put(acc, to_string(k), value)
              _ -> Map.put(acc, to_string(k), nil)
            end
          end)

        {:ok, map}

      :list_literal ->
        list = expr["items"] || expr[:items] || expr["elements"] || expr[:elements] || []

        list
        |> Enum.map(&maybe_evaluate(&1, env, context, stack))
        |> collect_ok()

      :tuple2 ->
        with {:ok, left} <- maybe_evaluate(expr["left"] || expr[:left], env, context, stack),
             {:ok, right} <- maybe_evaluate(expr["right"] || expr[:right], env, context, stack) do
          {:ok, {left, right}}
        end

      :tuple_first_expr ->
        with {:ok, value} <- maybe_evaluate(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, tuple_first(value)}
        end

      :tuple_second_expr ->
        with {:ok, value} <- maybe_evaluate(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, tuple_second(value)}
        end

      :tuple_first ->
        with {:ok, value} <- maybe_evaluate(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, tuple_first(value)}
        end

      :tuple_second ->
        with {:ok, value} <- maybe_evaluate(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, tuple_second(value)}
        end

      :string_length_expr ->
        with {:ok, value} <- maybe_evaluate(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, if(is_binary(value), do: String.length(value), else: 0)}
        end

      :char_from_code_expr ->
        with {:ok, value} <- maybe_evaluate(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, char_from_code(value)}
        end

      :let_in ->
        name = expr["name"] || expr[:name]
        value_expr = expr["value_expr"] || expr[:value_expr]
        in_expr = expr["in_expr"] || expr[:in_expr]

        with {:ok, value} <- maybe_evaluate(value_expr, env, context, stack) do
          next_env = if is_binary(name), do: Map.put(env, name, value), else: env
          maybe_evaluate(in_expr, next_env, context, stack)
        end

      :if ->
        with {:ok, condition} <- maybe_evaluate(expr["cond"] || expr[:cond], env, context, stack) do
          if condition == true do
            maybe_evaluate(expr["then_expr"] || expr[:then_expr], env, context, stack)
          else
            maybe_evaluate(expr["else_expr"] || expr[:else_expr], env, context, stack)
          end
        end

      :compare ->
        with {:ok, left} <- maybe_evaluate(expr["left"] || expr[:left], env, context, stack),
             {:ok, right} <- maybe_evaluate(expr["right"] || expr[:right], env, context, stack) do
          {:ok, compare(expr["kind"] || expr[:kind], left, right)}
        end

      :constructor_call ->
        target = to_string(expr["target"] || expr[:target] || "")
        args = expr["args"] || expr[:args] || []

        with {:ok, values} <-
               args |> Enum.map(&maybe_evaluate(&1, env, context, stack)) |> collect_ok() do
          short = short_ctor_name(target)

          case {short, values} do
            {"True", []} -> {:ok, true}
            {"False", []} -> {:ok, false}
            _ -> {:ok, %{"ctor" => short, "args" => values}}
          end
        end

      :lambda ->
        params = normalize_params(expr["params"] || expr[:params] || expr["args"] || expr[:args])
        body = expr["body"] || expr[:body]
        {:ok, {:closure, params, body, env}}

      :qualified_call ->
        target = to_string(expr["target"] || expr[:target] || "")
        args = expr["args"] || expr[:args] || []
        call_function(target, args, env, context, stack)

      :call ->
        name = to_string(expr["name"] || expr[:name] || "")
        args = expr["args"] || expr[:args] || []
        call_function(name, args, env, context, stack)

      :case ->
        with {:ok, subject} <-
               maybe_evaluate_with_env_lookup(
                 expr["subject"] || expr[:subject],
                 env,
                 context,
                 stack
               ) do
          branches = expr["branches"] || expr[:branches] || []
          evaluate_case_branches(branches, subject, env, context, stack)
        end

      _ ->
        value = expr["value"] || expr[:value]

        cond do
          is_integer(value) or is_float(value) or is_boolean(value) or is_binary(value) ->
            {:ok, value}

          true ->
            {:error, {:unsupported_op, op}}
        end
    end
  end

  defp do_evaluate(_expr, _env, _context, _stack), do: {:error, :invalid_expr}

  @spec maybe_evaluate(term(), term(), term(), term()) :: term()
  defp maybe_evaluate(expr, env, context, stack) when is_map(expr) do
    if Map.has_key?(expr, "op") or Map.has_key?(expr, :op) do
      do_evaluate(expr, env, context, stack)
    else
      {:ok, expr}
    end
  end

  defp maybe_evaluate(value, _env, _context, _stack), do: {:ok, value}

  @spec maybe_evaluate_with_env_lookup(term(), map(), term(), term()) :: term()
  defp maybe_evaluate_with_env_lookup(expr, env, context, stack)
       when is_binary(expr) and is_map(env) do
    case Map.fetch(env, expr) do
      {:ok, value} -> {:ok, value}
      :error -> maybe_evaluate(expr, env, context, stack)
    end
  end

  defp maybe_evaluate_with_env_lookup(expr, env, context, stack),
    do: maybe_evaluate(expr, env, context, stack)

  @spec collect_ok(term()) :: term()
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

  @spec call_function(term(), term(), term(), term(), term()) :: term()
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

  @spec apply_closure(term(), term(), term(), term(), term(), term(), term()) :: term()
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

  @spec eval_ui_builtin(term(), term()) :: term()
  defp eval_ui_builtin(name, values) when is_binary(name) and is_list(values) do
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
        with {:ok, normalized_bitmap_id} <- normalize_bitmap_id(bitmap_id),
             {:ok, {x, y, w, h}} <- normalize_rect(bounds) do
          {:ok,
           ui_node("bitmapInRect", Enum.map([normalized_bitmap_id, x, y, w, h], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawbitmapinrect", [bitmap_id, x, y, w, h]} ->
        with {:ok, normalized_bitmap_id} <- normalize_bitmap_id(bitmap_id),
             true <- Enum.all?([x, y, w, h], &is_integer/1) do
          {:ok,
           ui_node("bitmapInRect", Enum.map([normalized_bitmap_id, x, y, w, h], &expr_node/1))}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.drawrotatedbitmap", [bitmap_id, src_rect, angle, center]} ->
        with {:ok, normalized_bitmap_id} <- normalize_bitmap_id(bitmap_id),
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
        with {:ok, normalized_bitmap_id} <- normalize_bitmap_id(bitmap_id),
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
             {:ok, {x, y}} <- normalize_point(pos) do
          {:ok,
           ui_node(
             "textLabel",
             [
               expr_node(normalized_font_id),
               expr_node(x),
               expr_node(y),
               expr_node(text)
             ]
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.text", [font_id, bounds, value]} ->
        with {:ok, normalized_font_id} <- normalize_font_id(font_id),
             {:ok, {x, y, w, h}} <- normalize_rect(bounds),
             true <- is_binary(value) do
          {:ok,
           ui_node(
             "text",
             Enum.map([normalized_font_id, x, y, w, h, value], &expr_node/1)
           )}
        else
          _ -> :no_builtin
        end

      {"pebble.ui.context", [settings, ops]} when is_list(settings) and is_list(ops) ->
        {:ok, {:ui_context, settings, ops}}

      {"pebble.ui.group", [{:ui_context, _settings, ops}]} ->
        {:ok, ui_node("group", ui_children_from_value(ops))}

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

  @spec eval_ui_color_builtin(String.t(), term()) :: term()
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

  @spec eval_builtin(term(), term(), term(), term(), term()) :: term()
  defp eval_builtin(name, values, env, context, stack)
       when is_binary(name) and is_list(values) and is_map(env) and is_map(context) and
              is_list(stack) do
    normalized_full = normalize_builtin_name(name)
    {module_name, function_name} = split_builtin_name(normalized_full)
    allow_legacy_fallback = legacy_fallback_allowed_module?(module_name)
    force_legacy_operator_fallback = String.starts_with?(function_name, "__")

    if String.starts_with?(normalized_full, "elm.kernel.json.") do
      json_name = String.replace_prefix(normalized_full, "elm.kernel.json.", "")
      eval_kernel_json_builtin(json_name, values, env, context, stack)
    else
      case eval_builtin_by_module(normalized_full, values, env, context, stack) do
        {:ok, _} = ok ->
          ok

        {:error, _} = err ->
          err

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

  @spec eval_builtin_by_module(String.t(), term(), term(), term(), term()) :: term()
  defp eval_builtin_by_module(normalized_full, values, env, context, stack)
       when is_binary(normalized_full) and is_list(values) and is_map(env) and is_map(context) and
              is_list(stack) do
    {module_name, function_name} = split_builtin_name(normalized_full)

    case module_name do
      "list" ->
        eval_list_builtin(function_name, values, env, context, stack)

      "result" ->
        eval_result_builtin(function_name, values, env, context, stack)

      "maybe" ->
        eval_maybe_builtin(function_name, values, env, context, stack)

      "task" ->
        eval_task_builtin(function_name, values, env, context, stack)

      "basics" ->
        eval_basics_builtin(function_name, values, env, context, stack)

      "bitwise" ->
        eval_bitwise_builtin(function_name, values)

      "bit" ->
        eval_bitwise_builtin(function_name, values)

      "string" ->
        eval_string_builtin(function_name, values)

      "dict" ->
        eval_dict_builtin(function_name, values)

      "array" ->
        eval_array_builtin(function_name, values, env, context, stack)

      "set" ->
        eval_set_builtin(function_name, values)

      "char" ->
        eval_char_builtin(function_name, values)

      "url" ->
        eval_url_builtin(function_name, values)

      "time" ->
        eval_time_builtin(function_name, values)

      "elm.kernel.time" ->
        eval_kernel_time_builtin(function_name, values)

      "debug" ->
        eval_debug_builtin(function_name, values)

      "parser" ->
        eval_parser_builtin(function_name, values, env, context, stack)

      "parser.advanced" ->
        eval_parser_builtin(function_name, values, env, context, stack)

      "tuple" ->
        eval_tuple_builtin(function_name, values, env, context, stack)

      "pebble.ui" ->
        eval_ui_builtin(normalized_full, values)

      "pebble.ui.color" ->
        eval_ui_color_builtin(function_name, values)

      "json.decode" ->
        eval_json_decode_builtin(function_name, values, env, context, stack)

      "json.encode" ->
        eval_json_encode_builtin(function_name, values, env, context, stack)

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

  @spec eval_list_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_list_builtin("map", [fun, subject], env, context, stack),
    do: map_dispatch(fun, subject, env, context, stack)

  defp eval_list_builtin("map2", [fun, xs, ys], env, context, stack)
       when is_list(xs) and is_list(ys),
       do: list_map2_with_callable(fun, xs, ys, env, context, stack)

  defp eval_list_builtin("reverse", [xs], _env, _context, _stack) when is_list(xs),
    do: {:ok, Enum.reverse(xs)}

  defp eval_list_builtin("append", [xs, ys], _env, _context, _stack)
       when is_list(xs) and is_list(ys),
       do: {:ok, xs ++ ys}

  defp eval_list_builtin("cons", [head, tail], _env, _context, _stack) when is_list(tail),
    do: {:ok, [head | tail]}

  defp eval_list_builtin("append", [xs], _env, _context, _stack) when is_list(xs),
    do: {:ok, {:builtin_partial, "List.append", [xs]}}

  defp eval_list_builtin("foldl", [fun, init, xs], env, context, stack) when is_list(xs),
    do: foldl_with_callable(fun, init, xs, env, context, stack)

  defp eval_list_builtin("foldr", [fun, init, xs], env, context, stack) when is_list(xs),
    do: foldr_with_callable(fun, init, xs, env, context, stack)

  defp eval_list_builtin("all", [fun], _env, _context, _stack),
    do: {:ok, {:builtin_partial, "List.all", [fun]}}

  defp eval_list_builtin("any", [fun], _env, _context, _stack),
    do: {:ok, {:builtin_partial, "List.any", [fun]}}

  defp eval_list_builtin("filter", [fun, xs], env, context, stack) when is_list(xs),
    do: filter_with_callable(fun, xs, env, context, stack)

  defp eval_list_builtin("map", [fun], _env, _context, _stack),
    do: {:ok, {:builtin_partial, "List.map", [fun]}}

  defp eval_list_builtin("filter", [fun], _env, _context, _stack),
    do: {:ok, {:builtin_partial, "List.filter", [fun]}}

  defp eval_list_builtin("foldl", [fun, init], _env, _context, _stack),
    do: {:ok, {:builtin_partial, "List.foldl", [fun, init]}}

  defp eval_list_builtin("foldr", [fun, init], _env, _context, _stack),
    do: {:ok, {:builtin_partial, "List.foldr", [fun, init]}}

  defp eval_list_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_result_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_result_builtin("andthen", [fun, result], env, context, stack),
    do: result_and_then_with_callable(fun, result, env, context, stack)

  defp eval_result_builtin("map2", [a, b, c], env, context, stack),
    do: map2_dispatch(a, b, c, env, context, stack)

  defp eval_result_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_maybe_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_maybe_builtin("withdefault", [default, maybe_or_result], _env, _context, _stack),
    do: {:ok, with_default_maybe_or_result(default, maybe_or_result)}

  defp eval_maybe_builtin("map2", [a, b, c], env, context, stack),
    do: map2_dispatch(a, b, c, env, context, stack)

  defp eval_maybe_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_task_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_task_builtin("map2", [a, b, c], env, context, stack),
    do: map2_dispatch(a, b, c, env, context, stack)

  defp eval_task_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_basics_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_basics_builtin("map2", [a, b, c], env, context, stack),
    do: map2_dispatch(a, b, c, env, context, stack)

  defp eval_basics_builtin("negate", [value], _env, _context, _stack) when is_number(value),
    do: {:ok, -value}

  defp eval_basics_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_bitwise_builtin(String.t(), term()) :: term()
  defp eval_bitwise_builtin("and", [a, b]) when is_integer(a) and is_integer(b),
    do: {:ok, Bitwise.band(a, b)}

  defp eval_bitwise_builtin("or", [a, b]) when is_integer(a) and is_integer(b),
    do: {:ok, Bitwise.bor(a, b)}

  defp eval_bitwise_builtin("xor", [a, b]) when is_integer(a) and is_integer(b),
    do: {:ok, Bitwise.bxor(a, b)}

  defp eval_bitwise_builtin("complement", [a]) when is_integer(a), do: {:ok, Bitwise.bnot(a)}

  defp eval_bitwise_builtin("and", [a, b]) when is_number(a) and is_number(b),
    do: {:ok, Bitwise.band(trunc(a), trunc(b))}

  defp eval_bitwise_builtin("or", [a, b]) when is_number(a) and is_number(b),
    do: {:ok, Bitwise.bor(trunc(a), trunc(b))}

  defp eval_bitwise_builtin("xor", [a, b]) when is_number(a) and is_number(b),
    do: {:ok, Bitwise.bxor(trunc(a), trunc(b))}

  defp eval_bitwise_builtin("complement", [a]) when is_number(a),
    do: {:ok, Bitwise.bnot(trunc(a))}

  defp eval_bitwise_builtin("shiftleftby", [offset, value])
       when is_integer(offset) and is_integer(value) and offset >= 0,
       do: {:ok, Bitwise.bsl(value, offset)}

  defp eval_bitwise_builtin("shiftleftby", [offset, value])
       when is_number(offset) and is_number(value) do
    o = trunc(offset)
    v = trunc(value)
    if o >= 0, do: {:ok, Bitwise.bsl(v, o)}, else: {:ok, Bitwise.bsr(v, -o)}
  end

  defp eval_bitwise_builtin("shiftrightby", [offset, value])
       when is_integer(offset) and is_integer(value) and offset >= 0,
       do: {:ok, Bitwise.bsr(value, offset)}

  defp eval_bitwise_builtin("shiftrightby", [offset, value])
       when is_number(offset) and is_number(value) do
    o = trunc(offset)
    v = trunc(value)
    if o >= 0, do: {:ok, Bitwise.bsr(v, o)}, else: {:ok, Bitwise.bsl(v, -o)}
  end

  defp eval_bitwise_builtin("shiftrightzfby", [offset, value])
       when is_integer(offset) and is_integer(value) and offset >= 0 do
    shifted =
      value
      |> Bitwise.band(0xFFFFFFFF)
      |> Bitwise.bsr(offset)

    {:ok, shifted}
  end

  defp eval_bitwise_builtin("shiftrightzfby", [offset, value])
       when is_number(offset) and is_number(value) do
    o = trunc(offset)
    v = trunc(value)

    if o >= 0 do
      shifted = v |> Bitwise.band(0xFFFFFFFF) |> Bitwise.bsr(o)
      {:ok, shifted}
    else
      {:ok, Bitwise.bsl(v, -o)}
    end
  end

  defp eval_bitwise_builtin(_function_name, _values), do: :no_builtin

  @spec eval_string_builtin(String.t(), term()) :: term()
  defp eval_string_builtin("append", [a, b]) when is_binary(a) and is_binary(b), do: {:ok, a <> b}

  defp eval_string_builtin("fromint", [value]) when is_integer(value),
    do: {:ok, Integer.to_string(value)}

  defp eval_string_builtin("fromfloat", [value]) when is_number(value),
    do: {:ok, float_to_elm_string(value)}

  defp eval_string_builtin(_function_name, _values), do: :no_builtin

  @spec eval_dict_builtin(String.t(), term()) :: term()
  defp eval_dict_builtin("fromlist", [pairs]) when is_list(pairs),
    do: {:ok, Map.new(pairs)}

  defp eval_dict_builtin("tolist", [dict]) when is_map(dict),
    do: {:ok, dict_to_list(dict)}

  defp eval_dict_builtin("get", [key, dict]) when is_map(dict),
    do: {:ok, maybe_map_get_ctor(dict, key)}

  defp eval_dict_builtin("insert", [key, value, dict]) when is_map(dict),
    do: {:ok, Map.put(dict, key, value)}

  defp eval_dict_builtin(_function_name, _values), do: :no_builtin

  @spec eval_array_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_array_builtin("fromlist", [xs], _env, _context, _stack) when is_list(xs),
    do: {:ok, xs}

  defp eval_array_builtin("repeat", [n, value], _env, _context, _stack)
       when is_integer(n) and n >= 0,
       do: {:ok, List.duplicate(value, n)}

  defp eval_array_builtin("length", [xs], _env, _context, _stack) when is_list(xs),
    do: {:ok, length(xs)}

  defp eval_array_builtin("isempty", [xs], _env, _context, _stack) when is_list(xs),
    do: {:ok, xs == []}

  defp eval_array_builtin("slice", [start, stop, xs], _env, _context, _stack)
       when is_integer(start) and is_integer(stop) and is_list(xs),
       do: {:ok, list_slice(xs, start, stop)}

  defp eval_array_builtin("foldl", [fun, init, xs], env, context, stack) when is_list(xs),
    do: foldl_with_callable(fun, init, xs, env, context, stack)

  defp eval_array_builtin("foldr", [fun, init, xs], env, context, stack) when is_list(xs),
    do: foldr_with_callable(fun, init, xs, env, context, stack)

  defp eval_array_builtin("initialize", [n, fun], env, context, stack)
       when is_integer(n) and n >= 0,
       do: initialize_with_callable(n, fun, env, context, stack)

  defp eval_array_builtin("get", [idx, xs], _env, _context, _stack)
       when is_integer(idx) and is_list(xs),
       do: {:ok, maybe_get_ctor(xs, idx)}

  defp eval_array_builtin("set", [idx, value, xs], _env, _context, _stack)
       when is_integer(idx) and is_list(xs),
       do: {:ok, list_set(xs, idx, value)}

  defp eval_array_builtin("push", [value, xs], _env, _context, _stack) when is_list(xs),
    do: {:ok, xs ++ [value]}

  defp eval_array_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_set_builtin(String.t(), term()) :: term()
  defp eval_set_builtin("fromlist", [items]) when is_list(items),
    do: {:ok, items |> Enum.uniq() |> Enum.sort()}

  defp eval_set_builtin("tolist", [items]) when is_list(items), do: {:ok, items}
  defp eval_set_builtin(_function_name, _values), do: :no_builtin

  @spec eval_char_builtin(String.t(), term()) :: term()
  defp eval_char_builtin(_function_name, _values), do: :no_builtin

  @spec eval_url_builtin(String.t(), term()) :: term()
  defp eval_url_builtin("percentencode", [value]) when is_binary(value) do
    {:ok, URI.encode(value, &URI.char_unreserved?/1)}
  end

  defp eval_url_builtin("percentdecode", [value]) when is_binary(value) do
    try do
      {:ok, maybe_ctor({:just, URI.decode(value)})}
    rescue
      _ -> {:ok, maybe_ctor(:nothing)}
    end
  end

  defp eval_url_builtin(_function_name, _values), do: :no_builtin

  @spec eval_time_builtin(String.t(), term()) :: term()
  defp eval_time_builtin("millistoposix", [value]) when is_integer(value),
    do: {:ok, %{"ctor" => "Posix", "args" => [value]}}

  defp eval_time_builtin("millistoposix", [value]) when is_number(value),
    do: {:ok, %{"ctor" => "Posix", "args" => [trunc(value)]}}

  defp eval_time_builtin("posixtomillis", [value]) do
    case time_posix_millis(value) do
      {:ok, millis} -> {:ok, millis}
      :error -> :no_builtin
    end
  end

  defp eval_time_builtin("toadjustedminutes", [zone, posix]) do
    with {:ok, {default_offset, eras}} <- time_zone_parts(zone),
         {:ok, millis} <- time_posix_millis(posix) do
      posix_minutes = floor(millis / 60_000)
      {:ok, time_adjusted_minutes(default_offset, posix_minutes, eras)}
    else
      _ -> :no_builtin
    end
  end

  defp eval_time_builtin("pointone", []), do: {:ok, 100}
  defp eval_time_builtin(_function_name, _values), do: :no_builtin

  @spec eval_kernel_time_builtin(String.t(), term()) :: term()
  defp eval_kernel_time_builtin("nowmillis", [_unit]),
    do: {:ok, System.system_time(:millisecond)}

  defp eval_kernel_time_builtin("zoneoffsetminutes", [_unit]),
    do: {:ok, kernel_zone_offset_minutes()}

  defp eval_kernel_time_builtin("every", [_interval, _tagger]),
    do: {:ok, 1}

  defp eval_kernel_time_builtin(_function_name, _values), do: :no_builtin

  @spec time_posix_millis(term()) :: {:ok, integer()} | :error
  defp time_posix_millis(value) when is_integer(value), do: {:ok, value}
  defp time_posix_millis(value) when is_float(value), do: {:ok, trunc(value)}

  defp time_posix_millis(%{"ctor" => "Posix", "args" => [millis]}) when is_integer(millis),
    do: {:ok, millis}

  defp time_posix_millis(%{"ctor" => "Posix", "args" => [millis]}) when is_float(millis),
    do: {:ok, trunc(millis)}

  defp time_posix_millis(%{ctor: "Posix", args: [millis]}) when is_integer(millis),
    do: {:ok, millis}

  defp time_posix_millis(%{ctor: "Posix", args: [millis]}) when is_float(millis),
    do: {:ok, trunc(millis)}

  defp time_posix_millis(_), do: :error

  @spec time_zone_parts(term()) :: {:ok, {integer(), list()}} | :error
  defp time_zone_parts(%{"ctor" => "Zone", "args" => [default_offset, eras]})
       when is_integer(default_offset) and is_list(eras),
       do: {:ok, {default_offset, eras}}

  defp time_zone_parts(%{ctor: "Zone", args: [default_offset, eras]})
       when is_integer(default_offset) and is_list(eras),
       do: {:ok, {default_offset, eras}}

  defp time_zone_parts(_), do: :error

  @spec time_adjusted_minutes(integer(), integer(), list()) :: integer()
  defp time_adjusted_minutes(default_offset, posix_minutes, []),
    do: posix_minutes + default_offset

  defp time_adjusted_minutes(default_offset, posix_minutes, [era | older_eras]) do
    case time_era_parts(era) do
      {:ok, start, offset} ->
        if start < posix_minutes do
          posix_minutes + offset
        else
          time_adjusted_minutes(default_offset, posix_minutes, older_eras)
        end

      :error ->
        time_adjusted_minutes(default_offset, posix_minutes, older_eras)
    end
  end

  @spec time_era_parts(term()) :: {:ok, integer(), integer()} | :error
  defp time_era_parts(%{"start" => start, "offset" => offset})
       when is_integer(start) and is_integer(offset),
       do: {:ok, start, offset}

  defp time_era_parts(%{start: start, offset: offset})
       when is_integer(start) and is_integer(offset),
       do: {:ok, start, offset}

  defp time_era_parts(_), do: :error

  @spec kernel_zone_offset_minutes() :: integer()
  defp kernel_zone_offset_minutes do
    local_seconds =
      :calendar.local_time()
      |> :calendar.datetime_to_gregorian_seconds()

    utc_seconds =
      :calendar.universal_time()
      |> :calendar.datetime_to_gregorian_seconds()

    div(local_seconds - utc_seconds, 60)
  end

  @spec eval_debug_builtin(String.t(), term()) :: term()
  defp eval_debug_builtin("tostring", [value]), do: {:ok, elm_debug_to_string(value)}
  defp eval_debug_builtin(_function_name, _values), do: :no_builtin

  @spec eval_parser_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_parser_builtin("run", [parser, source], env, context, stack) when is_binary(source),
    do: call_callable(parser, [source], env, context, stack)

  defp eval_parser_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_tuple_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_tuple_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_json_decode_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_json_decode_builtin("decodestring", [decoder, source], env, context, stack),
    do: eval_kernel_json_builtin("runonstring", [decoder, source], env, context, stack)

  defp eval_json_decode_builtin("decodevalue", [decoder, value], env, context, stack),
    do: eval_kernel_json_builtin("run", [decoder, value], env, context, stack)

  defp eval_json_decode_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

  @spec eval_json_encode_builtin(String.t(), term(), term(), term(), term()) :: term()
  defp eval_json_encode_builtin("string", [value], _env, _context, _stack) when is_binary(value),
    do: {:ok, value}

  defp eval_json_encode_builtin("int", [value], _env, _context, _stack) when is_integer(value),
    do: {:ok, value}

  defp eval_json_encode_builtin("float", [value], _env, _context, _stack) when is_number(value),
    do: {:ok, value * 1.0}

  defp eval_json_encode_builtin("bool", [value], _env, _context, _stack) when is_boolean(value),
    do: {:ok, value}

  defp eval_json_encode_builtin("null", [_value], _env, _context, _stack), do: {:ok, nil}

  defp eval_json_encode_builtin("list", [encoder, items], env, context, stack)
       when is_list(items) do
    items
    |> Enum.map(&call_callable(encoder, [&1], env, context, stack))
    |> collect_ok()
  end

  defp eval_json_encode_builtin("object", [pairs], _env, _context, _stack) when is_list(pairs) do
    mapped =
      pairs
      |> Enum.map(fn
        {k, v} when is_binary(k) -> {k, v}
        [k, v] when is_binary(k) -> {k, v}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    {:ok, mapped}
  end

  defp eval_json_encode_builtin("encode", [indent, value], _env, _context, _stack)
       when is_integer(indent) and indent >= 0 do
    case Jason.encode(value) do
      {:ok, encoded} -> {:ok, encoded}
      _ -> {:ok, "null"}
    end
  end

  defp eval_json_encode_builtin(_function_name, _values, _env, _context, _stack), do: :no_builtin

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

  @spec eval_builtin_legacy(term(), term(), term(), term(), term()) :: term()
  defp eval_builtin_legacy(name, values, env, context, stack)
       when is_binary(name) and is_list(values) and is_map(env) and is_map(context) and
              is_list(stack) do
    normalized = normalize_builtin_short_name(name)

    case {normalized, values} do
      {"__add__", [a, b]} when is_number(a) and is_number(b) ->
        {:ok, a + b}

      {"__sub__", [a, b]} when is_number(a) and is_number(b) ->
        {:ok, a - b}

      {"__mul__", [a, b]} when is_number(a) and is_number(b) ->
        {:ok, a * b}

      {"__pow__", [a, b]} when is_number(a) and is_integer(b) ->
        {:ok, pow_number(a, b)}

      {"__fdiv__", [_a, 0]} ->
        {:ok, :nan}

      {"__fdiv__", [a, b]} when is_number(a) and is_number(b) ->
        {:ok, a / b}

      {"__idiv__", [_a, 0]} ->
        {:ok, nil}

      {"__idiv__", [a, b]} when is_integer(a) and is_integer(b) ->
        {:ok, div(a, b)}

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
        string_filter_with_callable(fun, text, env, context, stack)

      {"foldl", [fun, init, xs]} when is_list(xs) ->
        foldl_with_callable(fun, init, xs, env, context, stack)

      {"foldl", [fun, init, text]} when is_binary(text) ->
        string_foldl_with_callable(fun, init, text, env, context, stack)

      {"foldr", [fun, init, xs]} when is_list(xs) ->
        foldr_with_callable(fun, init, xs, env, context, stack)

      {"foldr", [fun, init, text]} when is_binary(text) ->
        string_foldr_with_callable(fun, init, text, env, context, stack)

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
        string_all_with_callable(fun, text, env, context, stack)

      {"any", [fun, text]} when is_binary(text) ->
        string_any_with_callable(fun, text, env, context, stack)

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
        result_and_then_with_callable(fun, result, env, context, stack)

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
        eval_ui_builtin(name, values)
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

  @spec normalize_builtin_name(term()) :: String.t()
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

  @spec normalize_builtin_short_name(term()) :: String.t()
  defp normalize_builtin_short_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.downcase()
  end

  @spec infinite_float?(term()) :: boolean()
  defp infinite_float?(x) when is_float(x) do
    rendered = :erlang.float_to_binary(x, [:compact]) |> String.downcase()
    String.contains?(rendered, "inf")
  end

  @spec nan_value?(term()) :: boolean()
  defp nan_value?(:nan), do: true
  defp nan_value?(x) when is_float(x), do: x != x
  defp nan_value?(_), do: false

  @spec infinite_value?(term()) :: boolean()
  defp infinite_value?(:nan), do: false
  defp infinite_value?(x) when is_float(x), do: infinite_float?(x)
  defp infinite_value?(_), do: false

  @spec safe_math_unary(term(), term()) :: term()
  defp safe_math_unary(fun, value) when is_function(fun, 1) do
    try do
      {:ok, fun.(value)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  @spec safe_math_binary(term(), term(), term()) :: term()
  defp safe_math_binary(fun, left, right) when is_function(fun, 2) do
    try do
      {:ok, fun.(left, right)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  @spec safe_log_base(term(), term()) :: term()
  defp safe_log_base(base, n) do
    try do
      {:ok, :math.log(n) / :math.log(base)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  @spec short_ctor_name(term()) :: String.t()
  defp short_ctor_name(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
  end

  @spec compare_ctor(term(), term()) :: term()
  defp compare_ctor(left, right) do
    cond do
      left < right -> %{"ctor" => "LT", "args" => []}
      left > right -> %{"ctor" => "GT", "args" => []}
      true -> %{"ctor" => "EQ", "args" => []}
    end
  end

  @spec char_from_code(term()) :: String.t()
  defp char_from_code(value) when is_integer(value) and value >= 0 and value <= 0x10FFFF do
    if value in 0xD800..0xDFFF do
      <<0xFFFD::utf8>>
    else
      try do
        <<value::utf8>>
      rescue
        _ -> <<0xFFFD::utf8>>
      end
    end
  end

  defp char_from_code(_), do: <<0xFFFD::utf8>>

  @spec char_predicate(term(), term()) :: term()
  defp char_predicate(char, fun) when is_function(fun, 1) do
    char
    |> normalize_char()
    |> case do
      nil -> false
      cp -> fun.(cp)
    end
  end

  @spec normalize_char(term()) :: integer() | nil
  defp normalize_char(char) when is_binary(char) do
    case String.to_charlist(char) do
      [cp] -> cp
      _ -> nil
    end
  end

  defp normalize_char(_), do: nil

  @spec char_alpha?(term()) :: boolean()
  defp char_alpha?(cp), do: (cp >= ?A and cp <= ?Z) or (cp >= ?a and cp <= ?z)
  @spec char_digit?(term()) :: boolean()
  defp char_digit?(cp), do: cp >= ?0 and cp <= ?9
  @spec char_alphanum?(term()) :: boolean()
  defp char_alphanum?(cp), do: char_alpha?(cp) or char_digit?(cp)
  @spec char_lower?(term()) :: boolean()
  defp char_lower?(cp), do: cp >= ?a and cp <= ?z
  @spec char_upper?(term()) :: boolean()
  defp char_upper?(cp), do: cp >= ?A and cp <= ?Z

  @spec maybe_get_ctor(term(), term()) :: term()
  defp maybe_get_ctor(xs, idx) when is_list(xs) and is_integer(idx) do
    if idx < 0 or idx >= length(xs) do
      %{"ctor" => "Nothing", "args" => []}
    else
      %{"ctor" => "Just", "args" => [Enum.at(xs, idx)]}
    end
  end

  @spec list_set(term(), term(), term()) :: term()
  defp list_set(xs, idx, value) when is_list(xs) and is_integer(idx) do
    if idx < 0 or idx >= length(xs) do
      xs
    else
      List.replace_at(xs, idx, value)
    end
  end

  @spec list_slice(term(), term(), term()) :: term()
  defp list_slice(xs, start, stop) when is_list(xs) and is_integer(start) and is_integer(stop) do
    len = length(xs)
    from = normalize_slice_index(start, len)
    to = normalize_slice_index(stop, len)
    count = max(to - from, 0)
    xs |> Enum.drop(from) |> Enum.take(count)
  end

  @spec normalize_slice_index(term(), term()) :: non_neg_integer()
  defp normalize_slice_index(index, len) when is_integer(index) and is_integer(len) do
    normalized = if index < 0, do: len + index, else: index
    normalized |> max(0) |> min(len)
  end

  @spec maybe_value(term()) :: {:just, term()} | :nothing | :invalid
  defp maybe_value(value) when is_map(value) do
    ctor = Map.get(value, "ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, :args) || []
    short = short_ctor_name(to_string(ctor || ""))

    case {short, args} do
      {"Just", [inner]} -> {:just, inner}
      {"Nothing", _} -> :nothing
      _ -> :invalid
    end
  end

  defp maybe_value({1, inner}), do: {:just, inner}
  defp maybe_value(0), do: :nothing
  defp maybe_value(_), do: :invalid

  @spec maybe_ctor(term()) :: map()
  defp maybe_ctor({:just, value}), do: %{"ctor" => "Just", "args" => [value]}
  defp maybe_ctor(:nothing), do: %{"ctor" => "Nothing", "args" => []}

  @spec maybe_ctor_like(term(), term()) :: term()
  defp maybe_ctor_like(source, {:just, value}) when is_tuple(source), do: {1, value}
  defp maybe_ctor_like(source, :nothing) when is_integer(source), do: 0
  defp maybe_ctor_like(_source, parsed), do: maybe_ctor(parsed)

  @spec result_value(term()) :: {:ok, term()} | {:err, term()} | :invalid
  defp result_value(value) when is_map(value) do
    ctor = Map.get(value, "ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, :args) || []
    short = short_ctor_name(to_string(ctor || ""))

    case {short, args} do
      {"Ok", [inner]} -> {:ok, inner}
      {"Err", [inner]} -> {:err, inner}
      _ -> :invalid
    end
  end

  defp result_value({1, inner}), do: {:ok, inner}
  defp result_value({0, inner}), do: {:err, inner}
  defp result_value(_), do: :invalid

  @spec result_ctor(term()) :: map()
  defp result_ctor({:ok, value}), do: %{"ctor" => "Ok", "args" => [value]}
  defp result_ctor({:err, error}), do: %{"ctor" => "Err", "args" => [error]}

  @spec result_ctor_like(term(), term()) :: term()
  defp result_ctor_like(source, {:ok, value}) when is_tuple(source), do: {1, value}
  defp result_ctor_like(source, {:err, error}) when is_tuple(source), do: {0, error}
  defp result_ctor_like(_source, parsed), do: result_ctor(parsed)

  @spec maybe_head_ctor(term()) :: term()
  defp maybe_head_ctor([]), do: maybe_ctor(:nothing)
  defp maybe_head_ctor([head | _]), do: maybe_ctor({:just, head})

  @spec maybe_tail_ctor(term()) :: term()
  defp maybe_tail_ctor([]), do: maybe_ctor(:nothing)
  defp maybe_tail_ctor([_ | tail]), do: maybe_ctor({:just, tail})

  @spec maybe_map_get_ctor(term(), term()) :: term()
  defp maybe_map_get_ctor(dict, key) when is_map(dict) do
    if Map.has_key?(dict, key),
      do: maybe_ctor({:just, Map.get(dict, key)}),
      else: maybe_ctor(:nothing)
  end

  @spec maybe_extreme_ctor(term(), term()) :: term()
  defp maybe_extreme_ctor([], _kind), do: maybe_ctor(:nothing)
  defp maybe_extreme_ctor(xs, :max), do: maybe_ctor({:just, Enum.max(xs)})
  defp maybe_extreme_ctor(xs, :min), do: maybe_ctor({:just, Enum.min(xs)})

  @spec dict_pair_list?(term()) :: boolean()
  defp dict_pair_list?(xs) when is_list(xs), do: Enum.all?(xs, &(pair_to_tuple(&1) != :error))

  @spec pair_to_tuple(term()) :: term()
  defp pair_to_tuple({k, v}), do: {k, v}
  defp pair_to_tuple([k, v]), do: {k, v}

  defp pair_to_tuple(%{"ctor" => ctor, "args" => [k, v]}) when is_binary(ctor) do
    if short_ctor_name(ctor) in ["Tuple2", "_Tuple2"], do: {k, v}, else: :error
  end

  defp pair_to_tuple(%{ctor: ctor, args: [k, v]}) when is_binary(ctor) do
    if short_ctor_name(ctor) in ["Tuple2", "_Tuple2"], do: {k, v}, else: :error
  end

  defp pair_to_tuple(_), do: :error

  @spec dict_from_pair_list(term()) :: term()
  defp dict_from_pair_list(xs) do
    xs
    |> Enum.map(&pair_to_tuple/1)
    |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, v) end)
  end

  @spec dict_sorted_pairs(term()) :: [{term(), term()}]
  defp dict_sorted_pairs(dict) when is_map(dict), do: dict |> Map.to_list() |> Enum.sort()
  @spec dict_to_list(term()) :: term()
  defp dict_to_list(dict) when is_map(dict), do: dict_sorted_pairs(dict)
  @spec dict_keys(term()) :: list()
  defp dict_keys(dict) when is_map(dict),
    do: dict_sorted_pairs(dict) |> Enum.map(fn {k, _} -> k end)

  @spec dict_values(term()) :: list()
  defp dict_values(dict) when is_map(dict),
    do: dict_sorted_pairs(dict) |> Enum.map(fn {_, v} -> v end)

  @spec list_intersperse(term(), term()) :: term()
  defp list_intersperse([], _sep), do: []
  defp list_intersperse([x], _sep), do: [x]
  defp list_intersperse([x | rest], sep), do: [x, sep | list_intersperse(rest, sep)]

  @spec list_unzip(term()) :: {list(), list()}
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

  @spec normalize_char_binary(term()) :: String.t()
  defp normalize_char_binary(char) when is_binary(char) do
    case String.graphemes(char) do
      [g | _] -> g
      [] -> ""
    end
  end

  defp normalize_char_binary(char) when is_integer(char), do: char_from_code(char)
  defp normalize_char_binary(_), do: ""

  @spec char_to_code(term()) :: non_neg_integer()
  defp char_to_code(char) do
    char
    |> normalize_char_binary()
    |> String.to_charlist()
    |> case do
      [cp] -> cp
      _ -> 0
    end
  end

  @spec char_octal_digit?(term()) :: boolean()
  defp char_octal_digit?(cp), do: cp >= ?0 and cp <= ?7

  @spec string_left(term(), term()) :: String.t()
  defp string_left(text, n) when is_binary(text) and is_integer(n) do
    text |> String.graphemes() |> Enum.take(max(n, 0)) |> Enum.join()
  end

  @spec string_right(term(), term()) :: String.t()
  defp string_right(text, n) when is_binary(text) and is_integer(n) do
    graphemes = String.graphemes(text)
    graphemes |> Enum.drop(max(length(graphemes) - max(n, 0), 0)) |> Enum.join()
  end

  @spec string_drop_left(term(), term()) :: String.t()
  defp string_drop_left(text, n) when is_binary(text) and is_integer(n) do
    text |> String.graphemes() |> Enum.drop(max(n, 0)) |> Enum.join()
  end

  @spec string_drop_right(term(), term()) :: String.t()
  defp string_drop_right(text, n) when is_binary(text) and is_integer(n) do
    graphemes = String.graphemes(text)
    graphemes |> Enum.take(max(length(graphemes) - max(n, 0), 0)) |> Enum.join()
  end

  @spec string_pad_center(term(), term(), term()) :: String.t()
  defp string_pad_center(text, width, fill) do
    text_len = String.length(text)
    total = max(width - text_len, 0)
    left = div(total, 2)
    string_pad_left(text, text_len + left, fill) |> string_pad_right(width, fill)
  end

  @spec string_pad_left(term(), term(), term()) :: String.t()
  defp string_pad_left(text, width, fill) do
    ch = normalize_char_binary(fill)
    missing = max(width - String.length(text), 0)
    String.duplicate(ch, missing) <> text
  end

  @spec string_pad_right(term(), term(), term()) :: String.t()
  defp string_pad_right(text, width, fill) do
    ch = normalize_char_binary(fill)
    missing = max(width - String.length(text), 0)
    text <> String.duplicate(ch, missing)
  end

  @spec string_slice(term(), term(), term()) :: String.t()
  defp string_slice(text, start, stop)
       when is_binary(text) and is_integer(start) and is_integer(stop) do
    graphemes = String.graphemes(text)
    len = length(graphemes)
    from = normalize_slice_index(start, len)
    to = normalize_slice_index(stop, len)
    graphemes |> Enum.drop(from) |> Enum.take(max(to - from, 0)) |> Enum.join()
  end

  @spec string_indexes(term(), term()) :: [non_neg_integer()]
  defp string_indexes("", _), do: []

  defp string_indexes(needle, haystack) when is_binary(needle) and is_binary(haystack) do
    n = String.length(needle)
    h = String.graphemes(haystack)
    max_start = length(h) - n

    if n <= 0 or max_start < 0 do
      []
    else
      0..max_start
      |> Enum.filter(fn idx ->
        h |> Enum.drop(idx) |> Enum.take(n) |> Enum.join() == needle
      end)
      |> Enum.to_list()
    end
  end

  @spec string_uncons_ctor(term()) :: map()
  defp string_uncons_ctor(text) when is_binary(text) do
    case String.graphemes(text) do
      [head | tail] -> maybe_ctor({:just, {head, Enum.join(tail)}})
      [] -> maybe_ctor(:nothing)
    end
  end

  @spec maybe_int_from_string(term()) :: map()
  defp maybe_int_from_string(text) when is_binary(text) do
    case Integer.parse(text) do
      {value, ""} -> maybe_ctor({:just, value})
      _ -> maybe_ctor(:nothing)
    end
  end

  @spec maybe_float_from_string(term()) :: map()
  defp maybe_float_from_string(text) when is_binary(text) do
    case Float.parse(text) do
      {value, ""} -> maybe_ctor({:just, value})
      _ -> maybe_ctor(:nothing)
    end
  end

  @spec float_to_elm_string(term()) :: String.t()
  defp float_to_elm_string(value) when is_integer(value), do: Integer.to_string(value)

  defp float_to_elm_string(value) when is_float(value) do
    if value == trunc(value) do
      Integer.to_string(trunc(value))
    else
      :erlang.float_to_binary(value, [:compact, decimals: 15])
    end
  end

  @spec with_default_maybe_or_result(term(), term()) :: term()
  defp with_default_maybe_or_result(default, value) do
    case {maybe_value(value), result_value(value)} do
      {{:just, inner}, _} -> inner
      {:nothing, _} -> default
      {_, {:ok, inner}} -> inner
      {_, {:err, _}} -> default
      _ -> default
    end
  end

  @spec eval_kernel_json_builtin(String.t(), list(), map(), map(), list()) :: term()
  defp eval_kernel_json_builtin(json_name, values, env, context, stack)
       when is_binary(json_name) and is_list(values) and is_map(env) and is_map(context) and
              is_list(stack) do
    case {json_name, values} do
      {"run", []} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.run", []}}

      {"run", [decoder]} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.run", [decoder]}}

      {"run", [decoder, value]} ->
        run_json_decoder(decoder, value, env, context, stack)

      {"runonstring", []} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.runOnString", []}}

      {"runonstring", [decoder]} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.runOnString", [decoder]}}

      {"runonstring", [decoder, text]} when is_binary(text) ->
        run_json_decoder_on_string(decoder, text, env, context, stack)

      {"decodebool", []} ->
        {:ok, {:json_decoder, :bool}}

      {"decodeint", []} ->
        {:ok, {:json_decoder, :int}}

      {"decodefloat", []} ->
        {:ok, {:json_decoder, :float}}

      {"decodestring", []} ->
        {:ok, {:json_decoder, :string}}

      {"decodevalue", []} ->
        {:ok, {:json_decoder, :value}}

      {"decodelist", [decoder]} ->
        {:ok, {:json_decoder, {:list, decoder}}}

      {"decodearray", [decoder]} ->
        {:ok, {:json_decoder, {:array, decoder}}}

      {"decodekeyvaluepairs", [decoder]} ->
        {:ok, {:json_decoder, {:key_value_pairs, decoder}}}

      {"decodefield", [field]} when is_binary(field) ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.decodeField", [field]}}

      {"decodefield", [field, decoder]} when is_binary(field) ->
        {:ok, {:json_decoder, {:field, field, decoder}}}

      {"decodeindex", [index]} when is_integer(index) ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.decodeIndex", [index]}}

      {"decodeindex", [index, decoder]} when is_integer(index) ->
        {:ok, {:json_decoder, {:index, index, decoder}}}

      {"decodenull", [value]} ->
        {:ok, {:json_decoder, {:null, value}}}

      {"oneof", [decoders]} when is_list(decoders) ->
        {:ok, {:json_decoder, {:one_of, decoders}}}

      {"succeed", [value]} ->
        {:ok, {:json_decoder, {:succeed, value}}}

      {"fail", [message]} when is_binary(message) ->
        {:ok, {:json_decoder, {:fail, message}}}

      {"andthen", [fun]} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.andThen", [fun]}}

      {"andthen", [fun, decoder]} ->
        {:ok, {:json_decoder, {:and_then, fun, decoder}}}

      {"map1", [fun, d1]} ->
        {:ok, {:json_decoder, {:map, fun, [d1]}}}

      {"map2", [fun, d1, d2]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2]}}}

      {"map3", [fun, d1, d2, d3]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3]}}}

      {"map4", [fun, d1, d2, d3, d4]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4]}}}

      {"map5", [fun, d1, d2, d3, d4, d5]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4, d5]}}}

      {"map6", [fun, d1, d2, d3, d4, d5, d6]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4, d5, d6]}}}

      {"map7", [fun, d1, d2, d3, d4, d5, d6, d7]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4, d5, d6, d7]}}}

      {"map8", [fun, d1, d2, d3, d4, d5, d6, d7, d8]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4, d5, d6, d7, d8]}}}

      _ ->
        :no_builtin
    end
  end

  @spec run_json_decoder_on_string(term(), term(), term(), term(), term()) :: term()
  defp run_json_decoder_on_string(decoder, text, env, context, stack)
       when is_binary(text) and is_map(env) and is_map(context) and is_list(stack) do
    case Jason.decode(text) do
      {:ok, value} -> run_json_decoder(decoder, value, env, context, stack)
      {:error, _reason} -> {:ok, result_ctor({:err, "invalid json"})}
    end
  end

  @spec run_json_decoder(term(), term(), term(), term(), term()) :: term()
  defp run_json_decoder(decoder, value, env, context, stack)
       when is_map(env) and is_map(context) and is_list(stack) do
    case json_decode(decoder, value, env, context, stack) do
      {:ok, decoded} -> {:ok, result_ctor({:ok, decoded})}
      {:error, reason} -> {:ok, result_ctor({:err, reason})}
    end
  end

  @spec json_decode(term(), term(), term(), term(), term()) :: term()
  defp json_decode({:json_decoder, :bool}, value, _env, _context, _stack) when is_boolean(value),
    do: {:ok, value}

  defp json_decode({:json_decoder, :int}, value, _env, _context, _stack) when is_integer(value),
    do: {:ok, value}

  defp json_decode({:json_decoder, :float}, value, _env, _context, _stack) when is_number(value),
    do: {:ok, value}

  defp json_decode({:json_decoder, :string}, value, _env, _context, _stack) when is_binary(value),
    do: {:ok, value}

  defp json_decode({:json_decoder, :value}, value, _env, _context, _stack), do: {:ok, value}

  defp json_decode({:json_decoder, {:succeed, v}}, _value, _env, _context, _stack), do: {:ok, v}

  defp json_decode({:json_decoder, {:fail, msg}}, _value, _env, _context, _stack),
    do: {:error, msg}

  defp json_decode({:json_decoder, {:null, v}}, nil, _env, _context, _stack), do: {:ok, v}

  defp json_decode({:json_decoder, {:null, _v}}, _value, _env, _context, _stack),
    do: {:error, "expected null"}

  defp json_decode({:json_decoder, {:list, decoder}}, value, env, context, stack)
       when is_list(value) do
    value
    |> Enum.map(&json_decode(decoder, &1, env, context, stack))
    |> collect_ok()
  end

  defp json_decode({:json_decoder, {:array, decoder}}, value, env, context, stack)
       when is_list(value) do
    value
    |> Enum.map(&json_decode(decoder, &1, env, context, stack))
    |> collect_ok()
  end

  defp json_decode({:json_decoder, {:field, field, decoder}}, value, env, context, stack)
       when is_binary(field) and is_map(value) do
    if Map.has_key?(value, field) do
      json_decode(decoder, Map.get(value, field), env, context, stack)
    else
      {:error, "missing field"}
    end
  end

  defp json_decode({:json_decoder, {:index, index, decoder}}, value, env, context, stack)
       when is_integer(index) and is_list(value) do
    if index >= 0 and index < length(value) do
      json_decode(decoder, Enum.at(value, index), env, context, stack)
    else
      {:error, "index out of range"}
    end
  end

  defp json_decode({:json_decoder, {:key_value_pairs, decoder}}, value, env, context, stack)
       when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {k, v} ->
      case json_decode(decoder, v, env, context, stack) do
        {:ok, decoded} -> {:ok, {k, decoded}}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> collect_ok()
  end

  defp json_decode({:json_decoder, {:one_of, decoders}}, value, env, context, stack)
       when is_list(decoders) do
    Enum.reduce_while(decoders, {:error, "oneOf failed"}, fn decoder, _acc ->
      case json_decode(decoder, value, env, context, stack) do
        {:ok, decoded} -> {:halt, {:ok, decoded}}
        {:error, _} -> {:cont, {:error, "oneOf failed"}}
      end
    end)
  end

  defp json_decode({:json_decoder, {:and_then, fun, decoder}}, value, env, context, stack) do
    with {:ok, first} <- json_decode(decoder, value, env, context, stack),
         {:ok, next_decoder} <- call_callable(fun, [first], env, context, stack),
         {:ok, decoded} <- json_decode(next_decoder, value, env, context, stack) do
      {:ok, decoded}
    end
  end

  defp json_decode({:json_decoder, {:map, fun, decoders}}, value, env, context, stack)
       when is_list(decoders) do
    with {:ok, decoded_values} <- json_decode_all(decoders, value, env, context, stack),
         {:ok, mapped} <- call_callable(fun, decoded_values, env, context, stack) do
      {:ok, mapped}
    end
  end

  defp json_decode({:json_decoder, _spec}, _value, _env, _context, _stack),
    do: {:error, "decoder mismatch"}

  defp json_decode(_decoder, _value, _env, _context, _stack), do: {:error, "not a decoder"}

  @spec json_decode_all([term()], term(), term(), term(), term()) :: term()
  defp json_decode_all(decoders, value, env, context, stack) when is_list(decoders) do
    decoders
    |> Enum.map(&json_decode(&1, value, env, context, stack))
    |> collect_ok()
  end

  @spec map_dispatch(term(), term(), term(), term(), term()) :: term()
  defp map_dispatch(fun, subject, env, context, stack) do
    cond do
      is_list(subject) ->
        map_with_callable(fun, subject, env, context, stack)

      is_binary(subject) ->
        string_map_with_callable(fun, subject, env, context, stack)

      true ->
        case maybe_map_with_callable(fun, subject, env, context, stack) do
          :no_builtin ->
            case result_map_with_callable(fun, subject, env, context, stack) do
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

  @spec map2_dispatch(term(), term(), term(), term(), term(), term()) :: term()
  defp map2_dispatch(a, b, c, env, context, stack) do
    candidates = [{a, b, c}, {c, a, b}, {b, c, a}, {c, b, a}]

    Enum.reduce_while(candidates, :no_builtin, fn {fun, left, right}, _acc ->
      result =
        case maybe_map2_with_callable(fun, left, right, env, context, stack) do
          :no_builtin -> result_map2_with_callable(fun, left, right, env, context, stack)
          other -> other
        end

      if result == :no_builtin, do: {:cont, :no_builtin}, else: {:halt, result}
    end)
  end

  @spec is_callable_like(term()) :: boolean()
  defp is_callable_like({:closure, _params, _body, _env}), do: true
  defp is_callable_like({:builtin_partial, _name, _bound}), do: true
  defp is_callable_like({:function_ref, _name}), do: true
  defp is_callable_like(name) when is_binary(name), do: true
  defp is_callable_like(_), do: false

  @spec maybe_map_with_callable(term(), term(), term(), term(), term()) :: term()
  defp maybe_map_with_callable(fun, maybe, env, context, stack) do
    case maybe_value(maybe) do
      {:just, value} ->
        case call_callable(fun, [value], env, context, stack) do
          {:ok, mapped} -> {:ok, maybe_ctor_like(maybe, {:just, mapped})}
          {:error, reason} -> {:error, reason}
        end

      :nothing ->
        {:ok, maybe_ctor_like(maybe, :nothing)}

      :invalid ->
        :no_builtin
    end
  end

  @spec maybe_map2_with_callable(term(), term(), term(), term(), term(), term()) :: term()
  defp maybe_map2_with_callable(fun, a, b, env, context, stack) do
    case {maybe_value(a), maybe_value(b)} do
      {{:just, av}, {:just, bv}} ->
        case call_callable(fun, [av, bv], env, context, stack) do
          {:ok, value} -> {:ok, maybe_ctor_like(a, {:just, value})}
          {:error, reason} -> {:error, reason}
        end

      {:invalid, _} ->
        :no_builtin

      {_, :invalid} ->
        :no_builtin

      _ ->
        {:ok, maybe_ctor_like(a, :nothing)}
    end
  end

  @spec result_map_with_callable(term(), term(), term(), term(), term()) :: term()
  defp result_map_with_callable(fun, result, env, context, stack) do
    case result_value(result) do
      {:ok, value} ->
        case call_callable(fun, [value], env, context, stack) do
          {:ok, mapped} -> {:ok, result_ctor_like(result, {:ok, mapped})}
          {:error, reason} -> {:error, reason}
        end

      {:err, error} ->
        {:ok, result_ctor_like(result, {:err, error})}

      :invalid ->
        :no_builtin
    end
  end

  @spec result_map2_with_callable(term(), term(), term(), term(), term(), term()) :: term()
  defp result_map2_with_callable(fun, a, b, env, context, stack) do
    case {result_value(a), result_value(b)} do
      {{:ok, av}, {:ok, bv}} ->
        case call_callable(fun, [av, bv], env, context, stack) do
          {:ok, value} -> {:ok, result_ctor_like(a, {:ok, value})}
          {:error, reason} -> {:error, reason}
        end

      {{:err, error}, _} ->
        {:ok, result_ctor_like(a, {:err, error})}

      {_, {:err, error}} ->
        {:ok, result_ctor_like(b, {:err, error})}

      _ ->
        :no_builtin
    end
  end

  @spec result_and_then_with_callable(term(), term(), term(), term(), term()) :: term()
  defp result_and_then_with_callable(fun, result, env, context, stack) do
    case result_value(result) do
      {:ok, value} ->
        call_callable(fun, [value], env, context, stack)

      {:err, error} ->
        {:ok, result_ctor_like(result, {:err, error})}

      :invalid ->
        :no_builtin
    end
  end

  @spec task_map_with_callable(term(), term(), term(), term(), term()) :: term()
  defp task_map_with_callable(fun, {:task, :ok, value}, env, context, stack) do
    case call_callable(fun, [value], env, context, stack) do
      {:ok, mapped} -> {:ok, {:task, :ok, mapped}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp task_map_with_callable(_fun, {:task, :err, error}, _env, _context, _stack),
    do: {:ok, {:task, :err, error}}

  defp task_map_with_callable(_fun, _task, _env, _context, _stack), do: :no_builtin

  @spec task_sequence(term()) :: term()
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

  @spec concat_map_with_callable(term(), term(), term(), term(), term()) :: term()
  defp concat_map_with_callable(fun, xs, env, context, stack) do
    xs
    |> Enum.map(fn x -> call_callable(fun, [x], env, context, stack) end)
    |> collect_ok()
    |> case do
      {:ok, lists} -> {:ok, Enum.flat_map(lists, fn x -> if is_list(x), do: x, else: [] end)}
      err -> err
    end
  end

  @spec list_map2_with_callable(term(), list(), list(), term(), term(), term()) :: term()
  defp list_map2_with_callable(fun, xs, ys, env, context, stack) do
    xs
    |> Enum.zip(ys)
    |> Enum.map(fn {x, y} -> call_callable(fun, [x, y], env, context, stack) end)
    |> collect_ok()
  end

  @spec all_with_callable(term(), term(), term(), term(), term()) :: term()
  defp all_with_callable(fun, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, true}, fn x, _ ->
      case call_callable(fun, [x], env, context, stack) do
        {:ok, true} -> {:cont, {:ok, true}}
        {:ok, _} -> {:halt, {:ok, false}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec any_with_callable(term(), term(), term(), term(), term()) :: term()
  defp any_with_callable(fun, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, false}, fn x, _ ->
      case call_callable(fun, [x], env, context, stack) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, _} -> {:cont, {:ok, false}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec partition_with_callable(term(), term(), term(), term(), term()) :: term()
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

  @spec sort_by_with_callable(term(), term(), term(), term(), term()) :: term()
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

  @spec sort_with_callable(term(), term(), term(), term(), term()) :: term()
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

  @spec compare_order_value(term()) :: term()
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

  @spec string_map_with_callable(term(), term(), term(), term(), term()) :: term()
  defp string_map_with_callable(fun, text, env, context, stack) do
    text
    |> String.graphemes()
    |> Enum.map(fn ch -> call_callable(fun, [ch], env, context, stack) end)
    |> collect_ok()
    |> case do
      {:ok, chars} -> {:ok, Enum.map(chars, &normalize_char_binary/1) |> Enum.join()}
      err -> err
    end
  end

  @spec string_filter_with_callable(term(), term(), term(), term(), term()) :: term()
  defp string_filter_with_callable(fun, text, env, context, stack) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({:ok, []}, fn ch, {:ok, acc} ->
      case call_callable(fun, [ch], env, context, stack) do
        {:ok, true} -> {:cont, {:ok, [ch | acc]}}
        {:ok, _} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, chars} -> {:ok, chars |> Enum.reverse() |> Enum.join()}
      err -> err
    end
  end

  @spec string_all_with_callable(term(), term(), term(), term(), term()) :: term()
  defp string_all_with_callable(fun, text, env, context, stack),
    do: all_with_callable(fun, String.graphemes(text), env, context, stack)

  @spec string_any_with_callable(term(), term(), term(), term(), term()) :: term()
  defp string_any_with_callable(fun, text, env, context, stack),
    do: any_with_callable(fun, String.graphemes(text), env, context, stack)

  @spec string_foldl_with_callable(term(), term(), term(), term(), term(), term()) :: term()
  defp string_foldl_with_callable(fun, init, text, env, context, stack),
    do: foldl_with_callable(fun, init, String.graphemes(text), env, context, stack)

  @spec string_foldr_with_callable(term(), term(), term(), term(), term(), term()) :: term()
  defp string_foldr_with_callable(fun, init, text, env, context, stack),
    do: foldr_with_callable(fun, init, String.graphemes(text), env, context, stack)

  @spec tuple_to_pair(term()) :: {:ok, {term(), term()}} | :error
  defp tuple_to_pair({a, b}), do: {:ok, {a, b}}
  defp tuple_to_pair([a, b]), do: {:ok, {a, b}}
  defp tuple_to_pair(_), do: :error

  @spec tuple_map_first_with_callable(term(), term(), term(), term(), term()) :: term()
  defp tuple_map_first_with_callable(fun, pair, env, context, stack) do
    with {:ok, {a, b}} <- tuple_to_pair(pair),
         {:ok, mapped} <- call_callable(fun, [a], env, context, stack) do
      {:ok, {mapped, b}}
    else
      :error -> :no_builtin
      err -> err
    end
  end

  @spec tuple_map_second_with_callable(term(), term(), term(), term(), term()) :: term()
  defp tuple_map_second_with_callable(fun, pair, env, context, stack) do
    with {:ok, {a, b}} <- tuple_to_pair(pair),
         {:ok, mapped} <- call_callable(fun, [b], env, context, stack) do
      {:ok, {a, mapped}}
    else
      :error -> :no_builtin
      err -> err
    end
  end

  @spec tuple_map_both_with_callable(term(), term(), term(), term(), term(), term()) :: term()
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

  @spec elm_debug_to_string(term()) :: String.t()
  defp elm_debug_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp elm_debug_to_string(value) when is_float(value), do: float_to_elm_string(value)
  defp elm_debug_to_string(value) when is_boolean(value), do: if(value, do: "True", else: "False")

  defp elm_debug_to_string(value) when is_binary(value) do
    if String.length(value) == 1 do
      "'#{value}'"
    else
      escaped = value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
      "\"#{escaped}\""
    end
  end

  defp elm_debug_to_string(value) when is_list(value),
    do: "[" <> (value |> Enum.map(&elm_debug_to_string/1) |> Enum.join(",")) <> "]"

  defp elm_debug_to_string(value) when is_tuple(value) do
    "(" <>
      (value |> Tuple.to_list() |> Enum.map(&elm_debug_to_string/1) |> Enum.join(", ")) <> ")"
  end

  defp elm_debug_to_string(%{"ctor" => ctor, "args" => args})
       when is_binary(ctor) and is_list(args),
       do: short_ctor_name(ctor) <> format_ctor_args(args)

  defp elm_debug_to_string(%{ctor: ctor, args: args}) when is_binary(ctor) and is_list(args),
    do: short_ctor_name(ctor) <> format_ctor_args(args)

  defp elm_debug_to_string(value), do: inspect(value)

  @spec format_ctor_args(term()) :: String.t()
  defp format_ctor_args([]), do: ""

  defp format_ctor_args(args),
    do: " " <> (args |> Enum.map(&elm_debug_to_string/1) |> Enum.join(" "))

  @spec map_with_callable(term(), term(), term(), term(), term()) :: term()
  defp map_with_callable(fun, xs, env, context, stack) do
    xs
    |> Enum.map(fn x -> call_callable(fun, [x], env, context, stack) end)
    |> collect_ok()
  end

  @spec filter_with_callable(term(), term(), term(), term(), term()) :: term()
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

  @spec foldl_with_callable(term(), term(), term(), term(), term(), term()) :: term()
  defp foldl_with_callable(fun, init, xs, env, context, stack) do
    Enum.reduce_while(xs, {:ok, init}, fn x, {:ok, acc} ->
      case call_callable(fun, [x, acc], env, context, stack) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec foldr_with_callable(term(), term(), term(), term(), term(), term()) :: term()
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

  @spec indexed_map_with_callable(term(), term(), term(), term(), term()) :: term()
  defp indexed_map_with_callable(fun, xs, env, context, stack) do
    xs
    |> Enum.with_index()
    |> Enum.map(fn {x, idx} -> call_callable(fun, [idx, x], env, context, stack) end)
    |> collect_ok()
  end

  @spec initialize_with_callable(term(), term(), term(), term(), term()) :: term()
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

  @spec call_callable(term(), term(), term(), term(), term()) :: {:ok, term()} | {:error, term()}
  defp call_callable(fun, args, env, context, stack) when is_list(args) do
    case fun do
      {:closure, params, body, closure_env} when is_list(params) and is_map(closure_env) ->
        apply_closure("<closure>", params, body, closure_env, args, context, stack)

      {:builtin_partial, name, bound} when is_binary(name) and is_list(bound) ->
        case eval_builtin(name, bound ++ args, env, context, stack) do
          {:ok, value} -> {:ok, value}
          :no_builtin -> {:error, {:unknown_function, {"<builtin>", name, length(bound ++ args)}}}
        end

      {:function_ref, name} when is_binary(name) ->
        call_function(name, Enum.map(args, &literal_or_expr/1), env, context, stack)

      name when is_binary(name) ->
        call_function(name, Enum.map(args, &literal_or_expr/1), env, context, stack)

      _ ->
        {:error, {:not_callable, fun}}
    end
  end

  @spec literal_or_expr(term()) :: term()
  defp literal_or_expr(value) when is_map(value), do: value
  defp literal_or_expr(value), do: value

  @spec tuple_first(term()) :: term() | nil
  defp tuple_first({left, _right}), do: left
  defp tuple_first([left, _right]), do: left
  defp tuple_first(_), do: nil

  @spec tuple_second(term()) :: term() | nil
  defp tuple_second({_left, right}), do: right
  defp tuple_second([_left, right]), do: right
  defp tuple_second(_), do: nil

  @spec normalize_indexed_color(term()) :: {:ok, integer()} | :no_builtin
  defp normalize_indexed_color(code) when is_integer(code), do: {:ok, clamp_int(code, 0, 255)}
  defp normalize_indexed_color(_code), do: :no_builtin

  @spec normalize_rgba_color(term(), term(), term(), term()) :: {:ok, integer()} | :no_builtin
  defp normalize_rgba_color(r, g, b, a)
       when is_integer(r) and is_integer(g) and is_integer(b) and is_integer(a),
       do: {:ok, color_rgba_to_int(r, g, b, a)}

  defp normalize_rgba_color(_r, _g, _b, _a), do: :no_builtin

  @spec normalize_color_result(term()) :: {:ok, integer()} | :no_builtin
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

  @spec normalize_color(term()) :: {:ok, integer()} | :error
  defp normalize_color(value) when is_integer(value), do: {:ok, clamp_int(value, 0, 255)}

  defp normalize_color(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args),
    do: normalize_color_ctor(ctor, args)

  defp normalize_color(%{ctor: ctor, args: args}) when is_binary(ctor) and is_list(args),
    do: normalize_color_ctor(ctor, args)

  defp normalize_color(_), do: :error

  @spec normalize_point(term()) :: {:ok, {integer(), integer()}} | :error
  defp normalize_point(value) when is_map(value) do
    x = Map.get(value, "x") || Map.get(value, :x)
    y = Map.get(value, "y") || Map.get(value, :y)

    if is_integer(x) and is_integer(y), do: {:ok, {x, y}}, else: :error
  end

  defp normalize_point(_), do: :error

  @spec normalize_rect(term()) :: {:ok, {integer(), integer(), integer(), integer()}} | :error
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

  @spec normalize_path(term()) ::
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

  @spec normalize_points(term()) :: {:ok, [{integer(), integer()}]} | :error
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

  @spec normalize_point_tuple(term()) :: {:ok, {integer(), integer()}} | :error
  defp normalize_point_tuple({x, y}) when is_integer(x) and is_integer(y), do: {:ok, {x, y}}
  defp normalize_point_tuple([x, y]) when is_integer(x) and is_integer(y), do: {:ok, {x, y}}

  defp normalize_point_tuple(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y),
    do: {:ok, {x, y}}

  defp normalize_point_tuple(%{x: x, y: y}) when is_integer(x) and is_integer(y),
    do: {:ok, {x, y}}

  defp normalize_point_tuple(_), do: :error

  @spec normalize_color_ctor(term(), term()) :: {:ok, integer()} | :error
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

  @spec normalize_bitmap_id(term()) :: {:ok, integer()} | :error
  defp normalize_bitmap_id(value) when is_integer(value), do: {:ok, value}

  defp normalize_bitmap_id(%{"tag" => tag}) when is_integer(tag), do: {:ok, tag}
  defp normalize_bitmap_id(%{tag: tag}) when is_integer(tag), do: {:ok, tag}

  defp normalize_bitmap_id(%{"ctor" => _ctor, "args" => []} = value) when is_map(value) do
    case Map.get(value, "tag") do
      tag when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  defp normalize_bitmap_id(%{ctor: _ctor, args: []} = value) when is_map(value) do
    case Map.get(value, :tag) do
      tag when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  defp normalize_bitmap_id(_), do: :error

  @spec normalize_font_id(term()) :: {:ok, integer()} | :error
  defp normalize_font_id(value) when is_integer(value), do: {:ok, value}

  defp normalize_font_id(%{"tag" => tag}) when is_integer(tag), do: {:ok, tag}
  defp normalize_font_id(%{tag: tag}) when is_integer(tag), do: {:ok, tag}

  defp normalize_font_id(%{"ctor" => _ctor, "args" => []} = value) when is_map(value) do
    case Map.get(value, "tag") do
      tag when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  defp normalize_font_id(%{ctor: _ctor, args: []} = value) when is_map(value) do
    case Map.get(value, :tag) do
      tag when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  defp normalize_font_id(_), do: :error

  @spec normalize_rotation_angle(term()) :: {:ok, integer()} | :error
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

  @spec color_rgba_to_int(term(), term(), term(), term()) :: integer()
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

  @spec color_channel_to_2bit(term()) :: non_neg_integer()
  defp color_channel_to_2bit(value) when is_integer(value) do
    div(clamp_int(value, 0, 255) * 3 + 127, 255)
  end

  @spec clamp_int(integer(), integer(), integer()) :: integer()
  defp clamp_int(value, low, high) when is_integer(value), do: max(low, min(high, value))

  @spec ui_node(term(), term()) :: map()
  defp ui_node(type, children) when is_binary(type) and is_list(children) do
    %{"type" => type, "children" => children, "label" => ""}
  end

  @spec expr_node(term()) :: map()
  defp expr_node(value) when is_integer(value) or is_float(value),
    do: %{"type" => "expr", "value" => value, "children" => []}

  defp expr_node(value) when is_binary(value),
    do: %{"type" => "expr", "label" => value, "children" => []}

  defp expr_node(value) when is_boolean(value),
    do: %{"type" => "expr", "label" => to_string(value), "children" => []}

  defp expr_node(%{} = node), do: node
  defp expr_node(value), do: %{"type" => "expr", "label" => inspect(value), "children" => []}

  @spec path_points_node(term()) :: map()
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

  @spec ui_children_from_value(term()) :: [map()]
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

  @spec apply_indexed_function(term(), term(), term(), term()) :: term()
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
      nil -> {:error, {:unknown_function, {module_name, function_name, length(values)}}}
      result -> result
    end
  end

  @spec apply_indexed_function_in_module(
          String.t(),
          String.t(),
          [term()],
          term(),
          term(),
          boolean()
        ) :: term()
  defp apply_indexed_function_in_module(
         module_name,
         function_name,
         values,
         context,
         stack,
         allow_global_lookup
       ) do
    functions = Map.get(context, :functions, %{})
    key = {module_name, function_name, length(values)}

    cond do
      key in stack ->
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
                _ -> {:error, {:unknown_function, key}}
              end
            else
              {:error, {:unknown_function, key}}
            end
        end
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

  @spec parse_function_name(term(), term()) :: {String.t(), String.t()}
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

  @spec evaluate_case_branches(term(), term(), term(), term(), term()) :: term()
  defp evaluate_case_branches(branches, subject, env, context, stack) when is_list(branches) do
    Enum.find_value(branches, {:error, :no_case_branch_match}, fn branch ->
      pattern = branch["pattern"] || branch[:pattern] || %{}
      expr = branch["expr"] || branch[:expr]

      case match_pattern(pattern, subject) do
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

  @spec match_pattern(term(), term()) :: term()
  defp match_pattern(pattern, value) when is_map(pattern) do
    kind = pattern["kind"] || pattern[:kind]

    case kind do
      :wildcard ->
        {:ok, %{}}

      :var ->
        name = pattern["name"] || pattern[:name]
        if is_binary(name), do: {:ok, %{name => value}}, else: {:ok, %{}}

      :literal ->
        expected = pattern["value"] || pattern[:value]
        if expected == value, do: {:ok, %{}}, else: :nomatch

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
                {^tag, payload} -> match_pattern(arg_pattern, payload)
                _ -> match_constructor_by_name(name, arg_pattern, bind_name, pattern, value)
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
                  match_constructor_by_name(name, arg_pattern, bind_name, pattern, value)
              end

            true ->
              match_constructor_by_name(name, arg_pattern, bind_name, pattern, value)
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
            with {:ok, lb} <- match_pattern(left, l),
                 {:ok, rb} <- match_pattern(right, r) do
              {:ok, Map.merge(lb, rb)}
            end

          _ ->
            :nomatch
        end

      :tuple ->
        elements = pattern["elements"] || pattern[:elements] || []

        cond do
          is_tuple(value) and tuple_size(value) == length(elements) ->
            match_pattern_list(elements, Tuple.to_list(value))

          length(elements) == 2 ->
            case value do
              {l, r} ->
                match_pattern_list(elements, [l, r])

              _ ->
                :nomatch
            end

          true ->
            :nomatch
        end

      :alias ->
        alias_name = pattern["name"] || pattern[:name]
        inner = pattern["pattern"] || pattern[:pattern]

        case match_pattern(inner, value) do
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

  defp match_pattern(_pattern, _value), do: :nomatch

  @spec match_constructor_by_name(String.t(), term(), term(), term(), term()) :: term()
  defp match_constructor_by_name(name, arg_pattern, bind_name, pattern, value)
       when is_binary(name) do
    case value do
      true when name == "True" ->
        {:ok, %{}}

      false when name == "False" ->
        {:ok, %{}}

      %{"ctor" => ^name, "args" => args} when is_list(args) ->
        match_constructor_args(pattern, arg_pattern, bind_name, args)

      %{ctor: ^name, args: args} when is_list(args) ->
        match_constructor_args(pattern, arg_pattern, bind_name, args)

      _ ->
        :nomatch
    end
  end

  @spec match_constructor_args(term(), term(), term(), list()) :: term()
  defp match_constructor_args(pattern, arg_pattern, bind_name, args) when is_list(args) do
    cond do
      is_map(arg_pattern) and length(args) == 1 ->
        with {:ok, bindings} <- match_pattern(arg_pattern, hd(args)) do
          if is_binary(bind_name) and bind_name != "" do
            {:ok, Map.put(bindings, bind_name, hd(args))}
          else
            {:ok, bindings}
          end
        end

      is_binary(bind_name) and bind_name != "" and length(args) == 1 ->
        {:ok, %{bind_name => hd(args)}}

      true ->
        arg_patterns = pattern["args"] || pattern[:args] || []
        match_pattern_list(arg_patterns, args)
    end
  end

  @spec match_pattern_list(term(), term()) :: term()
  defp match_pattern_list(patterns, values)
       when is_list(patterns) and is_list(values) and length(patterns) == length(values) do
    Enum.zip(patterns, values)
    |> Enum.reduce_while({:ok, %{}}, fn {pat, val}, {:ok, acc} ->
      case match_pattern(pat, val) do
        {:ok, b} -> {:cont, {:ok, Map.merge(acc, b)}}
        :nomatch -> {:halt, :nomatch}
      end
    end)
  end

  defp match_pattern_list(_patterns, _values), do: :nomatch

  @spec field_access(term(), term()) :: term()
  defp field_access(base, field) when is_map(base) and is_binary(field) do
    Map.get(base, field) || Map.get(base, String.to_atom(field))
  rescue
    _ -> nil
  end

  defp field_access(base, field) when is_map(base) and is_atom(field),
    do: Map.get(base, field) || Map.get(base, Atom.to_string(field))

  defp field_access(_base, _field), do: nil

  @spec normalize_record_fields(term()) :: term()
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

  @spec compare(term(), term(), term()) :: boolean()
  defp compare(kind, left, right) do
    normalized = kind |> to_string() |> String.downcase()

    case normalized do
      "eq" -> left == right
      "neq" -> left != right
      "lt" -> left < right
      "lte" -> left <= right
      "gt" -> left > right
      "gte" -> left >= right
      _ -> false
    end
  end
end
