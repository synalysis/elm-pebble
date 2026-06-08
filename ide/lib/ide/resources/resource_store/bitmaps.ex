defmodule Ide.Resources.ResourceStore.Bitmaps do
  @moduledoc false

  alias Ide.Resources.ResourceStore.Core

  defdelegate list(project), to: Core
  defdelegate import_bitmaps_from_directory(project, dir \\ nil, opts \\ []), to: Core
  defdelegate import_bitmap(project, upload_path, original_name, opts \\ []), to: Core
  defdelegate clear_bitmap_variant(project, ctor, color_mode), to: Core
  defdelegate delete_bitmap(project, ctor), to: Core
  defdelegate update_bitmap_base_name(project, old_ctor, new_base), to: Core
  defdelegate bitmap_file_path(project, ctor), to: Core
  defdelegate bitmap_file_path(project, ctor, color_mode), to: Core
  defdelegate bitmap_file_path_by_id(project, id), to: Core
end
