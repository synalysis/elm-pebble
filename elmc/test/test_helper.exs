ExUnit.start()

ExUnit.configure(
  exclude: [
    :corpus,
    :corpus_run,
    :corpus_elmx,
    :corpus_index,
    :fixture_codegen
  ]
)
