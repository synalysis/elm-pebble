defmodule Ide.Repo.Migrations.DeferLoginTokenUsers do
  use Ecto.Migration

  def up do
    alter table(:login_tokens) do
      add :email_hash, :string
    end

    case repo().__adapter__() do
      Ecto.Adapters.Postgres ->
        alter table(:login_tokens) do
          modify :user_id, references(:users, on_delete: :delete_all),
            null: true,
            from: references(:users, on_delete: :delete_all)
        end

      Ecto.Adapters.SQLite3 ->
        sqlite_make_user_id_nullable()

      adapter ->
        raise "unsupported repo adapter: #{inspect(adapter)}"
    end

    create index(:login_tokens, [:email_hash])
  end

  def down do
    drop_if_exists index(:login_tokens, [:email_hash])

    execute("DELETE FROM login_tokens WHERE user_id IS NULL")

    case repo().__adapter__() do
      Ecto.Adapters.Postgres ->
        alter table(:login_tokens) do
          modify :user_id, references(:users, on_delete: :delete_all),
            null: false,
            from: references(:users, on_delete: :delete_all)

          remove :email_hash
        end

      Ecto.Adapters.SQLite3 ->
        sqlite_restore_user_id_required()

      adapter ->
        raise "unsupported repo adapter: #{inspect(adapter)}"
    end
  end

  defp sqlite_make_user_id_nullable do
    execute(
      """
      CREATE TABLE login_tokens_deferred (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        email_hash TEXT,
        token_hash TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        used_at TEXT,
        inserted_at TEXT NOT NULL
      )
      """,
      ""
    )

    execute(
      """
      INSERT INTO login_tokens_deferred (
        id, user_id, email_hash, token_hash, expires_at, used_at, inserted_at
      )
      SELECT id, user_id, NULL, token_hash, expires_at, used_at, inserted_at
      FROM login_tokens
      """,
      ""
    )

    drop table(:login_tokens)
    execute("ALTER TABLE login_tokens_deferred RENAME TO login_tokens", "")

    create index(:login_tokens, [:user_id])
    create unique_index(:login_tokens, [:token_hash])
    create index(:login_tokens, [:expires_at])
  end

  defp sqlite_restore_user_id_required do
    execute(
      """
      CREATE TABLE login_tokens_legacy (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token_hash TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        used_at TEXT,
        inserted_at TEXT NOT NULL
      )
      """,
      ""
    )

    execute(
      """
      INSERT INTO login_tokens_legacy (
        id, user_id, token_hash, expires_at, used_at, inserted_at
      )
      SELECT id, user_id, token_hash, expires_at, used_at, inserted_at
      FROM login_tokens
      WHERE user_id IS NOT NULL
      """,
      ""
    )

    drop table(:login_tokens)
    execute("ALTER TABLE login_tokens_legacy RENAME TO login_tokens", "")

    create index(:login_tokens, [:user_id])
    create unique_index(:login_tokens, [:token_hash])
    create index(:login_tokens, [:expires_at])
  end
end
