defmodule Ide.Resources.ResourceStore.Animations do
  @moduledoc false

  alias Ide.Projects.Project
  alias Ide.Resources.AnimationStore
  alias Ide.Resources.Types

  @type animation_resource_entry :: Types.animation_resource_entry()

  @spec list(Project.t()) ::
          {:ok, [animation_resource_entry()]} | {:error, Types.resource_error()}
  defdelegate list(project), to: AnimationStore

  @spec import_animation(Project.t(), String.t(), String.t()) ::
          Types.animation_import_result()
  defdelegate import_animation(project, upload_path, original_name), to: AnimationStore

  @spec delete_animation(Project.t(), String.t()) :: Types.delete_entries_result()
  defdelegate delete_animation(project, ctor), to: AnimationStore

  @spec update_base_name(Project.t(), String.t(), String.t()) :: Types.rename_result()
  defdelegate update_base_name(project, old_ctor, new_base), to: AnimationStore

  @spec animation_file_path(Project.t(), String.t()) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  defdelegate animation_file_path(project, ctor), to: AnimationStore

  @spec animation_file_path_by_id(Project.t(), integer()) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def animation_file_path_by_id(%Project{} = project, id) when is_integer(id) and id >= 1 do
    with {:ok, entries} <- list(project),
         %{} = row <- Enum.at(entries, id - 1) do
      animation_file_path(project, row.ctor)
    else
      _ -> {:error, :not_found}
    end
  end

  def animation_file_path_by_id(_project, _), do: {:error, :not_found}
end
