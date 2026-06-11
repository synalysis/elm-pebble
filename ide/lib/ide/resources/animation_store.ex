defmodule Ide.Resources.AnimationStore do
  @moduledoc false

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.{ApngProbe, CtorNaming, GifToApng, ResourceStore}
  alias Ide.Resources.ResourceStore.Manifest
  alias Ide.Resources.Types

  @manifest_rel_path "watch/resources/animations.json"
  @assets_rel_dir "watch/resources/animations"

  @max_bytes 65_536
  @max_frames 64
  @max_dimension 200

  @type animation_resource_entry :: Types.animation_resource_entry()

  @spec manifest_rel_path() :: String.t()
  def manifest_rel_path, do: @manifest_rel_path

  @spec list(Project.t()) ::
          {:ok, [animation_resource_entry()]} | {:error, Types.resource_error()}
  def list(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_manifest(workspace) do
      entries =
        (manifest["entries"] || [])
        |> Enum.map(&animation_entry_from_row/1)
        |> Enum.filter(&animation_file_backed?(workspace, &1))

      {:ok, entries}
    end
  end

  @spec import_animation(Project.t(), String.t(), String.t()) :: Types.animation_import_result()
  def import_animation(%Project{} = project, upload_path, original_name)
      when is_binary(upload_path) and is_binary(original_name) do
    workspace = Projects.project_workspace_path(project)
    ext = Path.extname(original_name) |> String.downcase()

    with {:ok, apng_path, cleanup} <- apng_path_for_import(upload_path, ext, workspace),
         {:ok, bytes} <- File.read(apng_path),
         :ok <- validate_limits(bytes),
         {:ok, probe} <- ApngProbe.probe_bytes(bytes),
         :ok <- validate_probe(probe),
         {:ok, result} <- persist_animation(project, bytes, original_name, probe) do
      cleanup.()
      {:ok, result}
    else
      {:error, reason} ->
        {:error, reason}

      other ->
        other
    end
  end

  @spec delete_animation(Project.t(), String.t()) :: Types.delete_entries_result()
  def delete_animation(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @manifest_rel_path)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace) do
      entries = manifest["entries"] || []
      {to_remove, kept} = Enum.split_with(entries, &(Map.get(&1, "ctor") == ctor))

      Enum.each(to_remove, fn row ->
        filename = Map.get(row, "filename", "")
        if filename != "", do: File.rm(Path.join(assets_dir, filename))
      end)

      payload = %{"schema_version" => 1, "entries" => kept}

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- ResourceStore.ensure_generated(project) do
        {:ok, kept}
      end
    end
  end

  @spec animation_file_path(Project.t(), String.t()) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def animation_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace) do
      case Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)) do
        %{"filename" => filename} when is_binary(filename) and filename != "" ->
          path = Path.join(assets_dir, filename)
          if File.exists?(path), do: {:ok, path}, else: {:error, :missing_file}

        _ ->
          {:error, :not_found}
      end
    end
  end

  defp apng_path_for_import(upload_path, ".gif", workspace) do
    tmp = Path.join(workspace, ".tmp_animation_#{System.unique_integer([:positive])}.png")

    case GifToApng.convert(upload_path, tmp) do
      :ok ->
        {:ok, tmp, fn -> File.rm(tmp) end}

      {:error, :converter_missing} ->
        {:error, :gif_converter_missing}

      {:error, _} ->
        {:error, :gif_conversion_failed}
    end
  end

  defp apng_path_for_import(upload_path, ".png", _workspace) do
    {:ok, upload_path, fn -> :ok end}
  end

  defp apng_path_for_import(_upload_path, _ext, _workspace), do: {:error, :unsupported_format}

  defp validate_limits(bytes) when byte_size(bytes) <= @max_bytes, do: :ok
  defp validate_limits(_), do: {:error, :file_too_large}

  defp validate_probe(%{frame_count: frames, width: width, height: height})
       when frames <= @max_frames and width <= @max_dimension and height <= @max_dimension,
       do: :ok

  defp validate_probe(%{frame_count: frames}) when frames > @max_frames,
    do: {:error, :too_many_frames}

  defp validate_probe(%{width: width}) when width > @max_dimension,
    do: {:error, :dimensions_too_large}

  defp validate_probe(%{height: height}) when height > @max_dimension,
    do: {:error, :dimensions_too_large}

  defp validate_probe(_), do: {:error, :invalid_animation}

  defp persist_animation(project, bytes, original_name, probe) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    base_name = CtorNaming.base_name_from_filename(original_name)

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_manifest(workspace),
         nil <- duplicate_entry(manifest["entries"] || [], assets_dir, bytes),
         unique_ctor =
           CtorNaming.unique_ctor(:bitmap_animated, base_name, manifest["entries"] || []),
         basename = "#{unique_ctor}.png",
         :ok <- File.write(Path.join(assets_dir, basename), bytes) do
      play_count =
        case probe.play_count do
          :infinite -> 0
          count when is_integer(count) -> count
        end

      entry = %{
        "id" => "animation_" <> String.downcase(unique_ctor),
        "base_name" => CtorNaming.legacy_base_from_ctor(unique_ctor, :bitmap_animated),
        "ctor" => unique_ctor,
        "filename" => basename,
        "mime" => "image/png",
        "bytes" => byte_size(bytes),
        "width" => probe.width,
        "height" => probe.height,
        "frame_count" => probe.frame_count,
        "duration_ms" => probe.duration_ms,
        "play_count" => play_count
      }

      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == unique_ctor))
        |> Kernel.++([entry])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      payload = %{"schema_version" => 1, "entries" => entries}

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- ResourceStore.ensure_generated(project) do
        {:ok, %{entry: entry, entries: entries}}
      end
    else
      %{} = duplicate ->
        {:ok, %{duplicate: true, entry: duplicate}}

      other ->
        other
    end
  end

  defp duplicate_entry(entries, assets_dir, bytes) do
    Enum.find_value(entries, fn row ->
      filename = Map.get(row, "filename", "")
      path = Path.join(assets_dir, filename)

      if filename != "" and File.exists?(path) do
        case File.read(path) do
          {:ok, existing} when existing == bytes -> row
          _ -> nil
        end
      end
    end)
  end

  defp animation_file_backed?(workspace, row) when is_map(row) do
    filename =
      Map.get(row, :filename) ||
        Map.get(row, "filename") ||
        ""

    filename != "" and File.exists?(Path.join([workspace, @assets_rel_dir, filename]))
  end

  @spec migrate_manifest(String.t()) :: :ok | {:error, Types.resource_error()}
  def migrate_manifest(workspace) when is_binary(workspace) do
    manifest_path = Path.join(workspace, @manifest_rel_path)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace) do
      {entries, changed?} =
        Enum.map_reduce(manifest["entries"] || [], false, fn row, changed ->
          migrated = migrate_animation_row(assets_dir, row)
          {migrated, changed or migrated != row}
        end)

      if changed? do
        write_manifest(manifest_path, %{"schema_version" => 1, "entries" => entries})
      else
        :ok
      end
    end
  end

  @spec update_base_name(Project.t(), String.t(), String.t()) :: Types.rename_result()
  def update_base_name(%Project{} = project, old_ctor, new_base)
      when is_binary(old_ctor) and is_binary(new_base) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with {:ok, manifest} <- read_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == old_ctor)) do
      new_ctor =
        CtorNaming.unique_ctor(
          :bitmap_animated,
          new_base,
          manifest["entries"] || [],
          exclude_ctor: old_ctor
        )

      migrated_row = migrate_animation_row(assets_dir, row, old_ctor, new_ctor, new_base)

      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == old_ctor))
        |> Kernel.++([migrated_row])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      with :ok <- write_manifest(manifest_path, %{"schema_version" => 1, "entries" => entries}),
           :ok <- ResourceStore.ensure_generated(project) do
        {:ok, %{entry: migrated_row, entries: entries}}
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec migrate_animation_row(
          String.t(),
          Types.manifest_wire_row(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: Types.manifest_wire_row()
  defp migrate_animation_row(assets_dir, row, old_ctor \\ nil, new_ctor \\ nil, new_base \\ nil) do
    old_ctor = old_ctor || Map.get(row, "ctor", "")
    ensured = CtorNaming.ensure_row!(row, :bitmap_animated)
    new_ctor = new_ctor || Map.get(ensured, "ctor", "")

    if old_ctor == new_ctor do
      ensured
    else
      old_path = Path.join(assets_dir, Map.get(row, "filename", "#{old_ctor}.png"))
      new_filename = "#{new_ctor}.png"
      new_path = Path.join(assets_dir, new_filename)

      if File.exists?(old_path) do
        File.rename!(old_path, new_path)
      end

      ensured
      |> Map.put("filename", new_filename)
      |> CtorNaming.row_with_ctor(:bitmap_animated, new_ctor, new_base)
    end
  end

  @spec animation_entry_from_row(Types.manifest_wire_row()) :: animation_resource_entry()
  defp animation_entry_from_row(row) when is_map(row) do
    row = CtorNaming.ensure_row!(row, :bitmap_animated)

    play_count =
      case Map.get(row, "play_count", 0) do
        0 -> :infinite
        count when is_integer(count) -> count
        _ -> :infinite
      end

    %{
      id: to_string(Map.get(row, "id", "")),
      ctor: to_string(Map.get(row, "ctor", "")),
      base_name: to_string(Map.get(row, "base_name", "")),
      filename: to_string(Map.get(row, "filename", "")),
      mime: to_string(Map.get(row, "mime", "image/png")),
      bytes: Map.get(row, "bytes", 0),
      width: Map.get(row, "width", 0),
      height: Map.get(row, "height", 0),
      frame_count: Map.get(row, "frame_count", 0),
      duration_ms: Map.get(row, "duration_ms", 0),
      play_count: play_count
    }
  end

  @spec read_manifest(Types.workspace_path()) ::
          {:ok, Types.manifest()} | {:error, Types.resource_error() | :invalid_manifest}
  defp read_manifest(workspace) do
    Manifest.read_animation_manifest(workspace, strict: true)
  end

  @spec write_manifest(Path.t(), Types.manifest()) ::
          :ok | {:error, Types.manifest_io_error()}
  defp write_manifest(path, payload) do
    Manifest.write_manifest(path, payload)
  end
end
