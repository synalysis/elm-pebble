defmodule Ide.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :target_type, :string, null: false
      add :source_roots, {:array, :string}, null: false, default: []
      add :active, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:slug])
    create index(:projects, [:active])
  end
end
