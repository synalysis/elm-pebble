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
    :template_compile_gate,
    :template_pbw_gate,
    :template_parity,
    :template_parity_case,
    :imagemagick,
    :gif2apng
  ]
)

Ecto.Adapters.SQL.Sandbox.mode(Ide.Repo.Sqlite, :manual)
