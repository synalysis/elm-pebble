defmodule Elmc.Backend.Plan.Stream do
  @moduledoc """
  DirectRender scene-stream lowering via verified Plan SSA.

  Stream helpers push `render_cmd` values into `ElmcSceneWriter` instead of
  building boxed `List RenderOp` results. Used from `DirectRender.PlanStreamEmit`.
  """
  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Plan.Lower.SpecialValues
  alias Elmc.Backend.Plan.Lower.Stream.List, as: StreamList

  # Kernel scene constructors (FQ after import resolution). Direct render
  # streams their child lists; ids are layout, not draw ops.
  # `Pebble.Ui.group` is not here: arg 0 is a Context, not a child list.
  @scene_tree_child_index %{
    {"Pebble.Ui", "windowStack"} => 0,
    {"Pebble.Ui", "window"} => 1,
    {"Pebble.Ui", "canvasLayer"} => 1
  }

  @context_setting_names MapSet.new([
                           "strokeWidth",
                           "antialiased",
                           "strokeColor",
                           "fillColor",
                           "textColor",
                           "compositingMode"
                         ])

  @spec eligible_expr?(map() | term()) :: boolean()
  def eligible_expr?(expr), do: eligible_expr?(expr, %{}, nil)

  @spec eligible_expr?(map() | term(), map(), String.t() | nil) :: boolean()
  def eligible_expr?(expr, decl_map, module) when is_map(decl_map),
    do: eligible_expr?(expr, decl_map, module, MapSet.new(), MapSet.new())

  @spec eligible_expr?(map() | term(), map(), String.t() | nil, MapSet.t(), MapSet.t()) ::
          boolean()
  def eligible_expr?(expr, decl_map, module, seen, locals \\ MapSet.new())

  def eligible_expr?(%{op: :render_cmd}, _decl_map, _module, _seen, _locals), do: true
  def eligible_expr?(%{op: :render_text_cmd}, _decl_map, _module, _seen, _locals), do: true

  def eligible_expr?(%{op: :list_literal, items: items}, _decl_map, _module, _seen, _locals)
      when is_list(items),
      do: true

  def eligible_expr?(%{op: :var, name: name}, _decl_map, _module, _seen, locals)
      when is_binary(name),
      do: MapSet.member?(locals, name)

  def eligible_expr?(
        %{op: :runtime_call, function: "elmc_list_cons", args: [head, tail]},
        decl_map,
        module,
        seen,
        locals
      ),
      do:
        eligible_expr?(head, decl_map, module, seen, locals) and
          eligible_expr?(tail, decl_map, module, seen, locals)

  def eligible_expr?(
        %{op: :constructor_call, target: target, args: [head, tail]},
        decl_map,
        module,
        seen,
        locals
      )
      when is_binary(target) do
    if StreamList.cons_target?(target) do
      eligible_expr?(head, decl_map, module, seen, locals) and
        eligible_expr?(tail, decl_map, module, seen, locals)
    else
      false
    end
  end

  def eligible_expr?(
        %{op: :call, name: "__append__", args: [left, right]},
        decl_map,
        module,
        seen,
        locals
      ),
      do:
        eligible_expr?(left, decl_map, module, seen, locals) and
          eligible_expr?(right, decl_map, module, seen, locals)

  def eligible_expr?(
        %{op: :if, then_expr: then_expr, else_expr: else_expr},
        decl_map,
        module,
        seen,
        locals
      ),
      do:
        eligible_expr?(then_expr, decl_map, module, seen, locals) and
          eligible_expr?(else_expr, decl_map, module, seen, locals)

  def eligible_expr?(%{op: :if, then: then_expr, else: else_expr}, decl_map, module, seen, locals),
      do:
        eligible_expr?(then_expr, decl_map, module, seen, locals) and
          eligible_expr?(else_expr, decl_map, module, seen, locals)

  def eligible_expr?(
        %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
        decl_map,
        module,
        seen,
        locals
      )
      when is_binary(name) do
    locals =
      if eligible_expr?(value_expr, decl_map, module, seen, locals) do
        MapSet.put(locals, name)
      else
        locals
      end

    eligible_expr?(in_expr, decl_map, module, seen, locals)
  end

  def eligible_expr?(%{op: :let_in, in_expr: in_expr}, decl_map, module, seen, locals),
      do: eligible_expr?(in_expr, decl_map, module, seen, locals)

  def eligible_expr?(%{op: :case, branches: branches}, decl_map, module, seen, locals)
      when is_list(branches) do
    Enum.all?(branches, fn branch ->
      eligible_expr?(Map.get(branch, :expr), decl_map, module, seen, locals)
    end)
  end

  def eligible_expr?(%{op: op} = expr, decl_map, module, seen, locals)
      when op in [:call, :qualified_call] do
    cond do
      pebble_ui_context?(expr) ->
        eligible_ui_context?(expr, decl_map, module, seen, locals)

      pebble_ui_group?(expr) ->
        eligible_ui_group?(expr, decl_map, module, seen, locals)

      pebble_ui_render_special?(expr) ->
        true

      match?(%{}, scene_tree_child(expr, module)) ->
        eligible_expr?(scene_tree_child(expr, module), decl_map, module, seen, locals)

      StreamList.map_call?(expr, module) ->
        StreamList.eligible_map_call?(expr, decl_map, module, seen)

      StreamList.concat_call?(expr, module) ->
        StreamList.eligible_concat_call?(expr, decl_map, module, seen, locals)

      StreamList.cons_call?(expr, module) ->
        StreamList.eligible_cons_call?(expr, decl_map, module, seen, locals)

      StreamList.append_call?(expr, module) ->
        StreamList.eligible_append_call?(expr, decl_map, module, seen, locals)

      true ->
        follow_callee_body(expr, decl_map, module, seen, callee_key(expr, module))
    end
  end

  def eligible_expr?(_, _, _, _, _), do: false

  @doc """
  True when the command expr is a list pipeline (map/concat/cons/++), not a
  static `[clear, text, …]` list. Static lists stay on Host so literal text
  unroll and known-branch folds still run.
  """
  @spec pipeline_expr?(map() | term()) :: boolean()
  def pipeline_expr?(expr), do: pipeline_expr?(expr, %{}, nil)

  @spec pipeline_expr?(map() | term(), map(), String.t() | nil) :: boolean()
  def pipeline_expr?(expr, decl_map, module) when is_map(decl_map),
    do: pipeline_expr?(expr, decl_map, module, MapSet.new())

  @spec pipeline_expr?(map() | term(), map(), String.t() | nil, MapSet.t()) :: boolean()
  defp pipeline_expr?(
         %{op: :constructor_call, target: target, args: [head, tail]},
         decl_map,
         module,
         seen
       )
       when is_binary(target) do
    StreamList.cons_target?(target) and
      (pipeline_expr?(head, decl_map, module, seen) or
         pipeline_expr?(tail, decl_map, module, seen))
  end

  defp pipeline_expr?(%{op: :runtime_call, function: "elmc_list_cons", args: [head, tail]}, decl_map, module, seen),
    do: pipeline_expr?(head, decl_map, module, seen) or pipeline_expr?(tail, decl_map, module, seen)

  defp pipeline_expr?(%{op: :call, name: "__append__", args: [left, right]}, decl_map, module, seen),
    do: pipeline_expr?(left, decl_map, module, seen) or pipeline_expr?(right, decl_map, module, seen)

  defp pipeline_expr?(%{op: :list_literal, items: items}, decl_map, module, seen) when is_list(items),
    do: Enum.any?(items, &pipeline_expr?(&1, decl_map, module, seen))

  defp pipeline_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, decl_map, module, seen),
    do:
      pipeline_expr?(then_expr, decl_map, module, seen) or
        pipeline_expr?(else_expr, decl_map, module, seen)

  defp pipeline_expr?(%{op: :if, then: then_expr, else: else_expr}, decl_map, module, seen),
    do:
      pipeline_expr?(then_expr, decl_map, module, seen) or
        pipeline_expr?(else_expr, decl_map, module, seen)

  defp pipeline_expr?(%{op: :let_in, value_expr: value_expr, in_expr: in_expr}, decl_map, module, seen),
    do:
      pipeline_expr?(value_expr, decl_map, module, seen) or
        pipeline_expr?(in_expr, decl_map, module, seen)

  defp pipeline_expr?(%{op: :case, branches: branches}, decl_map, module, seen) when is_list(branches),
    do: Enum.any?(branches, &pipeline_expr?(Map.get(&1, :expr), decl_map, module, seen))

  defp pipeline_expr?(%{op: op} = expr, decl_map, module, seen) when op in [:call, :qualified_call] do
    cond do
      StreamList.map_call?(expr, module) ->
        true

      StreamList.concat_call?(expr, module) ->
        true

      StreamList.cons_call?(expr, module) ->
        true

      StreamList.append_call?(expr, module) ->
        true

      pebble_ui_context?(expr) ->
        expr |> Map.get(:args, []) |> Enum.at(1) |> pipeline_expr?(decl_map, module, seen)

      pebble_ui_group?(expr) ->
        expr |> Map.get(:args, []) |> Enum.at(0) |> pipeline_expr?(decl_map, module, seen)

      match?(%{}, scene_tree_child(expr, module)) ->
        pipeline_expr?(scene_tree_child(expr, module), decl_map, module, seen)

      true ->
        follow_pipeline_callee(expr, decl_map, module, seen)
    end
  end

  defp pipeline_expr?(_, _, _, _), do: false

  defp follow_pipeline_callee(expr, decl_map, module, seen) do
    case callee_key(expr, module) do
      {mod, _name} = key ->
        cond do
          MapSet.member?(seen, key) ->
            false

          match?(%{expr: body} when is_map(body), Map.get(decl_map, key)) ->
            pipeline_expr?(Map.get(decl_map, key).expr, decl_map, mod, MapSet.put(seen, key))

          true ->
            false
        end

      _ ->
        false
    end
  end

  @spec lower_function(map(), String.t(), map(), keyword()) ::
          {:ok, map()} | :unsupported | {:error, term()}
  def lower_function(decl, module_name, decl_map, opts \\ []) do
    expr = Map.get(decl, :expr)

    if eligible_expr?(expr, decl_map, module_name) do
      Function.lower(
        decl,
        module_name,
        decl_map,
        Keyword.merge([stream_mode: true, rc_required: true], opts)
      )
    else
      :unsupported
    end
  end

  @spec callee_key(map(), String.t() | nil) :: {String.t(), String.t()} | nil
  def callee_key(%{op: :qualified_call, target: target}, module) when is_binary(target),
    do: split_target(target, module)

  def callee_key(%{op: :call, target: target}, module) when is_binary(target),
    do: split_target(target, module)

  def callee_key(%{op: :call, name: name}, module) when is_binary(name),
    do: split_target(name, module)

  def callee_key(_, _), do: nil

  @spec scene_tree_child(map(), String.t() | nil) :: map() | nil
  def scene_tree_child(expr, module) when is_map(expr) do
    case Map.get(@scene_tree_child_index, callee_key(expr, module)) do
      idx when is_integer(idx) ->
        expr |> Map.get(:args, []) |> Enum.at(idx)

      _ ->
        nil
    end
  end

  def scene_tree_child(_, _), do: nil

  defp pebble_ui_context?(expr), do: pebble_ui_name?(expr, "context")
  defp pebble_ui_group?(expr), do: pebble_ui_name?(expr, "group")

  defp pebble_ui_name?(expr, name) when is_binary(name) do
    case callee_key(expr, nil) do
      {"Pebble.Ui", ^name} -> true
      _ -> false
    end
  end

  defp pebble_ui_render_special?(expr) when is_map(expr) do
    case callee_key(expr, nil) do
      {"Pebble.Ui", name} when is_binary(name) ->
        args = Map.get(expr, :args, [])

        case SpecialValues.special_value_from_target("Pebble.Ui.#{name}", args) do
          %{op: op} when op in [:render_cmd, :render_text_cmd] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp eligible_ui_context?(%{args: [settings, commands]}, decl_map, module, seen, locals) do
    eligible_context_settings?(settings, decl_map, module, seen, locals) and
      eligible_expr?(commands, decl_map, module, seen, locals)
  end

  defp eligible_ui_context?(_, _, _, _, _), do: false

  defp eligible_ui_group?(%{args: [inner]}, decl_map, module, seen, locals) do
    cond do
      pebble_ui_context?(inner) ->
        eligible_ui_context?(inner, decl_map, module, seen, locals)

      true ->
        eligible_expr?(inner, decl_map, module, seen, locals)
    end
  end

  defp eligible_ui_group?(_, _, _, _, _), do: false

  defp eligible_context_settings?(%{op: :list_literal, items: items}, decl_map, module, seen, locals)
       when is_list(items) do
    Enum.all?(items, &eligible_context_setting?(&1, decl_map, module, seen, locals))
  end

  defp eligible_context_settings?(_, _, _, _, _), do: false

  defp eligible_context_setting?(%{op: op} = expr, _decl_map, _module, _seen, _locals)
       when op in [:call, :qualified_call] do
    case callee_key(expr, nil) do
      {"Pebble.Ui", name} -> MapSet.member?(@context_setting_names, name)
      _ -> false
    end
  end

  defp eligible_context_setting?(_, _, _, _, _), do: false

  defp follow_callee_body(_expr, decl_map, _module, seen, {mod, _name} = key) do
    cond do
      MapSet.member?(seen, key) ->
        false

      match?(%{expr: body} when is_map(body), Map.get(decl_map, key)) ->
        eligible_expr?(
          Map.get(decl_map, key).expr,
          decl_map,
          mod,
          MapSet.put(seen, key),
          MapSet.new()
        )

      true ->
        false
    end
  end

  defp follow_callee_body(_, _, _, _, _), do: false

  defp split_target(target, module) when is_binary(target) do
    case String.split(target, ".", trim: true) do
      [name] ->
        if is_binary(module), do: {module, name}, else: nil

      [_ | _] = parts ->
        {Enum.join(Enum.drop(parts, -1), "."), List.last(parts)}

      _ ->
        nil
    end
  end
end
