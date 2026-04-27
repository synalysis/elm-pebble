defmodule Ide.Repo.Migrations.AddPublishMetadataToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :store_app_id, :string
      add :app_uuid, :string
      add :latest_published_version, :string
      add :latest_published_at, :utc_datetime
      add :store_sync_at, :utc_datetime
      add :store_metadata_cache, :map, null: false, default: %{}
      add :release_defaults, :map, null: false, default: %{}
    end
  end
end
