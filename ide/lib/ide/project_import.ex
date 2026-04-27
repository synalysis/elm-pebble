defmodule Ide.ProjectImport do
  @moduledoc """
  Imports existing project sources into an IDE workspace.
  """

  @source_roots ~w(watch protocol phone)

  @doc """
  Imports source files from an existing path into workspace roots.
  """
  @spec import(String.t(), String.t()) :: :ok | {:error, term()}
  def import(import_path, workspace_path) do
    source_path = Path.expand(import_path)

    with true <- File.dir?(source_path) or {:error, :import_source_not_found} do
      if multi_root_layout?(source_path) do
        Enum.reduce_while(@source_roots, :ok, fn root, :ok ->
          src = Path.join(source_path, root)
          dst = Path.join(workspace_path, root)

          if File.dir?(src) do
            case replace_dir(src, dst) do
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          else
            {:cont, :ok}
          end
        end)
      else
        replace_dir(source_path, Path.join(workspace_path, "watch"))
      end
    end
  end

  @spec multi_root_layout?(term()) :: term()
  defp multi_root_layout?(source_path) do
    Enum.any?(@source_roots, &File.dir?(Path.join(source_path, &1)))
  end

  @spec replace_dir(term(), term()) :: term()
  defp replace_dir(source, target) do
    _ = File.rm_rf(target)
    :ok = File.mkdir_p(Path.dirname(target))

    case File.cp_r(source, target) do
      {:ok, _paths} -> :ok
      {:error, reason, _path} -> {:error, reason}
    end
  end
end
