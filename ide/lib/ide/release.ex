defmodule Ide.Release do
  @moduledoc false

  require Logger

  alias Ide.RepoConfig

  @app :ide

  @doc """
  Creates repo storage (if needed) and runs migrations.
  """
  @spec setup() :: :ok
  def setup do
    load_app()
    create()
    migrate()
    :ok
  end

  @doc """
  Creates repo storage when missing (`mix ecto.create` equivalent for releases).
  """
  @spec create() :: :ok
  def create do
    load_app()

    for repo <- repos() do
      ensure_storage!(repo)
    end

    :ok
  end

  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end

    :ok
  end

  @spec ensure_storage!(module()) :: :ok
  defp ensure_storage!(repo) do
    adapter = repo.__adapter__()

    unless Code.ensure_loaded?(adapter) and function_exported?(adapter, :storage_up, 1) do
      :ok
    else
      config = RepoConfig.storage_config(repo)

      case adapter.storage_up(config) do
        :ok ->
          Logger.info("[Ide.Release] Created database storage for #{inspect(repo)}")
          :ok

        {:error, :already_up} ->
          :ok

        {:error, reason} when is_binary(reason) ->
          raise storage_error(repo, reason)

        {:error, reason} ->
          raise storage_error(repo, inspect(reason))
      end
    end
  end

  @spec storage_error(module(), String.t()) :: Exception.t()
  defp storage_error(repo, detail) do
    RuntimeError.exception("""
    Could not create database storage for #{inspect(repo)}.

    #{detail}

    If you use managed Postgres, create the database manually and ensure DATABASE_URL points at it.
    The database user also needs permission to connect to the maintenance database (usually "postgres")
    when auto-create is required.
    """)
  end

  @spec repos() :: [module()]
  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  @spec load_app() :: :ok
  defp load_app do
    Application.load(@app)
    :ok
  end
end
