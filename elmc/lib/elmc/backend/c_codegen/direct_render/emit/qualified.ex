defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Qualified do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Emit.Commands
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Qualified.Draws
  alias Elmc.Backend.CCodegen.DirectRender.Support
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @spec emit_qualified(
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  def emit_qualified("Pebble.Ui.toUiNode", [expr], env, counter),
    do: Host.direct_emit_expr(expr, env, counter)

  def emit_qualified("String.append", [left, right], env, counter) do
    with {:ok, left_code, counter} <- Host.direct_emit_expr(left, env, counter),
         {:ok, right_code, counter} <- Host.direct_emit_expr(right, env, counter) do
      {:ok, left_code <> right_code, counter}
    else
      _ -> :error
    end
  end

  def emit_qualified("List.cons", [head, tail], env, counter) do
    with {:ok, head_code, counter} <- Host.direct_emit_expr(head, env, counter),
         {:ok, tail_code, counter} <- Host.direct_emit_expr(tail, env, counter) do
      {:ok, head_code <> tail_code, counter}
    else
      _ -> :error
    end
  end

  def emit_qualified("List.concat", args, env, counter) do
    case Support.static_concat_items(args) do
      {:ok, items} ->
        Host.direct_emit_expr(%{op: :list_literal, items: items}, env, counter)

      :error ->
        :error
    end
  end

  def emit_qualified(
         "List.indexedMap",
         [%{op: :lambda, args: [index_arg, item_arg], body: body}, list_expr],
         env,
         counter
       ) do
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    if Support.map_fun_render_transparent?(
         %{op: :lambda, args: [index_arg, item_arg], body: body},
         module_name,
         decl_map,
         []
       ) do
      case Host.direct_static_list_items(list_expr) do
        {:ok, static_items} ->
          emit_static_render_items(static_items, env, counter)

        :error ->
          :error
      end
    else
      :error
    end
  end

  def emit_qualified("List.indexedMap", [fun_expr, list_expr], env, counter) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())
    decl_map = Map.get(env, :__program_decls__, %{})

    with {:ok, {target_module, target_name, prefix_args}, transparent?} <-
           Support.map_emit_target(fun_expr, module_name, targets, decl_map) do
      Host.direct_emit_indexed_map_loop(
        fun_expr,
        list_expr,
        {target_module, target_name, prefix_args},
        transparent?,
        env,
        counter
      )
    else
      _ -> :error
    end
  end

  def emit_qualified(
         "List.map",
         [%{op: :lambda, args: [arg], body: body}, list_expr],
         env,
         counter
       ) do
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    if Support.map_fun_render_transparent?(%{op: :lambda, args: [arg], body: body}, module_name, decl_map, []) do
      case Host.direct_static_list_items(list_expr) do
        {:ok, static_items} ->
          emit_static_render_items(static_items, env, counter)

        :error ->
          Host.direct_emit_lambda_map(arg, body, list_expr, env, counter)
      end
    else
      Host.direct_emit_lambda_map(arg, body, list_expr, env, counter)
    end
  end

  def emit_qualified("List.map", [fun_expr, list_expr], env, counter) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())
    decl_map = Map.get(env, :__program_decls__, %{})

    with {:ok, {target_module, target_name, prefix_args}, transparent?} <-
           Support.map_emit_target(fun_expr, module_name, targets, decl_map) do
      Host.direct_emit_map_loop(
        fun_expr,
        list_expr,
        {target_module, target_name, prefix_args},
        transparent?,
        env,
        counter
      )
    else
      _ -> :error
    end
  end

  def emit_qualified("List.concatMap", [fun_expr, list_expr], env, counter) do
    emit_qualified("List.map", [fun_expr, list_expr], env, counter)
  end

  def emit_qualified(
         "Pebble.Ui.windowStack",
         [%{op: :list_literal, items: items}],
         env,
         counter
       ),
       do: Host.direct_emit_expr(%{op: :list_literal, items: items}, env, counter)

  def emit_qualified(
         "Pebble.Ui.window",
         [_id, %{op: :list_literal, items: items}],
         env,
         counter
       ),
       do: Host.direct_emit_expr(%{op: :list_literal, items: items}, env, counter)

  def emit_qualified(
         "Pebble.Ui.canvasLayer",
         [_id, %{op: :list_literal, items: items}],
         env,
         counter
       ),
       do: Host.direct_emit_expr(%{op: :list_literal, items: items}, env, counter)

  def emit_qualified("Pebble.Ui.group", [context_expr], env, counter) do
    context_expr =
      case context_expr do
        %{op: :var, name: name} ->
          case Map.get(env, name) do
            {:direct_fragment, fragment} -> fragment
            _ -> context_expr
          end

        other ->
          other
      end

    case context_expr do
      %{op: :qualified_call, target: ctx_target, args: ctx_args} ->
        case {Host.normalize_special_target(ctx_target), ctx_args} do
          {"Pebble.Ui.context",
           [%{op: :list_literal, items: settings}, %{op: :list_literal, items: commands}]} ->
            with {:ok, push_code, counter} <-
                   Host.direct_append_command(draw_kind(:push_context), [], env, counter),
                 {:ok, settings_code, counter} <- Host.direct_emit_settings(settings, env, counter),
                 {:ok, command_code, counter} <-
                   Host.direct_emit_expr(%{op: :list_literal, items: commands}, env, counter),
                 {:ok, pop_code, counter} <-
                   Host.direct_append_command(draw_kind(:pop_context), [], env, counter) do
              {:ok, push_code <> settings_code <> command_code <> pop_code, counter}
            else
              _ -> :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  def emit_qualified(
         "Pebble.Ui.fillRadial",
         [bounds, start_angle, end_angle],
         env,
         counter
       ),
       do:
         Commands.bounds_command(
           draw_kind(:fill_radial),
           bounds,
           [start_angle, end_angle],
           env,
           counter
         )

  def emit_qualified(target, args, env, counter) do
    case Draws.emit(target, args, env, counter) do
      :no_match ->
        targets = Map.get(env, :__direct_targets__, MapSet.new())

        with {target_module, target_name} <- Support.qualified_function_target(target, targets),
             true <- MapSet.member?(targets, {target_module, target_name}) do
          Host.direct_emit_command_call({target_module, target_name}, args, env, counter)
        else
          _ -> :error
        end

      result ->
        result
    end
  end

  @spec emit_static_render_items(
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def emit_static_render_items(items, env, counter) do
    case Host.direct_static_draw_table_loop(items, env, counter) do
      {:ok, table_code, counter} ->
        {:ok, table_code, counter}

      :error ->
        Enum.reduce_while(items, {:ok, "", counter}, fn item, {:ok, acc, c} ->
          case Host.direct_emit_expr(item, env, c) do
            {:ok, code, c2} -> {:cont, {:ok, acc <> code, c2}}
            :error -> {:halt, :error}
          end
        end)
    end
  end

  defp draw_kind(kind), do: Elmc.Backend.Pebble.draw_kind_id!(kind)
end
