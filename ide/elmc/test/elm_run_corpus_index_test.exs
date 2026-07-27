defmodule Elmc.ElmRunCorpusIndexTest do
  use ExUnit.Case

  alias Elmc.Test.ElmRunCorpus

  @tag :corpus_index
  test "discovers and writes elm-run corpus index" do
    if corpus_skip?() or not ElmRunCorpus.available?() do
      IO.puts("Skipping corpus index test")
      :ok
    else
      index = ElmRunCorpus.build_index()
      path = ElmRunCorpus.write_index!(index)

      assert File.exists?(path)
      assert index["summary"]["total"] > 500
      assert index["summary"]["compile_candidate"] > 200
      assert index["summary"]["elm_run_only"] > 100
      assert index["summary"]["run_scalar"] + index["summary"]["run_structured"] > 300
      assert is_binary(index["corpus_sha"])
    end
  end

  defp corpus_skip? do
    System.get_env("CORPUS_SKIP") in ["1", "true", "yes"]
  end
end
