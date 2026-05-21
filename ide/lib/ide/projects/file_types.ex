defmodule Ide.Projects.FileTypes do
  @moduledoc """
  Filesystem and source-tree types for project workspaces.
  """

  alias Ide.Projects.Project

  @type tree_node :: %{
          required(:type) => :file | :dir,
          required(:name) => String.t(),
          required(:rel_path) => String.t(),
          required(:children) => [tree_node()]
        }

  @type source_root_tree :: %{
          required(:source_root) => String.t(),
          required(:nodes) => [tree_node()]
        }

  @type source_tree :: [source_root_tree()]

  @type path_error :: :invalid_path | :invalid_source_root | File.posix()

  @type read_result :: {:ok, binary()} | {:error, path_error() | File.posix()}
  @type write_result :: :ok | {:error, path_error() | File.posix()}
  @type delete_result :: :ok | {:error, path_error() | File.posix()}
  @type rename_result :: :ok | {:error, path_error() | File.posix()}
  @type ensure_roots_result :: :ok | {:error, File.posix()}

  @type projects_root :: String.t()
  @type workspace_path :: String.t()

  @type project_ref :: Project.t() | String.t()
end
