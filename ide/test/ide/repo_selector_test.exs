defmodule Ide.RepoSelectorTest do
  use ExUnit.Case, async: false

  alias Ide.RepoSelector

  setup do
    original = System.get_env("IDE_REPO_ADAPTER")
    original_url = System.get_env("DATABASE_URL")

    on_exit(fn ->
      restore_env("IDE_REPO_ADAPTER", original)
      restore_env("DATABASE_URL", original_url)
    end)

    :ok
  end

  test "postgres when IDE_REPO_ADAPTER=postgres" do
    System.put_env("IDE_REPO_ADAPTER", "postgres")
    System.delete_env("DATABASE_URL")

    assert RepoSelector.adapter() == Ecto.Adapters.Postgres
    assert RepoSelector.repo() == Ide.Repo.Postgres
  end

  test "sqlite when IDE_REPO_ADAPTER=sqlite" do
    System.put_env("IDE_REPO_ADAPTER", "sqlite")
    System.put_env("DATABASE_URL", "postgres://example.test/ide")

    assert RepoSelector.adapter() == Ecto.Adapters.SQLite3
    assert RepoSelector.repo() == Ide.Repo.Sqlite
  end

  test "infers postgres from DATABASE_URL when IDE_REPO_ADAPTER is unset" do
    System.delete_env("IDE_REPO_ADAPTER")
    System.put_env("DATABASE_URL", "postgres://ide:ide@db:5432/ide_prod")

    assert RepoSelector.adapter() == Ecto.Adapters.Postgres
    assert RepoSelector.repo() == Ide.Repo.Postgres
  end

  test "defaults to sqlite without DATABASE_URL" do
    System.delete_env("IDE_REPO_ADAPTER")
    System.delete_env("DATABASE_URL")

    assert RepoSelector.adapter() == Ecto.Adapters.SQLite3
    assert RepoSelector.repo() == Ide.Repo.Sqlite
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
