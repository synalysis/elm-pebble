defmodule Ide.Resources.ResourceStore.Vectors do
  @moduledoc false

  alias Ide.Resources.ResourceStore.Core

  defdelegate list_vectors(project), to: Core
  defdelegate import_vector(project, upload_path, original_name), to: Core
  defdelegate import_vector(project, upload_path, original_name, opts), to: Core
  defdelegate import_vector_svg(project, upload_path, original_name, opts), to: Core
  defdelegate import_vector_sequence(project, frames, original_name, opts), to: Core
  defdelegate delete_vector(project, ctor), to: Core
  defdelegate vector_file_path(project, ctor), to: Core
  defdelegate update_vector_base_name(project, old_ctor, new_base), to: Core
  defdelegate vector_file_path_by_id(project, id), to: Core
end
