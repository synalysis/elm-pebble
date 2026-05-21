defmodule Ide.RepoSelector do
  @moduledoc false

  @postgres Ecto.Adapters.Postgres
  @sqlite Ecto.Adapters.SQLite3

  @doc """
  Resolves the active Ecto adapter from runtime environment.

  `IDE_REPO_ADAPTER` is read at runtime (not only at image build time).
  When unset, Postgres is selected if `DATABASE_URL` is present, otherwise SQLite.
  """
  @spec adapter() :: module()
  def adapter do
    case normalized_adapter_env() do
      "postgres" -> @postgres
      "sqlite" -> @sqlite
      nil -> infer_adapter()
      other -> raise unknown_adapter_error(other)
    end
  end

  @spec repo() :: module()
  def repo do
    case adapter() do
      @postgres -> Ide.Repo.Postgres
      @sqlite -> Ide.Repo.Sqlite
    end
  end

  @spec infer_adapter() :: module()
  def infer_adapter do
    if present?(System.get_env("DATABASE_URL")) do
      @postgres
    else
      @sqlite
    end
  end

  @spec normalized_adapter_env() :: String.t() | nil
  defp normalized_adapter_env do
    case System.get_env("IDE_REPO_ADAPTER") do
      value when value in ~w(postgres postgresql) -> "postgres"
      value when value in ~w(sqlite sqlite3) -> "sqlite"
      nil -> nil
      value -> value |> String.trim() |> String.downcase()
    end
  end

  @spec unknown_adapter_error(String.t()) :: Exception.t()
  defp unknown_adapter_error(value) do
    RuntimeError.exception("""
    IDE_REPO_ADAPTER=#{inspect(value)} is not supported.

    Supported values: postgres, sqlite
    Or unset IDE_REPO_ADAPTER and use DATABASE_URL for Postgres / DATABASE_PATH for SQLite.
    """)
  end

  @spec present?(String.t() | nil) :: boolean()
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
