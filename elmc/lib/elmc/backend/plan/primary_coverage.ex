defmodule Elmc.Backend.Plan.PrimaryCoverage do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{DirectRender.Analysis, GenericReachability, RcRequired}
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.StrictPolicy

  @type report :: %{
          total: non_neg_integer(),
          lowered: non_neg_integer(),
          failed: [{String.t(), String.t(), term()}]
        }

  @type wire_summary :: %{
          optional(String.t()) => term()
        }

  @spec report(map(), keyword() | map()) :: report()
  def report(decl_map, opts \\ []) when is_map(decl_map) do
    with_constructor_tags!(opts)

    decl_map
    |> Enum.sort()
    |> Enum.reduce(%{total: 0, lowered: 0, failed: []}, fn {{mod, name}, decl}, acc ->
      rc_required? = RcRequired.rc_required?(mod, name)

      acc = %{acc | total: acc.total + 1}

      case PlanLower.lower(decl, mod, decl_map, rc_required: rc_required?) do
        {:ok, _} ->
          %{acc | lowered: acc.lowered + 1}

        other ->
          %{acc | failed: acc.failed ++ [{mod, name, other}]}
      end
    end)
  end

  @spec main_functions_report(map(), keyword() | map()) :: report()
  def main_functions_report(decl_map, opts \\ []) do
    decl_map
    |> Enum.filter(fn {{mod, _name}, _} -> mod == "Main" end)
    |> Map.new()
    |> report(opts)
  end

  @doc """
  Coverage for functions reachable from worker entry roots (`init`, `update`, …).

  Dead bundled helpers (for example phone-only `Pebble.Platform` JSON decoders)
  are excluded so audits reflect watch codegen obligations.
  """
  @spec reachable_report(map(), keyword() | map()) :: report()
  def reachable_report(decl_map, opts \\ []) when is_map(decl_map) do
    decl_map
    |> filter_reachable(opts)
    |> report(opts)
  end

  @spec module_prefix_report(map(), String.t(), keyword()) :: report()
  def module_prefix_report(decl_map, prefix, opts \\ []) when is_binary(prefix) do
    decl_map
    |> Enum.filter(fn {{mod, _name}, _} -> String.starts_with?(mod, prefix) end)
    |> Map.new()
    |> report(opts)
  end

  @spec filter_reachable(map(), keyword() | map()) :: map()
  def filter_reachable(decl_map, opts \\ []) when is_map(decl_map) do
    codegen_opts = codegen_opts(opts)
    roots = Analysis.entry_roots(decl_map, codegen_opts)

    reachable =
      GenericReachability.reachable_targets(roots, decl_map, MapSet.new())

    decl_map
    |> Enum.filter(fn {key, _} -> MapSet.member?(reachable, key) end)
    |> Map.new()
  end

  @spec reachable_function?(map(), String.t(), String.t(), keyword() | map()) :: boolean()
  def reachable_function?(decl_map, module_name, fun_name, opts \\ []) do
    decl_map
    |> filter_reachable(opts)
    |> Map.has_key?({module_name, fun_name})
  end

  defp codegen_opts(opts) do
    %{
      entry_module: opt(opts, :entry_module, "Main"),
      strip_dead_code: opt(opts, :strip_dead_code, true)
    }
  end

  defp opt(opts, key), do: opt(opts, key, nil)
  defp opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp opt(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  defp with_constructor_tags!(opts) do
    case opt(opts, :ir) do
      %ElmEx.IR{} = ir ->
        Process.put(
          :elmc_constructor_tags,
          Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir)
        )

      _ ->
        :ok
    end
  end

  @spec wire_summary(report()) :: wire_summary()
  def wire_summary(%{total: total, lowered: lowered, failed: failed}) do
    %{
      "total" => total,
      "lowered" => lowered,
      "failed_count" => length(failed),
      "ratio" => coverage_ratio(total, lowered),
      "failed_preview" =>
        Enum.map(Enum.take(failed, 12), fn {mod, name, reason} ->
          %{"module" => mod, "name" => name, "reason" => reason_string(reason)}
        end)
    }
  end

  defp coverage_ratio(_total, 0), do: 0.0
  defp coverage_ratio(total, lowered) when total > 0, do: Float.round(lowered / total, 4)
  defp coverage_ratio(_, _), do: 0.0

  @doc """
  Build compile-time diagnostics from bytecode `plan_coverage` stats.

  In `:primary` mode, unreachable bundled helpers are omitted from bytecode and
  do not appear in `reachable` stats — only gaps on the watch codegen path are reported.
  """
  @spec compile_diagnostics(map() | nil, keyword()) :: [map()]
  def compile_diagnostics(bytecode_summary, opts \\ [])

  def compile_diagnostics(%{available: true, plan_coverage: coverage} = bytecode_summary, opts)
      when is_map(coverage) do
    mode = Elmc.Backend.Plan.plan_ir_mode(opts)

    if mode in [:primary, :shadow] do
      reachable = Map.get(coverage, "reachable") || Map.get(coverage, :reachable) || %{}
      main = Map.get(coverage, "main") || Map.get(coverage, :main) || %{}
      pruned = Map.get(bytecode_summary, :pruned_count) || Map.get(bytecode_summary, "pruned_count") || 0

      gap_warnings(reachable, opts) ++
        coverage_info(reachable, main, pruned, mode, opts)
    else
      []
    end
  end

  def compile_diagnostics(_, _), do: []

  defp gap_warnings(reachable, opts) when is_map(reachable) do
    failed = int_field(reachable, "failed_count", 0)

    if failed > 0 do
      preview =
        (Map.get(reachable, "failed_preview") || Map.get(reachable, :failed_preview) || [])
        |> Enum.map(fn
          %{"module" => mod, "name" => name, "reason" => reason} ->
            "#{mod}.#{name} (#{reason})"

          %{module: mod, name: name, reason: reason} ->
            "#{mod}.#{name} (#{reason})"
        end)
        |> Enum.take(6)
        |> Enum.join(", ")

      severity = StrictPolicy.gap_severity(opts)

      [
        %{
          "source" => "elmc/plan",
          "code" => "plan_primary_gap",
          "severity" => severity,
          "message" =>
            "Plan IR could not lower #{failed} reachable function(s): #{preview}"
        }
      ]
    else
      []
    end
  end

  defp gap_warnings(_, _), do: []

  defp coverage_info(reachable, main, pruned, :primary, opts) when is_map(reachable) do
    failed = int_field(reachable, "failed_count", 0)
    lowered = int_field(reachable, "lowered", 0)
    total = int_field(reachable, "total", 0)
    main_lowered = int_field(main, "lowered", 0)
    main_total = int_field(main, "total", 0)

    if failed == 0 and total > 0 do
      mode = Elmc.Backend.Plan.plan_ir_mode(opts)
      strict = Elmc.Backend.Plan.strict_primary?(opts)
      toolchain = " (#{mode}#{if strict, do: " strict", else: ""})"

      [
        %{
          "source" => "elmc/plan",
          "code" => "plan_primary_coverage",
          "severity" => "info",
          "message" =>
            "Plan IR#{toolchain}: #{lowered}/#{total} reachable functions lowered" <>
              if(pruned > 0, do: " (#{pruned} dead helpers pruned)", else: "") <>
              ", Main #{main_lowered}/#{main_total}"
        }
      ]
    else
      []
    end
  end

  defp coverage_info(_, _, _, _, _), do: []

  defp int_field(map, key, default) when is_map(map) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      n when is_integer(n) -> n
      _ -> default
    end
  end

  defp reason_string(:unsupported), do: "unsupported"
  defp reason_string({:verify, reason, _}), do: "verify:#{reason}"
  defp reason_string(other), do: inspect(other)
end
