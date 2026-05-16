defmodule IdeWeb.WorkspaceLive.ResourcesFlow do
  @moduledoc false

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.ResourceStore
  alias Ide.Screenshots

  @spec bitmap_upload_output(term()) :: term()
  def bitmap_upload_output([]), do: "No file uploaded."

  def bitmap_upload_output(results) when is_list(results) do
    upload_summary(results, "bitmap", "bitmaps")
  end

  @spec font_upload_output(term()) :: term()
  def font_upload_output([]), do: "No file uploaded."

  def font_upload_output(results) when is_list(results) do
    upload_summary(results, "source font", "source fonts")
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

  @spec load_font_sources(term()) :: term()
  def load_font_sources(%Project{} = project) do
    case Projects.list_font_sources(project) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  @spec load_bitmap_resources(term()) :: term()
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

  @spec load_font_resources(term()) :: term()
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

  @spec bitmap_preview_data_url(term(), term()) :: term()
  def bitmap_preview_data_url(path, mime) when is_binary(path) and is_binary(mime) do
    with {:ok, bytes} <- File.read(path) do
      "data:#{mime};base64," <> Base.encode64(bytes)
    else
      _ -> nil
    end
  end

  @spec load_screenshots(term()) :: term()
  def load_screenshots(project) do
    case Screenshots.list(project.slug, []) do
      {:ok, shots} -> shots
      _ -> []
    end
  end

  @spec group_screenshots(term()) :: term()
  def group_screenshots(shots) do
    shots
    |> Enum.group_by(& &1.emulator_target)
    |> Enum.sort_by(fn {emulator_target, _} -> emulator_target end)
  end
end
