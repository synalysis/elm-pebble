alias ElmEx.Test.TreeSitterCorpus

corpus = System.get_env("TREE_SITTER_CORPUS_DIR") || TreeSitterCorpus.corpus_dir()

unless TreeSitterCorpus.available?() do
  IO.puts(:stderr, "Corpus not available at #{corpus}")
  System.halt(1)
end

scorecard = TreeSitterCorpus.run_parse_gate!(progress: true)
out = Path.expand("../test/tmp/tree_sitter_corpus", __DIR__)
TreeSitterCorpus.write_scorecard!(scorecard, out)

summary = scorecard["summary"]
IO.puts("attempted=#{summary["attempted"]} ok=#{summary["parse_ok"]} failed=#{summary["parse_failed"]} crashed=#{summary["parse_crashed"]}")

baseline = %{
  "corpus_sha" => scorecard["corpus_sha"],
  "attempted" => summary["attempted"],
  "parse_ok_min" => summary["parse_ok"],
  "crash_max" => summary["parse_crashed"],
  "notes" => "Eligible files are <=512KiB; #{summary["skipped_large"]} larger files skipped."
}

baseline_path = Path.expand("../docs/tree_sitter_corpus_baseline.json", __DIR__)
File.write!(baseline_path, Jason.encode!(baseline, pretty: true) <> "\n")
IO.puts("Wrote #{baseline_path}")
