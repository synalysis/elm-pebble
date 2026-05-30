defmodule Ide.Projects.FileStore do
  @moduledoc """
  Filesystem operations scoped to an IDE project workspace.
  """

  alias Ide.Projects.FileTypes
  alias Ide.Projects.Project
  alias Ide.Projects.WorkspaceMerge

  @protected_delete_paths ~w(
    src/Main.elm
    src/Companion/Types.elm
    src/Companion/GeneratedPreferences.elm
    src/Pebble/Ui/Resources.elm
  )

  @protected_delete_dirs ~w(src)
  @hidden_directories MapSet.new([
                      "elm-stuff",
                      "node_modules",
                      "_build",
                      "deps",
                      ".git",
                      ".elm-pebble-github"
                    ])

  # Files hidden from the editor/MCP tree (platform bridge/codegen internals).
  @editor_hidden_rel_paths %{
    "protocol" =>
      MapSet.new([
        "src/Companion/Internal.elm",
        "src/Companion/Watch.elm"
      ]),
    "phone" =>
      MapSet.new([
        "src/Companion/Internal.elm",
        "src/Companion/Http.elm",
        "src/Engine.elm",
        "src/Pebble/Companion/AppMessage.elm"
      ])
  }

  @type tree_node :: FileTypes.tree_node()
  @type source_tree :: FileTypes.source_tree()

  @doc """
  Removes a project's workspace directory from disk, if present.
  """
  @spec remove_workspace(Project.t(), FileTypes.projects_root()) :: :ok
  def remove_workspace(project, projects_root) do
    _ = File.rm_rf(project_root(project, projects_root))
    :ok
  end

  @doc """
  Removes the on-disk workspace directory for a user account, if present.
  """
  @spec remove_user_workspace(integer(), FileTypes.projects_root()) :: :ok
  def remove_user_workspace(owner_id, projects_root) when is_integer(owner_id) do
    _ = File.rm_rf(user_workspace_root(owner_id, projects_root))
    :ok
  end

  @doc """
  Returns the on-disk workspace directory for a user account.
  """
  @spec user_workspace_root(integer(), FileTypes.projects_root()) :: FileTypes.workspace_path()
  def user_workspace_root(owner_id, projects_root) when is_integer(owner_id) do
    Path.join([projects_root, "users", Integer.to_string(owner_id)])
  end

  @doc """
  Ensures root folders exist for a project.
  """
  @spec ensure_roots(Project.t(), FileTypes.projects_root()) :: FileTypes.ensure_roots_result()
  def ensure_roots(project, projects_root) do
    root = project_root(project, projects_root)

    with :ok <- File.mkdir_p(root) do
      Enum.reduce_while(project.source_roots, :ok, fn source_root, :ok ->
        source_abs = Path.join(root, source_root)

        case File.mkdir_p(source_abs) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @doc """
  Returns tree nodes grouped by source root.
  """
  @spec list_tree(Project.t(), FileTypes.projects_root(), keyword()) :: source_tree()
  def list_tree(project, projects_root, opts \\ []) do
    hidden_by_root =
      Keyword.get(opts, :hidden_rel_paths_by_root, @editor_hidden_rel_paths)

    Enum.map(project.source_roots, fn source_root ->
      abs_root = Path.join(project_root(project, projects_root), source_root)
      hidden = Map.get(hidden_by_root, source_root, MapSet.new())

      %{
        source_root: source_root,
        nodes: tree_nodes(abs_root, "", hidden) |> prune_empty_dirs()
      }
    end)
  end

  @doc """
  Reads a file by root and relative path.
  """
  @spec read_file(Project.t(), FileTypes.projects_root(), String.t(), String.t()) ::
          FileTypes.read_result()
  def read_file(project, projects_root, source_root, rel_path) do
    with {:ok, absolute_path} <- safe_path(project, projects_root, source_root, rel_path) do
      File.read(absolute_path)
    end
  end

  @doc """
  Writes file contents, creating missing parent directories.
  """
  @spec write_file(Project.t(), FileTypes.projects_root(), String.t(), String.t(), iodata()) ::
          FileTypes.write_result()
  def write_file(project, projects_root, source_root, rel_path, contents) do
    with {:ok, absolute_path} <- safe_path(project, projects_root, source_root, rel_path),
         :ok <- File.mkdir_p(Path.dirname(absolute_path)) do
      File.write(absolute_path, contents)
    end
  end

  @doc """
  Renames a file inside a source root.
  """
  @spec rename_file(Project.t(), FileTypes.projects_root(), String.t(), String.t(), String.t()) ::
          FileTypes.rename_result()
  def rename_file(project, projects_root, source_root, old_rel_path, new_rel_path) do
    with {:ok, old_abs} <- safe_path(project, projects_root, source_root, old_rel_path),
         {:ok, new_abs} <- safe_path(project, projects_root, source_root, new_rel_path),
         :ok <- File.mkdir_p(Path.dirname(new_abs)) do
      File.rename(old_abs, new_abs)
    end
  end

  @doc """
  Deletes a file or directory by relative path.
  """
  @spec delete_path(Project.t(), FileTypes.projects_root(), String.t(), String.t()) ::
          FileTypes.delete_result()
  def delete_path(project, projects_root, source_root, rel_path) do
    with :ok <- validate_deletable(rel_path),
         {:ok, absolute_path} <- safe_path(project, projects_root, source_root, rel_path) do
      cond do
        File.dir?(absolute_path) -> File.rm_rf(absolute_path) |> normalize_rm_rf()
        true -> File.rm(absolute_path)
      end
    end
  end

  @doc """
  Returns an absolute path to the project workspace root.
  """
  @spec project_root(Project.t(), FileTypes.projects_root()) :: FileTypes.workspace_path()
  def project_root(%Project{owner_id: owner_id, slug: slug}, projects_root)
      when is_integer(owner_id) do
    scoped = Path.join([projects_root, "users", Integer.to_string(owner_id), slug])
    legacy = Path.join(projects_root, slug)

    _ = maybe_adopt_legacy_workspace(scoped, legacy)
    scoped
  end

  def project_root(%Project{slug: slug}, projects_root), do: Path.join(projects_root, slug)

  @doc """
  True when the workspace contains at least one Elm project root (`elm.json`).
  """
  @spec workspace_has_elm_roots?(FileTypes.workspace_path()) :: boolean()
  def workspace_has_elm_roots?(workspace_path) when is_binary(workspace_path) do
    Enum.any?(compiler_root_candidates(workspace_path), &elm_project_dir?/1)
  end

  @spec compiler_root_candidates(FileTypes.workspace_path()) :: [FileTypes.workspace_path()]
  def compiler_root_candidates(workspace_path) when is_binary(workspace_path) do
    [
      workspace_path,
      Path.join(workspace_path, "watch"),
      Path.join(workspace_path, "protocol"),
      Path.join(workspace_path, "phone")
    ]
  end

  @spec elm_project_dir?(FileTypes.workspace_path()) :: boolean()
  def elm_project_dir?(path) when is_binary(path),
    do: File.exists?(Path.join(path, "elm.json"))

  @spec maybe_adopt_legacy_workspace(FileTypes.workspace_path(), FileTypes.workspace_path()) ::
          :ok
  defp maybe_adopt_legacy_workspace(scoped, legacy) do
    cond do
      workspace_has_elm_roots?(scoped) ->
        :ok

      not workspace_has_elm_roots?(legacy) ->
        :ok

      workspace_has_user_artifacts?(scoped) ->
        # Do not merge a legacy tree over a scoped workspace that already has
        # project metadata or uploaded resources but lost Elm sources.
        :ok

      not File.dir?(legacy) ->
        :ok

      true ->
        File.mkdir_p(Path.dirname(scoped))

        case WorkspaceMerge.merge_tree(legacy, scoped) do
          :ok -> :ok
          {:error, _reason} -> :ok
        end
    end
  end

  @spec validate_deletable(String.t()) :: :ok | {:error, :protected_path}
  defp validate_deletable(rel_path) when is_binary(rel_path) do
    normalized =
      rel_path
      |> String.trim()
      |> String.trim_leading("./")
      |> String.replace("\\", "/")

    cond do
      normalized in @protected_delete_paths ->
        {:error, :protected_path}

      normalized in @protected_delete_dirs ->
        {:error, :protected_path}

      true ->
        :ok
    end
  end

  @spec workspace_has_user_artifacts?(FileTypes.workspace_path()) :: boolean()
  defp workspace_has_user_artifacts?(workspace_path) when is_binary(workspace_path) do
    File.exists?(Path.join(workspace_path, "elm-pebble.project.json")) or
      File.exists?(Path.join(workspace_path, "watch/resources/bitmaps.json")) or
      File.exists?(Path.join(workspace_path, "watch/resources/vectors.json")) or
      File.exists?(Path.join(workspace_path, "watch/resources/fonts.json"))
  end

  @spec safe_path(Project.t(), FileTypes.projects_root(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, FileTypes.path_error()}
  defp safe_path(project, projects_root, source_root, rel_path) do
    if source_root in project.source_roots do
      source_base = Path.join(project_root(project, projects_root), source_root)
      expanded = Path.expand(rel_path, source_base)
      allowed_prefix = source_base <> "/"

      if expanded == source_base or String.starts_with?(expanded, allowed_prefix) do
        {:ok, expanded}
      else
        {:error, :invalid_path}
      end
    else
      {:error, :invalid_source_root}
    end
  end

  @spec tree_nodes(String.t(), String.t(), MapSet.t(String.t())) :: [tree_node()]
  defp tree_nodes(abs_dir, parent_rel, hidden) do
    case File.ls(abs_dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.reject(&hidden_entry?(abs_dir, &1))
        |> Enum.map(fn entry ->
          rel_path = rel_join(parent_rel, entry)
          full_path = Path.join(abs_dir, entry)

          cond do
            File.dir?(full_path) ->
              %{
                type: :dir,
                name: entry,
                rel_path: rel_path,
                children: tree_nodes(full_path, rel_path, hidden)
              }

            MapSet.member?(hidden, rel_path) ->
              nil

            true ->
              %{type: :file, name: entry, rel_path: rel_path, children: []}
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _reason} ->
        []
    end
  end

  @spec prune_empty_dirs([tree_node()]) :: [tree_node()]
  defp prune_empty_dirs(nodes) when is_list(nodes) do
    nodes
    |> Enum.map(fn
      %{type: :dir, children: children} = dir ->
        pruned = prune_empty_dirs(children)
        %{dir | children: pruned}

      other ->
        other
    end)
    |> Enum.reject(fn
      %{type: :dir, children: []} -> true
      _ -> false
    end)
  end

  @spec rel_join(String.t(), String.t()) :: String.t()
  defp rel_join("", segment), do: segment
  defp rel_join(parent, segment), do: Path.join(parent, segment)

  @spec normalize_rm_rf({:ok, [String.t()]} | {:error, File.posix(), String.t()}) ::
          :ok | {:error, File.posix()}
  defp normalize_rm_rf({:ok, _paths}), do: :ok
  defp normalize_rm_rf({:error, reason, _path}), do: {:error, reason}

  @spec hidden_entry?(String.t(), String.t()) :: boolean()
  defp hidden_entry?(abs_dir, entry) do
    full_path = Path.join(abs_dir, entry)
    File.dir?(full_path) and MapSet.member?(@hidden_directories, entry)
  end
end
