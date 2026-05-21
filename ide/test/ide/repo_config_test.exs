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
end
