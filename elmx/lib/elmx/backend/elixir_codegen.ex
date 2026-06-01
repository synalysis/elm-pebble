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
              function_arities,
              constructor_lookup,
              cross_module_arities,
              emit_module_names,
              Map.get(opts, :mode, :library)
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
          |> Map.take([:user_module_names])
          |> Enum.into([])

        ReachableModules.modules_for_emit(ir, entry_module, emit_opts)

      _ ->
        ir.modules
    end
  end

  defp cross_module_arities_from_modules(modules) when is_list(modules) do
    modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function and is_binary(&1.name)))
      |> Enum.map(fn decl -> {{mod.name, decl.name}, length(decl.args || [])} end)
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
    declarations
    |> Enum.filter(fn decl ->
      decl.kind == :function and is_binary(decl.name) and is_map(decl.expr)
    end)
    |> Map.new(fn decl -> {decl.name, length(decl.args || [])} end)
  end

  defp emit_function(
         module_name,
         decl,
         record_field_types,
         zero_arity_fns,
         function_arities,
         constructor_lookup,
         cross_module_arities,
         emit_module_names,
         emit_mode
       ) do
    env =
      module_name
      |> Emit.function_env(decl.args || [])
      |> Map.put(:record_field_types, record_field_types)
      |> Map.put(:zero_arity_fns, zero_arity_fns)
      |> Map.put(:function_arities, function_arities)
      |> Map.put(:constructor_lookup, constructor_lookup)
      |> Map.put(:cross_module_arities, cross_module_arities)
      |> Map.put(:emit_module_names, emit_module_names)
      |> Map.put(:emit_mode, emit_mode)

    {body, env, _} = Emit.compile_expr(decl.expr, env, 0)
    uses_bitwise = Map.get(env, :uses_bitwise, false)
    fn_name = function_symbol(module_name, decl.name)
    params = param_list(decl.args || [], emit_mode)

    source = """
    def #{fn_name}(#{params}) do
      #{IO.iodata_to_binary(body)}
    end
    """

    {source, uses_bitwise}
  end

  defp param_list(args, _emit_mode) when is_list(args) do
    Enum.map_join(args, ", ", fn arg ->
      arg |> Emit.param_name() |> Elmx.Backend.ElixirCodegen.Emit.Helpers.param_var_name(%{})
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
