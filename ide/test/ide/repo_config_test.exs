defmodule Ide.RepoConfigTest do
  use ExUnit.Case, async: true

  alias Ide.RepoConfig

  test "storage_config expands DATABASE_URL fields" do
    Application.put_env(:ide, Ide.Repo.Postgres,
      url: "postgres://ide:secret@db.example.test:5432/ide_prod",
      pool_size: 5
    )

    config = RepoConfig.storage_config(Ide.Repo.Postgres)

    assert config[:database] == "ide_prod"
    assert config[:username] == "ide"
    assert config[:password] == "secret"
    assert config[:hostname] == "db.example.test"
    assert config[:port] == 5432
    assert config[:pool_size] == 5
  end

  test "storage_config rebuilds from env when repo only has priv" do
    original_url = System.get_env("DATABASE_URL")
    original_adapter = System.get_env("IDE_REPO_ADAPTER")

    on_exit(fn ->
      restore_env("DATABASE_URL", original_url)
      restore_env("IDE_REPO_ADAPTER", original_adapter)
    end)

    System.put_env("IDE_REPO_ADAPTER", "postgres")
    System.put_env("DATABASE_URL", "postgres://ide:secret@db.example.test:5432/ide_prod")
    Application.put_env(:ide, Ide.Repo.Postgres, priv: "priv/repo")

    config = RepoConfig.storage_config(Ide.Repo.Postgres)

    assert config[:database] == "ide_prod"
    assert config[:hostname] == "db.example.test"
    assert config[:priv] == "priv/repo"
    refute Keyword.has_key?(config, :ssl)
  end

  test "put_runtime_repo_config! writes repo env from DATABASE_URL" do
    original_url = System.get_env("DATABASE_URL")
    original_adapter = System.get_env("IDE_REPO_ADAPTER")

    on_exit(fn ->
      restore_env("DATABASE_URL", original_url)
      restore_env("IDE_REPO_ADAPTER", original_adapter)
    end)

    System.put_env("IDE_REPO_ADAPTER", "postgres")
    System.put_env("DATABASE_URL", "postgres://ide:secret@db.example.test:5432/ide_prod")

    assert Ide.Repo.Postgres = RepoConfig.put_runtime_repo_config!()

    assert Application.fetch_env!(:ide, Ide.Repo.Postgres)[:database] == "ide_prod"
    refute Keyword.has_key?(Application.fetch_env!(:ide, Ide.Repo.Postgres), :url)
  end

  test "configured? is false when repo env only contains priv" do
    Application.put_env(:ide, Ide.Repo.Postgres, priv: "priv/repo")
    refute RepoConfig.configured?(Ide.Repo.Postgres)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
