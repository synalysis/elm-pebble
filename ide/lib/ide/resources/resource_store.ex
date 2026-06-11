defmodule Ide.Resources.ResourceStore do
  @moduledoc false

  alias Ide.Resources.ResourceStore.Animations
  alias Ide.Resources.ResourceStore.Bitmaps
  alias Ide.Resources.ResourceStore.Fonts
  alias Ide.Resources.ResourceStore.GeneratedModule
  alias Ide.Resources.ResourceStore.Manifest
  alias Ide.Resources.ResourceStore.Vectors

  @type bitmap_entry :: Ide.Resources.ResourceStore.Core.bitmap_entry()
  @type font_entry :: Ide.Resources.ResourceStore.Core.font_entry()
  @type font_source :: Ide.Resources.ResourceStore.Core.font_source()
  @type vector_entry :: Ide.Resources.ResourceStore.Core.vector_entry()

  defdelegate manifest_rel_path(), to: Manifest
  defdelegate generated_module_rel_path(), to: Manifest
  defdelegate read_only_generated_module?(source_root, rel_path), to: GeneratedModule

  defdelegate list(project), to: Bitmaps
  defdelegate import_bitmaps_from_directory(project, dir \\ nil, opts \\ []), to: Bitmaps
  defdelegate import_bitmap(project, upload_path, original_name, opts \\ []), to: Bitmaps
  defdelegate clear_bitmap_variant(project, ctor, color_mode), to: Bitmaps
  defdelegate delete_bitmap(project, ctor), to: Bitmaps
  defdelegate update_bitmap_base_name(project, old_ctor, new_base), to: Bitmaps
  defdelegate bitmap_file_path(project, ctor), to: Bitmaps
  defdelegate bitmap_file_path(project, ctor, color_mode), to: Bitmaps
  defdelegate bitmap_file_path_by_id(project, id), to: Bitmaps

  defdelegate list_vectors(project), to: Vectors
  defdelegate import_vector(project, upload_path, original_name), to: Vectors
  defdelegate import_vector(project, upload_path, original_name, opts), to: Vectors
  defdelegate import_vector_svg(project, upload_path, original_name, opts), to: Vectors
  defdelegate import_vector_sequence(project, frames, original_name, opts), to: Vectors
  defdelegate delete_vector(project, ctor), to: Vectors
  defdelegate vector_file_path(project, ctor), to: Vectors
  defdelegate update_vector_base_name(project, old_ctor, new_base), to: Vectors
  defdelegate vector_file_path_by_id(project, id), to: Vectors

  defdelegate ensure_generated(project), to: Manifest
  defdelegate ensure_generated_workspace(workspace), to: Manifest

  defdelegate list_fonts(project), to: Fonts
  defdelegate list_font_sources(project), to: Fonts
  defdelegate import_font(project, upload_path, original_name), to: Fonts
  defdelegate add_font_variant(project, params), to: Fonts
  defdelegate update_font_variant(project, ctor, params), to: Fonts
  defdelegate delete_font(project, ctor), to: Fonts
  defdelegate delete_font_source(project, source_id), to: Fonts
  defdelegate font_file_path(project, ctor), to: Fonts

  defdelegate animation_file_path_by_id(project, id), to: Animations
end
