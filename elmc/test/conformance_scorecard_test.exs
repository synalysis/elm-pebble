defmodule Elmc.ConformanceScorecardTest do
  use ExUnit.Case

  @guardrails %{
    min_required_functions: 59,
    min_required_runtime_symbols: 28,
    min_behavior_assertions: 61
  }

  setup_all do
    scorecard = build_scorecard()
    :ok = write_scorecard(scorecard)
    {:ok, scorecard: scorecard}
  end

  test "writes conformance scorecard artifacts", %{scorecard: scorecard} do
    json_path = Path.expand("tmp/conformance/scorecard.json", __DIR__)
    md_path = Path.expand("tmp/conformance/scorecard.md", __DIR__)

    assert File.exists?(json_path)
    assert File.exists?(md_path)

    assert scorecard.required_functions.present == scorecard.required_functions.total
    assert scorecard.required_runtime_symbols.present == scorecard.required_runtime_symbols.total
  end

  test "guardrails prevent conformance regressions", %{scorecard: scorecard} do
    assert scorecard.required_functions.total >= @guardrails.min_required_functions
    assert scorecard.required_runtime_symbols.total >= @guardrails.min_required_runtime_symbols
    assert scorecard.behavior_assertions.total >= @guardrails.min_behavior_assertions

    assert scorecard.required_functions.present == scorecard.required_functions.total
    assert scorecard.required_runtime_symbols.present == scorecard.required_runtime_symbols.total
  end

  defp build_scorecard do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/conformance_scorecard_build", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               strip_dead_code: false,
               entry_module: "Main"
             })

    compliance_path = Path.expand("core_compliance_test.exs", __DIR__)
    differential_path = Path.expand("core_differential_conformance_test.exs", __DIR__)

    compliance_src = File.read!(compliance_path)
    differential_src = File.read!(differential_path)

    required_functions = extract_quoted_attr_list(compliance_src, "required_functions")
    runtime_symbols = extract_quoted_attr_list(differential_src, "required_runtime_symbols")
    behavior_assertions = count_behavior_assertions(compliance_src)

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    runtime_h = File.read!(Path.join(out_dir, "runtime/elmc_runtime.h"))
    runtime_c = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    # New naming convention: elmc_fn_<Module>_<name>
    # All @required_functions from core_compliance_test are in the CoreCompliance module
    function_hits =
      Enum.count(required_functions, fn fn_name ->
        String.contains?(generated_c, "elmc_fn_#{fn_name}")
      end)

    runtime_hits =
      Enum.count(runtime_symbols, fn symbol ->
        String.contains?(runtime_h, symbol) and String.contains?(runtime_c, symbol)
      end)

    %{
      generated_at: Date.utc_today() |> Date.to_iso8601(),
      required_functions: coverage(required_functions, function_hits),
      required_runtime_symbols: coverage(runtime_symbols, runtime_hits),
      behavior_assertions: %{total: behavior_assertions}
    }
  end

  defp coverage(items, hits) do
    total = length(items)
    pct = if total == 0, do: 0.0, else: Float.round(hits * 100.0 / total, 2)
    %{total: total, present: hits, coverage_pct: pct}
  end

  defp extract_quoted_attr_list(source, attr_name) do
    regex = ~r/@#{attr_name}\s+\[(.*?)\]\n/s

    case Regex.run(regex, source, capture: :all_but_first) do
      [block] -> Regex.scan(~r/"([^"]+)"/, block, capture: :all_but_first) |> List.flatten()
      _ -> []
    end
  end

  defp count_behavior_assertions(source) do
    Regex.scan(~r/assert values\["[^"]+"\]/, source) |> length()
  end

  defp write_scorecard(scorecard) do
    out_dir = Path.expand("tmp/conformance", __DIR__)
    File.mkdir_p!(out_dir)

    json_path = Path.join(out_dir, "scorecard.json")
    md_path = Path.join(out_dir, "scorecard.md")

    File.write!(json_path, Jason.encode!(scorecard, pretty: true) <> "\n")
    File.write!(md_path, render_markdown(scorecard))
    :ok
  end

  defp render_markdown(scorecard) do
    funcs = scorecard.required_functions
    runtime = scorecard.required_runtime_symbols
    assertions = scorecard.behavior_assertions

    """
    # Conformance Scorecard

    Generated: `#{scorecard.generated_at}`

    ## Metrics

    - Required generated function symbols: `#{funcs.present}` / `#{funcs.total}` (`#{funcs.coverage_pct}%`)
    - Required runtime symbols: `#{runtime.present}` / `#{runtime.total}` (`#{runtime.coverage_pct}%`)
    - Behavior assertions in core compliance harness: `#{assertions.total}`
    """
  end
end
