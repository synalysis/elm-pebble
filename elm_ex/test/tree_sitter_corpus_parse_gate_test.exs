defmodule ElmEx.TreeSitterCorpusParseGateTest do
  use ExUnit.Case

  alias ElmEx.Test.TreeSitterCorpus

  @baseline_path Path.expand("../docs/tree_sitter_corpus_baseline.json", __DIR__)
  @scorecard_dir Path.expand("tmp/tree_sitter_corpus", __DIR__)

  @tag :ts_corpus_smoke
  @tag timeout: 120_000
  test "smoke parse gate on diverse real-world Elm sources" do
    if corpus_skip?() or not TreeSitterCorpus.available?() do
      IO.puts("Skipping tree-sitter corpus smoke parse gate")
      :ok
    else
      paths = TreeSitterCorpus.smoke_tests()

      assert paths != [],
             "tree-sitter corpus smoke list is empty; refresh ElmEx.Test.TreeSitterCorpus.@smoke_tests"

      scorecard =
        TreeSitterCorpus.run_parse_gate!(
          paths: paths,
          progress: false,
          timeout_ms: 15_000
        )

      TreeSitterCorpus.write_scorecard!(scorecard, Path.join(@scorecard_dir, "smoke"))

      failures =
        scorecard["results"]
        |> Enum.filter(&(&1["status"] != "ok"))
        |> Enum.map(& &1["path"])

      assert failures == [],
             "tree-sitter corpus smoke parse failures: #{inspect(failures, limit: 20)}"
    end
  end

  @tag :ts_corpus
  @tag timeout: :infinity
  test "full parse gate across eligible tree-sitter corpus programs" do
    if corpus_skip?() or not TreeSitterCorpus.available?() do
      IO.puts("Skipping tree-sitter corpus parse gate")
      :ok
    else
      scorecard =
        TreeSitterCorpus.run_parse_gate!(
          tmp_root: @scorecard_dir,
          progress: true
        )

      TreeSitterCorpus.write_scorecard!(scorecard, @scorecard_dir)
      assert_scorecard_against_baseline!(scorecard)
    end
  end

  defp assert_scorecard_against_baseline!(scorecard) do
    baseline = File.read!(@baseline_path) |> Jason.decode!()
    summary = scorecard["summary"]

    assert summary["parse_ok"] >= baseline["parse_ok_min"],
           """
           tree-sitter corpus parse regression:
           got #{summary["parse_ok"]} ok, baseline requires >= #{baseline["parse_ok_min"]}
           failed: #{summary["parse_failed"]}, crashed: #{summary["parse_crashed"]}
           """

    assert summary["parse_crashed"] <= baseline["crash_max"],
           """
           tree-sitter corpus parser crashes:
           got #{summary["parse_crashed"]}, baseline allows <= #{baseline["crash_max"]}
           """

    if baseline["corpus_sha"] && scorecard["corpus_sha"] != baseline["corpus_sha"] do
      IO.warn(
        "tree-sitter corpus SHA changed (#{baseline["corpus_sha"]} -> #{scorecard["corpus_sha"]}); refresh baseline after intentional corpus update"
      )
    end
  end

  defp corpus_skip? do
    System.get_env("CORPUS_SKIP") in ["1", "true", "yes"]
  end
end
