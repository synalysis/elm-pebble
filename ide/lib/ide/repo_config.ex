defmodule Ide.RepoConfig do
  @moduledoc false

  @doc """
  Normalizes repo configuration for storage/migration helpers.

  Expands `DATABASE_URL` into adapter fields expected by `storage_up/1`.
  """
  @spec storage_config(module()) :: keyword()
  def storage_config(repo) when is_atom(repo) do
    config = Application.fetch_env!(:ide, repo)
    url_config = Ecto.Repo.Supervisor.parse_url(Keyword.get(config, :url, ""))
    Keyword.merge(url_config, config)
  end
end
