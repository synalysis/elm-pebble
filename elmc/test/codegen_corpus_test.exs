defmodule Elmc.CodegenCorpusTest do
  use ExUnit.Case

  @moduledoc """
  Corpus-driven end-to-end test: parse → lower → codegen on all fixture projects.
  Tracks counters for parse failures, lowering diagnostics, unsupported backend nodes,
  codegen failures, and link failures. Writes a scorecard artifact.
  """

  @fixtures_dir Path.expand("fixtures", __DIR__)
  @scorecard_dir Path.expand("tmp/codegen_corpus", __DIR__)

  test "codegen corpus scorecard across all fixture projects" do
    File.mkdir_p!(@scorecard_dir)

    fixture_dirs =
      @fixtures_dir
      |> File.ls!()
      |> Enum.filter(fn name ->
        File.dir?(Path.join(@fixtures_dir, name)) and
          File.exists?(Path.join([@fixtures_dir, name, "elm.json"]))
      end)
      |> Enum.sort()

    results =
      Enum.map(fixture_dirs, fn fixture_name ->
        project_dir = Path.join(@fixtures_dir, fixture_name)
        out_dir = Path.join(@scorecard_dir, fixture_name)
        File.rm_rf!(out_dir)

        result = %{
          fixture: fixture_name,
          parse: :unknown,
          lower: :unknown,
          codegen: :unknown,
          unsupported_ops: 0,
          diagnostics: 0,
          modules: 0,
          functions: 0
        }

        case ElmEx.Frontend.Bridge.load_project(project_dir) do
          {:ok, project} ->
            result = %{result | parse: :ok, modules: length(project.modules)}

            case ElmEx.IR.Lowerer.lower_project(project) do
              {:ok, ir} ->
                diag_count = length(ir.diagnostics)

                func_count =
                  ir.modules
                  |> Enum.flat_map(& &1.declarations)
                  |> Enum.count(&(&1.kind == :function))

                unsupported = count_unsupported_ops(ir)

                result = %{
                  result
                  | lower: :ok,
                    diagnostics: diag_count,
                    functions: func_count,
                    unsupported_ops: unsupported
                }

                case Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false}) do
                  {:ok, _} -> %{result | codegen: :ok}
                  {:error, _} -> %{result | codegen: :error}
                end

              {:error, _} ->
                %{result | lower: :error}
            end

          {:error, _} ->
            %{result | parse: :error}
        end
      end)

    # Write scorecard
    scorecard_json =
      Jason.encode!(
        %{
          "results" => results,
          "summary" => %{
            "total" => length(results),
            "parse_ok" => Enum.count(results, &(&1.parse == :ok)),
            "lower_ok" => Enum.count(results, &(&1.lower == :ok)),
            "codegen_ok" => Enum.count(results, &(&1.codegen == :ok)),
            "total_unsupported" => Enum.sum(Enum.map(results, & &1.unsupported_ops)),
            "total_diagnostics" => Enum.sum(Enum.map(results, & &1.diagnostics)),
            "total_modules" => Enum.sum(Enum.map(results, & &1.modules)),
            "total_functions" => Enum.sum(Enum.map(results, & &1.functions))
          }
        },
        pretty: true
      )

    File.write!(Path.join(@scorecard_dir, "codegen_scorecard.json"), scorecard_json)

    # Write markdown scorecard
    md_lines =
      [
        "# Codegen Corpus Scorecard\n",
        "| Fixture | Parse | Lower | Codegen | Modules | Functions | Unsupported | Diagnostics |",
        "|---------|-------|-------|---------|---------|-----------|-------------|-------------|"
      ] ++
        Enum.map(results, fn r ->
          "| #{r.fixture} | #{r.parse} | #{r.lower} | #{r.codegen} | #{r.modules} | #{r.functions} | #{r.unsupported_ops} | #{r.diagnostics} |"
        end)

    File.write!(Path.join(@scorecard_dir, "codegen_scorecard.md"), Enum.join(md_lines, "\n"))

    # Gate assertions
    parse_ok = Enum.count(results, &(&1.parse == :ok))
    lower_ok = Enum.count(results, &(&1.lower == :ok))
    codegen_ok = Enum.count(results, &(&1.codegen == :ok))

    assert parse_ok >= 2, "Expected at least 2 projects to parse, got #{parse_ok}"
    assert lower_ok >= 2, "Expected at least 2 projects to lower, got #{lower_ok}"
    assert codegen_ok >= 2, "Expected at least 2 projects to generate code, got #{codegen_ok}"
  end

  defp count_unsupported_ops(%ElmEx.IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function and is_map(&1.expr)))
      |> Enum.flat_map(fn decl ->
        collect_ops(decl.expr, :unsupported)
      end)
    end)
    |> length()
  end

  defp collect_ops(%{op: target} = expr, target), do: [expr | collect_children(expr, target)]
  defp collect_ops(expr, target) when is_map(expr), do: collect_children(expr, target)
  defp collect_ops(_, _), do: []

  defp collect_children(expr, target) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn
      child when is_map(child) ->
        collect_ops(child, target)

      children when is_list(children) ->
        Enum.flat_map(children, fn
          child when is_map(child) -> collect_ops(child, target)
          _ -> []
        end)

      _ ->
        []
    end)
  end
end
