defmodule Elmc.Backend.CCodegen.DirectAffine do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @literal_text_unroll_max 16

  @type function_target :: Types.function_target()

  defp draw_kind(kind), do: Elmc.Backend.Pebble.draw_kind_id!(kind)

  @spec unwrap_bindings(Types.ir_expr()) :: Types.ir_expr()
  @doc false
  def unwrap_bindings(expr) do
    {expr, _} = unwrap_direct_affine_bindings(expr)
    expr
  end

  @spec direct_draw_affine_template(
          Types.function_decl_map(),
          function_target(),
          String.t(),
          Types.compile_env()
        ) :: Types.affine_analysis_result()
  def direct_draw_affine_template(
        decl_map,
        {target_module, target_name, _prefix_args},
        loop_var,
        env
      ) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{expr: expr} when not is_nil(expr) ->
        analyze_affine_draw_body(expr, loop_var, env)

      _ ->
        :error
    end
  end

  @spec direct_draw_affine_template_indexed(
          Types.function_decl_map(),
          function_target(),
          Types.compile_env()
        ) :: Types.affine_indexed_template_result()
  def direct_draw_affine_template_indexed(
        decl_map,
        {target_module, target_name, prefix_args},
        env
      ) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{args: args, expr: expr} when is_list(args) and not is_nil(expr) ->
        prefix_count = length(prefix_args)

        prefix_param_map =
          args
          |> Enum.take(prefix_count)
          |> Enum.with_index()
          |> Map.new(fn {param, idx} -> {affine_binding_name(param), idx} end)

        affine_env =
          env
          |> Map.put(:__affine_prefix_params__, prefix_param_map)
          |> Map.put(
            :__affine_prefix_shapes__,
            Enum.map(prefix_args, &Host.record_shape(&1, env))
          )

        case Enum.drop(args, prefix_count) do
          [index_param, item_param | _] ->
            case analyze_affine_draw_body_indexed(expr, index_param, item_param, affine_env) do
              {:ok, spec} ->
                {:ok,
                 Map.put(
                   spec,
                   :prefix_shapes,
                   Map.get(affine_env, :__affine_prefix_shapes__, [])
                 ), index_param, item_param}

              :error ->
                :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp analyze_affine_draw_body(expr, loop_var, env) do
    {expr, bindings} = unwrap_direct_affine_bindings(expr)

    analyze_affine_draw_target(expr, fn single ->
      analyze_affine_draw_expr(single, loop_var, env, bindings)
    end)
  end

  defp analyze_affine_draw_body_indexed(expr, index_param, item_param, env) do
    {expr, bindings} = unwrap_direct_affine_bindings(expr)

    analyze_affine_draw_target(expr, fn single ->
      analyze_affine_draw_expr_indexed(single, index_param, item_param, env, bindings)
    end)
  end

  defp unwrap_direct_affine_bindings(expr, bindings \\ %{}) do
    case expr do
      %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr} ->
        unwrap_direct_affine_bindings(
          in_expr,
          Map.put(bindings, affine_binding_name(name), value_expr)
        )

      _ ->
        {expr, bindings}
    end
  end

  defp affine_binding_name(name) when is_atom(name), do: Atom.to_string(name)
  defp affine_binding_name(name) when is_binary(name), do: name

  defp resolve_affine_expr(%{op: :var, name: name}, bindings) do
    key = affine_binding_name(name)

    case Map.get(bindings, key) || Map.get(bindings, name) do
      nil -> %{op: :var, name: name}
      expr -> resolve_affine_expr(expr, bindings)
    end
  end

  defp resolve_affine_expr(expr, _bindings), do: expr

  defp unwrap_direct_render_shell(expr) do
    case expr do
      %{op: :qualified_call, target: target, args: [inner]} ->
        case Host.normalize_special_target(target) do
          "Pebble.Ui.group" -> unwrap_direct_render_shell(inner)
          _ -> {:single, expr}
        end

      %{op: :qualified_call, target: target, args: [settings, commands]} ->
        case Host.normalize_special_target(target) do
          "Pebble.Ui.context" ->
            case {settings, commands} do
              {%{op: :list_literal, items: settings_items},
               %{op: :list_literal, items: command_items}} ->
                {:context, settings_items, command_items}

              _ ->
                {:single, expr}
            end

          _ ->
            {:single, expr}
        end

      _ ->
        {:single, expr}
    end
  end

  defp analyze_affine_draw_target(expr, analyze_one) do
    case unwrap_direct_render_shell(expr) do
      {:single, single} ->
        analyze_one.(single)

      {:context, settings, items} ->
        if Enum.all?(settings, &Host.direct_setting_supported?/1) do
          specs = Enum.map(items, analyze_one)

          if length(specs) == length(items) and Enum.all?(specs, &match?({:ok, _}, &1)) do
            {:ok,
             %{
               commands: Enum.map(specs, fn {:ok, spec} -> spec end),
               context_settings: settings
             }}
          else
            :error
          end
        else
          :error
        end
    end
  end

  defp analyze_affine_draw_expr(expr, loop_var, env, bindings) do
    case expr do
      %{op: :qualified_call, target: target, args: [font, pos, value]} ->
        case Host.normalize_special_target(target) do
          "Pebble.Ui.textInt" ->
            with {:ok, font_ref} <- direct_must_literal_int(font, env),
                 {:ok, x_param} <-
                   affine_bounds_field_param(
                     Host.record_field_expr(pos, "x"),
                     loop_var,
                     nil,
                     bindings
                   ),
                 {:ok, y_param} <-
                   affine_record_field_int_param(pos, "y", loop_var, env, bindings),
                 {:ok, value_ref} <- affine_native_loop_ref(value, loop_var, env) do
              {:ok,
               %{
                 kind: :text_int,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:text_int_with_font)),
                 params: [font_ref, x_param, y_param, value_ref]
               }}
            end

          _ ->
            :error
        end

      %{op: :qualified_call, target: target, args: args} ->
        case Host.normalize_special_target(target) do
          "Pebble.Ui.rect" ->
            with [bounds, color] <- args do
              analyze_affine_bounds_command(
                draw_kind(:rect),
                bounds,
                color,
                loop_var,
                nil,
                env,
                bindings
              )
            end

          "Pebble.Ui.fillRect" ->
            with [bounds, color] <- args do
              analyze_affine_bounds_command(
                draw_kind(:fill_rect),
                bounds,
                color,
                loop_var,
                nil,
                env,
                bindings
              )
            end

          "Pebble.Ui.pixel" ->
            with [pos, color] <- args,
                 {:ok, x_param} <-
                   affine_bounds_field_param(
                     Host.record_field_expr(pos, "x"),
                     loop_var,
                     nil,
                     bindings
                   ),
                 {:ok, y_param} <-
                   affine_record_field_int_param(pos, "y", loop_var, env, bindings),
                 {:ok, color_ref} <- direct_must_literal_int(color, env) do
              {:ok,
               %{
                 kind: :pixel,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:pixel)),
                 params: [x_param, y_param, color_ref]
               }}
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp analyze_affine_draw_expr_indexed(expr, index_param, item_param, env, bindings) do
    case expr do
      %{op: :qualified_call, target: target, args: [font, pos, value]} ->
        case Host.normalize_special_target(target) do
          "Pebble.Ui.textInt" ->
            with {:ok, font_ref} <- direct_must_literal_int(font, env),
                 {:ok, x_param} <-
                   affine_bounds_field_param(
                     Host.record_field_expr(pos, "x"),
                     index_param,
                     item_param,
                     bindings,
                     env
                   ),
                 {:ok, y_param} <-
                   affine_record_field_int_param_indexed(
                     pos,
                     "y",
                     index_param,
                     item_param,
                     env,
                     bindings
                   ),
                 {:ok, value_ref} <-
                   affine_native_loop_ref_indexed(value, index_param, item_param, env) do
              {:ok,
               %{
                 kind: :text_int,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:text_int_with_font)),
                 params: [font_ref, x_param, y_param, value_ref]
               }}
            end

          _ ->
            :error
        end

      %{op: :qualified_call, target: target, args: args} ->
        case Host.normalize_special_target(target) do
          "Pebble.Ui.rect" ->
            with [bounds, color] <- args do
              analyze_affine_bounds_command(
                draw_kind(:rect),
                bounds,
                color,
                index_param,
                item_param,
                env,
                bindings
              )
            end

          "Pebble.Ui.fillRect" ->
            with [bounds, color] <- args do
              analyze_affine_bounds_command(
                draw_kind(:fill_rect),
                bounds,
                color,
                index_param,
                item_param,
                env,
                bindings
              )
            end

          "Pebble.Ui.text" ->
            with [font, options, bounds, label] <- args do
              analyze_affine_text_command(
                font,
                options,
                bounds,
                label,
                index_param,
                item_param,
                env,
                bindings
              )
            end

          "Pebble.Ui.pixel" ->
            with [pos, color] <- args,
                 {:ok, x_param} <-
                   affine_bounds_field_param(
                     Host.record_field_expr(pos, "x"),
                     index_param,
                     item_param,
                     bindings,
                     env
                   ),
                 {:ok, y_param} <-
                   affine_record_field_int_param_indexed(
                     pos,
                     "y",
                     index_param,
                     item_param,
                     env,
                     bindings
                   ),
                 {:ok, color_ref} <- direct_must_literal_int(color, env) do
              {:ok,
               %{
                 kind: :pixel,
                 kind_macro: Host.generated_draw_kind_macro(draw_kind(:pixel)),
                 params: [x_param, y_param, color_ref]
               }}
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp analyze_affine_bounds_command(
         kind,
         bounds,
         color,
         index_param,
         item_param,
         env,
         bindings
       ) do
    with {:ok, x_param} <-
           affine_bounds_field_param(
             Host.record_field_expr(bounds, "x"),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, y_param} <-
           affine_bound_dimension(
             Host.record_field_expr(bounds, "y"),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, w_param} <-
           affine_bound_dimension(
             Host.record_field_expr(bounds, "w"),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, h_param} <-
           affine_bound_dimension(
             Host.record_field_expr(bounds, "h"),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, color_spec} <- analyze_affine_bounds_color(color, item_param, bindings, env) do
      {:ok,
       %{
         kind: kind,
         kind_macro: Host.generated_draw_kind_macro(kind),
         params: [x_param, y_param, w_param, h_param, affine_bounds_color_param(color_spec)],
         fill_emit_guard: affine_fill_emit_guard(color_spec, kind)
       }}
    end
  end

  defp analyze_affine_bounds_color(expr, item_param, bindings, env) do
    expr = resolve_affine_expr(expr, bindings)

    case expr do
      %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr} ->
        with true <- affine_zero_test?(cond, item_param),
             {:ok, _} <- direct_must_literal_int(then_expr, env),
             {:ok, nonzero} <- direct_must_literal_int(else_expr, env) do
          {:ok, {:skip_when_zero, affine_binding_name(item_param), nonzero}}
        else
          _ -> analyze_affine_bounds_color_literal(expr, env)
        end

      _ ->
        analyze_affine_bounds_color_literal(expr, env)
    end
  end

  defp analyze_affine_bounds_color_literal(expr, env) do
    case direct_must_literal_int(expr, env) do
      {:ok, color} -> {:ok, {:literal, color}}
      :error -> :error
    end
  end

  defp affine_bounds_color_param({:literal, color}), do: color
  defp affine_bounds_color_param({:skip_when_zero, _item, nonzero}), do: nonzero

  defp affine_fill_emit_guard({:skip_when_zero, item, _}, kind) do
    if kind == draw_kind(:fill_rect), do: {:nonzero, item}, else: nil
  end

  defp affine_fill_emit_guard(_, _), do: nil

  defp analyze_affine_text_command(
         font,
         options,
         bounds,
         label,
         index_param,
         item_param,
         env,
         bindings
       ) do
    with {:ok, font_ref} <- direct_must_literal_int(font, env),
         {:ok, options_ref} <- affine_text_options_ref(options, env),
         {:ok, x_param} <-
           affine_bounds_field_param(
             Host.record_field_expr(bounds, "x"),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, y_param} <-
           affine_bound_dimension(
             Host.record_field_expr(bounds, "y"),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, w_param} <-
           affine_bound_dimension(
             Host.record_field_expr(bounds, "w"),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, h_param} <-
           affine_bound_dimension(
             Host.record_field_expr(bounds, "h"),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, label_spec} <- analyze_affine_text_label(label, item_param, bindings) do
      {:ok,
       %{
         kind: :text,
         kind_macro: Host.generated_draw_kind_macro(draw_kind(:text)),
         params: [font_ref, x_param, y_param, w_param, h_param, options_ref],
         label: label_spec
       }}
    end
  end

  defp analyze_affine_text_label(expr, item_param, bindings) do
    expr = resolve_affine_expr(expr, bindings)

    case expr do
      %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr} ->
        with true <- affine_zero_test?(cond, item_param),
             {:ok, zero_label} <- direct_string_literal_value(then_expr),
             true <- affine_from_int_item?(else_expr, item_param) do
          {:ok, {:from_int, affine_binding_name(item_param), zero_label}}
        else
          _ -> :error
        end

      _ ->
        case direct_string_literal_value(expr) do
          {:ok, literal} -> {:ok, {:literal, literal}}
          :error -> :error
        end
    end
  end

  defp affine_zero_test?(
         %{
           op: :call,
           name: "__eq__",
           args: [%{op: :var, name: left}, %{op: :int_literal, value: 0}]
         },
         item_param
       ),
       do: affine_binding_name(left) == affine_binding_name(item_param)

  defp affine_zero_test?(
         %{
           op: :call,
           name: "__eq__",
           args: [%{op: :int_literal, value: 0}, %{op: :var, name: right}]
         },
         item_param
       ),
       do: affine_binding_name(right) == affine_binding_name(item_param)

  defp affine_zero_test?(
         %{op: :compare, kind: :eq, left: left, right: %{op: :int_literal, value: 0}},
         item_param
       ),
       do: affine_var_matches_loop_param?(left, item_param)

  defp affine_zero_test?(
         %{op: :compare, kind: :eq, left: %{op: :int_literal, value: 0}, right: right},
         item_param
       ),
       do: affine_var_matches_loop_param?(right, item_param)

  defp affine_zero_test?(_, _), do: false

  defp affine_from_int_item?(
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
         item_param
       ),
       do: affine_var_matches_loop_param?(value, item_param)

  defp affine_from_int_item?(
         %{op: :qualified_call, target: "String.fromInt", args: [value]},
         item_param
       ),
       do: affine_var_matches_loop_param?(value, item_param)

  defp affine_from_int_item?(_, _), do: false

  defp direct_string_literal_value(%{op: :string_literal, value: value}), do: {:ok, value}
  defp direct_string_literal_value(_), do: :error

  defp affine_text_options_ref(%{op: :qualified_call, target: target, args: []}, _env) do
    case Host.normalize_special_target(target) do
      "Pebble.Ui.defaultTextOptions" ->
        {:ok,
         "(ELMC_TEXT_ALIGN_CENTER + (ELMC_TEXT_OVERFLOW_WORD_WRAP * (1 << ELMC_TEXT_OVERFLOW_SHIFT)))"}

      _ ->
        :error
    end
  end

  defp affine_text_options_ref(%{op: :qualified_call, target: target, args: [inner]}, env) do
    case Host.normalize_special_target(target) do
      "Pebble.Ui.alignCenter" -> affine_text_options_ref(inner, env)
      _ -> :error
    end
  end

  defp affine_text_options_ref(options, env),
    do: direct_must_literal_int(Host.text_options_expr(options), env)

  defp affine_bound_dimension(field_expr, index_param, item_param, bindings, env) do
    case affine_bounds_field_param(field_expr, index_param, item_param, bindings, env) do
      {:ok, coord_param} ->
        {:ok, coord_param}

      :error ->
        case resolve_affine_expr(field_expr, bindings) do
          expr ->
            case direct_must_literal_int(expr, env) do
              {:ok, ref} -> {:ok, ref}
              :error -> :error
            end
        end
    end
  end

  defp affine_record_field_int_param(pos, field, param, env, bindings) do
    case affine_bounds_field_param(Host.record_field_expr(pos, field), param, nil, bindings) do
      {:ok, coord_param} ->
        {:ok, coord_param}

      :error ->
        expr = resolve_affine_expr(Host.record_field_expr(pos, field), bindings)

        if affine_var_matches_loop_param?(expr, param) do
          {:ok, {:loop, affine_var_name(expr)}}
        else
          case direct_must_literal_int(expr, env) do
            {:ok, ref} -> {:ok, ref}
            :error -> :error
          end
        end
    end
  end

  defp affine_record_field_int_param_indexed(pos, field, index_param, item_param, env, bindings) do
    case affine_bounds_field_param(
           Host.record_field_expr(pos, field),
           index_param,
           item_param,
           bindings,
           env
         ) do
      {:ok, coord_param} ->
        {:ok, coord_param}

      :error ->
        case resolve_affine_expr(Host.record_field_expr(pos, field), bindings) do
          expr ->
            case affine_native_loop_ref_indexed(expr, index_param, item_param, env) do
              {:ok, loop_param} -> {:ok, loop_param}
              :error -> :error
            end
        end
    end
  end

  defp affine_bounds_field_param(nil, _index_param, _item_param, _bindings), do: :error

  defp affine_bounds_field_param(field_expr, index_param, item_param, bindings, env \\ %{}) do
    field_expr
    |> resolve_affine_expr(bindings)
    |> affine_bounds_field_param_expr(index_param, item_param, bindings, env)
  end

  defp affine_bounds_field_param_expr(expr, index_param, item_param, bindings, env) do
    loop_params =
      [index_param, item_param]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&affine_binding_name/1)
      |> Enum.uniq()

    cond do
      match?({:ok, _}, affine_add_mod_mul_param(expr, index_param, item_param, bindings, env)) ->
        affine_add_mod_mul_param(expr, index_param, item_param, bindings, env)

      match?({:ok, _}, affine_add_idiv_mul_param(expr, index_param, item_param, bindings, env)) ->
        affine_add_idiv_mul_param(expr, index_param, item_param, bindings, env)

      match?(
        {:ok, _},
        affine_add_prefix_idiv_offset_param(expr, index_param, item_param, bindings, env)
      ) ->
        affine_add_prefix_idiv_offset_param(expr, index_param, item_param, bindings, env)

      match?({:ok, _}, affine_mul_param(expr, loop_params)) ->
        affine_mul_param(expr, loop_params)

      match?({:ok, _}, affine_add_mul_param(expr, loop_params, env)) ->
        affine_add_mul_param(expr, loop_params, env)

      match?({:ok, _}, affine_offset_param(expr, index_param, item_param, bindings)) ->
        affine_offset_param(expr, index_param, item_param, bindings)

      match?({:ok, _}, affine_add_const_param(expr, index_param, item_param, bindings)) ->
        affine_add_const_param(expr, index_param, item_param, bindings)

      match?({:ok, _}, affine_prefix_field_param(expr, env)) ->
        affine_prefix_field_param(expr, env)

      affine_var_matches_loop_param?(expr, index_param) ->
        {:ok, {:loop, affine_var_name(expr)}}

      affine_var_matches_loop_param?(expr, item_param) ->
        {:ok, {:loop, affine_var_name(expr)}}

      true ->
        :error
    end
  end

  defp affine_offset_param(
         %{op: :call, name: "__add__", args: [left, %{op: :int_literal, value: offset}]},
         index_param,
         item_param,
         bindings
       ) do
    case affine_bounds_field_param(left, index_param, item_param, bindings) do
      {:ok, base_param} -> {:ok, {:offset, base_param, offset}}
      :error -> :error
    end
  end

  defp affine_offset_param(
         %{op: :call, name: "__add__", args: [%{op: :int_literal, value: offset}, right]},
         index_param,
         item_param,
         bindings
       ) do
    case affine_bounds_field_param(right, index_param, item_param, bindings) do
      {:ok, base_param} -> {:ok, {:offset, base_param, offset}}
      :error -> :error
    end
  end

  defp affine_offset_param(_, _, _, _), do: :error

  defp affine_add_const_param(
         %{op: :add_const, var: name, value: offset},
         index_param,
         item_param,
         bindings
       ) do
    case affine_bounds_field_param(%{op: :var, name: name}, index_param, item_param, bindings) do
      {:ok, base_param} -> {:ok, {:offset, base_param, offset}}
      :error -> :error
    end
  end

  defp affine_add_const_param(_, _, _, _), do: :error

  defp affine_var_matches_loop_param?(%{op: :var, name: name}, loop_param) do
    not is_nil(loop_param) and affine_binding_name(name) == affine_binding_name(loop_param)
  end

  defp affine_var_matches_loop_param?(_, _), do: false

  defp affine_var_name(%{op: :var, name: name}), do: affine_binding_name(name)

  defp affine_mul_param(
         %{
           op: :call,
           name: "__mul__",
           args: [%{op: :var, name: param}, %{op: :int_literal, value: scale}]
         },
         loop_params
       ) do
    if affine_binding_name(param) in loop_params do
      {:ok, {:mul, affine_binding_name(param), scale}}
    else
      :error
    end
  end

  defp affine_mul_param(
         %{
           op: :call,
           name: "__mul__",
           args: [%{op: :int_literal, value: scale}, %{op: :var, name: param}]
         },
         loop_params
       ) do
    if affine_binding_name(param) in loop_params do
      {:ok, {:mul, affine_binding_name(param), scale}}
    else
      :error
    end
  end

  defp affine_mul_param(_, _), do: :error

  defp affine_add_mul_param(
         %{op: :call, name: "__add__", args: [left, right]},
         loop_params,
         env
       ) do
    with {:ok, base} <- affine_coord_operand(left, env),
         {:ok, {:mul, param, scale}} <- affine_mul_param(right, loop_params) do
      {:ok, {:affine, param, base, scale}}
    else
      _ ->
        with {:ok, base} <- affine_coord_operand(right, env),
             {:ok, {:mul, param, scale}} <- affine_mul_param(left, loop_params) do
          {:ok, {:affine, param, base, scale}}
        else
          _ -> :error
        end
    end
  end

  defp affine_add_mul_param(_, _, _), do: :error

  defp affine_coord_operand(expr, env) do
    cond do
      match?({:ok, _}, affine_coord_literal(expr)) ->
        affine_coord_literal(expr)

      match?({:ok, _}, affine_prefix_field_param(expr, env)) ->
        affine_prefix_field_param(expr, env)

      true ->
        :error
    end
  end

  defp affine_prefix_field_param(%{op: :field_access, arg: arg, field: field}, env) do
    case arg do
      %{op: :var, name: name} ->
        case Map.get(env, name) do
          {:native_record, native_fields} ->
            case Map.fetch(native_fields, field) do
              {:ok, native_ref} -> {:ok, {:native_ref, native_ref}}
              :error -> :error
            end

          _ ->
            affine_prefix_field_param_from_index(name, field, env)
        end

      _ ->
        case affine_field_access_root_name(arg) do
          nil -> :error
          name -> affine_prefix_field_param_from_index(name, field, env)
        end
    end
  end

  defp affine_prefix_field_param(_, _), do: :error

  defp affine_prefix_field_param_from_index(name, field, env) do
    case affine_prefix_param_index(env, name) do
      {:ok, idx} -> {:ok, {:prefix_field, idx, field}}
      :error -> :error
    end
  end

  defp affine_field_access_root_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp affine_field_access_root_name(name) when is_binary(name), do: name
  defp affine_field_access_root_name(_), do: nil

  defp affine_prefix_param_index(env, name) do
    env
    |> Map.get(:__affine_prefix_params__, %{})
    |> Map.fetch(affine_binding_name(name))
  end

  defp affine_stride_operand(expr, index_param, _item_param, _bindings, env) do
    cond do
      match?({:ok, _}, affine_coord_literal(expr)) ->
        affine_coord_literal(expr)

      match?({:ok, _}, affine_prefix_field_param(expr, env)) ->
        affine_prefix_field_param(expr, env)

      match?({:ok, _}, affine_prefix_add_operand(expr, env)) ->
        affine_prefix_add_operand(expr, env)

      match?({:ok, _}, affine_mod_mul_param(expr, index_param, env)) ->
        affine_mod_mul_param(expr, index_param, env)

      match?({:ok, _}, affine_idiv_mul_param(expr, index_param, env)) ->
        affine_idiv_mul_param(expr, index_param, env)

      true ->
        :error
    end
  end

  defp affine_prefix_add_operand(
         %{op: :call, name: "__add__", args: [left, right]},
         env
       ) do
    with {:ok, {:prefix_field, idx, left_field}} <- affine_prefix_field_param(left, env),
         {:ok, {:prefix_field, ^idx, right_field}} <- affine_prefix_field_param(right, env) do
      {:ok, {:prefix_add, idx, left_field, right_field}}
    else
      _ -> :error
    end
  end

  defp affine_prefix_add_operand(_, _), do: :error

  defp affine_mod_call(expr, index_param) do
    case expr do
      %{op: :call, name: "modBy", args: [base, value]} ->
        affine_mod_call_args(base, value, index_param)

      %{op: :qualified_call, target: target, args: [base, value]} ->
        case Host.normalize_special_target(target) do
          "Basics.modBy" -> affine_mod_call_args(base, value, index_param)
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp affine_mod_call_args(base, value, index_param) do
    with %{op: :int_literal, value: modulus} <- base,
         true <- affine_var_matches_loop_param?(value, index_param) do
      {:ok, {:mod, affine_var_name(value), modulus}}
    else
      _ -> :error
    end
  end

  defp affine_idiv_call(expr, index_param) do
    case expr do
      %{op: :call, name: "__idiv__", args: [left, %{op: :int_literal, value: divisor}]} ->
        if affine_var_matches_loop_param?(left, index_param) do
          {:ok, {:idiv, affine_var_name(left), divisor}}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp affine_mod_mul_param(%{op: :call, name: "__mul__", args: [left, right]}, index_param, env) do
    with {:ok, {:mod, param, modulus}} <- affine_mod_call(left, index_param),
         {:ok, stride} <- affine_stride_operand(right, index_param, nil, %{}, env) do
      {:ok, {:mod_mul, param, modulus, stride}}
    else
      _ ->
        with {:ok, {:mod, param, modulus}} <- affine_mod_call(right, index_param),
             {:ok, stride} <- affine_stride_operand(left, index_param, nil, %{}, env) do
          {:ok, {:mod_mul, param, modulus, stride}}
        else
          _ -> :error
        end
    end
  end

  defp affine_mod_mul_param(_, _, _), do: :error

  defp affine_idiv_mul_param(%{op: :call, name: "__mul__", args: [left, right]}, index_param, env) do
    with {:ok, {:idiv, param, divisor}} <- affine_idiv_call(left, index_param),
         {:ok, stride} <- affine_stride_operand(right, index_param, nil, %{}, env) do
      {:ok, {:idiv_mul, param, divisor, stride}}
    else
      _ ->
        with {:ok, {:idiv, param, divisor}} <- affine_idiv_call(right, index_param),
             {:ok, stride} <- affine_stride_operand(left, index_param, nil, %{}, env) do
          {:ok, {:idiv_mul, param, divisor, stride}}
        else
          _ -> :error
        end
    end
  end

  defp affine_idiv_mul_param(_, _, _), do: :error

  defp affine_add_mod_mul_param(
         %{op: :call, name: "__add__", args: [left, right]},
         index_param,
         _item_param,
         _bindings,
         env
       ) do
    with {:ok, base} <- affine_coord_operand(left, env),
         {:ok, mod_mul} <- affine_mod_mul_param(right, index_param, env) do
      {:ok, {:add_mod_mul, base, mod_mul}}
    else
      _ -> :error
    end
  end

  defp affine_add_mod_mul_param(_, _, _, _, _), do: :error

  defp affine_add_idiv_mul_param(
         %{op: :call, name: "__add__", args: [left, right]},
         index_param,
         _item_param,
         _bindings,
         env
       ) do
    with {:ok, base} <- affine_coord_operand(left, env),
         {:ok, idiv_mul} <- affine_idiv_mul_param(right, index_param, env) do
      {:ok, {:add_idiv_mul, base, idiv_mul}}
    else
      _ -> :error
    end
  end

  defp affine_add_idiv_mul_param(_, _, _, _, _), do: :error

  defp affine_prefix_idiv_operand(
         %{op: :call, name: "__idiv__", args: [left, %{op: :int_literal, value: divisor}]},
         env
       ) do
    case left do
      %{op: :call, name: "__sub__", args: [sub_left, %{op: :int_literal, value: subtrahend}]} ->
        with {:ok, {:prefix_field, idx, field}} <- affine_prefix_field_param(sub_left, env) do
          {:ok, {:prefix_idiv, idx, field, subtrahend, divisor}}
        end

      _ ->
        :error
    end
  end

  defp affine_prefix_idiv_operand(_, _), do: :error

  defp affine_add_prefix_idiv_offset_param(
         %{op: :call, name: "__add__", args: [left, right]},
         index_param,
         item_param,
         bindings,
         env
       ) do
    with {:ok, base} <-
           affine_bounds_field_param_expr(
             resolve_affine_expr(left, bindings),
             index_param,
             item_param,
             bindings,
             env
           ),
         {:ok, offset} <- affine_prefix_idiv_operand(right, env) do
      {:ok, {:add_prefix_idiv, base, offset}}
    else
      _ -> :error
    end
  end

  defp affine_add_prefix_idiv_offset_param(_, _, _, _, _), do: :error

  defp affine_coord_literal(%{op: :int_literal, value: value}), do: {:ok, value}
  defp affine_coord_literal(%{op: :char_literal, value: value}), do: {:ok, value}
  defp affine_coord_literal(_), do: :error

  defp direct_must_literal_int(%{op: :int_literal} = expr, _env),
    do: {:ok, "#{Host.int_literal_compile_value(expr)}"}

  defp direct_must_literal_int(%{op: :char_literal, value: value}, _env), do: {:ok, "#{value}"}

  defp direct_must_literal_int(%{op: :c_int_expr, value: value}, _env) when is_binary(value),
    do: {:ok, value}

  defp direct_must_literal_int(%{op: :qualified_call, target: target, args: args}, _env) do
    cond do
      Host.resource_union_constructor?(target, args) ->
        {:ok, "#{Host.pebble_resource_slot_index(target)}"}

      true ->
        case Host.special_value_from_target(target, args) do
          %{op: :int_literal, value: value} -> {:ok, "#{value}"}
          %{op: :c_int_expr, value: value} when is_binary(value) -> {:ok, value}
          _ -> :error
        end
    end
  end

  defp direct_must_literal_int(_, _), do: :error

  defp affine_native_loop_ref(%{op: :var, name: name}, item_param, _env)
       when name == item_param,
       do: {:ok, {:loop, item_param}}

  defp affine_native_loop_ref(%{op: :int_literal} = expr, _loop_var, _env),
    do: direct_must_literal_int(expr, %{})

  defp affine_native_loop_ref(_, _, _), do: :error

  defp affine_native_loop_ref_indexed(%{op: :var, name: name}, index_param, item_param, _env) do
    cond do
      name == index_param -> {:ok, {:loop, index_param}}
      name == item_param -> {:ok, {:loop, item_param}}
      true -> :error
    end
  end

  defp affine_native_loop_ref_indexed(
         %{op: :int_literal} = expr,
         _index_param,
         _item_param,
         _env
       ),
       do: direct_must_literal_int(expr, %{})

  defp affine_native_loop_ref_indexed(_, _, _, _), do: :error

  @spec map_affine_draw_range_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.affine_emit_result()
  def map_affine_draw_range_loop(
        spec,
        prefix_code,
        prefix_release_code,
        range_code,
        first_ref,
        last_ref,
        next,
        env,
        counter
      ) do
    with {:ok, context_prelude, counter} <-
           emit_affine_context_prelude(Map.get(spec, :context_settings, []), env, counter),
         {:ok, context_epilogue, counter} <-
           emit_affine_context_epilogue(Map.get(spec, :context_settings, []), env, counter) do
      command_emits = affine_draw_range_command_emits(spec, next, :map)

      {:ok,
       """
       #{prefix_code}
       #{range_code}
       #{context_prelude}
        elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
        for (elmc_int_t direct_item_i_#{next} = #{first_ref}; Rc == RC_SUCCESS; direct_item_i_#{next} += direct_step_#{next}) {
          #{command_emits}
          if (direct_item_i_#{next} == #{last_ref}) break;
        }
       #{context_epilogue}
       #{prefix_release_code}
       """, counter}
    end
  end

  @spec indexed_map_affine_draw_range_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          String.t(),
          [String.t()],
          map() | nil,
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.affine_emit_result()
  def indexed_map_affine_draw_range_loop(
        spec,
        index_param,
        item_param,
        prefix_code,
        prefix_refs,
        native_prefix_fields,
        prefix_release_code,
        range_code,
        first_ref,
        last_ref,
        next,
        env,
        counter
      ) do
    mode =
      affine_indexed_mode(
        :indexed,
        index_param,
        item_param,
        prefix_refs,
        Map.get(spec, :prefix_shapes, []),
        native_prefix_fields
      )

    with {:ok, context_prelude, counter} <-
           emit_affine_context_prelude(Map.get(spec, :context_settings, []), env, counter),
         {:ok, context_epilogue, counter} <-
           emit_affine_context_epilogue(Map.get(spec, :context_settings, []), env, counter) do
      command_emits = affine_draw_range_command_emits(spec, next, mode)

      {:ok,
       """
       #{prefix_code}
       #{range_code}
       #{context_prelude}
        elmc_int_t direct_index_#{next} = 0;
        elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
        for (elmc_int_t direct_item_i_#{next} = #{first_ref}; Rc == RC_SUCCESS; direct_item_i_#{next} += direct_step_#{next}) {
          #{command_emits}
          if (direct_item_i_#{next} == #{last_ref}) break;
          direct_index_#{next} += 1;
        }
       #{context_epilogue}
       #{prefix_release_code}
       """, counter}
    end
  end

  @spec indexed_map_affine_draw_list_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          String.t(),
          [String.t()],
          map() | nil,
          String.t(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.affine_emit_result()
  def indexed_map_affine_draw_list_loop(
        spec,
        index_param,
        item_param,
        prefix_code,
        prefix_refs,
        native_prefix_fields,
        prefix_release_code,
        list_expr,
        env,
        counter
      ) do
    {list_code, list_var, counter} = Host.compile_expr(list_expr, env, counter)
    next = counter + 1

    mode =
      affine_indexed_mode(
        :indexed_list,
        index_param,
        item_param,
        prefix_refs,
        Map.get(spec, :prefix_shapes, []),
        native_prefix_fields
      )

    with {:ok, context_prelude, counter} <-
           emit_affine_context_prelude(Map.get(spec, :context_settings, []), env, counter),
         {:ok, context_epilogue, counter} <-
           emit_affine_context_epilogue(Map.get(spec, :context_settings, []), env, counter) do
      command_emits = affine_draw_range_command_emits(spec, next, mode)

      {:ok,
       """
       #{list_code}
       #{prefix_code}
       #{context_prelude}
       ElmcValue *direct_cursor_#{next} = #{list_var};
       elmc_int_t direct_index_#{next} = 0;
       while (Rc == RC_SUCCESS && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
         ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
         #{command_emits}
         direct_index_#{next} += 1;
         direct_cursor_#{next} = direct_node_#{next}->tail;
       }
       elmc_release(#{list_var});
       #{context_epilogue}
       #{prefix_release_code}
       """, counter}
    end
  end

  @spec indexed_map_affine_draw_static_list_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          String.t(),
          [String.t()],
          map() | nil,
          String.t(),
          [Types.ir_expr()],
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.affine_emit_result()
  def indexed_map_affine_draw_static_list_loop(
        spec,
        index_param,
        item_param,
        prefix_code,
        prefix_refs,
        native_prefix_fields,
        prefix_release_code,
        static_items,
        next,
        env,
        counter
      ) do
    with {:ok, context_prelude, counter} <-
           emit_affine_context_prelude(Map.get(spec, :context_settings, []), env, counter),
         {:ok, context_epilogue, counter} <-
           emit_affine_context_epilogue(Map.get(spec, :context_settings, []), env, counter) do
      {body, counter} =
        static_items
        |> Enum.with_index()
        |> Enum.reduce({"", counter}, fn {item, index}, {acc, c} ->
          {item_code, item_ref, c2} = Host.direct_int_value(item, env, c)

          mode =
            affine_indexed_static_mode(
              index_param,
              item_param,
              prefix_refs,
              Map.get(spec, :prefix_shapes, []),
              native_prefix_fields,
              "#{index}",
              item_ref
            )

          emits = affine_draw_range_command_emits(spec, next, mode)

          snippet = """
          #{item_code}
            #{emits}
          """

          {acc <> snippet, c2}
        end)

      {:ok,
       """
       #{prefix_code}
       #{context_prelude}
       #{body}
       #{context_epilogue}
       #{prefix_release_code}
       """, counter}
    end
  end

  @spec map_affine_draw_list_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.affine_emit_result()
  def map_affine_draw_list_loop(spec, prefix_code, prefix_release_code, list_expr, env, counter) do
    {list_code, list_var, counter} = Host.compile_expr(list_expr, env, counter)
    next = counter + 1
    item_param = "direct_item"

    with {:ok, context_prelude, counter} <-
           emit_affine_context_prelude(Map.get(spec, :context_settings, []), env, counter),
         {:ok, context_epilogue, counter} <-
           emit_affine_context_epilogue(Map.get(spec, :context_settings, []), env, counter) do
      command_emits = affine_draw_range_command_emits(spec, next, {:map_list, item_param})

      {:ok,
       """
       #{list_code}
       #{prefix_code}
       #{context_prelude}
       ElmcValue *direct_cursor_#{next} = #{list_var};
       while (Rc == RC_SUCCESS && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
         ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
         #{command_emits}
         direct_cursor_#{next} = direct_node_#{next}->tail;
       }
       elmc_release(#{list_var});
       #{context_epilogue}
       #{prefix_release_code}
       """, counter}
    end
  end

  defp emit_affine_context_prelude([], _env, counter), do: {:ok, "", counter}

  defp emit_affine_context_prelude(settings, env, counter) do
    with {:ok, push_code, counter} <-
           Host.direct_append_command(draw_kind(:push_context), [], env, counter),
         {:ok, settings_code, counter} <- Host.direct_emit_settings(settings, env, counter) do
      {:ok, push_code <> settings_code, counter}
    else
      _ -> :error
    end
  end

  defp emit_affine_context_epilogue([], _env, counter), do: {:ok, "", counter}

  defp emit_affine_context_epilogue(_settings, env, counter) do
    Host.direct_append_command(draw_kind(:pop_context), [], env, counter)
  end

  defp affine_draw_range_command_emits(spec, next, mode) do
    spec
    |> affine_draw_commands()
    |> Enum.map_join("\n          ", fn command ->
      param_assignments = affine_draw_param_assignments(command.params, next, mode)
      text_copy = affine_draw_text_copy(command, next, mode)
      fill_skip_open = affine_draw_skip_nonempty_fill_open(command, next, mode)
      fill_skip_close = affine_draw_skip_nonempty_fill_close(fill_skip_open)
      text_skip_open = affine_draw_skip_empty_text_open(command, next, mode)
      text_skip_close = affine_draw_skip_empty_text_close(text_skip_open)

      """
      #{fill_skip_open}#{text_skip_open}#{Elmc.Backend.CCodegen.DirectRender.Emit.Commands.scene_emit_guard_open()}
            elmc_draw_cmd_init(&scene_cmd, #{command.kind_macro});
            #{param_assignments}
            #{text_copy}
            #{Elmc.Backend.CCodegen.DirectRender.Emit.Catch.push_cmd_check()}
          #{Elmc.Backend.CCodegen.DirectRender.Emit.Commands.scene_emit_guard_close()}#{text_skip_close}#{fill_skip_close}
      """
      |> String.trim_trailing()
    end)
  end

  defp affine_draw_skip_nonempty_fill_open(%{fill_emit_guard: {:nonzero, item_param}}, next, mode) do
    item_ref = affine_loop_item_ref(item_param, next, mode)
    "if (#{item_ref} != 0) {\n          "
  end

  defp affine_draw_skip_nonempty_fill_open(_command, _next, _mode), do: ""

  defp affine_draw_skip_nonempty_fill_close(""), do: ""

  defp affine_draw_skip_nonempty_fill_close(_skip_open),
    do: "\n          }"

  defp affine_draw_skip_empty_text_open(
         %{label: {:from_int, item_param, _zero_label}},
         next,
         mode
       ) do
    item_ref = affine_loop_item_ref(item_param, next, mode)
    "if (#{item_ref} != 0) {\n          "
  end

  defp affine_draw_skip_empty_text_open(_command, _next, _mode), do: ""

  defp affine_draw_skip_empty_text_close(""), do: ""

  defp affine_draw_skip_empty_text_close(_skip_open),
    do: "\n          }"

  defp affine_draw_text_copy(%{label: {:from_int, item_param, _zero_label}}, next, mode) do
    item_ref = affine_loop_item_ref(item_param, next, mode)
    CSource.indent(direct_int_text_copy_body(item_ref), 4)
  end

  defp affine_draw_text_copy(%{label: {:literal, literal}}, _next, _mode) do
    CSource.indent(direct_text_copy_body_for_literal(literal), 4)
  end

  defp affine_draw_text_copy(_command, _next, _mode), do: ""

  defp direct_text_copy_body_for_literal(literal) do
    bytes = :binary.bin_to_list(literal)

    if length(bytes) <= @literal_text_unroll_max do
      literal_text_assignments(bytes)
    else
      escaped = Util.escape_c_string(literal)

      """
      {
        const char *direct_text = "#{escaped}";
      #{CSource.indent(Host.direct_text_copy_body(), 2)}
      }
      """
    end
  end

  defp literal_text_assignments(bytes) do
    bytes = Enum.take(bytes, 63)

    assignments =
      bytes
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {byte, index} ->
        "scene_cmd.text[#{index}] = #{c_char_literal(byte)};"
      end)

    null_index = length(bytes)

    """
    {
      #{assignments}
      scene_cmd.text[#{null_index}] = '\\0';
    }
    """
  end

  defp c_char_literal(?\\), do: "'\\\\'"
  defp c_char_literal(?'), do: "'\\''"
  defp c_char_literal(?\n), do: "'\\n'"
  defp c_char_literal(?\r), do: "'\\r'"
  defp c_char_literal(?\t), do: "'\\t'"

  defp c_char_literal(byte) when byte >= 32 and byte <= 126 do
    "'#{<<byte>>}'"
  end

  defp c_char_literal(byte) do
    hex = byte |> Integer.to_string(16) |> String.pad_leading(2, "0")
    "'\\x#{hex}'"
  end

  defp direct_int_text_copy_body(item_ref) do
    """
    {
      elmc_int_t direct_value = #{item_ref};
      char direct_digits[32];
      int direct_digit_count = 0;
      int direct_text_i = 0;
      int direct_negative = direct_value < 0;
      if (direct_negative) {
        scene_cmd.text[direct_text_i++] = '-';
      }
      do {
        elmc_int_t direct_digit = direct_value % 10;
        if (direct_digit < 0) direct_digit = -direct_digit;
        direct_digits[direct_digit_count++] = (char)('0' + direct_digit);
        direct_value /= 10;
      } while (direct_value != 0 && direct_digit_count < (int)sizeof(direct_digits));
      while (direct_digit_count > 0 && direct_text_i < (int)sizeof(scene_cmd.text) - 1) {
        scene_cmd.text[direct_text_i++] = direct_digits[--direct_digit_count];
      }
      scene_cmd.text[direct_text_i] = '\\0';
    }
    """
  end

  defp affine_loop_item_ref(item_param, next, mode),
    do: affine_loop_ref(item_param, next, mode)

  defp affine_draw_commands(%{commands: commands}) when is_list(commands), do: commands
  defp affine_draw_commands(command), do: [command]

  defp affine_draw_param_assignments(params, next, mode) do
    params
    |> Enum.with_index()
    |> Enum.map_join("\n        ", fn {param, index} ->
      value = affine_draw_param_value(param, next, mode)
      "scene_cmd.p#{index} = #{value};"
    end)
  end

  defp affine_draw_param_value({:mul, _param_name, scale}, next, :map),
    do: "(direct_item_i_#{next} * #{scale})"

  defp affine_draw_param_value({:affine, _param_name, base, scale}, next, :map),
    do: "(#{affine_operand_c_value(base, next, :map)} + direct_item_i_#{next} * #{scale})"

  defp affine_draw_param_value({:loop, _param_name}, next, :map), do: "direct_item_i_#{next}"

  defp affine_draw_param_value({:mul, param_name, scale}, next, mode),
    do: "(#{affine_loop_ref(param_name, next, mode)} * #{scale})"

  defp affine_draw_param_value({:affine, param_name, base, scale}, next, mode),
    do:
      "(#{affine_operand_c_value(base, next, mode)} + #{affine_loop_ref(param_name, next, mode)} * #{scale})"

  defp affine_draw_param_value({:add_mod_mul, base, {:mod_mul, param, mod, stride}}, next, mode) do
    index_ref = affine_loop_ref(param, next, mode)

    "(#{affine_operand_c_value(base, next, mode)} + (#{affine_positive_mod_expr(index_ref, mod)} * #{affine_stride_c_value(stride, next, mode)}))"
  end

  defp affine_draw_param_value(
         {:add_idiv_mul, base, {:idiv_mul, param, divisor, stride}},
         next,
         mode
       ) do
    index_ref = affine_loop_ref(param, next, mode)

    "(#{affine_operand_c_value(base, next, mode)} + ((#{index_ref} / #{divisor}) * #{affine_stride_c_value(stride, next, mode)}))"
  end

  defp affine_draw_param_value(
         {:add_prefix_idiv, base, {:prefix_idiv, idx, field, subtrahend, divisor}},
         next,
         mode
       ) do
    field_ref =
      case affine_native_prefix_fields(mode) do
        native_fields when is_map(native_fields) ->
          Map.fetch!(native_fields, field)

        nil ->
          {prefix_refs, shapes} = affine_mode_prefix(mode)
          Host.record_get_int_expr(Enum.at(prefix_refs, idx), field, Enum.at(shapes, idx))
      end

    "(#{affine_draw_param_value(base, next, mode)} + ((#{field_ref} - #{subtrahend}) / #{divisor}))"
  end

  defp affine_draw_param_value({:loop, param_name}, next, mode),
    do: affine_loop_ref(param_name, next, mode)

  defp affine_draw_param_value({:offset, base_param, offset}, next, mode),
    do: "(#{affine_draw_param_value(base_param, next, mode)} + #{offset})"

  defp affine_draw_param_value(literal, _next, _mode) when is_binary(literal), do: literal

  defp affine_draw_param_value({:native_ref, native_ref}, _next, _mode), do: native_ref

  defp affine_draw_param_value({:prefix_field, idx, field}, _next, mode) do
    affine_prefix_field_ref(mode, idx, field)
  end

  defp affine_operand_c_value(value, _next, _mode) when is_integer(value),
    do: "#{value}"

  defp affine_operand_c_value(value, _next, _mode) when is_binary(value), do: value

  defp affine_operand_c_value({:native_ref, native_ref}, _next, _mode), do: native_ref

  defp affine_operand_c_value({:prefix_field, idx, field}, _next, mode) do
    affine_prefix_field_ref(mode, idx, field)
  end

  defp affine_operand_c_value({:prefix_add, idx, left_field, right_field}, _next, mode) do
    case affine_native_prefix_fields(mode) do
      native_fields when is_map(native_fields) ->
        "(#{Map.fetch!(native_fields, left_field)} + #{Map.fetch!(native_fields, right_field)})"

      nil ->
        {prefix_refs, shapes} = affine_mode_prefix(mode)
        source = Enum.at(prefix_refs, idx)
        shape = Enum.at(shapes, idx)

        "(#{Host.record_get_int_expr(source, left_field, shape)} + #{Host.record_get_int_expr(source, right_field, shape)})"
    end
  end

  defp affine_indexed_mode(kind, index_param, item_param, prefix_refs, shapes, native_fields) do
    {kind, index_param, item_param, prefix_refs, shapes, native_fields}
  end

  defp affine_indexed_static_mode(
         index_param,
         item_param,
         prefix_refs,
         shapes,
         native_fields,
         index_value,
         item_value
       ) do
    {:indexed_static, index_param, item_param, prefix_refs, shapes, native_fields, index_value,
     item_value}
  end

  defp affine_native_prefix_fields({:indexed, _, _, _, _, native_fields}), do: native_fields
  defp affine_native_prefix_fields({:indexed_list, _, _, _, _, native_fields}), do: native_fields

  defp affine_native_prefix_fields({:indexed_static, _, _, _, _, native_fields, _, _}),
    do: native_fields

  defp affine_native_prefix_fields(_), do: nil

  defp affine_prefix_field_ref(mode, idx, field) do
    case affine_native_prefix_fields(mode) do
      native_fields when is_map(native_fields) ->
        Map.fetch!(native_fields, field)

      nil ->
        {prefix_refs, shapes} = affine_mode_prefix(mode)
        Host.record_get_int_expr(Enum.at(prefix_refs, idx), field, Enum.at(shapes, idx))
    end
  end

  defp affine_stride_c_value(value, next, mode), do: affine_operand_c_value(value, next, mode)

  defp affine_positive_mod_expr(index_ref, mod),
    do: "((#{index_ref} % #{mod} + #{mod}) % #{mod})"

  defp affine_mode_prefix({:indexed, _, _, prefix_refs, shapes, _}), do: {prefix_refs, shapes}

  defp affine_mode_prefix({:indexed_list, _, _, prefix_refs, shapes, _}),
    do: {prefix_refs, shapes}

  defp affine_mode_prefix({:indexed_static, _, _, prefix_refs, shapes, _, _, _}),
    do: {prefix_refs, shapes}

  defp affine_mode_prefix(_), do: {[], []}

  defp affine_loop_ref(
         param_name,
         _next,
         {:indexed_static, index_param, item_param, _, _, _, index_value, item_value}
       ) do
    cond do
      affine_param_names_match?(param_name, index_param) -> index_value
      affine_param_names_match?(param_name, item_param) -> item_value
      true -> item_value
    end
  end

  defp affine_loop_ref(param_name, next, {:indexed_list, index_param, item_param, _, _, _}) do
    cond do
      affine_param_names_match?(param_name, index_param) ->
        "direct_index_#{next}"

      affine_param_names_match?(param_name, item_param) ->
        "elmc_as_int(direct_node_#{next}->head)"

      true ->
        "direct_item_i_#{next}"
    end
  end

  defp affine_loop_ref(param_name, next, {:indexed, index_param, item_param, _, _, _}) do
    cond do
      affine_param_names_match?(param_name, index_param) ->
        "direct_index_#{next}"

      affine_param_names_match?(param_name, item_param) ->
        "direct_item_i_#{next}"

      true ->
        "direct_item_i_#{next}"
    end
  end

  defp affine_loop_ref(_param_name, next, {:map_list, _item_param}),
    do: "elmc_as_int(direct_node_#{next}->head)"

  defp affine_loop_ref(_param_name, next, :map), do: "direct_item_i_#{next}"

  defp affine_param_names_match?(left, right),
    do: affine_binding_name(left) == affine_binding_name(right)
end
