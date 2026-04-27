defmodule Ide.GitHub.Push do
  @moduledoc false

  alias Ide.GitHub.Credentials
  alias Ide.Projects
  alias Ide.Projects.Project

  @spec push_project_snapshot(Project.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def push_project_snapshot(%Project{} = project, repo_config, opts \\ []) do
    with {:ok, token} <- fetch_access_token(),
         {:ok, owner} <- fetch_repo_value(repo_config, "owner"),
         {:ok, repo} <- fetch_repo_value(repo_config, "repo"),
         branch <- fetch_branch(repo_config),
         workspace_root <- Projects.project_workspace_path(project),
         {:ok, temp_dir} <- create_temp_dir(project.slug),
         :ok <- copy_workspace(workspace_root, temp_dir),
         :ok <- initialize_repo(temp_dir, branch, opts),
         :ok <- push_repo(temp_dir, token, owner, repo, branch),
         {:ok, commit_sha} <- read_commit_sha(temp_dir) do
      {:ok,
       %{
         branch: branch,
         owner: owner,
         repo: repo,
         commit_sha: commit_sha,
         remote_url: "https://github.com/#{owner}/#{repo}"
       }}
    end
  end

  @spec fetch_access_token() :: {:ok, String.t()} | {:error, :github_not_connected}
  defp fetch_access_token do
    case Credentials.access_token() do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :github_not_connected}
    end
  end

  @spec fetch_repo_value(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp fetch_repo_value(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))

    case value do
      str when is_binary(str) ->
        trimmed = String.trim(str)
        if trimmed == "", do: {:error, {:missing_repo_field, key}}, else: {:ok, trimmed}

      _ ->
        {:error, {:missing_repo_field, key}}
    end
  end

  defp fetch_repo_value(_map, key), do: {:error, {:missing_repo_field, key}}

  @spec fetch_branch(map()) :: String.t()
  defp fetch_branch(map) when is_map(map) do
    branch = Map.get(map, "branch") || Map.get(map, :branch) || "main"
    trimmed = if is_binary(branch), do: String.trim(branch), else: ""
    if trimmed == "", do: "main", else: trimmed
  end

  @spec create_temp_dir(String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  defp create_temp_dir(slug) do
    prefix = if is_binary(slug) and slug != "", do: slug, else: "project"

    path =
      Path.join(
        System.tmp_dir!(),
        "ide-github-push-#{prefix}-#{System.unique_integer([:positive])}"
      )

    case File.mkdir_p(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec copy_workspace(String.t(), String.t()) :: :ok | {:error, term()}
  defp copy_workspace(workspace_root, target_root) do
    case File.cp_r(workspace_root, target_root) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  @spec initialize_repo(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  defp initialize_repo(path, branch, opts) do
    commit_message = Keyword.get(opts, :commit_message, "Snapshot from Elm Pebble IDE")

    with :ok <- run_git(path, ["init"]),
         :ok <- run_git(path, ["checkout", "-B", branch]),
         :ok <- run_git(path, ["add", "."]),
         :ok <-
           run_git(path, ["commit", "-m", commit_message],
             env: [
               {"GIT_AUTHOR_NAME", "Elm Pebble IDE"},
               {"GIT_AUTHOR_EMAIL", "ide@elm-pebble.local"},
               {"GIT_COMMITTER_NAME", "Elm Pebble IDE"},
               {"GIT_COMMITTER_EMAIL", "ide@elm-pebble.local"}
             ]
           ) do
      :ok
    end
  end

  @spec push_repo(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  defp push_repo(path, token, owner, repo, branch) do
    remote_url =
      "https://x-access-token:#{URI.encode_www_form(token)}@github.com/#{owner}/#{repo}.git"

    with :ok <- run_git(path, ["push", remote_url, "HEAD:#{branch}"]) do
      :ok
    end
  end

  @spec read_commit_sha(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp read_commit_sha(path) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: path, stderr_to_stdout: true) do
      {sha, 0} -> {:ok, String.trim(sha)}
      {output, _} -> {:error, {:git_failed, "rev-parse HEAD", String.trim(output)}}
    end
  end

  @spec run_git(String.t(), [String.t()], keyword()) :: :ok | {:error, term()}
  defp run_git(path, args, opts \\ []) do
    cmd_opts =
      [cd: path, stderr_to_stdout: true]
      |> Keyword.merge(opts)

    case System.cmd("git", args, cmd_opts) do
      {_output, 0} ->
        :ok

      {output, _status} ->
        {:error, {:git_failed, Enum.join(args, " "), String.trim(output)}}
    end
  end
end
