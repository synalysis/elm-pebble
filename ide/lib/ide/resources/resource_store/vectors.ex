defmodule Ide.Resources.ResourceStore.Vectors do
  @moduledoc false

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.{CtorNaming, PdcDecoder, SvgConverter}
  alias Ide.Resources.ResourceStore.{Coercion, Duplicates, Manifest}
  alias Ide.Resources.Types

  @vector_manifest_rel_path "watch/resources/vectors.json"
  @vector_assets_rel_dir "watch/resources/vectors"

  @type vector_entry :: Types.vector_entry()
  @type vector_import_extras :: Types.vector_import_extras()

  @spec list_vectors(Project.t()) :: {:ok, [vector_entry()]} | {:error, Types.resource_error()}
  def list_vectors(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_manifest(workspace) do
      entries = file_backed_vector_entries(workspace, manifest["entries"] || [])

      {:ok,
       Enum.map(entries, fn row ->
         row = CtorNaming.ensure_row!(row, CtorNaming.vector_kind_from_row(row))

         %{
           id: to_string(Map.get(row, "id", "")),
           ctor: to_string(Map.get(row, "ctor", "")),
           base_name: to_string(Map.get(row, "base_name", "")),
           filename: to_string(Map.get(row, "filename", "")),
           mime: to_string(Map.get(row, "mime", "application/octet-stream")),
           bytes: Coercion.integer_or_zero(Map.get(row, "bytes", 0)),
           source: to_string(Map.get(row, "source", "pdc")),
           kind: to_string(Map.get(row, "kind", "image")),
           frames: optional_positive_int(Map.get(row, "frames")),
           frame_duration_ms: optional_positive_int(Map.get(row, "frame_duration_ms"))
         }
       end)}
    end
  end

  @spec import_vector(Project.t(), String.t(), String.t()) :: Types.vector_import_result()
  def import_vector(%Project{} = project, upload_path, original_name)
      when is_binary(upload_path) and is_binary(original_name) do
    import_vector(project, upload_path, original_name, [])
  end

  @spec import_vector(Project.t(), String.t(), String.t(), keyword()) ::
          Types.vector_import_result()
  def import_vector(%Project{} = project, upload_path, original_name, opts)
      when is_binary(upload_path) and is_binary(original_name) and is_list(opts) do
    with {:ok, safe_name, mime, source_kind} <- normalized_vector_filename(original_name),
         {:ok, pdc_bytes, extras} <-
           vector_bytes_from_upload(upload_path, safe_name, source_kind, opts) do
      persist_vector_bytes(project, pdc_bytes, safe_name, mime, source_kind, extras)
    end
  end

  @spec import_vector_svg(Project.t(), String.t(), String.t(), keyword()) ::
          Types.vector_import_result()
  def import_vector_svg(%Project{} = project, upload_path, original_name, opts)
      when is_binary(upload_path) and is_binary(original_name) do
    with {:ok, svg} <- File.read(upload_path),
         {:ok, result} <- SvgConverter.convert(svg, opts),
         :ok <- SvgConverter.validate_pdc_bytes(result.bytes),
         :ok <- PdcDecoder.validate_watch_compatible(result.bytes),
         {:ok, preview_svg} <- PdcDecoder.preview_svg(result.bytes) do
      safe_name =
        original_name
        |> Path.basename()
        |> then(&base_name(&1, ".svg"))

      persist_vector_bytes(project, result.bytes, safe_name, "image/svg+xml", "svg", %{
        report: result.report,
        preview_svg: preview_svg,
        kind: "image"
      })
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec import_vector_sequence(Project.t(), [String.t()], String.t(), keyword()) ::
          Types.vector_import_result()
  def import_vector_sequence(%Project{} = project, frames, original_name, opts)
      when is_list(frames) and is_binary(original_name) do
    opts = Keyword.put_new(opts, :play_count, 0)

    with {:ok, result} <- SvgConverter.convert_svg_sequence(frames, opts),
         :ok <- SvgConverter.validate_pdc_bytes(result.bytes),
         :ok <- PdcDecoder.validate_watch_compatible(result.bytes),
         {:ok, preview_svg} <- PdcDecoder.preview_svg(result.bytes) do
      safe_name =
        original_name
        |> Path.basename()
        |> then(fn name ->
          root = Path.rootname(name)

          if String.ends_with?(String.downcase(name), ".pdc") do
            String.downcase(name)
          else
            String.downcase(root <> ".pdc")
          end
        end)

      persist_vector_bytes(project, result.bytes, safe_name, "application/octet-stream", "svg", %{
        report: result.report,
        preview_svg: preview_svg,
        kind: "sequence",
        frames: length(frames),
        frame_duration_ms: Keyword.get(opts, :frame_duration_ms, 100)
      })
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_vector_bytes(project, pdc_bytes, safe_name, mime, source_kind, extras) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)
    manifest_path = Path.join(workspace, @vector_manifest_rel_path)
    vector_kind = vector_import_kind(extras)
    base_name = CtorNaming.base_name_from_filename(Path.rootname(safe_name))

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_manifest(workspace),
         nil <- Duplicates.duplicate_asset_entry(manifest["entries"] || [], assets_dir, pdc_bytes),
         unique_ctor = CtorNaming.unique_ctor(vector_kind, base_name, manifest["entries"] || []),
         basename = "#{unique_ctor}.pdc",
         asset_path <- Path.join(assets_dir, basename),
         :ok <- File.write(asset_path, pdc_bytes) do
      entry =
        %{
          "id" => "vector_" <> String.downcase(unique_ctor),
          "base_name" => CtorNaming.legacy_base_from_ctor(unique_ctor, vector_kind),
          "ctor" => unique_ctor,
          "filename" => basename,
          "mime" => mime,
          "bytes" => byte_size(pdc_bytes),
          "source" => source_kind,
          "kind" => Map.get(extras, :kind, vector_kind_from_bytes(pdc_bytes))
        }
        |> maybe_put_int("frames", Map.get(extras, :frames))
        |> maybe_put_int("frame_duration_ms", Map.get(extras, :frame_duration_ms))

      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == unique_ctor))
        |> Kernel.++([entry])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      payload = %{"schema_version" => 1, "entries" => entries}

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok,
         %{
           entry: entry,
           entries: entries,
           preview_svg: Map.get(extras, :preview_svg),
           report: Map.get(extras, :report)
         }}
      end
    else
      %{} = duplicate ->
        {:ok, %{duplicate: true, entry: duplicate}}

      other ->
        other
    end
  end

  defp vector_kind_from_bytes(bytes) when is_binary(bytes) do
    case SvgConverter.pdc_magic(bytes) do
      "PDCS" -> "sequence"
      _ -> "image"
    end
  end

  defp maybe_put_int(map, _key, nil), do: map
  defp maybe_put_int(map, key, value) when is_integer(value), do: Map.put(map, key, value)
  defp maybe_put_int(map, _key, _value), do: map

  defp optional_positive_int(value) when is_integer(value) and value > 0, do: value
  defp optional_positive_int(_), do: nil

  defp file_backed_vector_entries(workspace, entries) when is_list(entries) do
    assets_root = Path.join(workspace, @vector_assets_rel_dir)

    Enum.filter(entries, fn row ->
      filename = to_string(Map.get(row, "filename", ""))
      filename != "" and File.exists?(Path.join(assets_root, filename))
    end)
  end

  @spec delete_vector(Project.t(), String.t()) :: Types.delete_entries_result()
  def delete_vector(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @vector_manifest_rel_path)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace) do
      entries = manifest["entries"] || []
      {to_remove, kept} = Enum.split_with(entries, &(Map.get(&1, "ctor") == ctor))

      Enum.each(to_remove, fn row ->
        filename = Map.get(row, "filename", "")
        if filename != "", do: File.rm(Path.join(assets_dir, filename))
      end)

      payload = %{"schema_version" => 1, "entries" => kept}

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok, kept}
      end
    end
  end

  @spec vector_file_path(Project.t(), String.t()) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def vector_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)),
         filename when is_binary(filename) and filename != "" <- Map.get(row, "filename") do
      {:ok, Path.join(assets_dir, filename)}
    else
      _ -> {:error, :vector_not_found}
    end
  end
  @spec update_vector_base_name(Project.t(), String.t(), String.t()) :: Types.rename_result()
  def update_vector_base_name(%Project{} = project, old_ctor, new_base)
      when is_binary(old_ctor) and is_binary(new_base) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)
    manifest_path = Path.join(workspace, @vector_manifest_rel_path)

    with {:ok, manifest} <- read_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == old_ctor)) do
      kind = CtorNaming.vector_kind_from_row(row)

      new_ctor =
        CtorNaming.unique_ctor(kind, new_base, manifest["entries"] || [], exclude_ctor: old_ctor)

      migrated_row = migrate_vector_row_files(assets_dir, row, old_ctor, new_ctor, kind, new_base)

      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == old_ctor))
        |> Kernel.++([migrated_row])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      with :ok <-
             Manifest.write_manifest(manifest_path, %{"schema_version" => 1, "entries" => entries}),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok, %{entry: migrated_row, entries: entries}}
      end
    else
      nil -> {:error, :vector_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
  @spec read_manifest(Types.workspace_path()) ::
          {:ok, Types.manifest()} | {:error, Types.resource_error()}
  defp read_manifest(workspace), do: Manifest.read_vector_manifest(workspace)

  @spec normalized_vector_filename(String.t()) ::
          {:ok, String.t(), String.t(), String.t()} | {:error, Types.asset_type_error()}
  defp normalized_vector_filename(original_name) do
    ext =
      original_name
      |> Path.extname()
      |> String.downcase()

    case ext do
      ".pdc" ->
        base_name(original_name, ext)
        |> then(fn base -> {:ok, base, "application/octet-stream", "pdc"} end)

      ".svg" ->
        base_name(original_name, ext)
        |> then(fn base -> {:ok, base, "image/svg+xml", "svg"} end)

      _ ->
        {:error, :unsupported_vector_type}
    end
  end

  defp base_name(original_name, ext) do
    original_name
    |> Path.basename()
    |> Path.rootname()
    |> String.replace(~r/[^A-Za-z0-9_-]+/, "_")
    |> String.trim("_")
    |> case do
      "" -> "vector" <> ext
      value -> String.downcase(value) <> ext
    end
  end

  @spec vector_bytes_from_upload(Path.t(), String.t(), String.t(), keyword()) ::
          {:ok, binary(), vector_import_extras()} | {:error, Types.resource_error()}
  defp vector_bytes_from_upload(upload_path, _safe_name, "pdc", _opts) do
    case File.read(upload_path) do
      {:ok, bytes} ->
        with :ok <- SvgConverter.validate_pdc_bytes(bytes),
             :ok <- PdcDecoder.validate_watch_compatible(bytes) do
          extras = %{
            kind: vector_kind_from_bytes(bytes),
            preview_svg: preview_svg_for_bytes(bytes)
          }

          {:ok, bytes, extras}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp vector_bytes_from_upload(upload_path, _safe_name, "svg", opts) do
    case File.read(upload_path) do
      {:ok, svg} ->
        with {:ok, result} <- SvgConverter.convert(svg, opts),
             :ok <- SvgConverter.validate_pdc_bytes(result.bytes),
             :ok <- PdcDecoder.validate_watch_compatible(result.bytes),
             {:ok, preview_svg} <- PdcDecoder.preview_svg(result.bytes) do
          {:ok, result.bytes, %{report: result.report, preview_svg: preview_svg, kind: "image"}}
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp vector_bytes_from_upload(_upload_path, _safe_name, _kind, _opts),
    do: {:error, :unsupported_vector_type}

  defp preview_svg_for_bytes(bytes) do
    case PdcDecoder.preview_svg(bytes) do
      {:ok, svg} -> svg
      _ -> nil
    end
  end
  @spec migrate_manifest(Types.workspace_path()) :: :ok | {:error, Types.resource_error()}
  def migrate_manifest(workspace) do
    manifest_path = Path.join(workspace, @vector_manifest_rel_path)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)

    case read_manifest(workspace) do
      {:ok, manifest} ->
        {entries, changed?} =
          Enum.map_reduce(manifest["entries"] || [], false, fn row, changed ->
            kind = CtorNaming.vector_kind_from_row(row)
            migrated = migrate_vector_row_files(assets_dir, row, Map.get(row, "ctor"), nil, kind)
            {migrated, changed or migrated != row}
          end)

        if changed? do
          Manifest.write_manifest(manifest_path, %{"schema_version" => 1, "entries" => entries})
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp migrate_vector_row_files(assets_dir, row, old_ctor, new_ctor, kind, new_base \\ nil) do
    old_ctor = old_ctor || Map.get(row, "ctor", "")
    ensured = CtorNaming.ensure_row!(row, kind)
    new_ctor = new_ctor || Map.get(ensured, "ctor", "")

    if old_ctor == new_ctor do
      ensured
    else
      old_filename = Map.get(row, "filename", "#{old_ctor}.pdc")
      new_filename = "#{new_ctor}.pdc"
      old_path = Path.join(assets_dir, old_filename)
      new_path = Path.join(assets_dir, new_filename)

      if File.exists?(old_path) do
        File.rename!(old_path, new_path)
      end

      ensured
      |> Map.put("filename", new_filename)
      |> CtorNaming.row_with_ctor(kind, new_ctor, new_base)
    end
  end

  defp vector_import_kind(extras) do
    case Map.get(extras, :kind) do
      "sequence" -> :vector_animated
      _ -> :vector_static
    end
  end

  @spec vector_file_path_by_id(Project.t(), integer()) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def vector_file_path_by_id(%Project{} = project, id) when is_integer(id) and id >= 1 do
    with {:ok, entries} <- list_vectors(project),
         %{} = row <- Enum.at(entries, id - 1) do
      vector_file_path(project, row.ctor)
    else
      _ -> {:error, :vector_not_found}
    end
  end

  def vector_file_path_by_id(_project, _), do: {:error, :vector_not_found}
end
