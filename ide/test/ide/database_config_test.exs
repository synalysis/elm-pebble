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

  test "postgres release parses DATABASE_URL without ssl by default" do
    System.put_env("DATABASE_URL", "postgres://ide:ide@db:5432/ide_prod")

    config = DatabaseConfig.prod_repo_config(Ecto.Adapters.Postgres)

    assert config[:database] == "ide_prod"
    assert config[:username] == "ide"
    assert config[:password] == "ide"
    assert config[:hostname] == "db"
    assert config[:port] == 5432
    assert config[:pool_size] == 7
    assert config[:priv] == "priv/repo"
    refute Keyword.has_key?(config, :url)
    refute Keyword.has_key?(config, :ssl)
  end

  test "postgres release strips ssl=true from DATABASE_URL unless DATABASE_SSL is set" do
    System.put_env("DATABASE_URL", "postgres://ide:ide@db:5432/ide_prod?ssl=true")

    config = DatabaseConfig.prod_repo_config(Ecto.Adapters.Postgres)

    refute Keyword.has_key?(config, :ssl)
  end

  test "postgres release enables ssl when DATABASE_SSL is set" do
    System.put_env("DATABASE_URL", "postgres://ide:ide@db:5432/ide_prod")
    System.put_env("DATABASE_SSL", "true")

    config = DatabaseConfig.prod_repo_config(Ecto.Adapters.Postgres)

    assert config[:database] == "ide_prod"
    assert Keyword.has_key?(config, :ssl)
  end

  test "postgres release disables ssl when DATABASE_SSL=false" do
    System.put_env("DATABASE_URL", "postgres://ide:ide@db:5432/ide_prod?ssl=true")
    System.put_env("DATABASE_SSL", "false")

    assert DatabaseConfig.prod_repo_config(Ecto.Adapters.Postgres)[:ssl] == false
  end
end
