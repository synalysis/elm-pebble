defmodule Elmc.Backend.CCodegen.Native.PolarPoint do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr, as: CExpr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Types

  @point_suffixes [".Point", ".Ui.Point"]

  @spec native_field_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def native_field_expr?(%{op: :field_access, arg: arg, field: field}, env)
      when field in ["x", "y"] do
    with resolved <- resolve_let_arg(arg, env),
         {:ok, target, args} <- call_target(resolved, env),
         true <- polar_point_call?(target, args, env) do
      true
    else
      _ -> false
    end
  end

  def native_field_expr?(_expr, _env), do: false

  @spec polar_point_let?(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env()
        ) :: boolean()
  def polar_point_let?(name, value_expr, in_expr, env)
      when is_binary(name) or is_atom(name) do
    with resolved <- resolve_let_arg(value_expr, env),
         {:ok, target, args} <- call_target(resolved, env),
         true <- polar_point_call?(target, args, env),
         true <- polar_field_only_uses?(name, in_expr, env) do
      true
    else
      _ -> false
    end
  end

  def polar_point_let?(_name, _value_expr, _in_expr, _env), do: false

  @spec polar_point_target?(Types.function_decl_key(), Types.function_decl_map()) :: boolean()
  def polar_point_target?({module_name, _name} = target, decl_map) when is_map(decl_map) do
    case Map.fetch(decl_map, target) do
      {:ok, %{args: args}} when is_list(args) and length(args) == 4 ->
        point_return?(target, %{__module__: module_name, __program_decls__: decl_map})

      _ ->
        false
    end
  end

  def polar_point_target?(_target, _decl_map), do: false

  @spec compile_polar_native_record(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          {:ok, String.t(), %{String.t() => String.t()}, Types.compile_counter()} | :error
  def compile_polar_native_record(value_expr, env, counter) do
    resolved = resolve_let_arg(value_expr, env)

    with {:ok, _target, args} <- call_target(resolved, env),
         {:ok, x_code, x_ref, counter} <- compile_field(args, "x", env, counter),
         {:ok, y_code, y_ref, counter} <- compile_field(args, "y", env, counter) do
      code =
        [x_code, y_code]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")

      {:ok, code, %{"x" => x_ref, "y" => y_ref}, counter}
    else
      _ -> :error
    end
  end

  @spec try_compile_field(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def try_compile_field(arg, field, env, counter) when field in ["x", "y"] do
    case native_record_field_ref(arg, field, env) do
      {:ok, ref} ->
        {:ok, "", ref, counter}

      :error ->
        resolved = resolve_let_arg(arg, env)

        with {:ok, target, args} <- call_target(resolved, env),
             true <- polar_point_call?(target, args, env),
             {:ok, code, ref, counter} <- compile_field(args, field, env, counter) do
          {:ok, code, ref, counter}
        else
          _ -> :error
        end
    end
  end

  def try_compile_field(_arg, _field, _env, _counter), do: :error

  defp native_record_field_ref(%{op: :var, name: name}, field, env)
       when (is_binary(name) or is_atom(name)) and field in ["x", "y"] do
    case Map.get(env, name) do
      {:native_record, fields} ->
        Map.fetch(fields, field)

      _ ->
        case EnvBindings.lookup_binding(env, name) do
          {:native_record, fields} -> Map.fetch(fields, field)
          _ -> :error
        end
    end
  end

  defp native_record_field_ref(_arg, _field, _env), do: :error

  @spec xy_draw_center_let?(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env()
        ) :: boolean()
  def xy_draw_center_let?(name, %{op: :record_literal, fields: fields}, in_expr, env)
      when is_list(fields) do
    with %{expr: x} <- Enum.find(fields, &(&1.name == "x")),
         %{expr: y} <- Enum.find(fields, &(&1.name == "y")),
         true <- polar_coord_arg?(x, env),
         true <- polar_coord_arg?(y, env),
         true <- polar_field_only_uses?(name, in_expr, env) do
      true
    else
      _ -> false
    end
  end

  def xy_draw_center_let?(_name, _value_expr, _in_expr, _env), do: false

  @spec compile_xy_draw_center_native_record(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          {:ok, String.t(), %{String.t() => String.t()}, Types.compile_counter()} | :error
  def compile_xy_draw_center_native_record(
        %{op: :record_literal, fields: fields},
        env,
        counter
      )
      when is_list(fields) do
    with %{expr: x} <- Enum.find(fields, &(&1.name == "x")),
         %{expr: y} <- Enum.find(fields, &(&1.name == "y")),
         {x_code, x_ref, counter} <- NativeInt.compile_expr(x, env, counter),
         {y_code, y_ref, counter} <- NativeInt.compile_expr(y, env, counter) do
      code =
        [x_code, y_code]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")

      {:ok, code, %{"x" => x_ref, "y" => y_ref}, counter}
    else
      _ -> :error
    end
  end

  def compile_xy_draw_center_native_record(_value_expr, _env, _counter), do: :error

  @spec resolve_let_arg(Types.ir_expr(), Types.compile_env()) :: Types.ir_expr()
  def resolve_let_arg(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    case EnvBindings.let_value_expr(env, name) do
      bound when is_map(bound) -> resolve_let_arg(bound, env)
      _ -> %{op: :var, name: name}
    end
  end

  def resolve_let_arg(arg, _env), do: arg

  defp call_target(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    {:ok, {Map.get(env, :__module__, "Main"), name}, List.wrap(args)}
  end

  defp call_target(%{op: :qualified_call, target: target, args: args}, _env)
       when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> then(fn key -> {:ok, key, List.wrap(args)} end)
  end

  defp call_target(_expr, _env), do: :error

  defp polar_point_call?(target, args, env) do
    length(args) == 4 and Enum.all?(args, &polar_coord_arg?(&1, env)) and
      point_return?(target, env)
  end

  defp polar_coord_arg?(arg, env) do
    NativeInt.expr?(arg, env) or int_var_arg?(arg, env)
  end

  defp int_var_arg?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    key = EnvBindings.binding_key(name)

    case Map.get(env, :__var_types__, %{}) |> Map.get(key) do
      "Int" ->
        true

      _ ->
        EnvBindings.boxed_int_binding?(env, name) or
          EnvBindings.function_int_param?(env, name)
    end
  end

  defp int_var_arg?(_arg, _env), do: false

  defp point_return?(target, env) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target) do
      %{type: type} when is_binary(type) ->
        return_type = Host.function_return_type(type) |> Host.normalize_type_name()
        point_type?(return_type) or xy_record_return?(return_type, target, env)

      decl when is_map(decl) ->
        xy_record_return?(nil, target, env)

      _ ->
        false
    end
  end

  defp xy_record_return?(return_type, _target, env) when is_binary(return_type) do
    case CExpr.record_shape_for_type(return_type, env) do
      fields when is_list(fields) -> xy_field_names?(fields)
      _ -> false
    end
  end

  defp xy_record_return?(nil, target, env) do
    case CExpr.record_shape_for_function_return(target, env, 4) do
      fields when is_list(fields) -> xy_field_names?(fields)
      _ -> false
    end
  end

  defp xy_field_names?(fields) do
    fields |> Enum.map(&to_string/1) |> Enum.sort() == ["x", "y"]
  end

  defp point_type?(type) when is_binary(type) do
    normalized = Host.normalize_type_name(type)

    normalized == "Point" or normalized == "Ui.Point" or
      Enum.any?(@point_suffixes, &String.ends_with?(normalized, &1))
  end

  defp point_type?(_), do: false

  defp polar_field_only_uses?(name, expr, env) do
    invalid_uses(expr, name, nil, env) == []
  end

  defp invalid_uses(%{op: :var, name: var_name}, target, parent, env) do
    cond do
      not EnvBindings.same_binding?(var_name, target) ->
        []

      point_var_parent?(parent, env) ->
        []

      true ->
        [:bare_var]
    end
  end

  defp invalid_uses(%{op: :field_access, arg: %{op: :var, name: var_name}, field: field}, target, _parent, _env) do
    if EnvBindings.same_binding?(var_name, target) do
      if field in ["x", "y"], do: [], else: [:non_xy_field]
    else
      []
    end
  end

  defp invalid_uses(expr, target, _parent, env) when is_map(expr) do
    expr
    |> Enum.flat_map(fn
      {:args, value} when is_list(value) ->
        Enum.with_index(value, fn arg, idx ->
          invalid_uses(arg, target, {expr, :args, idx}, env)
        end)

      {key, value} ->
        [invalid_uses(value, target, {expr, key}, env)]
    end)
    |> List.flatten()
  end

  defp invalid_uses(exprs, target, parent, env) when is_list(exprs) do
    Enum.with_index(exprs, fn expr, idx ->
      invalid_uses(expr, target, {parent, idx}, env)
    end)
    |> List.flatten()
  end

  defp invalid_uses(_expr, _target, _parent, _env), do: []

  defp point_var_parent?({%{op: :qualified_call, target: target, args: _args}, :args, idx}, env)
       when is_binary(target) do
    normalized = Host.normalize_special_target(target)
    draw_point_arg_index?(normalized, idx) or direct_render_point_arg?(normalized, idx, env)
  end

  defp point_var_parent?({%{op: :call, name: name, args: _args}, :args, idx}, env) do
    module = Map.get(env, :__module__, "Main")
    direct_render_point_arg?("#{module}.#{name}", idx, env)
  end

  defp point_var_parent?(_parent, _env), do: false

  defp direct_render_point_arg?(target, idx, env) when is_binary(target) do
    with {module_name, function_name} <- Host.split_qualified_function_target(target),
         %{type: type, args: args} <-
           Map.get(Map.get(env, :__program_decls__, %{}), {module_name, function_name}),
         key <- {module_name, function_name},
         true <-
           MapSet.member?(Map.get(env, :__direct_targets__, MapSet.new()), key) or
             MapSet.member?(Map.get(env, :__direct_pruned__, MapSet.new()), key),
         arg_type <-
           type
           |> Host.function_arg_types()
           |> Enum.at(idx)
           |> Host.normalize_type_name(),
         true <- point_type?(arg_type) or xy_record_return?(arg_type, {module_name, function_name}, env) do
      is_binary(Enum.at(args || [], idx))
    else
      _ -> false
    end
  end

  defp direct_render_point_arg?(_target, _idx, _env), do: false

  defp draw_point_arg_index?("Pebble.Ui.line", idx) when idx in [0, 1], do: true
  defp draw_point_arg_index?("Pebble.Ui.fillCircle", 0), do: true
  defp draw_point_arg_index?("Pebble.Ui.circle", 0), do: true
  defp draw_point_arg_index?("Pebble.Ui.pixel", 0), do: true
  defp draw_point_arg_index?(_target, _idx), do: false

  defp compile_field(args, field, env, counter) do
    fn_name = if field == "x", do: "elmc_polar_point_x", else: "elmc_polar_point_y"

    {parts, counter} =
      Enum.map_reduce(args, counter, fn arg, c ->
        {code, ref, c} = NativeInt.compile_expr(arg, env, c)
        {{code, ref}, c}
      end)

    params_code =
      parts
      |> Enum.map(fn {code, _} -> code end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    refs = Enum.map(parts, fn {_, ref} -> ref end)
    next = counter + 1
    out = "native_polar_#{field}_#{next}"

    code = """
    #{params_code}
      const elmc_int_t #{out} = #{fn_name}(#{Enum.join(refs, ", ")});
    """

    {:ok, code, out, next}
  end
end
