defmodule Ide.DatabaseConfigTest do
  use ExUnit.Case, async: false

  alias Ide.DatabaseConfig

  setup do
    original_env = for key <- ~w(DATABASE_URL DATABASE_PATH IDE_DATA_ROOT DATABASE_SSL POOL_SIZE) do
      {key, System.get_env(key)}
    end

    on_exit(fn ->
      Enum.each(original_env, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    System.delete_env("DATABASE_URL")
    System.put_env("IDE_DATA_ROOT", "/tmp/ide-data")
    System.delete_env("DATABASE_PATH")
    System.delete_env("DATABASE_SSL")
    System.put_env("POOL_SIZE", "7")

    :ok
  end

  test "sqlite release uses DATABASE_PATH under IDE_DATA_ROOT" do
    assert [database: "/tmp/ide-data/ide_prod.db", pool_size: 7, priv: "priv/repo"] ==
             DatabaseConfig.prod_repo_config(Ecto.Adapters.SQLite3)
  end

  test "sqlite release rejects DATABASE_URL" do
    System.put_env("DATABASE_URL", "postgres://example.test/ide")

    assert_raise RuntimeError, ~r/DATABASE_URL is set but IDE_REPO_ADAPTER=sqlite/, fn ->
      DatabaseConfig.prod_repo_config(Ecto.Adapters.SQLite3)
    end
  end

  test "postgres release requires DATABASE_URL" do
    assert_raise RuntimeError, ~r/DATABASE_URL is required/, fn ->
      DatabaseConfig.prod_repo_config(Ecto.Adapters.Postgres)
    end
  end

  test "postgres release accepts DATABASE_URL" do
    System.put_env("DATABASE_URL", "postgres://ide:ide@db:5432/ide_prod")

    assert [url: "postgres://ide:ide@db:5432/ide_prod", pool_size: 7, priv: "priv/repo"] ==
             DatabaseConfig.prod_repo_config(Ecto.Adapters.Postgres)
  end

  test "postgres release enables ssl when DATABASE_SSL is set" do
    System.put_env("DATABASE_URL", "postgres://ide:ide@db:5432/ide_prod")
    System.put_env("DATABASE_SSL", "true")

    assert [url: "postgres://ide:ide@db:5432/ide_prod", pool_size: 7, priv: "priv/repo", ssl: true] ==
             DatabaseConfig.prod_repo_config(Ecto.Adapters.Postgres)
  end
end
