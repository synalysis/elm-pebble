defmodule Ide.Projects.FileStore do
  @moduledoc """
  Filesystem operations scoped to an IDE project workspace.
  """

  alias Ide.Projects.Project
  @hidden_directories MapSet.new(["elm-stuff", "node_modules", "_build", "deps", ".git"])

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

  @type tree_node ::
          %{
            type: :file | :dir,
            name: String.t(),
            rel_path: String.t(),
            children: [tree_node()]
          }

  @doc """
  Ensures root folders exist for a project.
  """
  @spec ensure_roots(term(), term()) :: term()
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
  @spec list_tree(term(), term(), term()) :: term()
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
  @spec read_file(term(), term(), term(), term()) :: term()
  def read_file(project, projects_root, source_root, rel_path) do
    with {:ok, absolute_path} <- safe_path(project, projects_root, source_root, rel_path) do
      File.read(absolute_path)
    end
  end

  @doc """
  Writes file contents, creating missing parent directories.
  """
  @spec write_file(term(), term(), term(), term(), term()) :: term()
  def write_file(project, projects_root, source_root, rel_path, contents) do
    with {:ok, absolute_path} <- safe_path(project, projects_root, source_root, rel_path),
         :ok <- File.mkdir_p(Path.dirname(absolute_path)) do
      File.write(absolute_path, contents)
    end
  end

  @doc """
  Renames a file inside a source root.
  """
  @spec rename_file(term(), term(), term(), term(), term()) :: term()
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
  @spec delete_path(term(), term(), term(), term()) :: term()
  def delete_path(project, projects_root, source_root, rel_path) do
    with {:ok, absolute_path} <- safe_path(project, projects_root, source_root, rel_path) do
      cond do
        File.dir?(absolute_path) -> File.rm_rf(absolute_path) |> normalize_rm_rf()
        true -> File.rm(absolute_path)
      end
    end
  end

  @doc """
  Returns an absolute path to the project workspace root.
  """
  @spec project_root(term(), term()) :: term()
  def project_root(%Project{slug: slug}, projects_root), do: Path.join(projects_root, slug)

  @spec safe_path(term(), term(), term(), term()) :: term()
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

  @spec tree_nodes(term(), term(), term()) :: term()
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

  @spec prune_empty_dirs(term()) :: term()
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

  @spec rel_join(term(), term()) :: term()
  defp rel_join("", segment), do: segment
  defp rel_join(parent, segment), do: Path.join(parent, segment)

  @spec normalize_rm_rf(term()) :: term()
  defp normalize_rm_rf({:ok, _paths}), do: :ok
  defp normalize_rm_rf({:error, reason, _path}), do: {:error, reason}

  @spec hidden_entry?(term(), term()) :: term()
  defp hidden_entry?(abs_dir, entry) do
    full_path = Path.join(abs_dir, entry)
    File.dir?(full_path) and MapSet.member?(@hidden_directories, entry)
  end
end
