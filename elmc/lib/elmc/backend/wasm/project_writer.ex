defmodule Elmc.Backend.Wasm.ProjectWriter do
  @moduledoc """
  Emit `.wat` modules and a manifest when WASM is an active compile target.
  """

  alias Elmc.Backend.Bytecode.FusionRunner
  alias Elmc.Backend.CCodegen.{IRQueries, RcRequired, RecordFieldMacros}
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.Backend.Wasm.{Module, Targets, WebCoverage}
  alias Elmc.Backend.Wasm.Lower.FusionFunction
  alias Elmc.Backend.Wasm.ImportSignatures
  alias Elmc.Backend.Wasm.Types, as: WasmTypes
  alias ElmEx.IR

  @manifest_name "elmc_wasm.manifest.json"
  @debug_manifest_name "elmc_wasm.manifest.debug.json"
  @manifest_contract "elmc.wasm_manifest.v1"
  @wat_name "elmc_generated.wat"

  @spec maybe_write(IR.t(), String.t(), Elmc.Types.compile_options()) :: :ok
  def maybe_write(%IR{} = ir, out_dir, opts) when is_map(opts) do
    if Targets.emit_wasm?(opts) and Plan.plan_ir_mode(opts) in [:shadow, :primary] do
      write(ir, out_dir, opts)
    else
      :ok
    end
  end

  @spec write(IR.t(), String.t(), Elmc.Types.compile_options()) :: :ok
  def write(%IR{} = ir, out_dir, opts \\ %{}) do
    wasm_dir = Path.join(out_dir, "wasm")
    File.mkdir_p!(wasm_dir)

    Process.put(:elmc_codegen_opts, opts)
    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
    Process.put(:elmc_inline_record_literal_shapes, IRQueries.inline_record_literal_shape_map(ir))
    Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))

    shapes = IRQueries.record_alias_shape_map(ir)
    {_record_field_defines, record_field_macros} = RecordFieldMacros.definitions(ir, used_fields: nil)
    Process.put(:elmc_record_field_macros, record_field_macros)
    Process.put(:elmc_wasm_record_field_macro_indices, macro_index_map(record_field_macros, shapes))

    try do
      decl_map =
        ir
        |> IRQueries.function_decl_map()
        |> inject_web_wire3_helpers(opts)
      coverage_opts = coverage_opts(opts)
      emit_map = emit_decl_map(decl_map, coverage_opts)
      pruned_count = map_size(decl_map) - map_size(emit_map)

      {plans, functions, fusion_functions, skipped, imports, _stubs_acc} =
        emit_map
        |> Enum.sort()
        |> Enum.reduce({[], [], [], [], MapSet.new(), []}, fn {{module, name}, decl},
                                                         {plans_acc, functions_acc, fusion_acc, skipped_acc,
                                                          imports_acc, stubs_acc} ->
          case lower_plan(decl, module, name, decl_map) do
            {:ok, plan} ->
              entry = %{
                "module" => module,
                "name" => name,
                "export" => WasmTypes.fn_ident(module, name) |> strip_dollar(),
                "params" => Map.get(decl, :args, []),
                "rc_required" => plan.rc_required
              }

              {[plan | plans_acc], [entry | functions_acc], fusion_acc, skipped_acc, imports_acc, stubs_acc}

            {:fusion, plan} ->
              fusion_entry = fusion_manifest_entry(module, name, decl, plan)

              {plans_acc, functions_acc, [fusion_entry | fusion_acc],
               [{module, name, :fusion_only} | skipped_acc], imports_acc, stubs_acc}

            {:skip, reason} ->
              {plans_acc, functions_acc, fusion_acc, [{module, name, reason} | skipped_acc], imports_acc,
               stubs_acc}
          end
        end)
        |> then(fn {plans, functions, fusion, skipped, imports, stubs} ->
          {Enum.reverse(plans), Enum.reverse(functions), fusion, skipped, imports, stubs}
        end)

      entry_module = Map.get(opts, :entry_module, "Main")
      entry_export = WasmTypes.fn_ident(entry_module, "main") |> strip_dollar()
      minify? = wasm_minify?(opts)

      {immortal_strings, immortal_index} = prepare_immortal_strings(plans, minify?)

      if is_map(immortal_index) do
        Process.put(:elmc_wasm_immortal_index, immortal_index)
        Process.put(:elmc_wasm_immortal_strings, immortal_strings)
      end

      module_map =
        try do
          Module.build(plans,
            export_all: not minify?,
            entry_exports: [entry_export]
          )
        after
          # Snapshot final dense table (may grow while lowering test/debug literals).
          if minify? do
            immortal_strings = Process.get(:elmc_wasm_immortal_strings, immortal_strings)
            Process.put(:elmc_wasm_immortal_strings_final, immortal_strings)
          end

          Process.delete(:elmc_wasm_immortal_index)
          Process.delete(:elmc_wasm_immortal_strings)
        end

      immortal_strings =
        if minify? do
          Process.get(:elmc_wasm_immortal_strings_final, immortal_strings)
        else
          immortal_strings
        end

      Process.delete(:elmc_wasm_immortal_strings_final)

      stub_functions = Map.get(module_map, :stub_functions, [])
      wat = Module.render_wat(module_map)
      :ok = File.write!(Path.join(wasm_dir, @wat_name), wat)

      all_imports =
        imports
        |> MapSet.union(module_map.imports)
        |> MapSet.to_list()
        |> Enum.sort()

      import_signatures =
        all_imports
        |> Enum.map(fn name ->
          arity = Map.get(module_map.import_arities, name, ImportSignatures.param_count(name))
          {name, %{"params" => arity, "results" => 1}}
        end)
        |> Map.new()

      stub_entries =
        Enum.map(stub_functions, fn entry ->
          %{
            "module" => entry.module,
            "name" => entry.name,
            "export" => entry.export,
            "arity" => entry.arity,
            "kind" => Atom.to_string(entry.kind)
          }
        end)

      full_manifest =
        %{
          "contract" => @manifest_contract,
          "version" => 1,
          "plan_toolchain" => plan_toolchain_manifest(opts),
          "wat_file" => @wat_name,
          "entry_module" => entry_module,
          "entry_export" => entry_export,
          "functions" => functions,
          "closures" => Map.get(module_map, :closures, []),
          "fusion_functions" => fusion_functions,
          "stub_functions" => stub_entries,
          "pruned_count" => pruned_count,
          "skipped" =>
            Enum.map(skipped, fn {m, n, r} ->
              %{"module" => m, "name" => n, "reason" => reason_string(r)}
            end),
          "imports" => all_imports,
          "import_signatures" => import_signatures,
          "export_signature" => %{"results" => 2},
          "immortal_strings" => immortal_strings,
          "constructor_tags" => IRQueries.constructor_tag_map(ir),
          "plan_coverage" => plan_coverage_manifest(decl_map, coverage_opts, opts),
          "minified" => minify?
        }
        |> maybe_put_wasm_binary(wasm_dir, opts)

      runtime_manifest =
        if minify? do
          slim_runtime_manifest(full_manifest)
        else
          full_manifest
        end

      :ok =
        wasm_dir
        |> Path.join(@manifest_name)
        |> then(&File.write!(&1, Jason.encode!(runtime_manifest)))

      if minify? do
        :ok =
          wasm_dir
          |> Path.join(@debug_manifest_name)
          |> then(&File.write!(&1, Jason.encode!(full_manifest)))
      end

      :ok
    after
      Process.delete(:elmc_codegen_opts)
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_inline_record_literal_shapes)
      Process.delete(:elmc_record_field_types)
      Process.delete(:elmc_record_field_macros)
      Process.delete(:elmc_wasm_record_field_macro_indices)
    end
  end

  @spec manifest_path(String.t()) :: String.t()
  def manifest_path(out_dir), do: Path.join([out_dir, "wasm", @manifest_name])

  @spec debug_manifest_path(String.t()) :: String.t()
  def debug_manifest_path(out_dir), do: Path.join([out_dir, "wasm", @debug_manifest_name])

  @spec wat_path(String.t()) :: String.t()
  def wat_path(out_dir), do: Path.join([out_dir, "wasm", @wat_name])

  @doc """
  Stub entries for diagnostics. Minified web builds keep stubs only in the
  debug sidecar; non-minified manifests still embed them in the runtime file.
  """
  @spec stub_functions(String.t()) :: [map()]
  def stub_functions(out_dir) when is_binary(out_dir) do
    runtime = out_dir |> manifest_path() |> File.read!() |> Jason.decode!()

    stubs =
      if runtime["minified"] == true do
        debug_path = debug_manifest_path(out_dir)

        if File.exists?(debug_path) do
          debug_path |> File.read!() |> Jason.decode!() |> Map.get("stub_functions", [])
        else
          []
        end
      else
        Map.get(runtime, "stub_functions", [])
      end

    stubs || []
  end

  @doc false
  def wasm_minify?(opts) when is_map(opts) do
    cond do
      Map.has_key?(opts, :wasm_minify) -> Map.get(opts, :wasm_minify) == true
      Map.get(opts, :wasm_export_all) == true -> false
      Map.get(opts, :web) == true -> true
      true -> false
    end
  end

  defp slim_runtime_manifest(full) do
    closures = Map.get(full, "closures", [])

    # stub_functions stay in the debug sidecar only — host runtime never reads them.
    # Imports are discovered via WebAssembly.Module.imports(module).
    # Short `cN` exports — host resolves `c#{fnIndex}` from closure_count.
    %{
      "contract" => full["contract"],
      "version" => full["version"],
      "entry_module" => full["entry_module"],
      "entry_export" => full["entry_export"],
      "closure_count" => length(closures),
      "immortal_strings" => full["immortal_strings"],
      "constructor_tags" => Map.get(full, "constructor_tags", %{}),
      "minified" => true
    }
  end

  defp lower_plan(decl, module, name, decl_map) do
    rc_required? = RcRequired.rc_required?(module, name)

    case lower_function_plan(decl, module, decl_map, rc_required?) do
      {:ok, plan} ->
        {:ok, plan}

      {:fusion, plan} ->
        {:fusion, plan}

      {:skip, reason} ->
        {:skip, reason}

      :unsupported ->
        reasons = Process.get(:elmc_plan_unsupported_reasons, %{})

        reason =
          Map.get(reasons, {module, name}) ||
            Enum.find_value(reasons, fn
              {{^module, fn_name}, meta} when is_binary(fn_name) and is_map(meta) ->
                if String.starts_with?(fn_name, name <> "_"), do: meta, else: nil

              _ ->
                nil
            end)

        if is_map(reason), do: {:skip, {:unsupported, reason}}, else: {:skip, :unsupported}

      {:error, reason} ->
        {:skip, reason}
    end
  end

  defp lower_function_plan(decl, module, decl_map, rc_required?) do
    lower_opts = [rc_required: rc_required?]

    case Plan.lower_function(decl, module, decl_map, lower_opts) do
      {:ok, plan} ->
        classify_lowered_plan(plan, decl, module, decl_map, rc_required?)

      other ->
        other
    end
  end

  defp classify_lowered_plan(plan, decl, module, decl_map, rc_required?) do
    cond do
      plan.blocks == [] and FusionRunner.runnable?(plan) and FusionFunction.emittable?(plan) ->
        {:ok, plan}

      plan.blocks == [] and FusionRunner.runnable?(plan) ->
        retry_without_c_fusion(decl, module, decl_map, rc_required?, plan)

      plan.blocks == [] ->
        {:skip, :empty_plan}

      true ->
        {:ok, plan}
    end
  end

  defp retry_without_c_fusion(decl, module, decl_map, rc_required?, fusion_plan) do
    case Plan.lower_function(decl, module, decl_map, rc_required: rc_required?, skip_c_fusion: true) do
      {:ok, %{} = plan} when plan.blocks != [] ->
        {:ok, plan}

      _ ->
        {:fusion, fusion_plan}
    end
  end

  # Minified builds use dense 0..n-1 ids (array in the manifesto). Non-minified
  # keeps phash2 object keys for historical probe compatibility.
  defp prepare_immortal_strings(plans, minify?) do
    values =
      plans
      |> flatten_plans_with_lambdas()
      |> Enum.flat_map(fn plan ->
        plan.blocks
        |> Enum.flat_map(& &1.instrs)
      end)
      |> Enum.filter(&match?(%{op: :const_immortal_string}, &1))
      |> Enum.map(fn %{args: %{value: value}} -> value end)
      |> Enum.uniq()

    if minify? do
      index = Map.new(Enum.with_index(values), fn {value, idx} -> {value, idx} end)
      {values, index}
    else
      table =
        Map.new(values, fn value ->
          {Integer.to_string(:erlang.phash2(value, 1_000_000)), value}
        end)

      {table, nil}
    end
  end

  defp flatten_plans_with_lambdas(plans) when is_list(plans) do
    Enum.flat_map(plans, fn plan ->
      [plan | flatten_plans_with_lambdas(Map.get(plan, :lambdas, []) || [])]
    end)
  end

  defp reason_string(:empty_plan), do: "empty_plan"
  defp reason_string(:unsupported), do: "unsupported"
  defp reason_string(:fusion_only), do: "fusion_only"
  defp reason_string({:verify, reason, _}), do: "verify:#{reason}"
  defp reason_string(other), do: inspect(other)

  defp fusion_manifest_entry(module, name, decl, plan) do
    %{
      "module" => module,
      "name" => name,
      "params" => Map.get(decl, :args, []),
      "fusion_kind" => plan.fusion_kind |> Atom.to_string(),
      "fusion_data" => wire_fusion_data(plan.fusion_data)
    }
  end

  defp wire_fusion_data(data) when is_map(data) do
    data
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), wire_fusion_value(v)}
      {k, v} -> {k, wire_fusion_value(v)}
    end)
    |> Map.new()
  end

  defp wire_fusion_data(other), do: other

  defp wire_fusion_value({mod, name}) when is_binary(mod) and is_binary(name),
    do: %{"module" => mod, "name" => name}

  defp wire_fusion_value(list) when is_list(list), do: Enum.map(list, &wire_fusion_value/1)
  defp wire_fusion_value(map) when is_map(map), do: wire_fusion_data(map)
  defp wire_fusion_value(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp wire_fusion_value(other), do: other

  defp coverage_opts(opts) do
    [
      entry_module: Map.get(opts, :entry_module, "Main"),
      strip_dead_code: Map.get(opts, :strip_dead_code, true),
      plan_ir_mode: Map.get(opts, :plan_ir_mode, Plan.plan_ir_mode(opts)),
      web: Map.get(opts, :web, false) == true
    ]
  end

  defp emit_decl_map(decl_map, coverage_opts) do
    strip? = Keyword.get(coverage_opts, :strip_dead_code, true)
    web? = Keyword.get(coverage_opts, :web, false) == true

    base =
      cond do
        strip? and web? ->
          WebCoverage.filter_reachable(decl_map, coverage_opts)

        strip? ->
          PrimaryCoverage.filter_reachable(decl_map, coverage_opts)

        true ->
          decl_map
      end

    if strip? and web? do
      Map.merge(web_wire3_decls(decl_map), base)
    else
      base
    end
  end

  defp inject_web_wire3_helpers(decl_map, opts) when is_map(decl_map) do
    if Map.get(opts, :web, false) != true do
      decl_map
    else
      if web_wire3_route_helpers?(decl_map) do
        Enum.reduce(web_wire3_synthetic_decls(decl_map), decl_map, fn {module, name, decl}, acc ->
          Map.put(acc, {module, name}, decl)
        end)
      else
        decl_map
      end
    end
  end

  defp web_wire3_route_helpers?(decl_map) do
    Enum.any?(decl_map, fn {{_module, name}, _} ->
      String.starts_with?(name, "w3_decode_") or String.starts_with?(name, "w3_encode_")
    end)
  end

  defp web_wire3_synthetic_decls(decl_map) do
    succeed =
      %{
        op: :qualified_call,
        target: "Bytes.Decode.succeed",
        args: [%{op: :record_literal, fields: []}]
      }

    defaults = [
      {"UrlPath", "w3_decode_UrlPath",
       %{kind: :function, name: "w3_decode_UrlPath", args: [], type: nil, expr: succeed}},
      {"Pages.Internal.NotFoundReason", "w3_decode_NotFoundReason",
       %{
         kind: :function,
         name: "w3_decode_NotFoundReason",
         args: [],
         type: nil,
         expr: succeed
       }}
    ]

    Enum.filter(defaults, fn {module, name, _} ->
      not Map.has_key?(decl_map, {module, name})
    end)
  end

  @doc false
  @spec web_wire3_synthetic_decls_for_test(map()) :: [{String.t(), String.t(), map()}]
  def web_wire3_synthetic_decls_for_test(decl_map) when is_map(decl_map) do
    web_wire3_synthetic_decls(decl_map)
  end

  defp web_wire3_decls(decl_map) do
    wire3 =
      decl_map
      |> Enum.filter(fn {{_module, name}, _} ->
        String.starts_with?(name, "w3_decode_") or String.starts_with?(name, "w3_encode_")
      end)
      |> Map.new()

    support =
      decl_map
      |> Enum.filter(fn key -> key in wire3_support_keys() end)
      |> Map.new()

    Map.merge(support, wire3)
  end

  defp wire3_support_keys do
    [
      {"Bytes.Decode", "succeed"},
      {"Bytes.Decode", "map"},
      {"Bytes.Decode", "map2"},
      {"Bytes.Decode", "map3"},
      {"Lamdera.Wire3", "encodeSequenceWithoutLength"},
      {"Lamdera.Wire3", "decodeString"},
      {"Lamdera.Wire3", "decodeMaybe"}
    ]
  end

  defp plan_coverage_manifest(decl_map, coverage_opts, compile_opts) do
    coverage_report_opts = coverage_report_opts(coverage_opts, compile_opts)

  all_report =
      if Plan.plan_ir_mode(coverage_report_opts) == :primary and
           opt_bool(coverage_report_opts, :strip_dead_code, true) do
        PrimaryCoverage.reachable_report(decl_map, coverage_report_opts)
      else
        PrimaryCoverage.report(decl_map, coverage_report_opts)
      end

    %{
      "all" => PrimaryCoverage.wire_summary(all_report),
      "main" => PrimaryCoverage.wire_summary(PrimaryCoverage.main_functions_report(decl_map, coverage_report_opts)),
      "reachable" =>
        PrimaryCoverage.wire_summary(
          PrimaryCoverage.reachable_report(decl_map, coverage_report_opts)
        )
    }
  end

  defp coverage_report_opts(coverage_opts, compile_opts) do
    base =
      coverage_opts
      |> Enum.into(%{})
      |> Map.merge(Map.take(compile_opts, [:plan_ir_mode, :plan_ir_strict]))

    Map.put_new(base, :plan_ir_mode, Plan.plan_ir_mode(base))
  end

  defp plan_toolchain_manifest(opts) do
    %{
      "mode" => Plan.plan_ir_mode(opts) |> Atom.to_string(),
      "strict" => Plan.strict_primary?(opts),
      "targets" => Targets.normalize(opts) |> Enum.map(&Atom.to_string/1)
    }
  end

  defp opt_bool(opts, key, default) when is_map(opts),
    do: Map.get(opts, key, default) == true

  defp maybe_put_wasm_binary(manifest, wasm_dir, opts) do
    if Map.get(opts, :wasm_binary, false) == true do
      wat_path = Path.join(wasm_dir, @wat_name)
      wasm_path = Path.join(wasm_dir, "app.wasm")

      case run_wat2wasm(wat_path, wasm_path) do
        :ok -> Map.put(manifest, "wasm_file", "app.wasm")
        {:error, _} -> manifest
      end
    else
      manifest
    end
  end

  defp run_wat2wasm(wat_path, wasm_path) do
    case System.find_executable("wat2wasm") do
      nil ->
        {:error, "wat2wasm not found"}

      wat2wasm ->
        {output, code} = System.cmd(wat2wasm, [wat_path, "-o", wasm_path], stderr_to_stdout: true)
        if code == 0, do: :ok, else: {:error, output}
    end
  end

  defp strip_dollar("$" <> rest), do: rest
  defp strip_dollar(other), do: other

  defp macro_index_map(record_field_macros, shapes) when is_map(record_field_macros) and is_map(shapes) do
    Map.new(record_field_macros, fn {{mod, type, field}, macro} ->
      idx =
        case Map.get(shapes, {mod, type}) do
          fields when is_list(fields) -> Enum.find_index(fields, &(&1 == field))
          _ -> nil
        end

      {macro, idx || 0}
    end)
  end
end
