defmodule Elmc.Backend.CCodegen.Native.UsageAnalysis do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.IntCase, as: NativeIntCase
  alias Elmc.Backend.CCodegen.Types

  @spec int_usage(
          Types.binding_name(),
          Types.ir_expr(),
          String.t() | nil,
          Types.function_decl_map()
        ) :: Types.native_int_usage_stats()
  def int_usage(name, expr, module_name, decl_map) do
    base_contexts = collect_var_contexts(name, expr, :boxed)
    native_arg_contexts = collect_native_function_arg_contexts(name, expr, module_name, decl_map)

    call_site_native_arg_contexts =
      collect_call_site_signature_native_int_arg_contexts(name, expr, module_name, decl_map)

    record_update_contexts =
      collect_record_update_int_field_contexts(name, expr, module_name, decl_map)

    usage =
      base_contexts
      |> Enum.reduce(%{total: 0, boxed: 0, native: 0, native_container: 0}, fn context, acc ->
        %{
          total: acc.total + 1,
          boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
          native: acc.native + if(context == :native, do: 1, else: 0),
          native_container:
            acc.native_container + if(context == :native_container, do: 1, else: 0)
        }
      end)

    (native_arg_contexts ++ call_site_native_arg_contexts ++ record_update_contexts)
    |> Enum.reduce(usage, fn context, acc ->
      boxed =
        if context == :native_container do
          max(acc.boxed - 1, 0)
        else
          acc.boxed
        end

      %{
        acc
        | boxed: boxed,
          native_container:
            acc.native_container + if(context == :native_container, do: 1, else: 0)
      }
    end)
  end

  defp collect_native_function_arg_contexts(name, expr, module_name, decl_map)
       when is_map(expr) do
    own_contexts =
      case function_call_arg_kinds(expr, module_name, decl_map) do
        {args, arg_kinds} ->
          args
          |> Enum.zip(arg_kinds)
          |> Enum.flat_map(fn
            {arg, :native_int} -> collect_var_contexts(name, arg, :native_container)
            {_arg, _kind} -> []
          end)

        nil ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(&collect_native_function_arg_contexts(name, &1, module_name, decl_map))

    own_contexts ++ child_contexts
  end

  defp collect_native_function_arg_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs),
       do:
         Enum.flat_map(
           exprs,
           &collect_native_function_arg_contexts(name, &1, module_name, decl_map)
         )

  defp collect_native_function_arg_contexts(_name, _expr, _module_name, _decl_map), do: []

  # Callee bodies may capture Int params in lambdas (for example canPlace x/y inside
  # List.all), so default arg_kinds stay :boxed even though call sites pass native ints.
  defp collect_call_site_signature_native_int_arg_contexts(name, expr, module_name, decl_map)
       when is_map(expr) and is_binary(module_name) do
    own_contexts =
      case expr do
        %{op: :call, name: callee, args: args} when is_binary(callee) ->
          call_site_signature_native_int_var_contexts(name, {module_name, callee}, args, decl_map)

        %{op: :qualified_call, target: target, args: args} when is_binary(target) ->
          case Host.normalize_special_target(target) |> Host.split_qualified_function_target() do
            nil -> []
            target_key -> call_site_signature_native_int_var_contexts(name, target_key, args, decl_map)
          end

        _ ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(&collect_call_site_signature_native_int_arg_contexts(name, &1, module_name, decl_map))

    own_contexts ++ child_contexts
  end

  defp collect_call_site_signature_native_int_arg_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs) and is_binary(module_name),
       do:
         Enum.flat_map(
           exprs,
           &collect_call_site_signature_native_int_arg_contexts(name, &1, module_name, decl_map)
         )

  defp collect_call_site_signature_native_int_arg_contexts(_name, _expr, _module_name, _decl_map),
    do: []

  defp call_site_signature_native_int_var_contexts(name, target, args, decl_map) do
    case Map.get(decl_map, target) do
      nil ->
        []

      decl ->
        decl
        |> NativeFunctionCall.signature_arg_kinds(elem(target, 0), decl_map)
        |> Enum.zip(args || [])
        |> Enum.flat_map(fn
          {:native_int, arg} -> collect_var_contexts(name, arg, :native_container)
          _ -> []
        end)
    end
  end

  defp collect_record_update_int_field_contexts(name, expr, module_name, decl_map)
       when is_map(expr) do
    own_contexts =
      case expr do
        %{op: :record_update, base: base, fields: fields} when is_list(fields) ->
          env = analysis_env(module_name, decl_map)

          field_names =
            Enum.map(fields, fn field -> Map.get(field, :name) || Map.get(field, :field) end)

          record_type =
            Expr.record_container_type_for_expr(base, env) ||
              Expr.record_type_for_field_names(field_names, env) ||
              infer_record_type_from_int_field_names(field_names, module_name)

          fields
          |> Enum.flat_map(fn field ->
            field_name = Map.get(field, :name) || Map.get(field, :field)
            field_expr = Map.get(field, :expr) || Map.get(field, :value)

            if record_field_is_int?(field_name, record_type, module_name) do
              collect_var_contexts(name, field_expr, :native_container)
            else
              []
            end
          end)

        _ ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(&collect_record_update_int_field_contexts(name, &1, module_name, decl_map))

    own_contexts ++ child_contexts
  end

  defp collect_record_update_int_field_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs),
       do:
         Enum.flat_map(
           exprs,
           &collect_record_update_int_field_contexts(name, &1, module_name, decl_map)
         )

  defp collect_record_update_int_field_contexts(_name, _expr, _module_name, _decl_map), do: []

  defp analysis_env(module_name, decl_map) do
    %{
      :__module__ => module_name,
      :__program_decls__ => decl_map,
      :__record_field_types__ => Process.get(:elmc_record_field_types, %{})
    }
  end

  defp infer_record_type_from_int_field_names(field_names, module_name)
       when is_list(field_names) and is_binary(module_name) do
    infer_record_type_from_scalar_field_names(field_names, module_name, "Int")
  end

  defp infer_record_type_from_int_field_names(_field_names, _module_name), do: nil

  defp infer_record_type_from_scalar_field_names(field_names, module_name, scalar_type)
       when is_list(field_names) and is_binary(module_name) and is_binary(scalar_type) do
    field_names = Enum.map(field_names, &to_string/1)

    Process.get(:elmc_record_field_types, %{})
    |> Enum.find_value(fn {{mod, type}, field_types} ->
      if mod == module_name and
           Enum.all?(field_names, fn field_name ->
             field_types
             |> Map.get(field_name)
             |> Host.normalize_type_name() == scalar_type
           end) do
        type
      end
    end)
  end

  defp infer_record_type_from_scalar_field_names(_field_names, _module_name, _scalar_type), do: nil

  defp record_field_is_scalar?(field_name, record_type, module_name, scalar_type)
       when is_binary(field_name) and is_binary(record_type) and is_binary(module_name) and
              is_binary(scalar_type) do
    type_name = Host.normalize_type_name(record_type)

    field_types =
      Process.get(:elmc_record_field_types, %{})
      |> Map.get({module_name, type_name}, %{})
      |> case do
        types when map_size(types) > 0 -> types
        _ -> Map.get(Process.get(:elmc_record_field_types, %{}), {module_name, record_type}, %{})
      end

    case field_types do
      types when is_map(types) ->
        types
        |> Map.get(field_name, Map.get(types, to_string(field_name)))
        |> Host.normalize_type_name() == scalar_type

      _ ->
        false
    end
  end

  defp record_field_is_scalar?(_field_name, _record_type, _module_name, _scalar_type), do: false

  defp record_field_is_int?(field_name, record_type, module_name) do
    record_field_is_scalar?(field_name, record_type, module_name, "Int")
  end

  @spec function_call_arg_kinds(Types.ir_expr(), String.t() | nil, Types.function_decl_map()) ::
          {[Types.ir_expr()], [Types.native_function_arg_kind()]} | nil
  def function_call_arg_kinds(%{op: :call, name: name, args: args}, module_name, decl_map)
       when is_binary(name) and is_binary(module_name) do
    native_function_arg_kinds_for({module_name, name}, args, decl_map)
  end

  def function_call_arg_kinds(
         %{op: :qualified_call, target: target, args: args},
         _module_name,
         decl_map
       )
       when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> native_function_arg_kinds_for(args, decl_map)
  end

  def function_call_arg_kinds(_expr, _module_name, _decl_map), do: nil

  defp native_function_arg_kinds_for(nil, _args, _decl_map), do: nil

  defp native_function_arg_kinds_for(target, args, decl_map) do
    case Map.get(decl_map, target) do
      nil ->
        nil

      decl ->
        arg_kinds = native_function_arg_kinds_for_analysis(decl, elem(target, 0), decl_map)

        if Enum.any?(arg_kinds, &(&1 in [:native_int, :native_bool])) do
          {args, arg_kinds}
        else
          nil
        end
    end
  end

  defp native_function_arg_kinds_for_analysis(decl, module_name, decl_map) do
    Process.put(:elmc_skip_int_usage_recursion, true)

    try do
      NativeFunctionCall.arg_kinds(decl, module_name, decl_map)
    after
      Process.delete(:elmc_skip_int_usage_recursion)
    end
  end

  @spec int_let?(Types.binding_name(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  def int_let?(name, value_expr, in_expr, env) when is_binary(name) or is_atom(name) do
  not union_ctor_literal?(value_expr) and
      (binding_scalar_unboxed?(env, name, :int) or
         int_let_without_union_guard?(name, value_expr, in_expr, env))
  end

  def int_let?(_name, _value_expr, _in_expr, _env), do: false

  defp binding_scalar_unboxed?(env, name, kind) when is_binary(name) or is_atom(name) do
    mod = Map.get(env, :__module__)
    fun = Map.get(env, :__function_name__)

    is_binary(mod) and is_binary(fun) and
      Elmc.Backend.CCodegen.BindingPlans.scalar_unboxed?(mod, fun, to_string(name), kind)
  end

  defp int_let_without_union_guard?(name, value_expr, in_expr, env) do
    usage =
      int_usage(
        name,
        in_expr,
        Map.get(env, :__module__),
        Map.get(env, :__program_decls__, %{})
      )

    value_native? = NativeInt.native_let_value_expr?(value_expr, env)

    value_native? and native_int_only_usage?(usage)
  end

  @spec native_int_only_usage?(Types.native_int_usage_stats()) :: boolean()
  def native_int_only_usage?(usage) when is_map(usage) do
    usage.total > 0 and
      (usage.boxed == 0 or usage.native_container >= usage.boxed) and
      (usage.native_container > 0 or usage.native > 0)
  end

  def native_int_only_usage?(_usage), do: false

  defp union_ctor_literal?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor), do: true
  defp union_ctor_literal?(_expr), do: false

  @spec float_usage(
          Types.binding_name(),
          Types.ir_expr(),
          String.t() | nil,
          Types.function_decl_map()
        ) :: Types.native_float_usage_stats()
  def float_usage(name, expr, module_name, decl_map) do
    base_contexts = collect_float_contexts(name, expr, :boxed)

    native_arg_contexts =
      if is_binary(module_name) do
        collect_native_float_function_arg_contexts(name, expr, module_name, decl_map)
      else
        []
      end

    call_site_native_arg_contexts =
      collect_call_site_signature_native_float_arg_contexts(name, expr, module_name, decl_map)

    record_update_contexts =
      collect_record_update_float_field_contexts(name, expr, module_name, decl_map)

    usage =
      base_contexts
      |> Enum.reduce(%{total: 0, boxed: 0, native: 0, native_container: 0}, fn context, acc ->
        %{
          total: acc.total + 1,
          boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
          native: acc.native + if(context == :native, do: 1, else: 0),
          native_container:
            acc.native_container + if(context == :native_container, do: 1, else: 0)
        }
      end)

    (native_arg_contexts ++ call_site_native_arg_contexts ++ record_update_contexts)
    |> Enum.reduce(usage, fn context, acc ->
      boxed =
        if context == :native_container do
          max(acc.boxed - 1, 0)
        else
          acc.boxed
        end

      %{
        acc
        | boxed: boxed,
          native: acc.native + if(context == :native, do: 1, else: 0),
          native_container:
            acc.native_container + if(context == :native_container, do: 1, else: 0)
      }
    end)
  end

  defp collect_call_site_signature_native_float_arg_contexts(name, expr, module_name, decl_map)
       when is_map(expr) and is_binary(module_name) do
    own_contexts =
      case expr do
        %{op: :call, name: callee, args: args} when is_binary(callee) ->
          call_site_signature_native_float_var_contexts(name, {module_name, callee}, args, decl_map)

        %{op: :qualified_call, target: target, args: args} when is_binary(target) ->
          case Host.normalize_special_target(target) |> Host.split_qualified_function_target() do
            nil -> []
            target_key -> call_site_signature_native_float_var_contexts(name, target_key, args, decl_map)
          end

        _ ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(
        &collect_call_site_signature_native_float_arg_contexts(name, &1, module_name, decl_map)
      )

    own_contexts ++ child_contexts
  end

  defp collect_call_site_signature_native_float_arg_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs) and is_binary(module_name),
       do:
         Enum.flat_map(
           exprs,
           &collect_call_site_signature_native_float_arg_contexts(name, &1, module_name, decl_map)
         )

  defp collect_call_site_signature_native_float_arg_contexts(_name, _expr, _module_name, _decl_map),
    do: []

  defp call_site_signature_native_float_var_contexts(name, target, args, decl_map) do
    case Map.get(decl_map, target) do
      %{type: type} when is_binary(type) ->
        arg_types = Host.function_arg_types(type)

        (args || [])
        |> Enum.zip(arg_types)
        |> Enum.flat_map(fn
          {arg, arg_type} ->
            if Host.normalize_type_name(arg_type) == "Float" do
              collect_float_contexts(name, arg, :native_container)
            else
              []
            end
        end)

      _ ->
        []
    end
  end

  defp collect_record_update_float_field_contexts(name, expr, module_name, decl_map)
       when is_map(expr) do
    own_contexts =
      case expr do
        %{op: :record_update, base: base, fields: fields} when is_list(fields) ->
          env = analysis_env(module_name, decl_map)

          field_names =
            Enum.map(fields, fn field -> Map.get(field, :name) || Map.get(field, :field) end)

          record_type =
            Expr.record_container_type_for_expr(base, env) ||
              Expr.record_type_for_field_names(field_names, env) ||
              infer_record_type_from_scalar_field_names(field_names, module_name, "Float")

          fields
          |> Enum.flat_map(fn field ->
            field_name = Map.get(field, :name) || Map.get(field, :field)
            field_expr = Map.get(field, :expr) || Map.get(field, :value)

            if record_field_is_scalar?(field_name, record_type, module_name, "Float") do
              collect_float_contexts(name, field_expr, :native_container)
            else
              []
            end
          end)

        _ ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(
        &collect_record_update_float_field_contexts(name, &1, module_name, decl_map)
      )

    own_contexts ++ child_contexts
  end

  defp collect_record_update_float_field_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs),
       do:
         Enum.flat_map(
           exprs,
           &collect_record_update_float_field_contexts(name, &1, module_name, decl_map)
         )

  defp collect_record_update_float_field_contexts(_name, _expr, _module_name, _decl_map), do: []

  @spec native_float_only_usage?(Types.native_float_usage_stats()) :: boolean()
  def native_float_only_usage?(usage) when is_map(usage) do
    usage.total > 0 and
      (usage.boxed == 0 or usage.native_container >= usage.boxed) and
      (usage.native_container > 0 or usage.native > 0)
  end

  def native_float_only_usage?(_usage), do: false

  defp collect_native_float_function_arg_contexts(name, expr, module_name, decl_map)
       when is_binary(name) or is_atom(name) do
    own_contexts =
      case expr do
        %{op: :call, name: call_name, args: args} ->
          case function_call_arg_kinds(
                 %{op: :call, name: call_name, args: args},
                 module_name,
                 decl_map
               ) do
            {_call_args, native_arg_kinds} ->
              args
              |> Enum.zip(native_arg_kinds)
              |> Enum.flat_map(fn
                {arg, :native_int} -> collect_float_contexts(name, arg, :native_container)
                {arg, _} -> collect_float_contexts(name, arg, :native)
              end)

            nil ->
              []
          end

        %{op: :qualified_call, target: target, args: args} ->
          collect_native_float_function_arg_contexts(
            name,
            %{op: :call, name: target, args: args},
            module_name,
            decl_map
          )

        _ ->
          []
      end

    child_contexts =
      if is_map(expr) do
        expr
        |> Map.values()
        |> Enum.flat_map(
          &collect_native_float_function_arg_contexts(name, &1, module_name, decl_map)
        )
      else
        []
      end

    own_contexts ++ child_contexts
  end

  defp collect_native_float_function_arg_contexts(_name, _expr, _module_name, _decl_map), do: []

  @spec float_let?(Types.binding_name(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  def float_let?(name, value_expr, in_expr, env) when is_binary(name) or is_atom(name) do
    binding_scalar_unboxed?(env, name, :float) or
      float_let_without_guard?(name, value_expr, in_expr, env)
  end

  def float_let?(_name, _value_expr, _in_expr, _env), do: false

  defp float_let_without_guard?(name, value_expr, in_expr, env) do
    usage = float_usage(name, in_expr, Map.get(env, :__module__), Map.get(env, :__program_decls__, %{}))

    Host.native_float_expr?(value_expr, env) and not Host.native_int_expr?(value_expr, env) and
      native_float_only_usage?(usage) and
      not Host.binding_used_in_lambda?(name, in_expr)
  end

  @spec string_let?(Types.binding_name(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  def string_let?(name, value_expr, in_expr, env) when is_binary(name) or is_atom(name) do
    usage = string_usage(name, in_expr, Map.get(env, :__module__), Map.get(env, :__program_decls__, %{}))

    Host.native_string_expr?(value_expr, env) and usage.total > 0 and
      (usage.native_string > 0 or usage.native_container > 0) and
      (usage.boxed == 0 or usage.native_container > 0) and
      not Host.binding_used_in_lambda?(name, in_expr) and
      not native_string_value_may_contain_nul?(value_expr)
  end

  def string_let?(_name, _value_expr, _in_expr, _env), do: false

  defp native_string_value_may_contain_nul?(%{op: :runtime_call, function: "elmc_string_from_char", args: [_]}),
    do: true

  defp native_string_value_may_contain_nul?(%{op: :qualified_call, target: target, args: [_]})
       when target in ["String.fromChar", "Basics.fromChar"],
       do: true

  defp native_string_value_may_contain_nul?(%{op: :call, name: name, args: [_]})
       when name in ["fromChar", "__fromChar__"],
       do: true

  defp native_string_value_may_contain_nul?(%{op: :runtime_call, function: "elmc_append", args: [left, right]}),
    do: native_string_value_may_contain_nul?(left) or native_string_value_may_contain_nul?(right)

  defp native_string_value_may_contain_nul?(%{op: :call, name: "__append__", args: [left, right]}),
    do: native_string_value_may_contain_nul?(left) or native_string_value_may_contain_nul?(right)

  defp native_string_value_may_contain_nul?(%{op: :string_literal, value: value}) when is_binary(value),
    do: String.contains?(value, <<0>>)

  defp native_string_value_may_contain_nul?(_), do: false

  @spec string_usage(
          Types.binding_name(),
          Types.ir_expr(),
          String.t() | nil,
          Types.function_decl_map()
        ) :: Types.native_string_usage_stats()
  def string_usage(name, expr, module_name, decl_map) do
    base_contexts = collect_string_var_contexts(name, expr, :boxed)

    native_arg_contexts =
      if is_binary(module_name) do
        collect_native_string_function_arg_contexts(name, expr, module_name, decl_map)
      else
        []
      end

    usage =
      base_contexts
      |> Enum.reduce(%{total: 0, boxed: 0, native_string: 0, native_container: 0}, fn context,
                                                                                        acc ->
        %{
          total: acc.total + 1,
          boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
          native_string: acc.native_string + if(context == :native_string, do: 1, else: 0),
          native_container:
            acc.native_container + if(context == :native_container, do: 1, else: 0)
        }
      end)

    native_arg_contexts
    |> Enum.reduce(usage, fn context, acc ->
      %{
        acc
        | native_string: acc.native_string + if(context == :native_string, do: 1, else: 0),
          native_container:
            acc.native_container + if(context == :native_container, do: 1, else: 0)
      }
    end)
  end

  defp collect_string_var_contexts(name, %{op: :var, name: var_name}, context) do
    if EnvBindings.same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_string_var_contexts(name, %{op: :call, name: "__append__", args: [left, right]}, _context) do
    collect_string_var_contexts(name, left, :native_string) ++
      collect_string_var_contexts(name, right, :native_string)
  end

  defp collect_string_var_contexts(
         name,
         %{op: :qualified_call, target: target, args: args},
         _context
       ) do
    case Host.normalize_special_target(target) do
      target when target in ["String.append", "Pebble.Ui.textLabel", "Pebble.Ui.text"] ->
        Enum.flat_map(args, &collect_string_var_contexts(name, &1, :native_string))

      _ ->
        []
    end
  end

  defp collect_string_var_contexts(name, %{op: :if, then_expr: then_expr, else_expr: else_expr}, _context) do
    collect_string_var_contexts(name, then_expr, :native_string) ++
      collect_string_var_contexts(name, else_expr, :native_string)
  end

  defp collect_string_var_contexts(name, %{op: :let_in, value_expr: value_expr, in_expr: in_expr}, _context) do
    collect_string_var_contexts(name, value_expr, :boxed) ++
      collect_string_var_contexts(name, in_expr, :native_string)
  end

  defp collect_string_var_contexts(name, expr, _context),
    do: collect_var_contexts(name, expr, :boxed)

  defp collect_native_string_function_arg_contexts(name, expr, module_name, decl_map) do
    case expr do
      %{op: :call, name: call_name, args: args} ->
        case function_call_arg_kinds(
               %{op: :call, name: call_name, args: args},
               module_name,
               decl_map
             ) do
          {_call_args, native_arg_kinds} ->
            args
            |> Enum.zip(native_arg_kinds)
            |> Enum.flat_map(fn
              {arg, :native_string} -> collect_string_var_contexts(name, arg, :native_string)
              {arg, _} -> collect_string_var_contexts(name, arg, :native)
            end)

          nil ->
            []
        end

      %{op: :qualified_call, target: target, args: args} ->
        collect_native_string_function_arg_contexts(
          name,
          %{op: :call, name: target, args: args},
          module_name,
          decl_map
        )

      _ ->
        []
    end
  end

  @spec pebble_angle_let?(Types.binding_name(), Types.ir_expr(), Types.ir_expr()) :: boolean()
  def pebble_angle_let?(name, value_expr, in_expr) when is_binary(name) or is_atom(name) do
    Host.pebble_angle_expr?(value_expr) and Host.binding_reference_count(name, in_expr) > 0 and
      Host.binding_reference_count(name, in_expr) ==
        Host.pebble_angle_optimized_reference_count(name, in_expr)
  end

  def pebble_angle_let?(_name, _value_expr, _in_expr), do: false

  @spec bool_usage(
          Types.binding_name(),
          Types.ir_expr(),
          String.t(),
          Types.function_decl_map()
        ) :: Types.native_bool_usage_stats()
  def bool_usage(name, expr, module_name, decl_map) do
    base_contexts = collect_bool_contexts(name, expr, :boxed)

    native_arg_contexts =
      collect_native_bool_function_arg_contexts(name, expr, module_name, decl_map)

    call_site_native_arg_contexts =
      collect_call_site_signature_native_bool_arg_contexts(name, expr, module_name, decl_map)

    record_update_contexts =
      collect_record_update_bool_field_contexts(name, expr, module_name, decl_map)

    usage =
      base_contexts
      |> Enum.reduce(%{total: 0, boxed: 0, tests: 0}, fn context, acc ->
        %{
          total: acc.total + 1,
          boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
          tests: acc.tests + if(context == :bool_test, do: 1, else: 0)
        }
      end)

    (native_arg_contexts ++ call_site_native_arg_contexts ++ record_update_contexts)
    |> Enum.reduce(usage, fn context, acc ->
      boxed =
        if context == :bool_test do
          max(acc.boxed - 1, 0)
        else
          acc.boxed
        end

      %{
        acc
        | boxed: boxed,
          tests: acc.tests + if(context == :bool_test, do: 1, else: 0)
      }
    end)
  end

  @spec bool_let?(Types.binding_name(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  def bool_let?(name, value_expr, in_expr, env) when is_binary(name) or is_atom(name) do
    binding_scalar_unboxed?(env, name, :bool) or
      bool_let_without_guard?(name, value_expr, in_expr, env)
  end

  def bool_let?(_name, _value_expr, _in_expr, _env), do: false

  defp bool_let_without_guard?(name, value_expr, in_expr, env) do
    usage =
      bool_usage(
        name,
        in_expr,
        Map.get(env, :__module__),
        Map.get(env, :__program_decls__, %{})
      )

    Host.native_bool_expr?(value_expr, env) and native_bool_only_usage?(usage) and
      not Host.binding_used_in_lambda?(name, in_expr)
  end

  @spec native_bool_only_usage?(Types.native_bool_usage_stats()) :: boolean()
  def native_bool_only_usage?(usage) when is_map(usage) do
    usage.total > 0 and (usage.boxed == 0 or usage.tests >= usage.boxed) and usage.tests > 0
  end

  def native_bool_only_usage?(_usage), do: false

  defp collect_call_site_signature_native_bool_arg_contexts(name, expr, module_name, decl_map)
       when is_map(expr) and is_binary(module_name) do
    own_contexts =
      case expr do
        %{op: :call, name: callee, args: args} when is_binary(callee) ->
          call_site_signature_native_bool_var_contexts(name, {module_name, callee}, args, decl_map)

        %{op: :qualified_call, target: target, args: args} when is_binary(target) ->
          case Host.normalize_special_target(target) |> Host.split_qualified_function_target() do
            nil -> []
            target_key -> call_site_signature_native_bool_var_contexts(name, target_key, args, decl_map)
          end

        _ ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(
        &collect_call_site_signature_native_bool_arg_contexts(name, &1, module_name, decl_map)
      )

    own_contexts ++ child_contexts
  end

  defp collect_call_site_signature_native_bool_arg_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs) and is_binary(module_name),
       do:
         Enum.flat_map(
           exprs,
           &collect_call_site_signature_native_bool_arg_contexts(name, &1, module_name, decl_map)
         )

  defp collect_call_site_signature_native_bool_arg_contexts(_name, _expr, _module_name, _decl_map),
    do: []

  defp call_site_signature_native_bool_var_contexts(name, target, args, decl_map) do
    case Map.get(decl_map, target) do
      nil ->
        []

      decl ->
        decl
        |> NativeFunctionCall.signature_arg_kinds(elem(target, 0), decl_map)
        |> Enum.zip(args || [])
        |> Enum.flat_map(fn
          {:native_bool, arg} -> collect_bool_contexts(name, arg, :bool_test)
          _ -> []
        end)
    end
  end

  defp collect_record_update_bool_field_contexts(name, expr, module_name, decl_map)
       when is_map(expr) do
    own_contexts =
      case expr do
        %{op: :record_update, base: base, fields: fields} when is_list(fields) ->
          env = analysis_env(module_name, decl_map)

          field_names =
            Enum.map(fields, fn field -> Map.get(field, :name) || Map.get(field, :field) end)

          record_type =
            Expr.record_container_type_for_expr(base, env) ||
              Expr.record_type_for_field_names(field_names, env) ||
              infer_record_type_from_scalar_field_names(field_names, module_name, "Bool")

          fields
          |> Enum.flat_map(fn field ->
            field_name = Map.get(field, :name) || Map.get(field, :field)
            field_expr = Map.get(field, :expr) || Map.get(field, :value)

            if record_field_is_scalar?(field_name, record_type, module_name, "Bool") do
              collect_bool_contexts(name, field_expr, :bool_test)
            else
              []
            end
          end)

        _ ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(
        &collect_record_update_bool_field_contexts(name, &1, module_name, decl_map)
      )

    own_contexts ++ child_contexts
  end

  defp collect_record_update_bool_field_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs),
       do:
         Enum.flat_map(
           exprs,
           &collect_record_update_bool_field_contexts(name, &1, module_name, decl_map)
         )

  defp collect_record_update_bool_field_contexts(_name, _expr, _module_name, _decl_map), do: []

  defp collect_native_bool_function_arg_contexts(name, expr, module_name, decl_map)
       when is_map(expr) do
    own_contexts =
      case function_call_arg_kinds(expr, module_name, decl_map) do
        {args, arg_kinds} ->
          args
          |> Enum.zip(arg_kinds)
          |> Enum.flat_map(fn
            {arg, :native_bool} -> collect_bool_contexts(name, arg, :bool_test)
            {_arg, _kind} -> []
          end)

        nil ->
          []
      end

    child_contexts =
      expr
      |> Map.values()
      |> Enum.flat_map(
        &collect_native_bool_function_arg_contexts(name, &1, module_name, decl_map)
      )

    own_contexts ++ child_contexts
  end

  defp collect_native_bool_function_arg_contexts(name, exprs, module_name, decl_map)
       when is_list(exprs),
       do:
         Enum.flat_map(
           exprs,
           &collect_native_bool_function_arg_contexts(name, &1, module_name, decl_map)
         )

  defp collect_native_bool_function_arg_contexts(_name, _expr, _module_name, _decl_map), do: []

  defp collect_bool_contexts(name, %{op: :var, name: var_name}, context) do
    if EnvBindings.same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_bool_contexts(
         name,
         %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr},
         _context
       ) do
    collect_bool_contexts(name, cond, :bool_test) ++
      collect_bool_contexts(name, then_expr, :boxed) ++
      collect_bool_contexts(name, else_expr, :boxed)
  end

  defp collect_bool_contexts(
         name,
         %{op: :let_in, name: binding_name, value_expr: value_expr, in_expr: in_expr},
         context
       ) do
    value_contexts = collect_bool_contexts(name, value_expr, context)

    if EnvBindings.same_binding?(name, binding_name) do
      value_contexts
    else
      value_contexts ++ collect_bool_contexts(name, in_expr, context)
    end
  end

  defp collect_bool_contexts(name, %{op: :lambda, args: args, body: body}, _context)
       when is_list(args) do
    if Enum.any?(args, &EnvBindings.same_binding?(name, &1)) do
      []
    else
      collect_bool_contexts(name, body, :boxed)
    end
  end

  defp collect_bool_contexts(name, %{op: :call, name: call_name, args: args}, _context)
       when is_list(args) do
    arg_context =
      if call_name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] do
        :bool_test
      else
        :boxed
      end

    Enum.flat_map(args, &collect_bool_contexts(name, &1, arg_context))
  end

  defp collect_bool_contexts(name, %{op: :qualified_call, target: target, args: args}, _context)
       when is_list(args) do
    arg_context =
      if Host.qualified_builtin_operator_member?(target, [
           "__eq__",
           "__neq__",
           "__lt__",
           "__lte__",
           "__gt__",
           "__gte__"
         ]) do
        :bool_test
      else
        :boxed
      end

    Enum.flat_map(args, &collect_bool_contexts(name, &1, arg_context))
  end

  defp collect_bool_contexts(
         name,
         %{op: :runtime_call, function: "elmc_basics_not", args: [value]},
         _context
       ) do
    collect_bool_contexts(name, value, :bool_test)
  end

  defp collect_bool_contexts(name, expr, context) when is_map(expr),
    do: collect_bool_contexts_from_map(name, expr, context)

  defp collect_bool_contexts(name, exprs, context) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_bool_contexts(name, &1, context))

  defp collect_bool_contexts(_name, _expr, _context), do: []

  defp collect_bool_contexts_from_map(name, expr, context) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_bool_contexts(name, &1, context))
  end

  defp collect_var_contexts(name, %{op: :var, name: var_name}, context) do
    if EnvBindings.same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_var_contexts(name, %{op: :add_const, var: var_name}, _context) do
    if EnvBindings.same_binding?(name, var_name), do: [:native], else: []
  end

  defp collect_var_contexts(name, %{op: :sub_const, var: var_name}, _context) do
    if EnvBindings.same_binding?(name, var_name), do: [:native], else: []
  end

  defp collect_var_contexts(name, %{op: :add_vars, left: left, right: right}, _context) do
    [left, right]
    |> Enum.filter(&EnvBindings.same_binding?(name, &1))
    |> Enum.map(fn _ -> :native end)
  end

  defp collect_var_contexts(name, %{op: :call, name: call_name, args: [left, right]}, _context)
       when call_name in ["__eq__", "__neq__"] do
    collect_var_contexts(name, left, equality_operand_context(right)) ++
      collect_var_contexts(name, right, equality_operand_context(left))
  end

  defp collect_var_contexts(name, %{op: :call, name: call_name, args: args}, _context)
       when call_name in [
              "__lt__",
              "__lte__",
              "__gt__",
              "__gte__",
              "__add__",
              "__sub__",
              "__mul__",
              "__idiv__",
              "modBy",
              "remainderBy"
            ] do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
  end

  defp collect_var_contexts(name, %{op: :runtime_call, function: function, args: args}, _context)
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
  end

  defp collect_var_contexts(name, %{op: :runtime_call, function: function, args: args}, _context)
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
  end

  defp collect_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context
       )
       when function in ["elmc_basics_mod_by", "elmc_basics_remainder_by"] do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
  end

  defp collect_var_contexts(
         name,
         %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
         _context
       ) do
    collect_var_contexts(name, value, :native)
  end

  @list_unary_container_runtime_functions ~w(
    elmc_list_length
    elmc_list_is_empty
    elmc_list_reverse
    elmc_list_head
    elmc_list_tail
    elmc_list_sum
    elmc_list_product
    elmc_list_maximum
    elmc_list_minimum
    elmc_list_sort
    elmc_list_concat
  )

  @list_hof_list_arg_index %{
    "elmc_list_foldl" => 2,
    "elmc_list_foldr" => 2,
    "elmc_list_map" => 1,
    "elmc_list_filter" => 1,
    "elmc_list_filter_map" => 1,
    "elmc_list_find_first" => 1,
    "elmc_list_all" => 1,
    "elmc_list_any" => 1,
    "elmc_list_concat_map" => 1,
    "elmc_list_indexed_map" => 1,
    "elmc_list_sort_by" => 1,
    "elmc_list_sort_with" => 1,
    "elmc_list_partition" => 1,
    "elmc_list_take" => 1,
    "elmc_list_drop" => 1,
    "elmc_list_intersperse" => 1,
    "elmc_list_slice_int" => 2,
    "elmc_list_member" => 1,
    "elmc_list_unzip" => 0
  }

  @list_binary_container_runtime_functions ~w(elmc_list_append)

  @list_hof_runtime_functions Map.keys(@list_hof_list_arg_index)

  defp collect_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: [arg]},
         _context
       )
       when function in @list_unary_container_runtime_functions do
    collect_var_contexts(name, arg, :native_container)
  end

  defp collect_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context
       )
       when function in @list_binary_container_runtime_functions do
    Enum.flat_map(args, &collect_var_contexts(name, &1, :native_container))
  end

  defp collect_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context
       )
       when function in @list_hof_runtime_functions do
    idx = Map.fetch!(@list_hof_list_arg_index, function)

    case Enum.at(args, idx) do
      nil -> []
      arg -> collect_var_contexts(name, arg, :native_container)
    end
  end

  defp collect_var_contexts(
         name,
         %{op: :qualified_call, target: target, args: args} = expr,
         context
       ) do
    normalized = Host.normalize_special_target(target)

    case text_command_var_contexts(name, normalized, args, context) do
      :skip ->
        case Host.special_value_from_target(target, args) do
          nil ->
            if Host.qualified_builtin_operator_member?(target, [
                 "__add__",
                 "__sub__",
                 "__mul__",
                 "__idiv__",
                 "modBy",
                 "remainderBy"
               ]) do
              Enum.flat_map(args, &collect_var_contexts(name, &1, :native))
            else
              collect_var_contexts_from_map(name, expr, context)
            end

          rewritten ->
            collect_var_contexts(name, rewritten, context)
        end

      contexts ->
        contexts
    end
  end

  defp collect_var_contexts(name, %{op: :tuple2, left: left, right: right}, _context) do
    collect_var_contexts(name, left, :boxed) ++ collect_var_contexts(name, right, :boxed)
  end

  defp collect_var_contexts(name, %{op: :record_literal, fields: fields}, _context)
       when is_list(fields) do
    Enum.flat_map(fields, fn field ->
      context =
        if int_candidate_for_analysis?(name, field.expr),
          do: :native_container,
          else: :boxed

      collect_var_contexts(name, field.expr, context)
    end)
  end

  defp collect_var_contexts(name, %{op: :compare, kind: kind, left: left, right: right}, _context)
       when kind in [:eq, :neq] do
    collect_var_contexts(name, left, equality_operand_context(right)) ++
      collect_var_contexts(name, right, equality_operand_context(left))
  end

  defp collect_var_contexts(name, %{op: :compare, left: left, right: right}, _context) do
    left_context =
      if int_candidate_for_analysis?(name, left), do: :native, else: :boxed

    right_context =
      if int_candidate_for_analysis?(name, right), do: :native, else: :boxed

    collect_var_contexts(name, left, left_context) ++
      collect_var_contexts(name, right, right_context)
  end

  defp collect_var_contexts(
         name,
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         _context
       ) do
    branch_context =
      if int_candidate_for_analysis?(name, then_expr) and
           int_candidate_for_analysis?(name, else_expr),
         do: :native,
         else: :boxed

    collect_var_contexts(name, cond_expr, :boxed) ++
      collect_var_contexts(name, then_expr, branch_context) ++
      collect_var_contexts(name, else_expr, branch_context)
  end

  defp collect_var_contexts(
         name,
         %{op: :case, subject: subject, branches: branches},
         context
       ) do
    subject_contexts =
      cond do
        EnvBindings.same_binding?(name, subject) and NativeIntCase.branches?(branches) ->
          [:native_container]

        EnvBindings.same_binding?(name, subject) ->
          [:boxed]

        NativeIntCase.branches?(branches) ->
          collect_var_contexts(name, subject, :native)

        true ->
          collect_var_contexts(name, subject, context)
      end

    subject_contexts ++ collect_var_contexts(name, branches, context)
  end

  defp collect_var_contexts(name, %{op: :lambda, args: args, body: body}, _context)
       when is_list(args) do
    if Enum.any?(args, &EnvBindings.same_binding?(name, &1)) do
      []
    else
      collect_var_contexts(name, body, :boxed)
    end
  end

  defp collect_var_contexts(
         name,
         %{op: :let_in, name: binding_name, value_expr: value_expr, in_expr: in_expr},
         context
       ) do
    value_contexts = collect_var_contexts(name, value_expr, context)

    if EnvBindings.same_binding?(name, binding_name) do
      value_contexts
    else
      value_contexts ++ collect_var_contexts(name, in_expr, context)
    end
  end

  defp collect_var_contexts(name, expr, context) when is_map(expr),
    do: collect_var_contexts_from_map(name, expr, context)

  defp collect_var_contexts(name, exprs, context) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_var_contexts(name, &1, context))

  defp collect_var_contexts(_name, _expr, _context), do: []

  defp text_command_var_contexts(name, "Pebble.Ui.text", args, context) when length(args) == 4 do
    collect_var_contexts_for_function_args(name, args, [:boxed, :boxed, :boxed, :boxed], context)
  end

  defp text_command_var_contexts(name, "Pebble.Ui.textLabel", args, context)
       when length(args) == 3 do
    collect_var_contexts_for_function_args(name, args, [:boxed, :boxed, :boxed], context)
  end

  defp text_command_var_contexts(name, "Pebble.Ui.textInt", args, context)
       when length(args) == 3 do
    collect_var_contexts_for_function_args(name, args, [:boxed, :boxed, :native], context)
  end

  defp text_command_var_contexts(_name, _target, _args, _context), do: :skip

  defp collect_var_contexts_for_function_args(name, args, kinds, default_context) do
    args
    |> Enum.zip(kinds)
    |> Enum.flat_map(fn {arg, kind} ->
      arg_context =
        case kind do
          :native -> :native
          :boxed -> :boxed
          _ -> default_context
        end

      collect_var_contexts(name, arg, arg_context)
    end)
  end

  defp collect_var_contexts_from_map(name, expr, context) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_var_contexts(name, &1, context))
  end

  defp collect_float_contexts(name, %{op: :var, name: var_name}, context) do
    if EnvBindings.same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_float_contexts(name, %{op: :call, name: call_name, args: args}, _context)
       when call_name in ["__add__", "__sub__", "__mul__", "__fdiv__"] do
    Enum.flat_map(args, &collect_float_contexts(name, &1, :native))
  end

  defp collect_float_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context
       )
       when function in [
              "elmc_basics_to_float",
              "elmc_basics_sin",
              "elmc_basics_cos",
              "elmc_basics_tan",
              "elmc_basics_sqrt",
              "elmc_basics_abs",
              "elmc_basics_negate",
              "elmc_basics_round",
              "elmc_basics_floor",
              "elmc_basics_ceiling",
              "elmc_basics_truncate"
            ] do
    Enum.flat_map(args, &collect_float_contexts(name, &1, :native))
  end

  defp collect_float_contexts(
         name,
         %{op: :qualified_call, target: target, args: args} = expr,
         context
       ) do
    case Host.special_value_from_target(target, args) do
      nil ->
        if Host.qualified_builtin_operator_member?(target, [
             "__add__",
             "__sub__",
             "__mul__",
             "__fdiv__",
             "toFloat",
             "round",
             "floor",
             "ceiling",
             "truncate",
             "abs",
             "negate"
           ]) do
          Enum.flat_map(args, &collect_float_contexts(name, &1, :native))
        else
          collect_float_contexts_from_map(name, expr, context)
        end

      rewritten ->
        collect_float_contexts(name, rewritten, context)
    end
  end

  defp collect_float_contexts(
         name,
         %{op: :let_in, name: binding_name, value_expr: value_expr, in_expr: in_expr},
         context
       ) do
    value_contexts = collect_float_contexts(name, value_expr, context)

    if EnvBindings.same_binding?(name, binding_name) do
      value_contexts
    else
      value_contexts ++ collect_float_contexts(name, in_expr, context)
    end
  end

  defp collect_float_contexts(name, %{op: :lambda, args: args, body: body}, _context)
       when is_list(args) do
    if Enum.any?(args, &EnvBindings.same_binding?(name, &1)) do
      []
    else
      collect_float_contexts(name, body, :boxed)
    end
  end

  defp collect_float_contexts(name, expr, context) when is_map(expr),
    do: collect_float_contexts_from_map(name, expr, context)

  defp collect_float_contexts(name, exprs, context) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_float_contexts(name, &1, context))

  defp collect_float_contexts(_name, _expr, _context), do: []

  defp collect_float_contexts_from_map(name, expr, context) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_float_contexts(name, &1, context))
  end

  @spec int_candidate_for_analysis?(Types.binding_name(), Types.ir_expr()) :: boolean()
  def int_candidate_for_analysis?(name, %{op: :var, name: var_name}),
    do: EnvBindings.same_binding?(name, var_name)

  def int_candidate_for_analysis?(_name, %{op: :field_access}), do: true

  def int_candidate_for_analysis?(name, %{
         op: :if,
         then_expr: then_expr,
         else_expr: else_expr
       }) do
    int_candidate_for_analysis?(name, then_expr) and
      int_candidate_for_analysis?(name, else_expr)
  end

  def int_candidate_for_analysis?(name, %{op: :call, name: call_name, args: args})
       when call_name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] do
    length(args || []) == 2 and Enum.all?(args, &int_candidate_for_analysis?(name, &1))
  end

  def int_candidate_for_analysis?(name, %{op: :call, name: call_name, args: args})
       when call_name in ["abs", "negate"] do
    length(args || []) == 1 and Enum.all?(args, &int_candidate_for_analysis?(name, &1))
  end

  def int_candidate_for_analysis?(name, %{
         op: :runtime_call,
         function: function,
         args: args
       })
       when function in [
              "elmc_basics_min",
              "elmc_basics_max",
              "elmc_basics_mod_by",
              "elmc_basics_remainder_by"
            ] do
    length(args || []) == 2 and Enum.all?(args, &int_candidate_for_analysis?(name, &1))
  end

  def int_candidate_for_analysis?(name, %{
         op: :runtime_call,
         function: function,
         args: args
       })
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    length(args || []) == 1 and Enum.all?(args, &int_candidate_for_analysis?(name, &1))
  end

  def int_candidate_for_analysis?(name, %{op: :qualified_call, target: target, args: args}) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil ->
        builtin = Host.qualified_builtin_operator_name(Host.normalize_special_target(target))
        int_candidate_for_analysis?(name, %{op: :call, name: builtin, args: args || []})

      rewritten ->
        int_candidate_for_analysis?(name, rewritten)
    end
  end

  def int_candidate_for_analysis?(_name, expr), do: NativeInt.structural_expr?(expr)

  defp equality_operand_context(other) do
    if non_int_equality_operand?(other), do: :boxed, else: :native
  end

  defp non_int_equality_operand?(%{op: :string_literal}), do: true
  defp non_int_equality_operand?(%{op: :char_literal}), do: true
  defp non_int_equality_operand?(_other), do: false

end
