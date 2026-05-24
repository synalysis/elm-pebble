defmodule IdeWeb.WorkspaceLive.ResourcesFlow do
  @moduledoc false

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.PdcDecoder
  alias Ide.Resources.ResourceStore
  alias Ide.Resources.Types, as: ResourceTypes
  alias Ide.Screenshots

  @type upload_result_row :: map()
  @type bitmap_resource_row :: ResourceTypes.bitmap_entry() | map()
  @type font_resource_row :: ResourceTypes.font_entry() | map()
  @type font_source_row :: ResourceTypes.font_source() | map()
  @type vector_resource_row :: ResourceTypes.vector_entry() | map()

  @spec bitmap_upload_output([upload_result_row()]) :: String.t()
  def bitmap_upload_output([]), do: "No file uploaded."

  def bitmap_upload_output(results) when is_list(results) do
    upload_summary(results, "bitmap", "bitmaps")
  end

  @spec font_upload_output([upload_result_row()]) :: String.t()
  def font_upload_output([]), do: "No file uploaded."

  def font_upload_output(results) when is_list(results) do
    upload_summary(results, "source font", "source fonts")
  end

  @spec vector_upload_output([upload_result_row()]) :: String.t()
  def vector_upload_output([]), do: "No file uploaded."

  def vector_upload_output(results) when is_list(results) do
    upload_summary(results, "vector graphic", "vector graphics")
  end

  defp upload_summary(results, singular, plural) do
    uploaded =
      Enum.count(
        results,
        &(is_map(&1) and not Map.get(&1, :duplicate) and not Map.has_key?(&1, :error))
      )

    duplicates = Enum.count(results, &(is_map(&1) and Map.get(&1, :duplicate)))
    failed = Enum.count(results, &(is_map(&1) and Map.has_key?(&1, :error)))

    [
      "Uploaded #{uploaded} #{if uploaded == 1, do: singular, else: plural}.",
      duplicates > 0 &&
        "Skipped #{duplicates} duplicate #{if duplicates == 1, do: singular, else: plural}.",
      failed > 0 && "#{failed} failed."
    ]
    |> Enum.reject(&(&1 in [false, nil]))
    |> Enum.join(" ")
  end

  @spec load_font_sources(Project.t()) :: [font_source_row()]
  def load_font_sources(%Project{} = project) do
    case Projects.list_font_sources(project) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  @spec load_bitmap_resources(Project.t()) :: [bitmap_resource_row()]
  def load_bitmap_resources(%Project{} = project) do
    case Projects.list_bitmap_resources(project) do
      {:ok, entries} ->
        Enum.with_index(entries, 1)
        |> Enum.map(fn {entry, idx} ->
          preview_data_url =
            case ResourceStore.bitmap_file_path(project, entry.ctor) do
              {:ok, path} -> bitmap_preview_data_url(path, entry.mime)
              _ -> nil
            end

          entry
          |> Map.put(:resource_id, idx)
          |> Map.put(:preview_data_url, preview_data_url)
        end)

      _ ->
        []
    end
  end

  @spec load_font_resources(Project.t()) :: [font_resource_row()]
  def load_font_resources(%Project{} = project) do
    case Projects.list_font_resources(project) do
      {:ok, entries} ->
        Enum.with_index(entries, 1)
        |> Enum.map(fn {entry, idx} ->
          entry
          |> Map.put(:resource_id, idx)
        end)

      _ ->
        []
    end
  end

  @spec load_vector_resources(Project.t()) :: [vector_resource_row()]
  def load_vector_resources(%Project{} = project) do
    case Projects.list_vector_resources(project) do
      {:ok, entries} ->
        Enum.with_index(entries, 1)
        |> Enum.map(fn {entry, idx} ->
          preview_svg =
            case ResourceStore.vector_file_path(project, entry.ctor) do
              {:ok, path} -> vector_preview_svg(path)
              _ -> nil
            end

          entry
          |> Map.put(:resource_id, idx)
          |> Map.put(:kind_label, vector_kind_label(entry))
          |> Map.put(:preview_svg, preview_svg)
          |> Map.put(:sequence_label, vector_sequence_label(entry))
        end)

      _ ->
        []
    end
  end

  defp vector_kind_label(%{kind: "sequence"}), do: "PDC sequence"
  defp vector_kind_label(%{source: "svg"}), do: "SVG → PDC"
  defp vector_kind_label(%{source: "pdc"}), do: "PDC"
  defp vector_kind_label(_), do: "vector"

  defp vector_sequence_label(%{kind: "sequence", frames: frames, frame_duration_ms: ms})
       when is_integer(frames) and is_integer(ms) do
    "#{frames} frames · #{ms}ms"
  end

  defp vector_sequence_label(_), do: nil

  @spec vector_preview_svg(String.t()) :: String.t() | nil
  defp vector_preview_svg(path) when is_binary(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, svg} <- PdcDecoder.preview_svg(bytes) do
      svg
    else
      _ -> nil
    end
  end

  @spec bitmap_preview_data_url(String.t(), String.t()) :: String.t() | nil
  def bitmap_preview_data_url(path, mime) when is_binary(path) and is_binary(mime) do
    with {:ok, bytes} <- File.read(path) do
      "data:#{mime};base64," <> Base.encode64(bytes)
    else
      _ -> nil
    end
  end

  @spec load_screenshots(Screenshots.project_ref()) :: [Screenshots.screenshot()]
  def load_screenshots(project) do
    case Screenshots.list(project, []) do
      {:ok, shots} -> shots
      _ -> []
    end
  end

  @spec group_screenshots([Screenshots.screenshot()]) :: [{String.t(), [Screenshots.screenshot()]}]
  def group_screenshots(shots) do
    shots
    |> Enum.group_by(& &1.emulator_target)
    |> Enum.sort_by(fn {emulator_target, _} -> emulator_target end)
  end
end
