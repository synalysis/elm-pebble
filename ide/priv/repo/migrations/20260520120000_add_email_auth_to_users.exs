defmodule Ide.Repo.Migrations.AddEmailAuthToUsers do
  use Ecto.Migration

  def up do
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

    create unique_index(:users, [:firebase_uid],
             where: "firebase_uid IS NOT NULL",
             name: :users_firebase_uid_index
           )

    create unique_index(:users, [:email], where: "email IS NOT NULL", name: :users_email_index)
  end

  def down do
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
end
