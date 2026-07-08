defmodule Elmc.CorpusResultAndThenProbeTest do
  use ExUnit.Case

  alias Elmc.Test.ElmRunCorpus

  @timeout_ms 60_000

  @tag timeout: @timeout_ms
  test "corpus execution Compiler/ResultAndThenDirect.elm" do
    run_corpus!("Compiler/ResultAndThenDirect.elm")
  end

  @tag timeout: @timeout_ms
  test "corpus execution Compiler/ResultAndThenChain.elm" do
    run_corpus!("Compiler/ResultAndThenChain.elm")
  end

  @tag timeout: @timeout_ms
  test "corpus execution Compiler/ResultAndThenCaptureShape.elm" do
    run_corpus!("Compiler/ResultAndThenCaptureShape.elm")
  end

  defp run_corpus!(path) do
    if not ElmRunCorpus.available?() do
      :ok
    else
      tmp = Path.join("test/tmp/corpus_probe", path_slug(path))

      assert {:ok, output} =
               ElmRunCorpus.run_elmc_execution!(path, tmp, timeout_ms: @timeout_ms)

      assert output == ElmRunCorpus.read_expected!(path)
    end
  end

  defp path_slug(path) do
    path
    |> String.replace(~r/[^A-Za-z0-9]+/, "_")
    |> String.trim("_")
  end
end
