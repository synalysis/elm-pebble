defmodule IdeWeb.WorkspaceLive.DebuggerPage.BitmapHydration do
  @moduledoc false

  alias Ide.Projects.Project
  alias Ide.Resources.ResourceStore
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type svg_op :: SupportTypes.svg_op()

  @spec hydrate_svg_ops([svg_op()], Project.t() | nil, String.t() | nil) :: [svg_op()]
  def hydrate_svg_ops(rows, %Project{} = project, color_mode) when is_list(rows) do
    Enum.map(rows, fn
      %{kind: :bitmap_in_rect, bitmap_id: bitmap_id} = row when bitmap_id > 0 ->
        Map.put(row, :href, bitmap_href_for(project, bitmap_id, color_mode))

      %{kind: :rotated_bitmap, bitmap_id: bitmap_id} = row when bitmap_id > 0 ->
        Map.put(row, :href, bitmap_href_for(project, bitmap_id, color_mode))

      other ->
        other
    end)
  end

  def hydrate_svg_ops(rows, _project, _color_mode), do: rows

  @spec bitmap_href_for(Project.t(), pos_integer(), String.t() | nil) :: String.t() | nil
  defp bitmap_href_for(%Project{} = project, bitmap_id, color_mode)
       when is_integer(bitmap_id) and bitmap_id > 0 do
    with {:ok, entries} <- ResourceStore.list(project),
         %{} = row <- Enum.at(entries, bitmap_id - 1),
         {:ok, path} <- ResourceStore.bitmap_file_path(project, row.ctor, color_mode),
         {:ok, bytes} <- File.read(path) do
      "data:#{bitmap_mime_for_path(path)};base64," <> Base.encode64(bytes)
    else
      _ -> nil
    end
  end

  defp bitmap_href_for(_project, _bitmap_id, _color_mode), do: nil

  @spec bitmap_mime_for_path(String.t()) :: String.t()
  defp bitmap_mime_for_path(path) when is_binary(path) do
    case path |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      ".bmp" -> "image/bmp"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end
end
