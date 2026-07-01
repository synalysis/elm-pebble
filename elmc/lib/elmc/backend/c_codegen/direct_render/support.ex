defmodule Elmc.Backend.CCodegen.DirectRender.Support do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @type seen_set :: MapSet.t(Types.function_decl_key())

  @type candidate_set ::
          MapSet.t(Types.function_decl_key())
          | Types.function_decl_map()
          | Enumerable.t(Types.function_decl_key())

  @spec supported?(
          Types.ir_expr(),
          String.t(),
          Types.function_decl_map(),
          seen_set()
        ) :: boolean()
  def supported?(expr, module_name, decl_map, seen) do
    case expr do
      %{op: :list_literal, items: items} ->
        Enum.all?(items, &supported?(&1, module_name, decl_map, seen))

      %{op: :let_in, in_expr: in_expr} ->
        supported?(in_expr, module_name, decl_map, seen)

      %{op: :case, branches: branches} ->
        Enum.all?(branches, &supported?(&1.expr, module_name, decl_map, seen))

      %{op: :if, then_expr: then_expr, else_expr: else_expr} ->
        supported?(then_expr, module_name, decl_map, seen) and
          supported?(else_expr, module_name, decl_map, seen)

      %{op: :lambda, body: body} ->
        supported?(body, module_name, decl_map, seen)

      %{op: :call, name: "__append__", args: [left, right]} ->
        supported?(left, module_name, decl_map, seen) and
          supported?(right, module_name, decl_map, seen)

      %{op: :call, name: name} ->
        target = {module_name, name}

        Map.has_key?(decl_map, target) and not MapSet.member?(seen, target) and
          supported?(
            decl_map[target].expr,
            module_name,
            decl_map,
            MapSet.put(seen, target)
          )

      %{op: :var} ->
        true

      %{op: :qualified_call, target: target, args: args} ->
        direct_qualified_supported?(
          Host.normalize_special_target(target),
          args,
          module_name,
          decl_map,
          seen
        )

      _ ->
        false
    end
  end

  @spec direct_qualified_supported?(
          String.t(),
          [Types.ir_expr()],
          String.t(),
          Types.function_decl_map(),
          seen_set()
        ) :: boolean()
  defp direct_qualified_supported?(target, args, module_name, decl_map, seen) do
    case {target, args} do
      {"Pebble.Ui.toUiNode", [expr]} ->
        supported?(expr, module_name, decl_map, seen)

      {"Pebble.Ui.windowStack", [%{op: :list_literal, items: items}]} ->
        Enum.all?(items, &supported?(&1, module_name, decl_map, seen))

      {"Pebble.Ui.window", [_id, %{op: :list_literal, items: items}]} ->
        Enum.all?(items, &supported?(&1, module_name, decl_map, seen))

      {"Pebble.Ui.canvasLayer", [_id, %{op: :list_literal, items: items}]} ->
        Enum.all?(items, &supported?(&1, module_name, decl_map, seen))

      {"Pebble.Ui.group", [%{op: :list_literal, items: items}]} ->
        Enum.all?(items, &supported?(&1, module_name, decl_map, seen))

      {"Pebble.Ui.group", [context_expr]} ->
        direct_group_context_supported?(context_expr, module_name, decl_map, seen)

      {"String.append", [left, right]} ->
        direct_string_leaf_supported?(left, module_name, decl_map, seen) and
          direct_string_leaf_supported?(right, module_name, decl_map, seen)

      {"String.fromInt", [arg]} ->
        supported?(arg, module_name, decl_map, seen)

      {"List.cons", [head, tail]} ->
        supported?(head, module_name, decl_map, seen) and
          supported?(tail, module_name, decl_map, seen)

      {"List.concat", args} ->
        case direct_static_concat_items(args) do
          {:ok, items} ->
            Enum.all?(items, &supported?(&1, module_name, decl_map, seen))

          :error ->
            false
        end

      {"List.indexedMap", [fun_expr, list_expr]} ->
        direct_map_fun_supported?(fun_expr, list_expr, module_name, decl_map, seen)

      {"List.concatMap", [fun_expr, list_expr]} ->
        direct_map_fun_supported?(fun_expr, list_expr, module_name, decl_map, seen)

      {"List.map", [fun_expr, list_expr]} ->
        direct_map_fun_supported?(fun_expr, list_expr, module_name, decl_map, seen)

      {target, _args}
      when target in [
             "Pebble.Ui.clear",
             "Pebble.Ui.pixel",
             "Pebble.Ui.line",
             "Pebble.Ui.rect",
             "Pebble.Ui.fillRect",
             "Pebble.Ui.circle",
             "Pebble.Ui.fillCircle",
             "Pebble.Ui.textInt",
             "Pebble.Ui.textLabel",
             "Pebble.Ui.text",
             "Pebble.Ui.roundRect",
             "Pebble.Ui.arc",
             "Pebble.Ui.fillRadial",
             "Pebble.Ui.drawBitmapInRect",
             "Pebble.Ui.drawRotatedBitmap",
             "Pebble.Ui.drawVectorAt",
             "Pebble.Ui.drawVectorSequenceAt"
           ] ->
        true

      {target, [path_arg]}
      when target in [
             "Pebble.Ui.pathFilled",
             "Pebble.Ui.pathOutline",
             "Pebble.Ui.pathOutlineOpen"
           ] ->
        case path_arg do
          %{op: :qualified_call, target: path_target, args: path_args} ->
            direct_path_supported?(Host.normalize_special_target(path_target), path_args)

          %{op: :var} ->
            true

          _ ->
            false
        end

      {target, _args} ->
        case direct_qualified_function_target(target, decl_map) do
          nil ->
            false

          target_key ->
            Map.has_key?(decl_map, target_key) and
              not MapSet.member?(seen, target_key) and
              supported?(
                decl_map[target_key].expr,
                elem(target_key, 0),
                decl_map,
                MapSet.put(seen, target_key)
              )
        end
    end
  end

  defp direct_context_supported?(
         "Pebble.Ui.context",
         [%{op: :list_literal, items: settings}, %{op: :list_literal, items: commands}],
         module_name,
         decl_map,
         seen
       ) do
    Enum.all?(settings, &setting_supported?/1) and
      Enum.all?(commands, &supported?(&1, module_name, decl_map, seen))
  end

  defp direct_context_supported?(_, _, _, _, _), do: false

  defp direct_group_context_supported?(
         %{op: :qualified_call, target: ctx_target, args: ctx_args},
         module_name,
         decl_map,
         seen
       ) do
    direct_context_supported?(
      Host.normalize_special_target(ctx_target),
      ctx_args,
      module_name,
      decl_map,
      seen
    )
  end

  defp direct_group_context_supported?(_, _, _, _), do: false

  @spec direct_static_concat_items([Types.ir_expr()]) :: {:ok, [Types.ir_expr()]} | :error
  defp direct_static_concat_items(args) when is_list(args) do
    Enum.reduce_while(args, [], fn expr, acc ->
      case expr do
        %{op: :list_literal, items: items} -> {:cont, acc ++ items}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      items when is_list(items) -> {:ok, items}
      :error -> :error
    end
  end

  @spec setting_supported?(Types.ir_expr()) :: boolean()
  def setting_supported?(%{op: :qualified_call, target: target, args: [_]}) do
    Host.normalize_special_target(target) in [
      "Pebble.Ui.strokeWidth",
      "Pebble.Ui.antialiased",
      "Pebble.Ui.strokeColor",
      "Pebble.Ui.fillColor",
      "Pebble.Ui.textColor",
      "Pebble.Ui.compositingMode"
    ]
  end

  def setting_supported?(_), do: false

  @spec static_concat_items([Types.ir_expr()]) :: {:ok, [Types.ir_expr()]} | :error
  def static_concat_items(args), do: direct_static_concat_items(args)

  @spec map_fun_render_transparent?(
          Types.ir_expr(),
          String.t(),
          Types.function_decl_map(),
          [Types.ir_expr()]
        ) :: boolean()
  def map_fun_render_transparent?(fun_expr, module_name, decl_map, prefix_args),
    do: direct_map_fun_render_transparent?(fun_expr, module_name, decl_map, prefix_args)

  @spec qualified_function_target(String.t(), candidate_set()) ::
          Types.function_decl_key() | nil
  def qualified_function_target(target, candidates),
    do: direct_qualified_function_target(target, candidates)

  defp direct_path_supported?("Pebble.Ui.path", [
         %{op: :list_literal, items: points},
         offset,
         _rotation
       ]) do
    (length(points) <= 16 and
       Enum.all?(points, &(Host.record_field_expr(&1, "x") && Host.record_field_expr(&1, "y"))) and
       Host.record_field_expr(offset, "x")) && Host.record_field_expr(offset, "y")
  end

  defp direct_path_supported?(_, _), do: false

  defp direct_function_target(%{op: :var, name: name}, module_name, decl_map, seen) do
    target = {module_name, name}

    if Map.has_key?(decl_map, target) and
         not MapSet.member?(seen, target) and
         supported?(decl_map[target].expr, module_name, decl_map, MapSet.put(seen, target)) do
      {module_name, name, []}
    end
  end

  defp direct_function_target(%{op: :call, name: name, args: args}, module_name, decl_map, seen) do
    case direct_function_target(%{op: :var, name: name}, module_name, decl_map, seen) do
      {target_module, target_name, []} -> {target_module, target_name, args}
      other -> other
    end
  end

  defp direct_function_target(
         %{op: :qualified_call, target: target, args: args},
         _module_name,
         decl_map,
         seen
       ) do
    with {target_module, target_name} = target_key <-
           direct_qualified_function_target(Host.normalize_special_target(target), decl_map),
         true <- Map.has_key?(decl_map, target_key),
         true <- not MapSet.member?(seen, target_key),
         true <-
           supported?(
             decl_map[target_key].expr,
             target_module,
             decl_map,
             MapSet.put(seen, target_key)
           ) do
      {target_module, target_name, args}
    else
      _ -> nil
    end
  end

  defp direct_function_target(_expr, _module_name, _decl_map, _seen), do: nil

  defp direct_map_fun_supported?(fun_expr, list_expr, module_name, decl_map, seen) do
    direct_function_target(fun_expr, module_name, decl_map, seen) != nil or
      direct_lambda_supported?(fun_expr, module_name, decl_map, seen) or
      direct_map_fun_static_transparent?(fun_expr, list_expr, module_name, decl_map, seen) or
      direct_dynamic_list_expr?(list_expr)
  end

  defp direct_dynamic_list_expr?(%{op: :var}), do: true

  defp direct_dynamic_list_expr?(%{op: :field_access, arg: %{op: :var}}), do: true

  defp direct_dynamic_list_expr?(%{op: :field_access, arg: arg}) when is_binary(arg), do: true

  defp direct_dynamic_list_expr?(_), do: false

  defp direct_string_leaf_supported?(%{op: :string_literal}, _module_name, _decl_map, _seen), do: true

  defp direct_string_leaf_supported?(%{op: :var}, _module_name, _decl_map, _seen), do: true

  defp direct_string_leaf_supported?(%{op: :field_access, arg: %{op: :var}}, _module_name, _decl_map, _seen),
    do: true

  defp direct_string_leaf_supported?(%{op: :field_access, arg: arg}, _module_name, _decl_map, _seen)
       when is_binary(arg),
       do: true

  defp direct_string_leaf_supported?(
         %{op: :qualified_call, target: target, args: [arg]},
         module_name,
         decl_map,
         seen
       ) do
    Host.normalize_special_target(target) == "String.fromInt" and
      direct_string_leaf_supported?(arg, module_name, decl_map, seen)
  end

  defp direct_string_leaf_supported?(
         %{op: :call, name: "__append__", args: [left, right]},
         module_name,
         decl_map,
         seen
       ) do
    direct_string_leaf_supported?(left, module_name, decl_map, seen) and
      direct_string_leaf_supported?(right, module_name, decl_map, seen)
  end

  defp direct_string_leaf_supported?(_, _module_name, _decl_map, _seen), do: false

  defp direct_map_fun_static_transparent?(fun_expr, list_expr, module_name, decl_map, seen) do
    with {:ok, items} <- Host.direct_static_list_items(list_expr),
         true <- direct_map_fun_render_transparent?(fun_expr, module_name, decl_map, []) do
      Enum.all?(items, &supported?(&1, module_name, decl_map, seen))
    else
      _ -> false
    end
  end

  @spec direct_map_fun_render_transparent?(
          Types.ir_expr(),
          String.t(),
          Types.function_decl_map(),
          [Types.ir_expr()]
        ) :: boolean()
  defp direct_map_fun_render_transparent?(
         %{op: :lambda, args: args, body: body},
         _module_name,
         _decl_map,
         _prefix_args
       ) do
    case Host.unwrap_direct_lets(body) do
      %{op: :var, name: name} -> name in args
      _ -> false
    end
  end

  defp direct_map_fun_render_transparent?(
         %{op: :var, name: name},
         module_name,
         decl_map,
         prefix_args
       ) do
    direct_render_transparent_decl?(decl_map, {module_name, name}, prefix_args)
  end

  defp direct_map_fun_render_transparent?(
         %{op: :call, name: name, args: args},
         module_name,
         decl_map,
         _prefix_args
       ) do
    direct_map_fun_render_transparent?(
      %{op: :var, name: name},
      module_name,
      decl_map,
      args
    )
  end

  defp direct_map_fun_render_transparent?(_, _, _, _), do: false

  defp direct_render_transparent_decl?(decl_map, {module_name, name}, prefix_args) do
    case Map.get(decl_map, {module_name, name}) do
      %{args: args, expr: expr} ->
        forwarded = Enum.drop(args || [], length(prefix_args))

        case Host.unwrap_direct_lets(expr) do
          %{op: :var, name: var_name} -> var_name in forwarded
          _ -> false
        end

      _ ->
        false
    end
  end

  @spec map_emit_target(
          Types.ir_expr(),
          String.t(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: {:ok, Types.direct_emit_target(), boolean()} | :error
  def map_emit_target(fun_expr, module_name, targets, decl_map) do
    case Host.direct_emit_function_target(fun_expr, module_name) do
      {target_module, target_name, prefix_args} = target ->
        transparent? =
          direct_render_transparent_decl?(decl_map, {target_module, target_name}, prefix_args)

        if transparent? or MapSet.member?(targets, {target_module, target_name}) do
          {:ok, target, transparent?}
        else
          :error
        end

      nil ->
        if direct_map_fun_render_transparent?(fun_expr, module_name, decl_map, []) do
          {:ok, {module_name, nil, []}, true}
        else
          :error
        end
    end
  end

  defp direct_lambda_supported?(
         %{op: :lambda, args: args, body: body},
         module_name,
         decl_map,
         seen
       ) do
    supported?(body, module_name, decl_map, seen) and
      (length(args) == 1 or direct_map_fun_render_transparent?(%{op: :lambda, args: args, body: body}, module_name, decl_map, []))
  end

  defp direct_lambda_supported?(_expr, _module_name, _decl_map, _seen), do: false

  @spec direct_qualified_function_target(String.t(), candidate_set()) ::
          Types.function_decl_key() | nil
  defp direct_qualified_function_target(target, candidates) when is_binary(target) do
    candidate_keys =
      cond do
        match?(%MapSet{}, candidates) -> MapSet.to_list(candidates)
        is_map(candidates) -> Map.keys(candidates)
        true -> Enum.to_list(candidates)
      end

    Enum.find_value(candidate_keys, fn {module_name, decl_name} = key ->
      if target == "#{module_name}.#{decl_name}", do: key
    end)
  end
end
