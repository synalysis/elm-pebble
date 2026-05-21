defmodule Ide.RepoConfig do
  @moduledoc false

  alias Ide.DatabaseConfig
  alias Ide.RepoSelector

  @doc """
  Normalizes repo configuration for storage/migration helpers.

  Expands `DATABASE_URL` into adapter fields expected by `storage_up/1`.
  """
  @spec storage_config(module()) :: keyword()
  def storage_config(repo) when is_atom(repo) do
    repo
    |> repo_config()
    |> expand_url_config()
  end

  @doc """
  Ensures repo runtime configuration is present in `Application` env.

  Release `eval` can run before repo config from `runtime.exs` is visible on
  the repo module, so setup/migration code rebuilds it from environment vars.
  """
  @spec put_runtime_repo_config!() :: module()
  def put_runtime_repo_config! do
    repo = RepoSelector.repo()
    adapter = RepoSelector.adapter()
    config = DatabaseConfig.prod_repo_config(adapter)

    Application.put_env(:ide, :ecto_repos, [repo])
    Application.put_env(:ide, :repo_module, repo)
    Application.put_env(:ide, :ecto_adapter, adapter)
    Application.put_env(:ide, repo, config)

    repo
  end

  @spec repo_config(module()) :: keyword()
  defp repo_config(repo) do
    base =
      case Application.fetch_env(:ide, repo) do
        {:ok, config} when is_list(config) -> config
        _ -> []
      end

    if storage_ready?(base) do
      base
    else
      Keyword.merge(base, DatabaseConfig.prod_repo_config(adapter_for(repo)))
    end
  end

  @spec expand_url_config(keyword()) :: keyword()
  defp expand_url_config(config) do
    url_config = Ecto.Repo.Supervisor.parse_url(Keyword.get(config, :url, ""))
    Keyword.merge(url_config, config)
  end

  @spec storage_ready?(keyword()) :: boolean()
  defp storage_ready?(config) do
    Keyword.has_key?(config, :database) or Keyword.has_key?(config, :url)
  end

  @spec adapter_for(module()) :: module()
  defp adapter_for(Ide.Repo.Postgres), do: Ecto.Adapters.Postgres
  defp adapter_for(Ide.Repo.Sqlite), do: Ecto.Adapters.SQLite3

  defp adapter_for(repo) do
    raise ArgumentError, "unknown repo module #{inspect(repo)}"
  end
end
