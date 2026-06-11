ExUnit.start()

{:ok, _} = Ide.TestSupport.DebuggerSessionLock.start_link()

ExUnit.configure(
  exclude: [
    :integration,
    :slow,
    :live_emulator,
    :template_corpus,
    :template_corpus_step,
    :compiled_elixir_corpus,
    :template_compile_gate
  ]
)

Ecto.Adapters.SQL.Sandbox.mode(Ide.Repo.Sqlite, :manual)
