defmodule Ide.Resources.ResourceStore.Bitmaps do
  @moduledoc false

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.{
    BitmapMonochrome,
    BitmapRaster,
    BitmapVariants,
    CtorNaming,
    PngInfo
  }

  @stored_bitmap_ext ".png"

  alias Ide.Resources.ResourceStore.{Coercion, CtorDedup, Duplicates, Manifest}
  alias Ide.Resources.Types

  @manifest_rel_path "watch/resources/bitmaps.json"
  @assets_rel_dir "watch/resources/bitmaps"

  @type bitmap_variant_entry :: Types.bitmap_variant_entry()
  @type bitmap_entry :: Types.bitmap_entry()

  @spec manifest_rel_path() :: String.t()
  def manifest_rel_path, do: @manifest_rel_path

  @spec list(Project.t()) :: {:ok, [bitmap_entry()]} | {:error, Types.resource_error()}
  def list(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_manifest(workspace) do
      entries = manifest["entries"] || []

      {:ok, Enum.map(entries, &bitmap_entry_from_row/1)}
    end
  end

  @doc """
  Registers every `*.png` in the bitmap assets directory (or `dir`) that is not already
  recorded in `bitmaps.json`. Existing ctors are left unchanged; duplicate file bytes are skipped.
  """
  @spec import_bitmaps_from_directory(Project.t(), String.t() | nil, keyword()) ::
          {:ok, Types.bitmap_directory_import_stats()}
  def import_bitmaps_from_directory(%Project{} = project, dir \\ nil, opts \\ []) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = dir || Path.join(workspace, @assets_rel_dir)
    import_opts = Keyword.take(opts, [:color_mode, :ctor])

    result =
      assets_dir
      |> Path.join("*.png")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce(%{imported: 0, skipped: 0, duplicates: 0}, fn path, acc ->
        case import_bitmap(project, path, Path.basename(path), import_opts) do
          {:ok, %{duplicate: true}} ->
            %{acc | duplicates: acc.duplicates + 1}

          {:ok, _} ->
            %{acc | imported: acc.imported + 1}

          {:error, _} ->
            %{acc | skipped: acc.skipped + 1}
        end
      end)

    {:ok, result}
  end

  @spec import_bitmap(Project.t(), String.t(), String.t(), keyword()) ::
          Types.bitmap_import_result()
  def import_bitmap(%Project{} = project, upload_path, original_name, opts \\ [])
      when is_binary(upload_path) and is_binary(original_name) and is_list(opts) do
    color_mode = Keyword.get(opts, :color_mode)
    ctor_hint = Keyword.get(opts, :ctor)

    with {:ok, bytes} <- File.read(upload_path),
         {:ok, prepared} <- BitmapRaster.normalize_for_import(bytes, original_name) do
      if is_binary(color_mode) and BitmapVariants.valid_color_mode?(color_mode) do
        import_bitmap_variant_prepared(project, prepared, color_mode, ctor_hint)
      else
        import_bitmap_legacy_prepared(project, prepared)
      end
    end
  end

  defp import_bitmap_legacy_prepared(%Project{} = project, prepared) do
    if PngInfo.color_palette_image?(prepared.bytes) do
      import_bitmap_variant_prepared(project, prepared, "Color", nil)
    else
      import_bitmap_legacy_universal_prepared(project, prepared)
    end
  end

  defp import_bitmap_legacy_universal_prepared(%Project{} = project, prepared) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)
    %{bytes: bytes, width: width, height: height, safe_name: safe_name} = prepared

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_manifest(workspace),
         nil <- Duplicates.duplicate_asset_entry(manifest["entries"] || [], assets_dir, bytes),
         base_name <- CtorNaming.base_name_from_filename(safe_name),
         unique_ctor <-
           CtorNaming.unique_ctor(:bitmap_static, base_name, manifest["entries"] || []),
         basename <- BitmapVariants.legacy_filename(unique_ctor, @stored_bitmap_ext),
         :ok <- remove_bitmap_row_files(assets_dir, existing_row(manifest, unique_ctor)),
         :ok <- File.write(Path.join(assets_dir, basename), bytes) do
      entry =
        BitmapVariants.normalize_row(%{
          "id" => "bitmap_" <> String.downcase(unique_ctor),
          "base_name" => CtorNaming.legacy_base_from_ctor(unique_ctor, :bitmap_static),
          "ctor" => unique_ctor,
          "filename" => basename,
          "mime" => "image/png",
          "bytes" => byte_size(bytes),
          "width" => width,
          "height" => height,
          "variants" => %{}
        })

      persist_bitmap_entries(workspace, manifest_path, manifest, entry)
    else
      %{} = duplicate ->
        {:ok, %{duplicate: true, entry: duplicate}}

      other ->
        other
    end
  end

  defp import_bitmap_variant_prepared(%Project{} = project, prepared, color_mode, ctor_hint) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)
    %{bytes: bytes, width: width, height: height, safe_name: safe_name} = prepared

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_manifest(workspace),
         ctor <- resolve_bitmap_ctor(manifest, safe_name, ctor_hint),
         unique_ctor <- CtorDedup.among_entries(ctor, manifest["entries"] || [], ctor_hint),
         basename <-
           BitmapVariants.variant_filename(unique_ctor, color_mode, @stored_bitmap_ext),
         nil <- duplicate_variant_asset(manifest, assets_dir, bytes, unique_ctor, basename),
         :ok <- File.write(Path.join(assets_dir, basename), bytes) do
      prior = existing_row(manifest, unique_ctor) |> BitmapVariants.normalize_row()

      variants =
        prior
        |> Map.get("variants", %{})
        |> Map.put(color_mode, %{
          "filename" => basename,
          "mime" => "image/png",
          "bytes" => byte_size(bytes),
          "width" => width,
          "height" => height
        })

      :ok = remove_legacy_filename(assets_dir, prior)

      entry =
        prior
        |> Map.put("ctor", unique_ctor)
        |> Map.put("base_name", CtorNaming.legacy_base_from_ctor(unique_ctor, :bitmap_static))
        |> Map.put("id", "bitmap_" <> String.downcase(unique_ctor))
        |> Map.put("variants", variants)
        |> Map.drop(["filename", "mime", "bytes", "width", "height"])
        |> BitmapVariants.normalize_row()

      with {:ok, %{entry: entry} = result} <-
             persist_bitmap_entries(workspace, manifest_path, manifest, entry) do
        finalize_color_bitmap_import(
          workspace,
          assets_dir,
          manifest_path,
          result,
          entry,
          bytes,
          @stored_bitmap_ext
        )
      end
    else
      %{} = duplicate ->
        {:ok, %{duplicate: true, entry: duplicate}}

      other ->
        other
    end
  end

  @spec clear_bitmap_variant(Project.t(), String.t(), String.t()) ::
          Types.delete_entries_result()
  def clear_bitmap_variant(%Project{} = project, ctor, color_mode)
      when is_binary(ctor) and is_binary(color_mode) do
    unless BitmapVariants.valid_color_mode?(color_mode) do
      raise ArgumentError, "invalid bitmap color mode #{inspect(color_mode)}"
    end

    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with {:ok, manifest} <- read_manifest(workspace),
         %{} = row <- existing_row(manifest, ctor) do
      normalized = BitmapVariants.normalize_row(row)
      variant = Map.get(normalized["variants"], color_mode)

      if is_map(variant) do
        filename = Map.get(variant, "filename", "")
        if filename != "", do: File.rm(Path.join(assets_dir, filename))
      end

      variants = Map.delete(normalized["variants"], color_mode)

      entry =
        if map_size(variants) == 0 and not Map.has_key?(normalized, "filename") do
          nil
        else
          normalized |> Map.put("variants", variants) |> BitmapVariants.normalize_row()
        end

      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == ctor))
        |> then(fn kept ->
          if entry, do: kept ++ [entry], else: kept
        end)
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      payload = %{"schema_version" => 2, "entries" => entries}

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok, entries}
      end
    else
      _ -> {:error, :bitmap_not_found}
    end
  end
  @spec delete_bitmap(Project.t(), String.t()) :: Types.delete_entries_result()
  def delete_bitmap(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @manifest_rel_path)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace) do
      entries = manifest["entries"] || []

      {to_remove, kept} = Enum.split_with(entries, &(Map.get(&1, "ctor") == ctor))

      Enum.each(to_remove, &remove_bitmap_row_files(assets_dir, &1))

      payload = %{"schema_version" => 2, "entries" => kept}

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok, kept}
      end
    end
  end
  @spec update_bitmap_base_name(Project.t(), String.t(), String.t()) :: Types.rename_result()
  def update_bitmap_base_name(%Project{} = project, old_ctor, new_base)
      when is_binary(old_ctor) and is_binary(new_base) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with {:ok, manifest} <- read_manifest(workspace),
         %{} = row <- existing_row(manifest, old_ctor) do
      new_ctor =
        CtorNaming.unique_ctor(
          :bitmap_static,
          new_base,
          manifest["entries"] || [],
          exclude_ctor: old_ctor
        )

      migrated_row = migrate_bitmap_row_files(assets_dir, row, old_ctor, new_ctor, new_base)

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
      nil -> {:error, :bitmap_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
  @spec bitmap_file_path(Project.t(), String.t()) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def bitmap_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    bitmap_file_path(project, ctor, nil)
  end

  @spec bitmap_file_path(Project.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def bitmap_file_path(%Project{} = project, ctor, color_mode)
      when is_binary(ctor) and (is_binary(color_mode) or is_nil(color_mode)) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace),
         %{} = row <- existing_row(manifest, ctor),
         filename when is_binary(filename) and filename != "" <-
           bitmap_preview_filename(row, color_mode) do
      {:ok, Path.join(assets_dir, filename)}
    else
      _ -> {:error, :bitmap_not_found}
    end
  end
  @spec read_manifest(Types.workspace_path()) ::
          {:ok, Types.manifest()} | {:error, Types.resource_error()}
  defp read_manifest(workspace), do: Manifest.read_bitmap_manifest(workspace)

  defp duplicate_variant_asset(manifest, assets_dir, bytes, ctor, basename) do
    case File.read(Path.join(assets_dir, basename)) do
      {:ok, ^bytes} ->
        existing_row(manifest, ctor)

      _ ->
        nil
    end
  end

  defp persist_bitmap_entries(workspace, manifest_path, manifest, entry) do
    entries =
      (manifest["entries"] || [])
      |> Enum.reject(&(Map.get(&1, "ctor") == Map.get(entry, "ctor")))
      |> Kernel.++([entry])
      |> Enum.sort_by(&Map.get(&1, "ctor", ""))

    payload = %{"schema_version" => 2, "entries" => entries}

    with :ok <- Manifest.write_manifest(manifest_path, payload),
         :ok <- Manifest.write_generated_module(workspace) do
      {:ok, %{entry: entry, entries: entries}}
    end
  end

  defp finalize_color_bitmap_import(
         workspace,
         assets_dir,
         manifest_path,
         result,
         entry,
         color_bytes,
         ext
       )
       when is_map(result) and is_map(entry) and is_binary(color_bytes) and is_binary(ext) do
    entries = Map.get(result, :entries) || Map.get(result, "entries") || []

    case append_auto_black_white_variant(
           workspace,
           assets_dir,
           manifest_path,
           entries,
           entry,
           color_bytes,
           ext
         ) do
      {:ok, updated_entry} ->
        {:ok, result |> Map.put(:entry, updated_entry) |> Map.put(:auto_black_white, true)}

      :skip ->
        {:ok, result}

      {:error, reason} ->
        {:ok, Map.put(result, :auto_black_white_error, reason)}
    end
  end

  defp append_auto_black_white_variant(
         workspace,
         assets_dir,
         manifest_path,
         entries,
         entry,
         color_bytes,
         ext
       )
       when is_list(entries) and is_map(entry) and is_binary(color_bytes) and is_binary(ext) do
    normalized = BitmapVariants.normalize_row(entry)

    if Map.has_key?(Map.get(normalized, "variants", %{}), "BlackWhite") do
      :skip
    else
      with {:ok, bw_bytes} <- BitmapMonochrome.convert_bytes(color_bytes),
           basename <-
             BitmapVariants.variant_filename(
               Map.get(normalized, "ctor", ""),
               "BlackWhite",
               ext
             ),
           :ok <- File.write(Path.join(assets_dir, basename), bw_bytes) do
        {width, height} = bitmap_dimensions(bw_bytes, "image/png")

        variants =
          Map.put(Map.get(normalized, "variants", %{}), "BlackWhite", %{
            "filename" => basename,
            "mime" => "image/png",
            "bytes" => byte_size(bw_bytes),
            "width" => width,
            "height" => height
          })

        updated =
          normalized
          |> Map.put("variants", variants)
          |> BitmapVariants.normalize_row()

        updated_entries =
          entries
          |> Enum.reject(&(Map.get(&1, "ctor") == Map.get(updated, "ctor")))
          |> Kernel.++([updated])
          |> Enum.sort_by(&Map.get(&1, "ctor", ""))

        payload = %{"schema_version" => 2, "entries" => updated_entries}

        with :ok <- Manifest.write_manifest(manifest_path, payload),
             :ok <- Manifest.write_generated_module(workspace) do
          {:ok, updated}
        end
      else
        {:error, :converter_missing} -> {:error, :monochrome_converter_missing}
        {:error, :conversion_failed} -> {:error, :monochrome_conversion_failed}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp existing_row(manifest, ctor) do
    Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)) || %{}
  end

  defp remove_bitmap_row_files(assets_dir, row) when is_map(row) do
    Enum.each(BitmapVariants.filenames_for_row(row), fn filename ->
      path = Path.join(assets_dir, filename)
      if File.exists?(path), do: File.rm(path)
    end)

    :ok
  end

  defp remove_bitmap_row_files(_assets_dir, _), do: :ok

  defp remove_legacy_filename(assets_dir, row) when is_map(row) do
    case Map.get(row, "filename") do
      filename when is_binary(filename) and filename != "" ->
        path = Path.join(assets_dir, filename)
        if File.exists?(path), do: File.rm(path)
        :ok

      _ ->
        :ok
    end
  end

  defp resolve_bitmap_ctor(manifest, safe_name, ctor_hint) do
    base = CtorNaming.base_name_from_filename(safe_name)

    cond do
      is_binary(ctor_hint) and ctor_hint != "" ->
        ctor_hint

      true ->
        case existing_row(manifest, CtorNaming.ctor(:bitmap_static, base)) do
          %{"ctor" => ctor} -> ctor
          _ -> CtorNaming.ctor(:bitmap_static, base)
        end
    end
  end

  defp bitmap_preview_filename(row, color_mode) do
    normalized = BitmapVariants.normalize_row(row)
    variants = Map.get(normalized, "variants", %{})

    cond do
      is_binary(color_mode) ->
        variant_filename(variants, color_mode) ||
          variant_filename(variants, "Color") ||
          variant_filename(variants, "BlackWhite") ||
          legacy_filename(normalized)

      true ->
        variant_filename(variants, "Color") ||
          variant_filename(variants, "BlackWhite") ||
          legacy_filename(normalized)
    end
  end

  defp variant_filename(variants, color_mode) do
    case Map.get(variants, color_mode) do
      %{"filename" => filename} when is_binary(filename) and filename != "" -> filename
      _ -> nil
    end
  end

  defp legacy_filename(row) do
    case Map.get(row, "filename") do
      filename when is_binary(filename) and filename != "" -> filename
      _ -> nil
    end
  end

  defp bitmap_entry_from_row(row) when is_map(row) do
    normalized = BitmapVariants.normalize_row(row)
    {width, height} = BitmapVariants.primary_dimensions(normalized)

    variants =
      normalized
      |> Map.get("variants", %{})
      |> Enum.map(fn {mode, variant} ->
        {mode,
         %{
           filename: Map.get(variant, "filename", ""),
           mime: Map.get(variant, "mime", "image/png"),
           bytes: Coercion.integer_or_zero(Map.get(variant, "bytes", 0)),
           width: Coercion.integer_or_zero(Map.get(variant, "width", 0)),
           height: Coercion.integer_or_zero(Map.get(variant, "height", 0))
         }}
      end)
      |> Map.new()

    row = CtorNaming.ensure_row!(normalized, :bitmap_static)

    %{
      id: Map.get(row, "id", ""),
      ctor: Map.get(row, "ctor", ""),
      base_name: Map.get(row, "base_name", ""),
      filename: Map.get(row, "filename"),
      mime: Map.get(normalized, "mime"),
      bytes: Coercion.integer_or_zero(Map.get(normalized, "bytes", 0)),
      width: width,
      height: height,
      variants: variants
    }
  end

  @spec bitmap_dimensions(binary(), String.t()) :: {non_neg_integer(), non_neg_integer()}
  defp bitmap_dimensions(
         <<0x89, "PNG\r\n", 0x1A, "\n", _len::32, "IHDR", width::32, height::32, _::binary>>,
         "image/png"
       ),
       do: {width, height}

  defp bitmap_dimensions(_bytes, _mime), do: {0, 0}

  @spec migrate_manifest(Types.workspace_path()) :: :ok | {:error, Types.resource_error()}
  def migrate_manifest(workspace) do
    manifest_path = Path.join(workspace, @manifest_rel_path)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    case read_manifest(workspace) do
      {:ok, manifest} ->
        {entries, changed?} =
          Enum.map_reduce(manifest["entries"] || [], false, fn row, changed ->
            migrated = migrate_bitmap_row_files(assets_dir, row)
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
  defp migrate_bitmap_row_files(
         assets_dir,
         row,
         old_ctor \\ nil,
         new_ctor \\ nil,
         new_base \\ nil
       ) do
    old_ctor = old_ctor || Map.get(row, "ctor", "")
    ensured = CtorNaming.ensure_row!(row, :bitmap_static)
    new_ctor = new_ctor || Map.get(ensured, "ctor", "")

    if old_ctor == new_ctor do
      ensured
    else
      Enum.each(BitmapVariants.filenames_for_row(row), fn filename ->
        old_path = Path.join(assets_dir, filename)

        if File.exists?(old_path) do
          new_filename = String.replace_prefix(filename, old_ctor, new_ctor)
          File.rename!(old_path, Path.join(assets_dir, new_filename))
        end
      end)

      ensured
      |> rewrite_ctor_in_row_filenames(old_ctor, new_ctor)
      |> CtorNaming.row_with_ctor(:bitmap_static, new_ctor, new_base)
    end
  end
  defp rewrite_ctor_in_row_filenames(row, old_ctor, new_ctor) do
    variants =
      row
      |> Map.get("variants", %{})
      |> Enum.map(fn {mode, variant} ->
        filename = Map.get(variant, "filename", "")

        new_filename =
          if filename != "" do
            String.replace_prefix(filename, old_ctor, new_ctor)
          else
            filename
          end

        {mode, Map.put(variant, "filename", new_filename)}
      end)
      |> Map.new()

    legacy =
      case Map.get(row, "filename") do
        filename when is_binary(filename) and filename != "" ->
          String.replace_prefix(filename, old_ctor, new_ctor)

        other ->
          other
      end

    row
    |> Map.put("variants", variants)
    |> Map.put("filename", legacy)
  end

  @spec bitmap_file_path_by_id(Project.t(), integer()) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def bitmap_file_path_by_id(%Project{} = project, id) when is_integer(id) and id >= 1 do
    with {:ok, entries} <- list(project),
         %{} = row <- Enum.at(entries, id - 1) do
      bitmap_file_path(project, row.ctor)
    else
      _ -> {:error, :bitmap_not_found}
    end
  end

  def bitmap_file_path_by_id(_project, _), do: {:error, :bitmap_not_found}
end
