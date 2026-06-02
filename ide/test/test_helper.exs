ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Ide.Repo.Sqlite, :manual)

{:ok, _} = Application.ensure_all_started(:ide)
{:ok, _} = Application.ensure_all_started(:elmx)
