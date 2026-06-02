defmodule Ide.DatabaseConfig do
  @moduledoc false

  @postgres Ecto.Adapters.Postgres
  @sqlite Ecto.Adapters.SQLite3

  @spec prod_repo_config(module()) :: keyword()
  def prod_repo_config(@postgres) do
    case blank_to_nil(System.get_env("DATABASE_URL")) do
      url when is_binary(url) ->
        url
        |> Ecto.Repo.Supervisor.parse_url()
        |> apply_database_ssl_settings()
        |> Keyword.merge(pool_size: pool_size(), priv: "priv/repo")

      _ ->
        raise """
        DATABASE_URL is required when using Postgres (IDE_REPO_ADAPTER=postgres or DATABASE_URL set).

        Example:
          DATABASE_URL=postgres://ide:ide@db:5432/ide_prod
        """
    end
  end

  def prod_repo_config(@sqlite) do
    if url = blank_to_nil(System.get_env("DATABASE_URL")) do
      raise """
      DATABASE_URL is set but IDE_REPO_ADAPTER=sqlite (or inferred SQLite).

      Unset DATABASE_URL, or set IDE_REPO_ADAPTER=postgres to use Postgres.
      Current value: #{url}
      """
    end

    data_root = System.get_env("IDE_DATA_ROOT") || "/var/lib/ide"

    database_path =
      System.get_env("DATABASE_PATH") || Path.join(data_root, "ide_prod.db")

    [database: database_path, pool_size: pool_size(), priv: "priv/repo"]
  end

  def prod_repo_config(adapter) do
    raise "Unsupported repo adapter: #{inspect(adapter)}"
  end

  @doc """
  Normalizes repo config that may still contain a `:url` or stale `:ssl` flag.
  """
  @spec normalize_postgres_config(keyword()) :: keyword()
  def normalize_postgres_config(config) when is_list(config) do
    config
    |> expand_url_fields()
    |> apply_database_ssl_settings()
  end

  @spec pool_size() :: pos_integer()
  defp pool_size do
    System.get_env("POOL_SIZE", "10") |> String.to_integer()
  end

  @spec apply_database_ssl_settings(keyword()) :: keyword()
  defp apply_database_ssl_settings(config) do
    case database_ssl_mode() do
      :require ->
        Keyword.put(config, :ssl, ssl_connect_options())

      :disable ->
        Keyword.put(config, :ssl, false)

      :off ->
        Keyword.delete(config, :ssl)
    end
  end

  @spec database_ssl_mode() :: :require | :disable | :off
  defp database_ssl_mode do
    case System.get_env("DATABASE_SSL") do
      value when value in ~w(true 1 yes require) -> :require
      value when value in ~w(false 0 no disable) -> :disable
      _ -> :off
    end
  end

  @spec ssl_connect_options() :: keyword()
  defp ssl_connect_options do
    case :public_key.cacerts_get() do
      cacerts when is_list(cacerts) and cacerts != [] ->
        [verify: :verify_peer, cacerts: cacerts]

      _ ->
        case default_cacertfile() do
          nil -> [verify: :verify_none]
          path -> [verify: :verify_peer, cacertfile: path]
        end
    end
  end

  @spec default_cacertfile() :: String.t() | nil
  defp default_cacertfile do
    Enum.find(
      [
        "/etc/ssl/cert.pem",
        "/etc/pki/tls/certs/ca-bundle.crt",
        "/etc/ssl/certs/ca-certificates.crt"
      ],
      &File.regular?/1
    )
  end

  @spec expand_url_fields(keyword()) :: keyword()
  defp expand_url_fields(config) do
    case Keyword.get(config, :url) do
      url when is_binary(url) ->
        config
        |> Keyword.delete(:url)
        |> Keyword.merge(Ecto.Repo.Supervisor.parse_url(url))

      _ ->
        config
    end
  end

  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
