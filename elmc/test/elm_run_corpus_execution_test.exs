defmodule Elmc.ElmRunCorpusExecutionTest do
  use ExUnit.Case

  alias Elmc.Test.ElmRunCorpus

  @baseline_path Path.expand("../docs/elm_run_corpus_execution_baseline.json", __DIR__)
  @scorecard_dir Path.expand("tmp/elm_run_corpus_execution", __DIR__)

  @tag :corpus_run_smoke
  @tag timeout: 120_000
  test "smoke execution gate matches corpus gold on canary programs" do
    if corpus_skip?() or not ElmRunCorpus.available?() do
      IO.puts("Skipping corpus execution smoke")
      :ok
    else
      index = ElmRunCorpus.build_index()

      scorecard =
        ElmRunCorpus.run_execution_gate!(
          index: index,
          backend: :elmc,
          tmp_root: Path.join(@scorecard_dir, "smoke"),
          paths: ElmRunCorpus.execution_smoke_tests(),
          timeout_ms: 15_000
        )

      ElmRunCorpus.write_execution_scorecard!(scorecard, Path.join(@scorecard_dir, "smoke"))
      assert_execution_against_baseline!(scorecard, "elmc_smoke")
    end
  end

  @tag :corpus_run
  @tag timeout: :infinity
  test "full elmc execution gate across strict corpus gold programs" do
    if corpus_skip?() or not ElmRunCorpus.available?() do
      IO.puts("Skipping corpus execution gate")
      :ok
    else
      index = ElmRunCorpus.build_index()

      scorecard =
        ElmRunCorpus.run_execution_gate!(
          index: index,
          backend: :elmc,
          tmp_root: Path.join(@scorecard_dir, "elmc"),
          progress: true,
          timeout_ms: 15_000
        )

      ElmRunCorpus.write_execution_scorecard!(scorecard, Path.join(@scorecard_dir, "elmc"))
      assert_execution_against_baseline!(scorecard, "elmc")
    end
  end

  @tag :corpus_run
  @tag timeout: :infinity
  test "full elmx execution gate across strict corpus gold programs" do
    if corpus_skip?() or not ElmRunCorpus.available?() do
      IO.puts("Skipping corpus elmx execution gate")
      :ok
    else
      index = ElmRunCorpus.build_index()

      scorecard =
        ElmRunCorpus.run_execution_gate!(
          index: index,
          backend: :elmx,
          tmp_root: Path.join(@scorecard_dir, "elmx"),
          progress: true,
          timeout_ms: 15_000
        )

      ElmRunCorpus.write_execution_scorecard!(scorecard, Path.join(@scorecard_dir, "elmx"))
      assert_execution_against_baseline!(scorecard, "elmx")
    end
  end

  @tag :corpus_parity
  @tag timeout: 120_000
  test "elmc and elmx agree on corpus execution smoke outputs when both succeed" do
    if corpus_skip?() or not ElmRunCorpus.available?() do
      IO.puts("Skipping corpus parity smoke")
      :ok
    else
      paths = ElmRunCorpus.parity_smoke_tests()
      tmp_root = Path.join(@scorecard_dir, "parity")

      mismatches =
        Enum.flat_map(paths, fn path ->
          elmc = ElmRunCorpus.run_elmc_execution!(path, tmp_root, timeout_ms: 15_000)
          elmx = ElmRunCorpus.run_elmx_execution!(path, tmp_root, timeout_ms: 15_000)

          case {elmc, elmx} do
            {{:ok, elmc_out}, {:ok, elmx_out}} ->
              if elmc_out == elmx_out, do: [], else: [{path, %{elmc: elmc_out, elmx: elmx_out}}]

            _ ->
              []
          end
        end)

      assert mismatches == [],
             "corpus elmc/elmx parity smoke mismatches: #{inspect(mismatches, limit: 10)}"
    end
  end

  defp assert_execution_against_baseline!(scorecard, backend_key) do
    baseline = File.read!(@baseline_path) |> Jason.decode!()
    backend = baseline[backend_key]
    summary = scorecard["summary"]

    assert summary["run_ok"] >= backend["run_ok_min"],
           """
           corpus #{backend_key} execution regression:
           got #{summary["run_ok"]} ok, baseline requires >= #{backend["run_ok_min"]}
           mismatch: #{summary["run_mismatch"]}, failed: #{summary["run_failed"]}
           """

    if summary["run_ok"] > backend["run_ok_min"] do
      IO.warn(
        "corpus #{backend_key} execution improved (#{summary["run_ok"]} > #{backend["run_ok_min"]}); consider raising baseline"
      )
    end
  end

  defp corpus_skip? do
    System.get_env("CORPUS_SKIP") in ["1", "true", "yes"]
  end
end
