defmodule Elmc.Backend.Bytecode.ProjectWriter do
  @moduledoc """
  Emit `.elmcbc` sections and a manifest alongside C codegen when plan IR is active.
  """

  alias Elmc.Backend.Bytecode.Lower
  alias Elmc.Backend.CCodegen.{IRQueries, RcRequired}
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.PrimaryCoverage
  alias ElmEx.IR

  @manifest_name "elmc_bytecode.manifest.json"
  @manifest_contract "elmc.bytecode_manifest.v1"

  @spec maybe_write(IR.t(), String.t(), map()) :: :ok | {:error, term()}
  def maybe_write(%IR{} = ir, out_dir, opts) when is_map(opts) do
    if Plan.plan_ir_mode(opts) in [:shadow, :primary] do
      write(ir, out_dir, opts)
    else
      :ok
    end
  end

  @spec write(IR.t(), String.t(), map()) :: :ok | {:error, term()}
  def write(%IR{} = ir, out_dir, opts \\ %{}) do
    bc_dir = Path.join(out_dir, "bytecode")
    File.mkdir_p!(bc_dir)

    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))

    try do
      decl_map = IRQueries.function_decl_map(ir)
      coverage_opts = coverage_opts(opts)
      emit_map = emit_decl_map(decl_map, coverage_opts)
      pruned_count = map_size(decl_map) - map_size(emit_map)

      {functions, skipped} =
        emit_map
        |> Enum.sort()
        |> Enum.map_reduce([], fn {{module, name}, decl}, skipped_acc ->
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

                {entry, skipped_acc}
              rescue
                _ -> {nil, [{module, name, :encode_error} | skipped_acc]}
              end

            {:skip, reason} ->
              {nil, [{module, name, reason} | skipped_acc]}
          end
        end)
        |> then(fn {entries, skipped} ->
          {Enum.reject(entries, &is_nil/1), skipped}
        end)

      manifest = %{
        "contract" => @manifest_contract,
        "version" => Lower.manifest_version(),
        "plan_toolchain" => plan_toolchain_manifest(opts),
        "functions" => functions,
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
    end
  end

  @spec manifest_path(String.t()) :: String.t()
  def manifest_path(out_dir), do: Path.join([out_dir, "bytecode", @manifest_name])

  defp lower_plan(decl, module, name, decl_map) do
    rc_required? = RcRequired.rc_required?(module, name)

    case Plan.lower_function(decl, module, decl_map, rc_required: rc_required?) do
      {:ok, plan} ->
        if plan.blocks == [] do
          {:skip, :empty_plan}
        else
          section = Lower.lower(plan)
          {:ok, plan, section}
        end

      :unsupported ->
        {:skip, :unsupported}

      {:error, reason} ->
        {:skip, reason}
    end
  end

  defp section_filename(module, name) do
    safe_mod = module |> String.replace(".", "_")
    "#{safe_mod}_#{name}.elmcbc"
  end

  defp reason_string(:empty_plan), do: "empty_plan"
  defp reason_string(:encode_error), do: "encode_error"
  defp reason_string(:unsupported), do: "unsupported"
  defp reason_string({:verify, reason, _}), do: "verify:#{reason}"
  defp reason_string(other), do: inspect(other)

  defp coverage_opts(opts) do
    [
      entry_module: Map.get(opts, :entry_module, "Main"),
      strip_dead_code: Map.get(opts, :strip_dead_code, true),
      plan_ir_mode: Map.get(opts, :plan_ir_mode, Plan.plan_ir_mode(opts))
    ]
  end

  defp emit_decl_map(decl_map, coverage_opts) do
    if Keyword.get(coverage_opts, :strip_dead_code, true) do
      PrimaryCoverage.filter_reachable(decl_map, coverage_opts)
    else
      decl_map
    end
  end

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

  defp all_coverage_report(decl_map, coverage_report_opts) do
    if Plan.plan_ir_mode(coverage_report_opts) == :primary and
         opt_bool(coverage_report_opts, :strip_dead_code, true) do
      PrimaryCoverage.reachable_report(decl_map, coverage_report_opts)
    else
      PrimaryCoverage.report(decl_map, coverage_report_opts)
    end
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
      "strict" => Plan.strict_primary?(opts)
    }
  end

  defp opt_bool(opts, key, default) when is_list(opts),
    do: Keyword.get(opts, key, default) == true

  defp opt_bool(opts, key, default) when is_map(opts),
    do: Map.get(opts, key, default) == true
end
