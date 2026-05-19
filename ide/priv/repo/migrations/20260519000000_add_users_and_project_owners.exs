defmodule Ide.Repo.Migrations.AddUsersAndProjectOwners do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :firebase_uid, :string, null: false
      add :email, :string
      add :display_name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:firebase_uid])
    create index(:users, [:email])

    alter table(:projects) do
      add :owner_id, references(:users, on_delete: :delete_all)
    end

    drop_if_exists unique_index(:projects, [:slug])
    create unique_index(:projects, [:owner_id, :slug])

    create unique_index(:projects, [:slug],
             where: "owner_id IS NULL",
             name: :projects_local_slug_index
           )

    create index(:projects, [:owner_id])
  end
end
