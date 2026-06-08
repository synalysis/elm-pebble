defmodule Ide.Resources.ResourceStore.Fonts do
  @moduledoc false

  alias Ide.Resources.ResourceStore.Core

  defdelegate list_fonts(project), to: Core
  defdelegate list_font_sources(project), to: Core
  defdelegate import_font(project, upload_path, original_name), to: Core
  defdelegate add_font_variant(project, params), to: Core
  defdelegate update_font_variant(project, ctor, params), to: Core
  defdelegate delete_font(project, ctor), to: Core
  defdelegate delete_font_source(project, source_id), to: Core
  defdelegate font_file_path(project, ctor), to: Core
end
