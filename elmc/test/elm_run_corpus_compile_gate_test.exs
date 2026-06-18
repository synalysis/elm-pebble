defmodule Elmc.ElmRunCorpusCompileGateTest do
  use ExUnit.Case

  alias Elmc.Test.ElmRunCorpus

  @baseline_path Path.expand("../docs/elm_run_corpus_baseline.json", __DIR__)
  @scorecard_dir Path.expand("tmp/elm_run_corpus", __DIR__)

  @tag :corpus_smoke
  @tag timeout: 120_000
  test "smoke compile gate on corpus canary programs" do
    if corpus_skip?() or not ElmRunCorpus.available?() do
      IO.puts("Skipping corpus smoke compile gate")
      :ok
    else
      index = ElmRunCorpus.build_index()
      paths = ElmRunCorpus.smoke_tests()

      scorecard =
        ElmRunCorpus.run_compile_gate!(
          index: index,
          tmp_root: Path.join(@scorecard_dir, "smoke"),
          paths: paths
        )

      ElmRunCorpus.write_scorecard!(scorecard, Path.join(@scorecard_dir, "smoke"))

      failures =
        scorecard["results"]
        |> Enum.filter(&(&1["status"] != "ok"))
        |> Enum.map(& &1["path"])

      assert failures == [],
             "corpus smoke compile failures: #{inspect(failures, limit: 20)}"
    end
  end

  @tag :corpus
  @tag timeout: :infinity
  test "full compile gate across portable corpus programs" do
    if corpus_skip?() or not ElmRunCorpus.available?() do
      IO.puts("Skipping corpus compile gate")
      :ok
    else
      index = ElmRunCorpus.build_index()
      ElmRunCorpus.write_index!(index)

      scorecard =
        ElmRunCorpus.run_compile_gate!(
          index: index,
          tmp_root: Path.join(@scorecard_dir, "full"),
          progress: true,
          timeout_ms: 15_000
        )

      ElmRunCorpus.write_scorecard!(scorecard, @scorecard_dir)
      assert_scorecard_against_baseline!(scorecard)
    end
  end

  defp assert_scorecard_against_baseline!(scorecard) do
    baseline = File.read!(@baseline_path) |> Jason.decode!()
    summary = scorecard["summary"]

    assert summary["compile_ok"] >= baseline["compile_ok_min"],
           """
           corpus compile regression:
           got #{summary["compile_ok"]} ok, baseline requires >= #{baseline["compile_ok_min"]}
           failed: #{summary["compile_failed"]}
           """

    if baseline["corpus_sha"] && scorecard["corpus_sha"] != baseline["corpus_sha"] do
      IO.warn(
        "corpus SHA changed (#{baseline["corpus_sha"]} -> #{scorecard["corpus_sha"]}); refresh baseline after intentional corpus update"
      )
    end
  end

  defp corpus_skip? do
    System.get_env("CORPUS_SKIP") in ["1", "true", "yes"]
  end
end
