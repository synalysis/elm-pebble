defmodule Elmc.Backend.Wasm.Module do
  @moduledoc false


  alias Elmc.Backend.Wasm.ClosureRegistry
  alias Elmc.Backend.Wasm.Lower.Function
  alias Elmc.Backend.Wasm.{FunctionOrder, HostKernels, ImportCollect, ImportSignatures, StubFunctions}
  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @type t :: %{
          functions: [Function.function_unit()],
          closures: [map()],
          imports: MapSet.t(String.t()),
          import_arities: %{String.t() => non_neg_integer()},
          wat: binary()
        }

  @type build_opts :: [
          export_all: boolean(),
          entry_exports: [String.t()]
        ]

  @spec build([Elmc.Backend.Plan.Types.FunctionPlan.t()]) :: t()
  @spec build([Elmc.Backend.Plan.Types.FunctionPlan.t()], build_opts()) :: t()
  def build(plans, opts \\ []) when is_list(plans) do
    export_all? = Keyword.get(opts, :export_all, true)
    entry_exports = opts |> Keyword.get(:entry_exports, []) |> MapSet.new()

    plans = FunctionOrder.sort(plans)
    closure_registry = ClosureRegistry.build(plans)

    native_scalar_returns =
      Map.new(plans, fn plan -> {{plan.module, plan.name}, Map.get(plan, :native_scalar_return)} end)

    Process.put(:elmc_wasm_native_scalar_returns, native_scalar_returns)
    Process.put(:elmc_wasm_closure_registry, closure_registry)

    plans_for_imports =
      Enum.flat_map(plans, fn plan -> [plan | plan.lambdas || []] end)

    {_imports, import_arities} =
      plans_for_imports
      |> Enum.map(&ImportCollect.collect/1)
      |> ImportCollect.merge()
      |> then(fn {imports, arities} -> {add_core_imports(imports), merge_core_import_arities(arities)} end)

    Process.put(:elmc_wasm_import_arities, import_arities)
    Process.put(:elmc_wasm_forward_ref_ids, %{})

    closure_functions =
      Enum.map(closure_registry.entries, fn entry ->
        Function.lower_closure(entry.parent_plan, entry.lambda, entry.lambda_index)
      end)

    functions =
      (Enum.map(plans, &Function.lower/1) ++ closure_functions)
      |> Enum.map(&HostKernels.maybe_override/1)

    {functions, closures} =
      if export_all? do
        {functions, detailed_closures(closure_registry)}
      else
        short_export_closures(functions, closure_registry)
      end

    stub_entries = StubFunctions.missing_callees(plans)

    emitted_calls = Process.get(:elmc_wasm_emitted_calls, %{})
    Process.delete(:elmc_wasm_emitted_calls)
    Process.delete(:elmc_wasm_emitted_calls)
    Process.delete(:elmc_wasm_forward_ref_ids)

    emitted_exports =
      functions
      |> Enum.map(& &1.export_name)
      |> MapSet.new()

    extra_stubs =
      emitted_calls
      |> Enum.reject(fn {{mod, name}, _arity} ->
        MapSet.member?(emitted_exports, WasmTypes.fn_ident(mod, name))
      end)
      |> Enum.map(fn {{mod, name}, arity} ->
        %{
          module: mod,
          name: name,
          export: WasmTypes.fn_ident(mod, name) |> strip_export_dollar(),
          arity: arity,
          kind: StubFunctions.stub_kind(mod)
        }
      end)

    all_stub_entries =
      (stub_entries ++ extra_stubs)
      |> Enum.uniq_by(fn entry -> {entry.module, entry.name} end)

    stub_functions = Enum.map(all_stub_entries, &StubFunctions.lower_stub/1)
    functions = functions ++ stub_functions

    imports =
      functions
      |> Enum.reduce(MapSet.new(), fn fun, acc -> MapSet.union(acc, fun.imports) end)
      |> add_core_imports()

    import_arities =
      functions
      |> Enum.reduce(import_arities, fn fun, acc ->
        Enum.reduce(fun.import_arities, acc, fn {name, arity}, merged ->
          Map.update(merged, name, arity, &max(&1, arity))
        end)
      end)
      |> merge_core_import_arities()

    Process.put(:elmc_wasm_import_arities, import_arities)

    wat = render_module(functions, imports, import_arities, export_all?, entry_exports)

    %{
      functions: functions,
      closures: closures,
      imports: imports,
      import_arities: import_arities,
      wat: wat,
      stub_functions: all_stub_entries
    }
    |> tap(fn _ ->
      Process.delete(:elmc_wasm_closure_registry)
    end)
  end

  @spec render_wat(t()) :: binary()
  def render_wat(%{wat: wat}), do: wat

  defp add_core_imports(imports) do
    imports
    |> MapSet.put("runtime.retain")
    |> MapSet.put("runtime.release")
    |> MapSet.put("runtime.release_unless_reachable")
    |> MapSet.put("runtime.release_unless_reachable_from_roots")
    |> MapSet.put("runtime.release_array_lifo")
    |> MapSet.put("runtime.value_cache_get")
    |> MapSet.put("runtime.value_cache_put")
    |> MapSet.put("runtime.as_int")
    |> MapSet.put("runtime.as_bool")
    |> MapSet.put("runtime.union_tag_as_int")
  end

  defp merge_core_import_arities(arities) do
    arities
    |> Map.put_new("runtime.retain", ImportSignatures.param_count("runtime.retain"))
    |> Map.put_new("runtime.release", ImportSignatures.param_count("runtime.release"))
    |> Map.put_new("runtime.release_unless_reachable", 2)
    |> Map.put_new("runtime.release_unless_reachable_from_roots", 3)
    |> Map.put_new("runtime.release_array_lifo", ImportSignatures.param_count("runtime.release_array_lifo"))
    |> Map.put_new("runtime.value_cache_get", 2)
    |> Map.put_new("runtime.value_cache_put", 2)
    |> Map.put_new("runtime.as_int", ImportSignatures.param_count("runtime.as_int"))
    |> Map.put_new("runtime.as_bool", ImportSignatures.param_count("runtime.as_bool"))
    |> Map.put_new("runtime.union_tag_as_int", ImportSignatures.param_count("runtime.union_tag_as_int"))
    |> then(fn merged ->
      Enum.reduce(merged, %{}, fn {name, collected}, acc ->
        Map.put(acc, name, ImportSignatures.param_count(name, collected))
      end)
    end)
  end

  defp render_module(functions, imports, import_arities, export_all?, entry_exports) do
    import_lines =
      imports
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(&import_line(&1, import_arities))

    func_lines =
      Enum.map(functions, fn fun ->
        render_function(fun, export_function?(fun, export_all?, entry_exports))
      end)

    """
    (module
    #{indent_lines(import_lines)}
      (memory (export "memory") 1)
    #{indent_lines(func_lines)}
    )
    """
    |> String.trim()
  end

  defp import_line(name, import_arities) do
    arity = Map.get(import_arities, name, ImportSignatures.param_count(name))

    type_sexpr =
      if name in ["runtime.as_int", "runtime.as_bool", "runtime.union_tag_as_int"] do
        ImportSignatures.value_import_type_sexpr(name, arity)
      else
        ImportSignatures.import_type_sexpr(name, arity)
      end

    """
    (import "runtime" "#{import_suffix(name)}" #{type_sexpr})
    """
    |> String.trim()
  end

  defp import_suffix("runtime." <> rest), do: rest
  defp import_suffix(name), do: name

  defp export_function?(_fun, true, _entry_exports), do: true

  defp export_function?(%{export_name: export} = fun, false, entry_exports) do
    name = strip_dollar(export)
    wasm_export = Map.get(fun, :wasm_export)

    MapSet.member?(entry_exports, name) or String.contains?(name, "_closure_") or
      (is_binary(wasm_export) and String.match?(wasm_export, ~r/^c\d+$/))
  end

  defp render_function(%{export_name: export, params: params, body: body} = fun, export?) do
    param_decls =
      Enum.with_index(params, fn _name, idx ->
        "(param $param#{idx} i32)"
      end)

    result = ImportSignatures.function_result_sexpr()
    export_label = Map.get(fun, :wasm_export) || strip_dollar(export)
    export_clause = if export?, do: ~s| (export "#{export_label}")|, else: ""

    """
    (func #{export}#{export_clause} #{Enum.join(param_decls, " ")} #{result}
    #{indent_binary(body, 1)}
    )
    """
    |> String.trim()
  end

  defp detailed_closures(closure_registry) do
    Enum.map(closure_registry.entries, fn entry ->
      %{
        "index" => entry.index,
        "export" => entry.export,
        "parent_module" => entry.parent_module,
        "parent_name" => entry.parent_name,
        "lambda_index" => entry.lambda_index,
        "arity" => entry.arity,
        "capture_count" => entry.capture_count,
        "rc_required" => entry.rc_required
      }
    end)
  end

  # Keep internal $func ids descriptive (call sites), but export short `cN`
  # names so the wasm export section stays tiny.
  defp short_export_closures(functions, closure_registry) do
    by_long_export =
      Map.new(closure_registry.entries, fn entry ->
        {entry.export, entry.index}
      end)

    functions =
      Enum.map(functions, fn fun ->
        long = strip_dollar(fun.export_name)

        case Map.fetch(by_long_export, long) do
          {:ok, idx} -> Map.put(fun, :wasm_export, "c#{idx}")
          :error -> fun
        end
      end)

    closures =
      Enum.map(closure_registry.entries, fn entry ->
        %{
          "index" => entry.index,
          "export" => "c#{entry.index}",
          "debug_export" => entry.export,
          "parent_module" => entry.parent_module,
          "parent_name" => entry.parent_name,
          "lambda_index" => entry.lambda_index,
          "arity" => entry.arity,
          "capture_count" => entry.capture_count,
          "rc_required" => entry.rc_required
        }
      end)

    {functions, closures}
  end

  defp indent_lines(lines) do
    lines
    |> Enum.map_join("\n", fn line -> "  " <> line end)
  end

  defp indent_binary(body, level) when is_binary(body) do
    pad = String.duplicate("  ", level)

    body
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join("\n", &"#{pad}#{&1}")
  end

  defp indent_binary(body, level), do: indent_binary(IO.iodata_to_binary(body), level)

  defp strip_dollar("$" <> rest), do: rest
  defp strip_dollar(other), do: other

  defp strip_export_dollar(ident) when is_binary(ident), do: strip_dollar(ident)
end
