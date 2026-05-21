defmodule Ide.DatabaseConfig do
  @moduledoc false

  @postgres Ecto.Adapters.Postgres
  @sqlite Ecto.Adapters.SQLite3

  @spec prod_repo_config(module()) :: keyword()
  def prod_repo_config(@postgres) do
    case blank_to_nil(System.get_env("DATABASE_URL")) do
      url when is_binary(url) ->
        [url: url, pool_size: pool_size()] ++ ssl_options()

      _ ->
        raise """
        DATABASE_URL is required when this release was built with IDE_REPO_ADAPTER=postgres.

        Example:
          DATABASE_URL=postgres://ide:ide@db:5432/ide_prod
        """
    end
  end

  def prod_repo_config(@sqlite) do
    if url = blank_to_nil(System.get_env("DATABASE_URL")) do
      raise """
      DATABASE_URL is set but this release uses SQLite.

      Remove DATABASE_URL or rebuild the image with IDE_REPO_ADAPTER=postgres.
      Current value: #{url}
      """
    end

    data_root = System.get_env("IDE_DATA_ROOT") || "/var/lib/ide"

    database_path =
      System.get_env("DATABASE_PATH") || Path.join(data_root, "ide_prod.db")

    [database: database_path, pool_size: pool_size()]
  end

  def prod_repo_config(adapter) do
    raise "Unsupported repo adapter: #{inspect(adapter)}"
  end

  @spec pool_size() :: pos_integer()
  defp pool_size do
    System.get_env("POOL_SIZE", "10") |> String.to_integer()
  end

  @spec ssl_options() :: keyword()
  defp ssl_options do
    case System.get_env("DATABASE_SSL") do
      value when value in ~w(true 1 yes) -> [ssl: true]
      _ -> []
    end
  end

  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
