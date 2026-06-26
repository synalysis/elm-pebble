defmodule Ide.Paths do
  @moduledoc false

  @app :ide

  @spec priv_dir() :: String.t()
  def priv_dir do
    case Application.get_env(@app, __MODULE__, []) |> Keyword.get(:priv_dir) do
      dir when is_binary(dir) -> dir
      _ -> :code.priv_dir(@app)
    end
  end

  @spec priv_path(String.t()) :: String.t()
  def priv_path(relative) when is_binary(relative), do: Path.join(priv_dir(), relative)

  @spec repo_root() :: String.t()
  def repo_root do
    Application.get_env(@app, __MODULE__, [])
    |> Keyword.get(:repo_root, default_repo_root())
  end

  @doc """
  Prefer Elm sources vendored under `priv/bundled_elm` (release/Docker), else repo checkout paths (dev).
  """
  @spec bundled_elm_path(String.t(), String.t()) :: String.t()
  def bundled_elm_path(bundled_relative, repo_relative)
      when is_binary(bundled_relative) and is_binary(repo_relative) do
    bundled = priv_path(Path.join("bundled_elm", bundled_relative))

    if File.exists?(bundled) do
      bundled
    else
      Path.join(repo_root(), repo_relative)
    end
  end

  defp default_repo_root do
    Path.expand("../../..", __DIR__)
  end
end
