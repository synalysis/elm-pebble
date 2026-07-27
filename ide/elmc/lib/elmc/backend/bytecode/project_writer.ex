defmodule Elmc.Backend.Bytecode.ProjectWriter do
  @moduledoc """
  Emit `.elmcbc` sections and a manifest alongside C codegen when plan IR is active.
  """
  alias Elmc.Backend.Bytecode.Artifacts.Types, as: Types


  alias Elmc.Backend.Bytecode.{FusionRunner, Lower}
  alias Elmc.Backend.CCodegen.{IRQueries, RcRequired}
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.Backend.Wasm.Targets
  alias ElmEx.IR

  @manifest_name "elmc_bytecode.manifest.json"
  @manifest_contract "elmc.bytecode_manifest.v1"

  @spec maybe_write(IR.t(), String.t(), Elmc.Types.compile_options()) :: :ok
  def maybe_write(%IR{} = ir, out_dir, opts) when is_map(opts) do
    if emit_bytecode?(opts) do
      write(ir, out_dir, opts)
    else
      :ok
    end
  end

  @doc false
  @spec emit_bytecode?(Elmc.Types.compile_options()) :: boolean()
  def emit_bytecode?(opts) when is_map(opts) do
    Plan.plan_ir_mode(opts) in [:shadow, :primary] and not skip_pebble_bytecode?(opts)
  end

  # Pebble watch PBW builds already lower Plan IR to C; emitting bytecode sections
  # duplicates the full plan-lowering pass. Keep bytecode for WASM/shadow/audits.
  @spec skip_pebble_bytecode?(keyword()) :: boolean()

  defp skip_pebble_bytecode?(opts) do
    Plan.plan_ir_mode(opts) == :primary and Targets.emit_c?(opts) and not Targets.emit_wasm?(opts) and
      Map.get(opts, :pebble_int32, false) == true and Map.get(opts, :emit_bytecode, false) != true
  end

  @spec write(IR.t(), String.t(), Elmc.Types.compile_options()) :: :ok
  def write(%IR{} = ir, out_dir, opts \\ %{}) do
    bc_dir = Path.join(out_dir, "bytecode")
    File.mkdir_p!(bc_dir)

    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
    Process.put(:elmc_inline_record_literal_shapes, IRQueries.inline_record_literal_shape_map(ir))
    Process.put(:elmc_union_constructor_payload_specs, IRQueries.union_constructor_payload_specs_map(ir))
    Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))

    try do
      decl_map = IRQueries.function_decl_map(ir)
      coverage_opts = coverage_opts(opts)
      emit_map = emit_decl_map(decl_map, coverage_opts)
      pruned_count = map_size(decl_map) - map_size(emit_map)

      {functions, fusion_functions, skipped} =
        emit_map
        |> Enum.sort()
        |> Enum.map_reduce({[], []}, fn {{module, name}, decl}, {fusion_acc, skipped_acc} ->
          case lower_plan(decl, module, name, decl_map) do
            {:ok, _plan, section} ->
              filename = section_filename(module, name)

              try do
                path = Path.join(bc_dir, filename)
                :ok = File.write!(path, Lower.encode_section(section))

                entry = %{
                  "module" => module,
                  "name" => name,
                  "file" => filename,
                  "params" => Map.get(decl, :args, []),
                  "locals" => section.locals,
                  "fn_table" => Enum.map(section.fn_table, fn {m, n} -> [m, n] end)
                }

                {entry, {fusion_acc, skipped_acc}}
              rescue
                _ -> {nil, {fusion_acc, [{module, name, :encode_error} | skipped_acc]}}
              end

            {:fusion, plan} ->
              fusion_entry = fusion_manifest_entry(module, name, decl, plan)
              {nil, {[fusion_entry | fusion_acc], skipped_acc}}

            {:skip, reason} ->
              {nil, {fusion_acc, [{module, name, reason} | skipped_acc]}}
          end
        end)
        |> then(fn {entries, {fusion_entries, skipped}} ->
          {Enum.reject(entries, &is_nil/1), Enum.reverse(fusion_entries), skipped}
        end)

      manifest = %{
        "contract" => @manifest_contract,
        "version" => Lower.manifest_version(),
        "plan_toolchain" => plan_toolchain_manifest(opts),
        "functions" => functions,
        "fusion_functions" => fusion_functions,
        "pruned_count" => pruned_count,
        "skipped" => Enum.map(skipped, fn {m, n, r} -> %{"module" => m, "name" => n, "reason" => reason_string(r)} end),
        "plan_coverage" => plan_coverage_manifest(decl_map, coverage_opts, opts)
      }

      :ok =
        bc_dir
        |> Path.join(@manifest_name)
        |> then(&File.write(&1, Jason.encode!(manifest, pretty: true)))
    after
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_inline_record_literal_shapes)
      Process.delete(:elmc_record_field_types)
    end
  end

  @spec manifest_path(String.t()) :: String.t()
  def manifest_path(out_dir), do: Path.join([out_dir, "bytecode", @manifest_name])

  @spec lower_plan(Types.decl(), String.t(), String.t(), Types.decl_map()) :: Types.ir_expr()

  defp lower_plan(decl, module, name, decl_map) do
    rc_required? = RcRequired.rc_required?(module, name)

    case Plan.lower_function(decl, module, decl_map, rc_required: rc_required?) do
      {:ok, plan} ->
        cond do
          plan.blocks == [] and FusionRunner.runnable?(plan) ->
            {:fusion, plan}

          plan.blocks == [] ->
            {:skip, :empty_plan}

          true ->
            section = Lower.lower(plan)
            {:ok, plan, section}
        end

      :unsupported ->
        {:skip, :unsupported}

      {:error, reason} ->
        {:skip, reason}
    end
  end

  @spec section_filename(String.t(), String.t()) :: Types.ir_expr()

  defp section_filename(module, name) do
    safe_mod = module |> String.replace(".", "_")
    "#{safe_mod}_#{name}.elmcbc"
  end

  @spec reason_string(integer() | Types.ir_expr() | term()) :: Types.ir_expr()

  defp reason_string(:empty_plan), do: "empty_plan"
  defp reason_string(:encode_error), do: "encode_error"
  defp reason_string(:unsupported), do: "unsupported"
  defp reason_string({:verify, reason, _}), do: "verify:#{reason}"
  defp reason_string(other), do: inspect(other)

  @spec fusion_manifest_entry(String.t(), String.t(), Types.decl(), integer()) :: Types.ir_expr()

  defp fusion_manifest_entry(module, name, decl, plan) do
    %{
      "module" => module,
      "name" => name,
      "params" => Map.get(decl, :args, []),
      "fusion_kind" => plan.fusion_kind |> Atom.to_string(),
      "fusion_data" => wire_fusion_data(plan.fusion_data)
    }
  end

  @spec wire_fusion_data(map() | Types.ir_expr()) :: Types.ir_expr()

  defp wire_fusion_data(data) when is_map(data) do
    data
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), wire_fusion_value(v)}
      {k, v} -> {k, wire_fusion_value(v)}
    end)
    |> Map.new()
  end

  defp wire_fusion_data(other), do: other

  @spec wire_fusion_value(term() | list() | map() | atom() | Types.ir_expr()) :: Types.ir_expr()

  defp wire_fusion_value({mod, name}) when is_binary(mod) and is_binary(name),
    do: %{"module" => mod, "name" => name}

  defp wire_fusion_value(list) when is_list(list), do: Enum.map(list, &wire_fusion_value/1)
  defp wire_fusion_value(map) when is_map(map), do: wire_fusion_data(map)
  defp wire_fusion_value(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp wire_fusion_value(other), do: other

  @spec coverage_opts(keyword()) :: Types.ir_expr()

  defp coverage_opts(opts) do
    [
      entry_module: Map.get(opts, :entry_module, "Main"),
      strip_dead_code: Map.get(opts, :strip_dead_code, true),
      plan_ir_mode: Map.get(opts, :plan_ir_mode, Plan.plan_ir_mode(opts))
    ]
  end

  @spec emit_decl_map(Types.decl_map(), keyword()) :: Types.ir_expr()

  defp emit_decl_map(decl_map, coverage_opts) do
    if Keyword.get(coverage_opts, :strip_dead_code, true) do
      PrimaryCoverage.filter_reachable(decl_map, coverage_opts)
    else
      decl_map
    end
  end

  @spec plan_coverage_manifest(Types.decl_map(), keyword(), keyword()) :: Types.ir_expr()

  defp plan_coverage_manifest(decl_map, coverage_opts, compile_opts) do
    coverage_report_opts = coverage_report_opts(coverage_opts, compile_opts)
    all_report = all_coverage_report(decl_map, coverage_report_opts)

    %{
      "all" => PrimaryCoverage.wire_summary(all_report),
      "main" => PrimaryCoverage.wire_summary(PrimaryCoverage.main_functions_report(decl_map, coverage_report_opts)),
      "reachable" =>
        PrimaryCoverage.wire_summary(
          PrimaryCoverage.reachable_report(decl_map, coverage_report_opts)
        )
    }
  end

  @spec all_coverage_report(Types.decl_map(), keyword()) :: Types.ir_expr()

  defp all_coverage_report(decl_map, coverage_report_opts) do
    if Plan.plan_ir_mode(coverage_report_opts) == :primary and
         opt_bool(coverage_report_opts, :strip_dead_code, true) do
      PrimaryCoverage.reachable_report(decl_map, coverage_report_opts)
    else
      PrimaryCoverage.report(decl_map, coverage_report_opts)
    end
  end

  @spec coverage_report_opts(keyword(), keyword()) :: Types.ir_expr()

  defp coverage_report_opts(coverage_opts, compile_opts) do
    base =
      coverage_opts
      |> Enum.into(%{})
      |> Map.merge(Map.take(compile_opts, [:plan_ir_mode, :plan_ir_strict]))

    Map.put_new(base, :plan_ir_mode, Plan.plan_ir_mode(base))
  end

  @spec plan_toolchain_manifest(keyword()) :: Types.ir_expr()

  defp plan_toolchain_manifest(opts) do
    %{
      "mode" => Plan.plan_ir_mode(opts) |> Atom.to_string(),
      "strict" => Plan.strict_primary?(opts)
    }
  end

  @spec opt_bool(list() | map(), String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp opt_bool(opts, key, default) when is_list(opts),
    do: Keyword.get(opts, key, default) == true

  defp opt_bool(opts, key, default) when is_map(opts),
    do: Map.get(opts, key, default) == true
end
