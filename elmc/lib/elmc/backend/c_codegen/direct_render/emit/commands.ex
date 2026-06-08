defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Commands do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Emit.Catch
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec emit_settings([Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          Types.direct_emit_result()
  def emit_settings(settings, env, counter) do
    Enum.reduce_while(settings, {:ok, "", counter}, fn setting, {:ok, acc, c} ->
      case setting_command(setting, env, c) do
        {:ok, code, c2} -> {:cont, {:ok, acc <> code, c2}}
        :error -> {:halt, :error}
      end
    end)
  end

  @spec setting_command(Types.ir_qualified_call_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.direct_emit_result()
  def setting_command(%{op: :qualified_call, target: target, args: [value]}, env, counter) do
    kind =
      case Host.normalize_special_target(target) do
        "Pebble.Ui.strokeWidth" -> draw_kind(:stroke_width)
        "Pebble.Ui.antialiased" -> draw_kind(:antialiased)
        "Pebble.Ui.strokeColor" -> draw_kind(:stroke_color)
        "Pebble.Ui.fillColor" -> draw_kind(:fill_color)
        "Pebble.Ui.textColor" -> draw_kind(:text_color)
        "Pebble.Ui.compositingMode" -> draw_kind(:compositing_mode)
        _ -> nil
      end

    if kind, do: append(kind, [value], env, counter), else: :error
  end

  def setting_command(_, _, _), do: :error

  @spec bounds_command(
          non_neg_integer(),
          Types.ir_expr(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def bounds_command(kind, bounds, extra_args, env, counter) do
    {bounds_code, bounds_values, counter} = bounds_values(bounds, env, counter)

    {extra_code, extra_values, counter} =
      Enum.reduce(extra_args, {"", [], counter}, fn arg, {acc, vars, c} ->
        {arg_code, value_ref, c2} = Host.direct_int_value(arg, env, c)
        {acc <> arg_code, vars ++ [value_ref], c2}
      end)

    command_code(kind, bounds_code <> extra_code, bounds_values ++ extra_values, counter)
  end

  @spec append(
          non_neg_integer(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def append(kind, args, env, counter) do
    {code, values, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg, {acc, vars, c} ->
        {arg_code, value_ref, c2} = Host.direct_int_value(arg, env, c)
        {acc <> arg_code, vars ++ [value_ref], c2}
      end)

    command_code(kind, code, values, counter)
  end

  @spec command_code(
          non_neg_integer(),
          String.t(),
          [String.t()],
          Types.compile_counter()
        ) :: {:ok, String.t(), Types.compile_counter()}
  defp command_code(kind, code, values, counter) do
    next = counter + 1

    assignments =
      values
      |> Enum.with_index()
      |> Enum.map_join("\n  ", fn {value, index} -> "scene_cmd.p#{index} = #{value};" end)

    {:ok,
     """
     #{CSource.indent(code, 4)}
       elmc_draw_cmd_init(&scene_cmd, #{Host.generated_draw_kind_macro(kind)});
         #{assignments}
         #{Catch.push_cmd_check()}
     """, next}
  end

  @spec bounds_values(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {String.t(), [String.t()], Types.compile_counter()}
  defp bounds_values(%{op: :call, name: name, args: args} = bounds, env, counter) do
    module_name = Map.get(env, :__module__, "Main")

    case inline_bounds_values({module_name, name}, args, env, counter) do
      :error -> runtime_bounds_values(bounds, env, counter)
      result -> result
    end
  end

  defp bounds_values(%{op: :qualified_call, target: target, args: args} = bounds, env, counter) do
    case Util.split_qualified_function_target(Host.normalize_special_target(target)) do
      nil ->
        runtime_bounds_values(bounds, env, counter)

      target_key ->
        case inline_bounds_values(target_key, args, env, counter) do
          :error -> runtime_bounds_values(bounds, env, counter)
          result -> result
        end
    end
  end

  defp bounds_values(bounds, env, counter), do: runtime_bounds_values(bounds, env, counter)

  @spec inline_bounds_values(
          Types.function_decl_key(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), [String.t()], Types.compile_counter()} | :error
  defp inline_bounds_values(target_key, args, env, counter) do
    decl_map = Map.get(env, :__program_decls__, %{})

    with %{args: arg_names, expr: expr} when is_list(arg_names) <- Map.get(decl_map, target_key),
         true <- length(arg_names) == length(args),
         substituted <- Host.substitute_expr(expr, Map.new(Enum.zip(arg_names, args))),
         %{op: :record_literal} <- substituted,
         true <- bounds_record_literal?(substituted) do
      runtime_bounds_values(substituted, env, counter)
    else
      _ -> :error
    end
  end

  @spec bounds_record_literal?(Types.ir_record_literal_expr()) :: boolean()
  defp bounds_record_literal?(%{op: :record_literal} = expr) do
    Enum.all?(["x", "y", "w", "h"], &SpecialValues.field_access_expr(expr, &1))
  end

  @spec runtime_bounds_values(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {String.t(), [String.t()], Types.compile_counter()}
  defp runtime_bounds_values(bounds, env, counter) do
    fields = ["x", "y", "w", "h"]

    inlined =
      Enum.map(fields, &Host.record_field_expr(bounds, &1))

    if Enum.all?(inlined) do
      Enum.reduce(inlined, {"", [], counter}, fn field_expr, {acc, vars, c} ->
        {field_code, field_ref, c2} = Host.direct_int_value(field_expr, env, c)
        {acc <> field_code, vars ++ [field_ref], c2}
      end)
    else
      case bounds do
        %{op: :var} ->
          Enum.reduce(fields, {"", [], counter}, fn field, {acc, vars, c} ->
            {field_code, field_ref, c2} =
              Host.direct_int_value(%{op: :field_access, arg: bounds, field: field}, env, c)

            {acc <> field_code, vars ++ [field_ref], c2}
          end)

        _ ->
          {bounds_code, bounds_var, counter} = Host.compile_expr(bounds, env, counter)
          next = counter + 1
          shape = Host.record_shape(bounds, env)

          field_refs =
            Enum.map(fields, fn field ->
              "direct_bounds_#{field}_#{next}"
            end)

          field_code =
            fields
            |> Enum.zip(field_refs)
            |> Enum.map_join("\n", fn {field, ref} ->
              "  const elmc_int_t #{ref} = #{Host.record_get_int_expr(bounds_var, field, shape)};"
            end)

          code = """
          #{bounds_code}
          #{field_code}
            elmc_release(#{bounds_var});
          """

          {code, field_refs, next}
      end
    end
  end

  @spec append_text(
          non_neg_integer(),
          [Types.ir_expr()],
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def append_text(kind, args, text_expr, env, counter) do
    {code, values, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg, {acc, vars, c} ->
        {arg_code, value_ref, c2} = Host.direct_int_value(arg, env, c)
        {acc <> arg_code, vars ++ [value_ref], c2}
      end)

    {text_code, text_copy_code, text_release_code, counter} = text_copy_code(text_expr, env, counter)

    assignments =
      values
      |> Enum.with_index()
      |> Enum.map_join("\n  ", fn {value, index} -> "scene_cmd.p#{index} = #{value};" end)

    {:ok,
     """
     #{CSource.indent(code, 2)}
     #{CSource.indent(text_code, 2)}
       elmc_draw_cmd_init(&scene_cmd, #{Host.generated_draw_kind_macro(kind)});
         #{assignments}
     #{CSource.indent(text_copy_code, 4)}
         #{Catch.push_cmd_check()}
     #{CSource.indent(text_release_code, 4)}
     """, counter}
  end

  @spec text_copy_body() :: String.t()
  def text_copy_body do
    """
    int direct_text_i = 0;
    while (direct_text[direct_text_i] && direct_text_i < 63) {
      scene_cmd.text[direct_text_i] = direct_text[direct_text_i];
      direct_text_i++;
    }
    scene_cmd.text[direct_text_i] = '\\0';
    """
  end

  @type text_copy_result :: {String.t(), String.t(), String.t(), Types.compile_counter()}

  @spec text_copy_code(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          text_copy_result()
  defp text_copy_code(%{op: :string_literal, value: value}, _env, counter) do
    escaped = Util.escape_c_string(value)
    {"", text_copy_from("\"#{escaped}\""), "", counter}
  end

  defp text_copy_code(%{op: :call, name: "__append__", args: [left, right]}, env, counter) do
    text_copy_append_code(left, right, env, counter)
  end

  defp text_copy_code(%{op: :var, name: name}, env, counter) do
    expr = %{op: :var, name: name}

    case EnvBindings.native_string_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", text_copy_from(native_ref), "", counter}

      nil ->
        if Host.typed_string_expr?(expr, env) do
          {text_code, text_ref, cleanup, counter} = Host.compile_native_string_expr(expr, env, counter)
          cleanup_code = Enum.map_join(cleanup, "\n", fn var -> "elmc_release(#{var});" end)
          {text_code, text_copy_from(text_ref), cleanup_code, counter}
        else
          text_copy_boxed_code(expr, env, counter)
        end
    end
  end

  defp text_copy_code(text_expr, env, counter) do
    if Host.native_string_expr?(text_expr, env) do
      {text_code, text_ref, cleanup, counter} = Host.compile_native_string_expr(text_expr, env, counter)
      cleanup_code = Enum.map_join(cleanup, "\n", fn var -> "elmc_release(#{var});" end)
      {text_code, text_copy_from(text_ref), cleanup_code, counter}
    else
      text_copy_boxed_code(text_expr, env, counter)
    end
  end

  @spec text_copy_append_code(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: text_copy_result()
  defp text_copy_append_code(left, right, env, counter) do
    {left_code, left_ref, left_cleanup, counter} = Host.compile_native_string_expr(left, env, counter)

    {right_code, right_ref, right_cleanup, counter} =
      Host.compile_native_string_expr(right, env, counter)

    cleanup_code =
      (left_cleanup ++ right_cleanup)
      |> Enum.map_join("\n", fn var -> "elmc_release(#{var});" end)

    copy_code = """
    {
      int direct_text_i = 0;
      const char *direct_text = #{left_ref};
      while (direct_text && direct_text[direct_text_i] && direct_text_i < 63) {
        scene_cmd.text[direct_text_i] = direct_text[direct_text_i];
        direct_text_i++;
      }
      const char *direct_text_right = #{right_ref};
      int direct_text_right_i = 0;
      while (direct_text_right && direct_text_right[direct_text_right_i] && direct_text_i < 63) {
        scene_cmd.text[direct_text_i] = direct_text_right[direct_text_right_i];
        direct_text_i++;
        direct_text_right_i++;
      }
      scene_cmd.text[direct_text_i] = '\\0';
    }
    """

    {left_code <> right_code, copy_code, cleanup_code, counter}
  end

  @spec text_copy_boxed_code(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          text_copy_result()
  defp text_copy_boxed_code(text_expr, env, counter) do
    {text_code, text_var, counter} = Host.compile_expr(text_expr, env, counter)

    copy_code = """
    if (#{text_var} && #{text_var}->tag == ELMC_TAG_STRING && #{text_var}->payload) {
      const char *direct_text = (const char *)#{text_var}->payload;
    #{CSource.indent(text_copy_body(), 2)}
    }
    """

    {text_code, copy_code, "elmc_release(#{text_var});", counter}
  end

  @spec text_copy_from(String.t()) :: String.t()
  defp text_copy_from(source) do
    """
    {
      const char *direct_text = #{source};
    #{CSource.indent(text_copy_body(), 2)}
    }
    """
  end

  @spec path_command(
          non_neg_integer(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def path_command(kind, path, env, counter) do
    {target, args} =
      case path do
        %{op: :qualified_call, target: target, args: args} ->
          {Host.normalize_special_target(target), args}

        %{op: :var, name: name} ->
          case Map.get(env, name) do
            {:direct_fragment, %{op: :qualified_call, target: target, args: args}} ->
              {Host.normalize_special_target(target), args}

            _ ->
              {nil, nil}
          end

        _ ->
          {nil, nil}
      end

    with "Pebble.Ui.path" <- target,
         [%{op: :list_literal, items: points}, offset, rotation] <- args,
         true <- length(points) <= 16 do
      {code, point_assignments, counter} =
        points
        |> Enum.with_index()
        |> Enum.reduce({"", [], counter}, fn {point, index}, {acc, assignments, c} ->
          {x_code, x_ref, c} =
            Host.direct_int_value(Host.record_field_expr(point, "x"), env, c)

          {y_code, y_ref, c} =
            Host.direct_int_value(Host.record_field_expr(point, "y"), env, c)

          assignment = """
              scene_cmd.path_x[#{index}] = #{x_ref};
              scene_cmd.path_y[#{index}] = #{y_ref};
          """

          {acc <> x_code <> y_code, assignments ++ [assignment], c}
        end)

      {offset_x_code, offset_x, counter} =
        Host.direct_int_value(Host.record_field_expr(offset, "x"), env, counter)

      {offset_y_code, offset_y, counter} =
        Host.direct_int_value(Host.record_field_expr(offset, "y"), env, counter)

      {rotation_code, rotation_ref, counter} = Host.direct_int_value(rotation, env, counter)

      {:ok,
       """
       #{CSource.indent(code, 4)}
       #{CSource.indent(offset_x_code, 4)}
       #{CSource.indent(offset_y_code, 4)}
       #{CSource.indent(rotation_code, 4)}
         elmc_draw_cmd_init(&scene_cmd, #{Host.generated_draw_kind_macro(kind)});
           scene_cmd.path_point_count = #{length(points)};
           scene_cmd.path_offset_x = #{offset_x};
           scene_cmd.path_offset_y = #{offset_y};
           scene_cmd.path_rotation = #{rotation_ref};
       #{Enum.join(point_assignments, "\n")}
           #{Catch.push_cmd_check()}
       """, counter}
    else
      _ -> :error
    end
  end

  @spec scene_emit_guard_open() :: String.t()
  def scene_emit_guard_open, do: ""

  @spec scene_emit_guard_close() :: String.t()
  def scene_emit_guard_close, do: ""

  defp draw_kind(kind), do: Elmc.Backend.Pebble.draw_kind_id!(kind)
end
