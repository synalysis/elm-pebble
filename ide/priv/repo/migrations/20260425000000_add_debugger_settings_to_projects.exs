defmodule Ide.Repo.Migrations.AddDebuggerSettingsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :debugger_settings, :map, null: false, default: %{}
    end
  end
end
