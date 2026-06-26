defmodule Elmx.Backend.ElixirCodegen do
  @moduledoc """
  Emits Elixir source from lowered `ElmEx.IR`.
  """

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ReachableModules
  alias Elmx.Backend.UnsupportedOpError
  alias Elmx.Types

  @type emit_options :: Types.emit_options()
  @type emit_error :: Types.emit_error()

  @spec emit_project(ElmEx.IR.t(), emit_options()) ::
          {:ok, [Elmx.CompileResult.compiled_module()]} | {:error, emit_error()}
  def emit_project(%ElmEx.IR{} = ir, opts \\ %{}) do
    entry_module = Map.get(opts, :entry_module, "Main")
    ir_sha256 = Map.get(opts, :ir_sha256) || Elmx.IRDigest.sha256(ir)
    generated_name = generated_module_name(entry_module, ir_sha256)
    virtual_dir = "elmx/generated/#{String.slice(ir_sha256, 0, 8)}"

    try do
      constructor_lookup = Elmx.Backend.ConstructorLookup.from_ir(ir)

      emit_modules = modules_for_emit(ir, opts)
      cross_module_arities = cross_module_arities_from_modules(emit_modules)
      port_signatures = port_signatures_from_modules(emit_modules)
      emit_module_names = Enum.map(emit_modules, & &1.name)

      function_results =
        emit_modules
        |> Enum.flat_map(fn mod ->
          record_field_types = record_field_types_from_declarations(mod.declarations)
          zero_arity_fns = zero_arity_fns_from_declarations(mod.declarations)
          function_arities = function_arities_from_declarations(mod.declarations)

          mod.declarations
          |> Enum.filter(&(&1.kind == :function and is_map(&1.expr)))
          |> Enum.map(fn decl ->
            emit_function(
              mod.name,
              decl,
              record_field_types,
              zero_arity_fns,
              function_arities.callable,
              function_arities.explicit,
              constructor_lookup,
              cross_module_arities,
              emit_module_names,
              port_signatures,
              Map.get(opts, :mode, :library),
              ir_sha256
            )
          end)
        end)

      {function_sources, uses_bitwise_flags} = Enum.unzip(function_results)
      needs_bitwise = Enum.any?(uses_bitwise_flags)

      worker_source = Elmx.Backend.Worker.render(generated_name, entry_module, ir, opts)
      runtime_imports = runtime_import_header(needs_bitwise)

      source =
        [
          runtime_imports,
          "\n\ndefmodule ",
          generated_name,
          " do\n  @moduledoc false\n\n",
          Enum.join(function_sources, "\n\n"),
          "\n\n",
          worker_source,
          "\nend\n"
        ]
        |> IO.iodata_to_binary()

      modules = [
        %{
          name: generated_name,
          source: source,
          virtual_path: Path.join(virtual_dir, Macro.underscore(generated_name) <> ".ex")
        }
      ]

      {:ok, modules}
    rescue
      e in UnsupportedOpError ->
        {:error, {:unsupported_op, e.op, e.message}}

      e ->
        {:error, {:emit_failed, Exception.message(e)}}
    end
  end

  @spec write_project(ElmEx.IR.t(), String.t(), emit_options()) :: :ok | {:error, emit_error()}
  def write_project(%ElmEx.IR{} = ir, out_dir, opts \\ %{}) when is_binary(out_dir) do
    with {:ok, modules} <- emit_project(ir, opts) do
      elixir_dir = Path.join(out_dir, "elixir")
      File.mkdir_p!(elixir_dir)

      Enum.each(modules, fn %{name: name, source: source} ->
        basename =
          name
          |> to_string()
          |> String.split(".")
          |> List.last()
          |> Macro.underscore()

        path = Path.join(elixir_dir, basename <> ".ex")
        File.write!(path, source)
      end)

      write_manifest(out_dir, modules, opts)
      :ok
    end
  end

  @spec generated_module_name(String.t(), String.t()) :: String.t()
  def generated_module_name(entry_module, ir_sha256) do
    safe = entry_module |> String.replace(".", "_")
    suffix = String.slice(ir_sha256, 0, 8)
    "Elmx.Generated.#{safe}_#{suffix}"
  end

  defp modules_for_emit(%ElmEx.IR{} = ir, opts) do
    entry_module = Map.get(opts, :entry_module, "Main")

    case Map.get(opts, :mode, :library) do
      :ide_runtime ->
        emit_opts =
          opts
          |> Map.take([:user_module_names, :mode])
          |> Enum.into([])

        ReachableModules.modules_for_emit(ir, entry_module, emit_opts)

      _ ->
        ir.modules
    end
  end

  defp cross_module_arities_from_modules(modules) when is_list(modules) do
    modules
    |> Enum.map(fn mod ->
      arities = function_arities_from_declarations(mod.declarations)

      mod.declarations
      |> Enum.filter(&(&1.kind == :function and is_binary(&1.name)))
      |> Enum.map(fn decl ->
        name = decl.name

        {{mod.name, name},
         %{
           explicit: Map.get(arities.explicit, name, 0),
           callable: Map.get(arities.callable, name, 0)
         }}
      end)
    end)
    |> List.flatten()
    |> Map.new()
  end

  defp port_signatures_from_modules(modules) when is_list(modules) do
    modules
    |> Enum.flat_map(fn mod ->
      ports = Map.get(mod, :ports, [])

      for name <- ports, is_binary(name) do
        {{mod.name, name}, true}
      end
    end)
    |> Map.new()
  end

  defp record_field_types_from_declarations(declarations) when is_list(declarations) do
    Enum.reduce(declarations, %{}, fn
      %{kind: :type_alias, name: name, expr: %{op: :record_alias, field_types: types}}, acc
      when is_map(types) ->
        Map.put(acc, name, types)

      _, acc ->
        acc
    end)
  end

  defp zero_arity_fns_from_declarations(declarations) when is_list(declarations) do
    declarations
    |> Enum.filter(fn
      %{kind: :function, name: name, args: args} when is_binary(name) ->
        args in [nil, []]

      _ ->
        false
    end)
    |> MapSet.new(& &1.name)
  end

  defp function_arities_from_declarations(declarations) when is_list(declarations) do
    explicit =
      declarations
      |> Enum.filter(fn decl ->
        decl.kind == :function and is_binary(decl.name) and is_map(decl.expr)
      end)
      |> Map.new(fn decl -> {decl.name, length(decl.args || [])} end)

    callable =
      declarations
      |> Enum.filter(fn decl ->
        decl.kind == :function and is_binary(decl.name) and is_map(decl.expr)
      end)
      |> Map.new(fn decl ->
        {decl.name, effective_function_arity(decl, explicit)}
      end)

  %{callable: callable, explicit: explicit}
  end

  defp effective_function_arity(%{args: args} = decl, _explicit) when is_list(args) and args != [] do
    length(args) + infer_nested_lambda_arity(decl.expr)
  end

  defp effective_function_arity(%{expr: expr}, arities) do
    infer_callable_arity(expr, arities)
  end

  defp infer_nested_lambda_arity(%{op: :lambda, args: lambda_args, body: body}) when is_list(lambda_args) do
    length(lambda_args) + infer_nested_lambda_arity(body)
  end

  defp infer_nested_lambda_arity(_), do: 0

  defp infer_callable_arity(%{op: :lambda, args: args, body: body}, arities) when is_list(args) do
    length(args) + infer_callable_arity(body, arities)
  end

  defp infer_callable_arity(%{op: :lambda, args: args}, _arities) when is_list(args), do: length(args)

  defp infer_callable_arity(%{op: :call, name: name, args: args}, _arities)
       when name in ["__add__", "__sub__", "__mul__", "__fdiv__", "__idiv__", "__append__"] and is_list(args) do
    max(2 - length(args), 0)
  end

  defp infer_callable_arity(%{op: :call, name: name, args: args}, _arities)
       when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] and is_list(args) do
    max(2 - length(args), 0)
  end

  defp infer_callable_arity(%{op: :call, name: name, args: args}, arities)
       when is_binary(name) and is_list(args) do
    target_arity = Map.get(arities, name, 0)
    max(target_arity - length(args), 0)
  end

  defp infer_callable_arity(%{op: op, target: target, args: args}, arities)
       when op in [:qualified_call, :call] and is_binary(target) and is_list(args) do
    case Elmx.Runtime.Stdlib.qualified_full_arity(target) do
      {:ok, full_arity} ->
        max(full_arity - length(args), 0)

      :error ->
        case Elmx.Backend.QualifiedPartials.rewrite(target, args) do
          {:ok, %{op: :lambda, args: lambda_args}} when is_list(lambda_args) ->
            length(lambda_args)

          _ ->
            infer_user_callable_arity(target, args, arities)
        end
    end
  end

  defp infer_callable_arity(_expr, _arities), do: 0

  defp infer_user_callable_arity(target, args, arities) do
    case Elmx.Backend.CrossModuleCall.split_target(target) do
      {module, name} ->
        target_arity = Map.get(arities, name, Map.get(arities, "#{module}.#{name}", 0))
        max(target_arity - length(args), 0)

      nil ->
        name = target |> String.split(".") |> List.last()
        target_arity = Map.get(arities, name, Map.get(arities, target, 0))
        max(target_arity - length(args), 0)
    end
  end

  defp maybe_saturate_value_function_expr(expr, _decl_args, arity, callable_arities, explicit_arities)
       when is_map(expr) and is_integer(arity) and arity > 0 do
    case expr do
      %{op: op, args: args} = call when op in [:qualified_call, :call] and is_list(args) ->
        name = call_target_name(call)
        explicit = Map.get(explicit_arities, name, 0)
        callable = Map.get(callable_arities, name, 0)
        given = length(args)

        if given == explicit and callable > explicit do
          {:apply_saturated, call, arity}
        else
          extra =
            Enum.map(1..arity, fn i ->
              %{op: :var, name: "__p#{i}"}
            end)

          Map.put(call, :args, args ++ extra)
        end

      _ ->
        expr
    end
  end

  defp maybe_saturate_value_function_expr(expr, _, _, _, _), do: expr

  defp call_target_name(%{op: :call, name: name}) when is_binary(name), do: name

  defp call_target_name(%{op: :qualified_call, target: target}) when is_binary(target),
    do: call_target_name(target)

  defp call_target_name(target) when is_binary(target) do
    case Elmx.Backend.CrossModuleCall.split_target(target) do
      {_module, name} -> name
      nil -> target |> String.split(".") |> List.last()
    end
  end

  defp compile_apply_saturated_body(%{op: _} = call, sat_arity, env) do
    env = Map.put(env, :emit_partial_value, true)
    {call_code, env, _} = Emit.compile_expr(call, env, 0)

    param_refs =
      Enum.map(1..sat_arity, fn i ->
        Elmx.Backend.ElixirCodegen.Emit.Helpers.binding_ref("__p#{i}", env)
      end)

    code = [
      "Elmx.Runtime.Core.Apply.apply#{sat_arity}(",
      call_code,
      ", ",
      Enum.intersperse(param_refs, ", "),
      ")"
    ]

    {code, env}
  end

  defp unwrap_nested_lambdas(%{op: :lambda, args: args, body: body}, acc) when is_list(args) do
    unwrap_nested_lambdas(body, acc ++ args)
  end

  defp unwrap_nested_lambdas(expr, acc), do: {expr, acc}

  defp emit_function(
         module_name,
         decl,
         record_field_types,
         zero_arity_fns,
         function_arities,
         explicit_function_arities,
         constructor_lookup,
         cross_module_arities,
         emit_module_names,
         port_signatures,
         emit_mode,
         ir_sha256
       ) do
    env =
      module_name
      |> Emit.function_env(decl.args || [])
      |> Map.put(:record_field_types, record_field_types)
      |> Map.put(:zero_arity_fns, zero_arity_fns)
      |> Map.put(:function_arities, function_arities)
      |> Map.put(:explicit_function_arities, explicit_function_arities)
      |> Map.put(:constructor_lookup, constructor_lookup)
      |> Map.put(:cross_module_arities, cross_module_arities)
      |> Map.put(:port_signatures, port_signatures)
      |> Map.put(:emit_module_names, emit_module_names)
      |> Map.put(:emit_mode, emit_mode)

    {expr0, synthetic_params} =
      if (decl.args || []) == [] do
        unwrap_nested_lambdas(decl.expr, [])
      else
        {decl.expr, []}
      end

    saturated_arity =
      if (decl.args || []) == [] and synthetic_params == [] do
        effective_function_arity(decl, function_arities)
      else
        0
      end

    param_source =
      cond do
        is_list(decl.args) and decl.args != [] ->
          decl.args

        synthetic_params != [] ->
          synthetic_params

        saturated_arity > 0 ->
          Enum.map(1..saturated_arity, &"__p#{&1}")

        true ->
          []
      end

    arity =
      if param_source != [] do
        length(param_source)
      else
        0
      end

    env =
      Enum.reduce(param_source, env, fn arg, acc ->
        Map.put(acc, String.to_atom(Emit.param_name(arg)), true)
      end)

    expr =
      cond do
        synthetic_params != [] ->
          expr0

        (decl.args || []) == [] ->
          maybe_saturate_value_function_expr(
            decl.expr,
            decl.args || [],
            arity,
            function_arities,
            explicit_function_arities
          )

        true ->
          decl.expr
      end

    {body, env} =
      case expr do
        {:apply_saturated, call, sat_arity} ->
          compile_apply_saturated_body(call, sat_arity, env)

        other ->
          {compiled, env, _} = Emit.compile_expr(other, env, 0)
          {compiled, env}
      end
    uses_bitwise = Map.get(env, :uses_bitwise, false)
    fn_name = function_symbol(module_name, decl.name)

    used_params =
      case expr do
        {:apply_saturated, call, sat_arity} when is_map(call) and is_integer(sat_arity) and
                                                    sat_arity > 0 ->
          Enum.reduce(1..sat_arity, Emit.referenced_binding_names(call), fn i, acc ->
            MapSet.put(acc, "__p#{i}")
          end)

        other ->
          Emit.referenced_binding_names(other)
      end

    params =
      param_list(param_source, if(param_source == [], do: arity, else: nil), used_params)

    body_str = IO.iodata_to_binary(body)

    source =
      if module_value_binding?(decl, synthetic_params, saturated_arity) do
        cache_key = {:elmx, ir_sha256, module_name, decl.name}

        """
        def #{fn_name}() do
          try do
            :persistent_term.get(#{inspect(cache_key)})
          rescue
            ArgumentError ->
              value = #{body_str}
              :persistent_term.put(#{inspect(cache_key)}, value)
              value
          end
        end
        """
      else
        """
        def #{fn_name}(#{params}) do
          #{body_str}
        end
        """
      end

    {source, uses_bitwise}
  end

  defp module_value_binding?(decl, synthetic_params, saturated_arity) do
    (decl.args || []) == [] and synthetic_params == [] and saturated_arity == 0 and
      not function_like_value_expr?(decl.expr)
  end

  defp function_like_value_expr?(%{op: :lambda}), do: true
  defp function_like_value_expr?(%{op: :qualified_call, args: []}), do: true
  defp function_like_value_expr?(%{op: :var}), do: true
  defp function_like_value_expr?(_), do: false

  defp param_list(args, arity, used_params) when is_list(args) do
    names =
      cond do
        args != [] ->
          Enum.map(args, &Emit.param_name/1)

        is_integer(arity) and arity > 0 ->
          Enum.map(1..arity, &"__p#{&1}")

        true ->
          []
      end

    Enum.map_join(Enum.with_index(names), ", ", fn {name, index} ->
      emit_name = name |> Elmx.Backend.ElixirCodegen.Emit.Helpers.param_var_name(%{})

      if MapSet.member?(used_params, name) or MapSet.member?(used_params, emit_name) do
        emit_name
      else
        "_unused#{index}"
      end
    end)
  end

  defp function_symbol(module, name) do
    "elmx_fn_#{module |> String.replace(".", "_")}_#{name}"
  end

  defp runtime_import_header(true), do: "import Bitwise\n"
  defp runtime_import_header(_), do: ""

  defp write_manifest(out_dir, modules, opts) do
    entry_module = Map.get(opts, :entry_module, "Main")
    ir_sha256 = Map.get(opts, :ir_sha256, "")

    manifest = %{
      "compiler" => "elmx",
      "contract" => "elmx.runtime_executor.v1",
      "entry_module" => entry_module,
      "generated_module" => List.first(modules)[:name],
      "ir_sha256" => ir_sha256,
      "elmx_version" => "0.1.0"
    }

    path = Path.join([out_dir, "elixir", "elmx_manifest.json"])
    File.write!(path, Jason.encode!(manifest, pretty: true))
  end
end
