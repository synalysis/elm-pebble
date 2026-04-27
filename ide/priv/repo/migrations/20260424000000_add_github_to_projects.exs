defmodule Ide.Repo.Migrations.AddGithubToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :github, :map, null: false, default: %{}
    end
  end
end
