defmodule IdeWeb.WorkspaceLive.ResourcesFlow do
  @moduledoc false

  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.Component, only: [assign: 3, upload_errors: 1]
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3, put_flash: 3, uploaded_entries: 2]

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.AnimationStore
  alias Ide.Resources.BitmapVariants
  alias Ide.Resources.CtorNaming
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
  @type animation_resource_row :: map()

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

  @spec animation_upload_output([upload_result_row()]) :: String.t()
  def animation_upload_output([]), do: "No file uploaded."

  def animation_upload_output(results) when is_list(results) do
    upload_summary(results, "animation", "animations")
  end

  @spec filter_vectors([vector_resource_row()], :static | :animated) :: [vector_resource_row()]
  def filter_vectors(resources, :static) when is_list(resources) do
    Enum.filter(resources, fn row -> Map.get(row, :kind) != "sequence" end)
  end

  def filter_vectors(resources, :animated) when is_list(resources) do
    Enum.filter(resources, fn row -> Map.get(row, :kind) == "sequence" end)
  end

  defp upload_summary(results, singular, plural) do
    normalized = Enum.map(results, &normalize_upload_result/1)

    {ok_rows, failed_rows} =
      Enum.split_with(normalized, fn
        %{} = row -> not Map.has_key?(row, :error)
        _ -> false
      end)

    uploaded =
      Enum.count(
        ok_rows,
        &(is_map(&1) and Map.get(&1, :duplicate, false) != true)
      )

    duplicates =
      Enum.count(ok_rows, &(is_map(&1) and Map.get(&1, :duplicate, false) == true))

    failure_messages =
      failed_rows
      |> Enum.map(fn
        %{error: message} when is_binary(message) -> message
        %{error: reason} -> resource_import_error_message(reason)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    [
      "Uploaded #{uploaded} #{if uploaded == 1, do: singular, else: plural}.",
      duplicates > 0 &&
        "Skipped #{duplicates} duplicate #{if duplicates == 1, do: singular, else: plural}.",
      failure_messages != [] && Enum.join(failure_messages, " ")
    ]
    |> Enum.reject(&(&1 in [false, nil, ""]))
    |> Enum.join(" ")
  end

  @spec resource_import_error_message(term()) :: String.t()
  def resource_import_error_message(reason) do
    case reason do
      :gif_converter_missing ->
        "GIF import requires gif2apng (run `mix ide.install_gif2apng` in ide/, or install on PATH)."

      :gif_conversion_failed ->
        "GIF could not be converted to APNG. Check that the file is a valid GIF."

      :not_animated ->
        "File is not an animated PNG (APNG). Upload a GIF or a multi-frame APNG."

      :requires_apng8 ->
        "Animation must be APNG8 (8-bit indexed palette). Upload a GIF to convert automatically, or re-export the PNG as palette APNG8."

      :malformed_apng ->
        "Animated PNG is missing frame metadata (fcTL chunks). Re-export the APNG or upload a GIF."

      :unsupported_format ->
        "Unsupported file type. Use .gif or animated .png."

      :file_too_large ->
        "Animation file is too large (max 64 KB)."

      :too_many_frames ->
        "Too many frames (max 64)."

      :dimensions_too_large ->
        "Image dimensions are too large (max 200×200 px)."

      :invalid_png ->
        "Could not read PNG/APNG metadata."

      :invalid_animation ->
        "Invalid animation file."

      :invalid_manifest ->
        "animations.json is invalid."

      :invalid_watch_pdc ->
        "Vector file is not a valid Pebble PDC/PDCS image for the watch."

      :pdc_too_large ->
        "Vector file is too large (max 64 KB)."

      :pdc_dimensions_too_large ->
        "Vector canvas is too large (max 200×200 px)."

      :pdc_too_many_frames ->
        "Vector sequence has too many frames (max 64)."

      other when is_binary(other) ->
        other

      other ->
        "Import failed: #{inspect(other)}"
    end
  end

  @spec upload_ready?(map()) :: boolean()
  def upload_ready?(upload) when is_map(upload) do
    upload.entries != [] and Enum.all?(upload.entries, &upload_entry_ready?(&1, upload))
  end

  def upload_ready?(_), do: false

  # With default LiveView uploads (no auto_upload), files upload on form submit; done? stays
  # false until then, so the submit button must not require done?.
  defp upload_entry_ready?(entry, upload) do
    entry.valid? and (not upload_auto_upload?(upload) or entry.done?)
  end

  defp upload_auto_upload?(upload) do
    Map.get(upload, :auto_upload?) == true
  end

  @spec consume_resource_upload(socket(), atom(), (map(), map() -> {:ok, map()})) ::
          {socket(), [upload_result_row()], String.t()}
  defp consume_resource_upload(socket, upload_name, import_fn) do
    upload = Map.fetch!(socket.assigns.uploads, upload_name)
    upload_config_errors = upload_errors(upload) |> Enum.map(&format_upload_error/1)
    {done, in_progress} = uploaded_entries(socket, upload_name)

    invalid_entries = Enum.filter(upload.entries, fn entry -> not entry.valid? end)

    cond do
      upload_config_errors != [] ->
        {socket, [], Enum.join(upload_config_errors, " ")}

      in_progress != [] and upload_auto_upload?(upload) ->
        {socket, [], "Files are still uploading. Wait until the upload finishes, then try again."}

      invalid_entries != [] and done == [] ->
        reasons =
          invalid_entries
          |> Enum.map(fn entry -> entry.client_name <> ": not accepted or too large" end)

        {socket, [], Enum.join(reasons, " ")}

      done == [] ->
        {socket, [], "No file uploaded. Choose a file first."}

      true ->
        results =
          consume_uploaded_entries(socket, upload_name, fn meta, entry ->
            import_fn.(meta, entry)
          end)

        {socket, results, ""}
    end
  rescue
    error in ArgumentError ->
      Logger.warning("resource upload #{upload_name} failed: #{Exception.message(error)}")
      {socket, [], Exception.message(error)}
  end

  @spec format_upload_error(term()) :: String.t()
  def format_upload_error(:too_large), do: "File is too large."
  def format_upload_error(:not_accepted), do: "File type is not accepted."
  def format_upload_error(:too_many_files), do: "Too many files selected."
  def format_upload_error(other), do: "Upload error: #{inspect(other)}"

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
    |> Map.put(:ctor_prefix, CtorNaming.prefix(:bitmap_static))
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

          ctor_prefix =
            if entry.kind == "sequence",
              do: CtorNaming.prefix(:vector_animated),
              else: CtorNaming.prefix(:vector_static)

          entry
          |> Map.put(:resource_id, idx)
          |> Map.put(:ctor_prefix, ctor_prefix)
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

  @spec load_animation_resources(Project.t()) :: [animation_resource_row()]
  def load_animation_resources(%Project{} = project) do
    case Projects.list_animation_resources(project) do
      {:ok, entries} ->
        Enum.with_index(entries, 1)
        |> Enum.map(fn {entry, idx} ->
          preview =
            case AnimationStore.animation_file_path(project, entry.ctor) do
              {:ok, path} -> animation_preview_data_url(path)
              _ -> nil
            end

          loop_label = animation_loop_label(entry)

          entry
          |> Map.put(:resource_id, idx)
          |> Map.put(:ctor_prefix, CtorNaming.prefix(:bitmap_animated))
          |> Map.put(:preview_data_url, preview)
          |> Map.put(:loop_label, loop_label)
        end)

      _ ->
        []
    end
  end

  defp animation_loop_label(%{play_count: :infinite}), do: "loops forever"
  defp animation_loop_label(%{play_count: 1}), do: "plays once"

  defp animation_loop_label(%{play_count: count}) when is_integer(count),
    do: "plays #{count} times"

  defp animation_loop_label(_), do: nil

  @spec animation_preview_data_url(String.t()) :: String.t() | nil
  defp animation_preview_data_url(path) when is_binary(path) do
    bitmap_preview_data_url(path, "image/png")
  end

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

  @spec group_screenshots([Screenshots.screenshot()]) :: [
          {String.t(), [Screenshots.screenshot()]}
        ]
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
    update-bitmap-base-name
    upload-vector-resource
    delete-vector-resource
    update-vector-base-name
    upload-animation-resource
    delete-animation-resource
    update-animation-base-name
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

    {socket, results, output} =
      consume_resource_upload(socket, :bitmap, fn %{path: path}, entry ->
        case Projects.import_bitmap_resource(project, path, entry.client_name, import_opts) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: resource_import_error_message(reason)}}
        end
      end)

    output = upload_result_message(output, results, &bitmap_upload_output/1)

    socket =
      socket
      |> assign_bitmap_resources(project)
      |> assign(:bitmap_upload_output, output)
      |> maybe_flash_upload_result(output, results)
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

  def handle_event("upload-vector-resource", _params, socket) do
    project = socket.assigns.project

    {socket, results, output} =
      consume_resource_upload(socket, :vector, fn %{path: path}, entry ->
        case Projects.import_vector_resource(project, path, entry.client_name) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: resource_import_error_message(reason)}}
        end
      end)

    output = upload_result_message(output, results, &vector_upload_output/1)

    socket =
      socket
      |> assign(:vector_resources, load_vector_resources(project))
      |> assign(:vector_upload_output, output)
      |> maybe_flash_upload_result(output, results)
      |> EditorSupport.refresh_tree()

    {:noreply, socket}
  end

  def handle_event("delete-vector-resource", %{"ctor" => ctor}, socket) do
    case Projects.delete_vector_resource(socket.assigns.project, ctor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:vector_resources, load_vector_resources(socket.assigns.project))
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Deleted vector #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete vector: #{inspect(reason)}")}
    end
  end

  def handle_event("upload-animation-resource", _params, socket) do
    project = socket.assigns.project

    {socket, results, output} =
      consume_resource_upload(socket, :animation, fn %{path: path}, entry ->
        case Projects.import_animation_resource(project, path, entry.client_name) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: resource_import_error_message(reason)}}
        end
      end)

    output = upload_result_message(output, results, &animation_upload_output/1)

    socket =
      socket
      |> assign(:animation_resources, load_animation_resources(project))
      |> assign(:animation_upload_output, output)
      |> maybe_flash_upload_result(output, results)
      |> EditorSupport.refresh_tree()

    {:noreply, socket}
  end

  def handle_event("delete-animation-resource", %{"ctor" => ctor}, socket) do
    case Projects.delete_animation_resource(socket.assigns.project, ctor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:animation_resources, load_animation_resources(socket.assigns.project))
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Deleted animation #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete animation: #{inspect(reason)}")}
    end
  end

  def handle_event("upload-font-resource", _params, socket) do
    project = socket.assigns.project

    {socket, results, output} =
      consume_resource_upload(socket, :font, fn %{path: path}, entry ->
        case Projects.import_font_resource(project, path, entry.client_name) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: resource_import_error_message(reason)}}
        end
      end)

    output = upload_result_message(output, results, &font_upload_output/1)

    socket =
      socket
      |> assign(:font_resources, load_font_resources(project))
      |> assign(:font_sources, load_font_sources(project))
      |> assign(:font_upload_output, output)
      |> maybe_flash_upload_result(output, results)
      |> EditorSupport.refresh_tree()

    {:noreply, socket}
  end

  def handle_event("update-bitmap-base-name", %{"ctor" => ctor, "base_name" => base_name}, socket) do
    project = socket.assigns.project

    case Projects.update_bitmap_resource_base_name(project, ctor, base_name) do
      {:ok, _} ->
        {bitmaps, err} = load_bitmap_resources(project)

        {:noreply,
         socket
         |> assign(:bitmap_resources, bitmaps)
         |> assign(:bitmap_resources_error, err)
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Updated bitmap resource name.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not rename bitmap: #{inspect(reason)}")}
    end
  end

  def handle_event("update-vector-base-name", %{"ctor" => ctor, "base_name" => base_name}, socket) do
    project = socket.assigns.project

    case Projects.update_vector_resource_base_name(project, ctor, base_name) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:vector_resources, load_vector_resources(project))
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Updated vector resource name.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not rename vector: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "update-animation-base-name",
        %{"ctor" => ctor, "base_name" => base_name},
        socket
      ) do
    project = socket.assigns.project

    case Projects.update_animation_resource_base_name(project, ctor, base_name) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:animation_resources, load_animation_resources(project))
         |> EditorSupport.refresh_tree()
         |> put_flash(:info, "Updated animation resource name.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not rename animation: #{inspect(reason)}")}
    end
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

  defp normalize_upload_result({:ok, row}) when is_map(row), do: row
  defp normalize_upload_result(row) when is_map(row), do: row
  defp normalize_upload_result(_), do: nil

  defp upload_result_message("", results, summary_fun) do
    case import_failure_lines(results) do
      [] -> summary_fun.(results)
      lines -> Enum.join(lines, " ")
    end
  end

  defp upload_result_message(message, _results, _summary_fun) when is_binary(message), do: message

  defp import_failure_lines(results) do
    Enum.flat_map(results, fn
      {:ok, %{error: message}} when is_binary(message) -> [message]
      %{error: message} when is_binary(message) -> [message]
      _ -> []
    end)
  end

  defp maybe_flash_upload_result(socket, output, results) do
    failed? =
      output =~ "failed" or output =~ "requires" or output =~ "not " or
        output =~ "too large" or output =~ "Wait until" or
        Enum.any?(results, fn
          {:ok, %{error: _}} -> true
          %{error: _} -> true
          _ -> false
        end)

    uploaded? =
      Enum.any?(results, fn
        {:ok, row} when is_map(row) ->
          not Map.has_key?(row, :error) and Map.get(row, :duplicate) != true

        row when is_map(row) ->
          not Map.has_key?(row, :error) and Map.get(row, :duplicate) != true

        _ ->
          false
      end)

    cond do
      uploaded? ->
        put_flash(socket, :info, output)

      failed? ->
        put_flash(socket, :error, output)

      true ->
        socket
    end
  end
end
