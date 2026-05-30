defmodule Ide.ProjectImport do
  @moduledoc """
  Imports existing project sources into an IDE workspace.

  Imports are always **merge** operations: existing workspace files are never
  deleted because they are missing from the import tree.
  """

  alias Ide.Projects.WorkspaceMerge

  @source_roots ~w(watch protocol phone)

  @type import_error :: :import_source_not_found | File.posix()
  @type import_result :: :ok | {:error, import_error()}

  @doc """
  Imports source files from an existing path into workspace roots.
  """
  @spec import(String.t(), String.t()) :: import_result()
  def import(import_path, workspace_path) do
    source_path = Path.expand(import_path)

    with true <- File.dir?(source_path) or {:error, :import_source_not_found} do
      if multi_root_layout?(source_path) do
        import_multi_root(source_path, workspace_path)
      else
        import_single_root(source_path, workspace_path)
      end
    end
  end

  @spec import_multi_root(String.t(), String.t()) :: import_result()
  defp import_multi_root(source_path, workspace_path) do
    Enum.reduce_while(@source_roots, :ok, fn root, :ok ->
      src = Path.join(source_path, root)
      dst = Path.join(workspace_path, root)

      if File.dir?(src) do
        case WorkspaceMerge.merge_tree(src, dst) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  @spec import_single_root(String.t(), String.t()) :: import_result()
  defp import_single_root(source_path, workspace_path) do
    watch_target = Path.join(workspace_path, "watch")

    cond do
      watch_import_source_safe?(source_path) ->
        WorkspaceMerge.merge_tree(source_path, watch_target)

      File.dir?(Path.join(source_path, "resources")) ->
        WorkspaceMerge.merge_tree(
          Path.join(source_path, "resources"),
          Path.join(watch_target, "resources")
        )

      true ->
        WorkspaceMerge.merge_tree(source_path, Path.join(watch_target, "resources/bitmaps"))
    end
  end

  @spec watch_import_source_safe?(String.t()) :: boolean()
  defp watch_import_source_safe?(source_path) do
    File.exists?(Path.join(source_path, "elm.json")) or
      File.exists?(Path.join(source_path, "src/Main.elm"))
  end

  @spec multi_root_layout?(String.t()) :: boolean()
  defp multi_root_layout?(source_path) do
    Enum.any?(@source_roots, &File.dir?(Path.join(source_path, &1)))
  end
end
