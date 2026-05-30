defmodule IdeWeb.WorkspaceLive.ResourcesFlow do
  @moduledoc false

  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3, put_flash: 3]

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.BitmapVariants
  alias Ide.Resources.PdcDecoder
  alias Ide.Resources.ResourceStore
  alias Ide.Resources.Types, as: ResourceTypes
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.EditorSupport

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_noreply :: {:noreply, socket()}
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

  # Inline data-URL previews larger than this can break LiveView payloads (many bitmaps × variants).
  @bitmap_preview_max_bytes 32_000

  @spec load_bitmap_resources(Project.t()) :: {[bitmap_resource_row()], String.t() | nil}
  def load_bitmap_resources(%Project{} = project) do
    case Projects.list_bitmap_resources(project) do
      {:ok, entries} ->
        {decorated, errors} =
          entries
          |> Enum.with_index(1)
          |> Enum.map_reduce([], fn {entry, idx}, errs ->
            try do
              {decorate_bitmap_entry(project, entry, idx), errs}
            rescue
              exception ->
                Logger.error(
                  "bitmap resource UI row failed for #{inspect(entry.ctor)}: #{Exception.message(exception)}"
                )

                {minimal_bitmap_row(entry, idx), [:row_decode | errs]}
            end
          end)

        error_message =
          case errors do
            [] -> nil
            _ -> "Some bitmap resources could not be previewed. Files on disk are unchanged."
          end

        {decorated, error_message}

      {:error, :invalid_manifest} ->
        {[],
         "bitmaps.json could not be read (invalid JSON). Repair the file under watch/resources/ or restore from git."}

      {:error, reason} ->
        Logger.warning("list_bitmap_resources failed: #{inspect(reason)}")
        {[], "Could not load bitmap resources (#{inspect(reason)})."}
    end
  end

  defp decorate_bitmap_entry(project, entry, idx) do
    variants_map = entry.variants || %{}

    variants =
      BitmapVariants.color_modes()
      |> Enum.map(fn color_mode ->
        variant = Map.get(variants_map, color_mode)

        preview =
          case ResourceStore.bitmap_file_path(project, entry.ctor, color_mode) do
            {:ok, path} ->
              mime =
                case variant do
                  %{mime: mime} -> mime
                  _ -> entry.mime || "image/png"
                end

              bitmap_preview_data_url(path, mime)

            _ ->
              nil
          end

        %{
          color_mode: color_mode,
          label: variant_label(color_mode),
          platforms: BitmapVariants.platforms_label(color_mode),
          preview_data_url: preview,
          preview_skipped: preview == nil and variant != nil,
          filename: variant && variant.filename,
          bytes: variant && variant.bytes
        }
      end)

    legacy_preview =
      if entry.filename not in [nil, ""] do
        case ResourceStore.bitmap_file_path(project, entry.ctor) do
          {:ok, path} -> bitmap_preview_data_url(path, entry.mime || "image/png")
          _ -> nil
        end
      else
        nil
      end

    entry
    |> Map.put(:resource_id, idx)
    |> Map.put(:variant_slots, variants)
    |> Map.put(:legacy_preview_data_url, legacy_preview)
    |> Map.put(:has_legacy, entry.filename not in [nil, ""])
  end

  defp minimal_bitmap_row(entry, idx) do
    entry
    |> Map.put(:resource_id, idx)
    |> Map.put(:variant_slots, [])
    |> Map.put(:legacy_preview_data_url, nil)
    |> Map.put(:has_legacy, false)
  end

  defp variant_label("BlackWhite"), do: "Monochrome"
  defp variant_label("Color"), do: "Color"
  defp variant_label(_), do: "Variant"

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
    with {:ok, %File.Stat{size: size}} <- File.stat(path),
         true <- size <= @bitmap_preview_max_bytes,
         {:ok, bytes} <- File.read(path) do
      "data:#{mime};base64," <> Base.encode64(bytes)
    else
      {:ok, %File.Stat{size: size}} when size > @bitmap_preview_max_bytes ->
        nil

      _ ->
        nil
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

  @resource_events ~w(
    upload-bitmap-resource
    clear-bitmap-variant
    validate-resource-upload
    delete-bitmap-resource
    upload-font-resource
    add-font-variant
    update-font-variant
    delete-font-resource
    delete-font-source
  )

  @spec resource_events() :: [String.t()]
  def resource_events, do: @resource_events

  @spec handles?(String.t()) :: boolean()
  def handles?(event) when is_binary(event), do: event in @resource_events

  @spec assign_bitmap_resources(socket(), Project.t()) :: socket()
  def assign_bitmap_resources(socket, %Project{} = project) do
    {resources, error} = load_bitmap_resources(project)

    socket
    |> assign(:bitmap_resources, resources)
    |> assign(:bitmap_resources_error, error)
  end

  @spec handle_event(String.t(), map(), socket()) :: lv_noreply()
  def handle_event("upload-bitmap-resource", params, socket) do
    project = socket.assigns.project
    import_opts = bitmap_import_opts(params)

    results =
      consume_uploaded_entries(socket, :bitmap, fn %{path: path}, entry ->
        case Projects.import_bitmap_resource(project, path, entry.client_name, import_opts) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: inspect(reason)}}
        end
      end)

    socket =
      socket
      |> assign_bitmap_resources(project)
      |> assign(:bitmap_upload_output, bitmap_upload_output(results))
      |> EditorSupport.refresh_tree()

    {:noreply, socket}
  end

  def handle_event("clear-bitmap-variant", %{"ctor" => ctor, "color_mode" => color_mode}, socket) do
    project = socket.assigns.project

    socket =
      case Projects.clear_bitmap_variant_resource(project, ctor, color_mode) do
        {:ok, _} ->
          socket
          |> assign_bitmap_resources(project)
          |> EditorSupport.refresh_tree()
          |> put_flash(:info, "Cleared #{ctor} #{color_mode} variant.")

        {:error, reason} ->
          put_flash(socket, :error, "Could not clear bitmap variant: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_event("validate-resource-upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete-bitmap-resource", %{"ctor" => ctor}, socket) do
    case Projects.delete_bitmap_resource(socket.assigns.project, ctor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign_bitmap_resources(socket.assigns.project)
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Deleted bitmap #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete bitmap: #{inspect(reason)}")}
    end
  end

  def handle_event("upload-font-resource", _params, socket) do
    project = socket.assigns.project

    results =
      consume_uploaded_entries(socket, :font, fn %{path: path}, entry ->
        case Projects.import_font_resource(project, path, entry.client_name) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: inspect(reason)}}
        end
      end)

    socket =
      socket
      |> assign(:font_resources, load_font_resources(project))
      |> assign(:font_sources, load_font_sources(project))
      |> assign(:font_upload_output, font_upload_output(results))
      |> EditorSupport.refresh_tree()

    {:noreply, socket}
  end

  def handle_event("add-font-variant", %{"variant" => params}, socket) do
    project = socket.assigns.project

    case Projects.add_font_variant(project, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_sources, load_font_sources(project))
         |> assign(:font_resources, load_font_resources(project))
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Added font identifier.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add font identifier: #{inspect(reason)}")}
    end
  end

  def handle_event("update-font-variant", %{"ctor" => ctor, "variant" => params}, socket) do
    project = socket.assigns.project

    case Projects.update_font_variant(project, ctor, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_sources, load_font_sources(project))
         |> assign(:font_resources, load_font_resources(project))
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Updated font #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not update font: #{inspect(reason)}")}
    end
  end

  def handle_event("delete-font-resource", %{"ctor" => ctor}, socket) do
    case Projects.delete_font_resource(socket.assigns.project, ctor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_sources, load_font_sources(socket.assigns.project))
         |> assign(:font_resources, load_font_resources(socket.assigns.project))
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Deleted font #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete font: #{inspect(reason)}")}
    end
  end

  def handle_event("delete-font-source", %{"source-id" => source_id}, socket) do
    case Projects.delete_font_source(socket.assigns.project, source_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_sources, load_font_sources(socket.assigns.project))
         |> assign(:font_resources, load_font_resources(socket.assigns.project))
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Deleted source font.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete source font: #{inspect(reason)}")}
    end
  end

  @spec bitmap_import_opts(map()) :: keyword()
  defp bitmap_import_opts(params) when is_map(params) do
    []
    |> maybe_put_import_opt(:color_mode, blank_to_nil(Map.get(params, "color_mode")))
    |> maybe_put_import_opt(:ctor, blank_to_nil(Map.get(params, "ctor")))
  end

  defp maybe_put_import_opt(opts, _key, nil), do: opts
  defp maybe_put_import_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
