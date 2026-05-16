defmodule Ide.Repo.Migrations.AddPackageMetadataCacheToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :package_metadata_cache, :map, default: %{}, null: false
    end
  end
end
