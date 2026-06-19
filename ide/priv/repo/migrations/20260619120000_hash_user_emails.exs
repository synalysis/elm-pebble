defmodule Ide.Repo.Migrations.HashUserEmails do
  use Ecto.Migration

  import Ecto.Query

  alias Ide.Auth.EmailHash

  def up do
    alter table(:users) do
      add :email_hash, :string
    end

    flush()
    backfill_email_hashes()

    case repo().__adapter__() do
      Ecto.Adapters.Postgres -> postgres_finalize()
      Ecto.Adapters.SQLite3 -> sqlite_finalize()
      adapter -> raise "unsupported repo adapter: #{inspect(adapter)}"
    end

    recreate_email_hash_indexes()
  end

  def down do
    raise "Irreversible migration: user emails were replaced with blind indexes"
  end

  defp backfill_email_hashes do
    repo = repo()

    rows =
      repo.all(
        from(u in "users",
          select: %{id: u.id, email: u.email},
          where: not is_nil(u.email)
        )
      )

    Enum.each(rows, fn %{id: id, email: email} ->
      hash = EmailHash.hash(email)

      repo.update_all(
        from(u in "users", where: u.id == ^id),
        set: [email_hash: hash]
      )
    end)
  end

  defp postgres_finalize do
    alter table(:users) do
      remove :email
    end
  end

  defp sqlite_finalize do
    execute(
      """
      CREATE TABLE users_email_hashed (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_uid TEXT,
        email_hash TEXT,
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
      INSERT INTO users_email_hashed (
        id, firebase_uid, email_hash, display_name, password_hash, inserted_at, updated_at
      )
      SELECT
        id, firebase_uid, email_hash, display_name, password_hash, inserted_at, updated_at
      FROM users
      """,
      ""
    )

    drop table(:users)
    execute("ALTER TABLE users_email_hashed RENAME TO users", "")
  end

  defp recreate_email_hash_indexes do
    drop_if_exists unique_index(:users, [:email], name: :users_email_index)
    drop_if_exists index(:users, [:email])

    create unique_index(:users, [:email_hash],
             where: "email_hash IS NOT NULL",
             name: :users_email_hash_index
           )
  end
end
