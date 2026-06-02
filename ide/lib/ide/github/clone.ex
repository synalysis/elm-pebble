defmodule Ide.GitHub.Clone do
  @moduledoc false

  alias Ide.GitHub.{Credentials, Types}

  @spec clone(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Types.clone_error()}
  def clone(owner, repo, branch, opts \\ []) do
    owner = String.trim(owner)
    repo = String.trim(repo)
    branch = branch |> to_string() |> String.trim()
    branch = if branch == "", do: "main", else: branch

    with :ok <- validate_segment(owner, "owner"),
         :ok <- validate_segment(repo, "repo"),
         {:ok, token} <- fetch_token(),
         {:ok, dest} <- create_temp_dir(repo),
         :ok <- run_clone(dest, clone_url(token, owner, repo), branch, opts) do
      {:ok, dest}
    end
  end

  @doc false
  @spec parse_repo_ref(String.t()) :: {:ok, map()} | {:error, Types.clone_error()}
  def parse_repo_ref(ref) when is_binary(ref) do
    ref = String.trim(ref)

    cond do
      ref == "" ->
        {:error, :empty_repo_ref}

      String.starts_with?(ref, "https://github.com/") or
          String.starts_with?(ref, "http://github.com/") ->
        parse_github_url(ref)

      String.starts_with?(ref, "git@github.com:") ->
        parse_git_ssh_url(ref)

      String.contains?(ref, "/") ->
        case String.split(ref, "/", parts: 2) do
          [owner, repo] ->
            {:ok, %{owner: owner, repo: strip_repo_suffix(repo), branch: "main"}}

          _ ->
            {:error, :invalid_repo_ref}
        end

      true ->
        {:error, :invalid_repo_ref}
    end
  end

  def parse_repo_ref(_), do: {:error, :invalid_repo_ref}

  @spec parse_github_url(String.t()) :: {:ok, map()} | {:error, :invalid_repo_ref}
  defp parse_github_url(url) do
    uri = URI.parse(url)
    segments = uri.path |> to_string() |> String.trim("/") |> String.split("/", trim: true)

    case segments do
      [owner, repo | _] ->
        {:ok, %{owner: owner, repo: strip_repo_suffix(repo), branch: "main"}}

      _ ->
        {:error, :invalid_repo_ref}
    end
  end

  @spec parse_git_ssh_url(String.t()) :: {:ok, map()} | {:error, :invalid_repo_ref}
  defp parse_git_ssh_url(url) do
    case String.split(url, ":", parts: 2) do
      ["git@github.com", path] ->
        case String.split(path, "/", trim: true) do
          [owner, repo | _] ->
            {:ok, %{owner: owner, repo: strip_repo_suffix(repo), branch: "main"}}

          _ ->
            {:error, :invalid_repo_ref}
        end

      _ ->
        {:error, :invalid_repo_ref}
    end
  end

  @spec strip_repo_suffix(String.t()) :: String.t()
  defp strip_repo_suffix(repo) do
    repo
    |> String.trim()
    |> String.trim_trailing(".git")
  end

  @spec validate_segment(String.t(), String.t()) :: :ok | {:error, Types.repo_field_error()}
  defp validate_segment(value, label) do
    if value != "" and Path.basename(value) == value and not String.contains?(value, "/") do
      :ok
    else
      {:error, {:invalid_repo_field, label}}
    end
  end

  @spec fetch_token() :: {:ok, String.t()} | {:error, :github_not_connected}
  defp fetch_token do
    case Credentials.access_token() do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :github_not_connected}
    end
  end

  @spec clone_url(String.t(), String.t(), String.t()) :: String.t()
  defp clone_url(token, owner, repo) do
    "https://x-access-token:#{URI.encode_www_form(token)}@github.com/#{owner}/#{repo}.git"
  end

  @spec create_temp_dir(String.t()) :: {:ok, String.t()} | {:error, File.posix()}
  defp create_temp_dir(repo) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ide-github-clone-#{repo}-#{System.unique_integer([:positive])}"
      )

    case File.mkdir_p(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec run_clone(String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, Types.git_error()}
  defp run_clone(dest, url, branch, opts) do
    args =
      if Keyword.get(opts, :full_clone, false) do
        ["clone", "--branch", branch, url, dest]
      else
        ["clone", "--depth", "1", "--branch", branch, "--single-branch", url, dest]
      end

    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _} -> {:error, {:git_failed, "clone", String.trim(output)}}
    end
  end
end
