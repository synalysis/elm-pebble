defmodule Ide.Repo.Migrations.AddEmailAuthToUsers do
  use Ecto.Migration

  def up do
    case repo().__adapter__() do
      Ecto.Adapters.Postgres -> postgres_up()
      Ecto.Adapters.SQLite3 -> sqlite_up()
      adapter -> raise "unsupported repo adapter: #{inspect(adapter)}"
    end
  end

  def down do
    case repo().__adapter__() do
      Ecto.Adapters.Postgres -> postgres_down()
      Ecto.Adapters.SQLite3 -> sqlite_down()
      adapter -> raise "unsupported repo adapter: #{inspect(adapter)}"
    end
  end

  defp postgres_up do
    alter table(:users) do
      add :password_hash, :string
      modify :firebase_uid, :string, null: true, from: {:string, null: false}
    end

    recreate_partial_user_indexes()
  end

  defp postgres_down do
    drop_if_exists unique_index(:users, [:firebase_uid], name: :users_firebase_uid_index)
    drop_if_exists unique_index(:users, [:email], name: :users_email_index)

    execute("DELETE FROM users WHERE firebase_uid IS NULL")

    alter table(:users) do
      remove :password_hash
      modify :firebase_uid, :string, null: false, from: {:string, null: true}
    end

    create unique_index(:users, [:firebase_uid])
    create index(:users, [:email])
  end

  defp sqlite_up do
    alter table(:users) do
      add :password_hash, :string
    end

    execute(
      """
      CREATE TABLE users_email_auth (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_uid TEXT,
        email TEXT,
        display_name TEXT,
        password_hash TEXT,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """,
      ""
    )

    execute(
      """
      INSERT INTO users_email_auth (id, firebase_uid, email, display_name, password_hash, inserted_at, updated_at)
      SELECT id, firebase_uid, email, display_name, password_hash, inserted_at, updated_at
      FROM users
      """,
      ""
    )

    drop table(:users)
    execute("ALTER TABLE users_email_auth RENAME TO users", "")

    recreate_partial_user_indexes()
  end

  defp sqlite_down do
    execute(
      """
      CREATE TABLE users_legacy (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_uid TEXT NOT NULL,
        email TEXT,
        display_name TEXT,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """,
      ""
    )

    execute(
      """
      INSERT INTO users_legacy (id, firebase_uid, email, display_name, inserted_at, updated_at)
      SELECT id, firebase_uid, email, display_name, inserted_at, updated_at
      FROM users
      WHERE firebase_uid IS NOT NULL
      """,
      ""
    )

    drop table(:users)
    execute("ALTER TABLE users_legacy RENAME TO users", "")

    create unique_index(:users, [:firebase_uid])
    create index(:users, [:email])
  end

  defp recreate_partial_user_indexes do
    drop_if_exists unique_index(:users, [:firebase_uid])
    drop_if_exists index(:users, [:email])

    create unique_index(:users, [:firebase_uid],
             where: "firebase_uid IS NOT NULL",
             name: :users_firebase_uid_index
           )

    create unique_index(:users, [:email], where: "email IS NOT NULL", name: :users_email_index)
  end
end
