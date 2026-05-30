defmodule Ide.Resources.ResourceStore do
  @moduledoc """
  Project-local resource storage and generated Elm resources module management.
  """

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.PebbleToolchain
  alias Ide.Resources.{AnimationStore, BitmapVariants, CtorNaming, PdcDecoder, SvgConverter}
  alias Ide.Resources.Types

  @manifest_rel_path "watch/resources/bitmaps.json"
  @assets_rel_dir "watch/resources/bitmaps"
  @font_manifest_rel_path "watch/resources/fonts.json"
  @font_assets_rel_dir "watch/resources/fonts"
  @vector_manifest_rel_path "watch/resources/vectors.json"
  @vector_assets_rel_dir "watch/resources/vectors"
  @animation_manifest_rel_path "watch/resources/animations.json"
  @generated_module_rel_path "watch/src/Pebble/Ui/Resources.elm"
  @legacy_generated_module_rel_path "watch/src/Pebble/Ui/Bitmap.elm"

  @type bitmap_variant_entry :: %{
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @type bitmap_entry :: %{
          id: String.t(),
          ctor: String.t(),
          base_name: String.t(),
          filename: String.t() | nil,
          mime: String.t() | nil,
          bytes: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          variants: %{optional(String.t()) => bitmap_variant_entry()}
        }

  @type font_entry :: %{
          id: String.t(),
          ctor: String.t(),
          source_id: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer(),
          height: non_neg_integer(),
          characters: String.t(),
          tracking_adjust: integer(),
          compatibility: String.t(),
          target_platforms: [String.t()]
        }

  @type font_lookup_error :: Types.font_lookup_error()
  @type form_params :: map()
  @type font_source :: %{
          id: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer()
        }

  @type vector_entry :: %{
          id: String.t(),
          ctor: String.t(),
          base_name: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer(),
          source: String.t(),
          kind: String.t(),
          frames: non_neg_integer() | nil,
          frame_duration_ms: non_neg_integer() | nil
        }

  @spec manifest_rel_path() :: String.t()
  def manifest_rel_path, do: @manifest_rel_path

  @spec generated_module_rel_path() :: String.t()
  def generated_module_rel_path, do: @generated_module_rel_path

  @spec read_only_generated_module?(String.t(), String.t()) :: boolean()
  def read_only_generated_module?(source_root, rel_path)
      when is_binary(source_root) and is_binary(rel_path) do
    {normalize_source_root(source_root), normalize_editor_rel_path(rel_path)} in [
      {"watch", "src/Pebble/Ui/Resources.elm"},
      {"watch", "src/Pebble/Ui/Bitmap.elm"},
      {"phone", "src/Companion/GeneratedPreferences.elm"}
    ]
  end

  def read_only_generated_module?(_, _), do: false

  defp normalize_source_root(source_root) do
    source_root
    |> String.trim()
    |> String.trim("/")
  end

  defp normalize_editor_rel_path(rel_path) do
    rel_path =
      rel_path
      |> String.trim()
      |> String.trim_leading("/")

    rel_path =
      if String.starts_with?(rel_path, "src/") do
        rel_path
      else
        "src/" <> rel_path
      end

    if Path.extname(rel_path) == "" do
      rel_path <> ".elm"
    else
      rel_path
    end
  end

  @spec list(Project.t()) :: {:ok, [bitmap_entry()]} | {:error, Types.resource_error()}
  def list(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_bitmap_manifest(workspace) do
      entries = manifest["entries"] || []

      {:ok, Enum.map(entries, &bitmap_entry_from_row/1)}
    end
  end

  @doc """
  Registers every `*.png` in the bitmap assets directory (or `dir`) that is not already
  recorded in `bitmaps.json`. Existing ctors are left unchanged; duplicate file bytes are skipped.
  """
  @spec import_bitmaps_from_directory(Project.t(), String.t() | nil, keyword()) ::
          {:ok, %{imported: non_neg_integer(), skipped: non_neg_integer(), duplicates: non_neg_integer()}}
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
          {:ok, map()} | {:error, Types.resource_error()}
  def import_bitmap(%Project{} = project, upload_path, original_name, opts \\ [])
      when is_binary(upload_path) and is_binary(original_name) and is_list(opts) do
    color_mode = Keyword.get(opts, :color_mode)
    ctor_hint = Keyword.get(opts, :ctor)

    if is_binary(color_mode) and BitmapVariants.valid_color_mode?(color_mode) do
      import_bitmap_variant(project, upload_path, original_name, color_mode, ctor_hint)
    else
      import_bitmap_legacy(project, upload_path, original_name)
    end
  end

  @spec import_bitmap_legacy(Project.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Types.resource_error()}
  defp import_bitmap_legacy(%Project{} = project, upload_path, original_name) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_bitmap_manifest(workspace),
         {:ok, bytes} <- File.read(upload_path),
         {:ok, safe_name, mime} <- normalized_filename_and_mime(original_name),
         nil <- duplicate_asset_entry(manifest["entries"] || [], assets_dir, bytes),
         base_name <- CtorNaming.base_name_from_filename(safe_name),
         unique_ctor <-
           CtorNaming.unique_ctor(:bitmap_static, base_name, manifest["entries"] || []),
         basename <- BitmapVariants.legacy_filename(unique_ctor, Path.extname(safe_name)),
         :ok <- remove_bitmap_row_files(assets_dir, existing_row(manifest, unique_ctor)),
         :ok <- File.write(Path.join(assets_dir, basename), bytes) do
      {width, height} = bitmap_dimensions(bytes, mime)

      entry =
        BitmapVariants.normalize_row(%{
          "id" => "bitmap_" <> String.downcase(unique_ctor),
          "base_name" => CtorNaming.legacy_base_from_ctor(unique_ctor, :bitmap_static),
          "ctor" => unique_ctor,
          "filename" => basename,
          "mime" => mime,
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

  @spec import_bitmap_variant(Project.t(), String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, Types.resource_error()}
  defp import_bitmap_variant(%Project{} = project, upload_path, original_name, color_mode, ctor_hint) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_bitmap_manifest(workspace),
         {:ok, bytes} <- File.read(upload_path),
         {:ok, safe_name, mime} <- normalized_filename_and_mime(original_name),
         ctor <- resolve_bitmap_ctor(manifest, safe_name, ctor_hint),
         unique_ctor <- unique_ctor(ctor, manifest["entries"] || [], ctor_hint),
         basename <-
           BitmapVariants.variant_filename(unique_ctor, color_mode, Path.extname(safe_name)),
         nil <- duplicate_variant_asset(manifest, assets_dir, bytes, unique_ctor, basename),
         :ok <- File.write(Path.join(assets_dir, basename), bytes) do
      {width, height} = bitmap_dimensions(bytes, mime)

      prior = existing_row(manifest, unique_ctor) |> BitmapVariants.normalize_row()

      variants =
        prior
        |> Map.get("variants", %{})
        |> Map.put(color_mode, %{
          "filename" => basename,
          "mime" => mime,
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

      persist_bitmap_entries(workspace, manifest_path, manifest, entry)
    else
      %{} = duplicate ->
        {:ok, %{duplicate: true, entry: duplicate}}

      other ->
        other
    end
  end

  @spec clear_bitmap_variant(Project.t(), String.t(), String.t()) ::
          {:ok, [map()]} | {:error, Types.resource_error()}
  def clear_bitmap_variant(%Project{} = project, ctor, color_mode)
      when is_binary(ctor) and is_binary(color_mode) do
    unless BitmapVariants.valid_color_mode?(color_mode) do
      raise ArgumentError, "invalid bitmap color mode #{inspect(color_mode)}"
    end

    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with {:ok, manifest} <- read_bitmap_manifest(workspace),
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

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, entries}
      end
    else
      _ -> {:error, :bitmap_not_found}
    end
  end

  @spec list_vectors(Project.t()) :: {:ok, [vector_entry()]} | {:error, Types.resource_error()}
  def list_vectors(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_vector_manifest(workspace) do
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
           bytes: integer_or_zero(Map.get(row, "bytes", 0)),
           source: to_string(Map.get(row, "source", "pdc")),
           kind: to_string(Map.get(row, "kind", "image")),
           frames: optional_positive_int(Map.get(row, "frames")),
           frame_duration_ms: optional_positive_int(Map.get(row, "frame_duration_ms"))
         }
       end)}
    end
  end

  @spec import_vector(Project.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Types.resource_error()}
  def import_vector(%Project{} = project, upload_path, original_name)
      when is_binary(upload_path) and is_binary(original_name) do
    import_vector(project, upload_path, original_name, [])
  end

  @spec import_vector(Project.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Types.resource_error()}
  def import_vector(%Project{} = project, upload_path, original_name, opts)
      when is_binary(upload_path) and is_binary(original_name) and is_list(opts) do
    with {:ok, safe_name, mime, source_kind} <- normalized_vector_filename(original_name),
         {:ok, pdc_bytes, extras} <- vector_bytes_from_upload(upload_path, safe_name, source_kind, opts) do
      persist_vector_bytes(project, pdc_bytes, safe_name, mime, source_kind, extras)
    end
  end

  @spec import_vector_svg(Project.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Types.resource_error()}
  def import_vector_svg(%Project{} = project, upload_path, original_name, opts)
      when is_binary(upload_path) and is_binary(original_name) do
    with {:ok, svg} <- File.read(upload_path),
         {:ok, result} <- SvgConverter.convert(svg, opts),
         :ok <- SvgConverter.validate_pdc_bytes(result.bytes),
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
          {:ok, map()} | {:error, Types.resource_error()}
  def import_vector_sequence(%Project{} = project, frames, original_name, opts)
      when is_list(frames) and is_binary(original_name) do
    with {:ok, result} <- SvgConverter.convert_svg_sequence(frames, opts),
         :ok <- SvgConverter.validate_pdc_bytes(result.bytes),
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
         {:ok, manifest} <- read_vector_manifest(workspace),
         nil <- duplicate_asset_entry(manifest["entries"] || [], assets_dir, pdc_bytes),
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

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
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

  @spec delete_vector(Project.t(), String.t()) :: {:ok, [map()]} | {:error, Types.resource_error()}
  def delete_vector(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @vector_manifest_rel_path)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)

    with {:ok, manifest} <- read_vector_manifest(workspace) do
      entries = manifest["entries"] || []
      {to_remove, kept} = Enum.split_with(entries, &(Map.get(&1, "ctor") == ctor))

      Enum.each(to_remove, fn row ->
        filename = Map.get(row, "filename", "")
        if filename != "", do: File.rm(Path.join(assets_dir, filename))
      end)

      payload = %{"schema_version" => 1, "entries" => kept}

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, kept}
      end
    end
  end

  @spec vector_file_path(Project.t(), String.t()) :: {:ok, String.t()} | {:error, Types.resource_error()}
  def vector_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)

    with {:ok, manifest} <- read_vector_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)),
         filename when is_binary(filename) and filename != "" <- Map.get(row, "filename") do
      {:ok, Path.join(assets_dir, filename)}
    else
      _ -> {:error, :vector_not_found}
    end
  end

  @spec delete_bitmap(Project.t(), String.t()) :: {:ok, [map()]} | {:error, Types.resource_error()}
  def delete_bitmap(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @manifest_rel_path)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_bitmap_manifest(workspace) do
      entries = manifest["entries"] || []

      {to_remove, kept} = Enum.split_with(entries, &(Map.get(&1, "ctor") == ctor))

      Enum.each(to_remove, &remove_bitmap_row_files(assets_dir, &1))

      payload = %{"schema_version" => 2, "entries" => kept}

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, kept}
      end
    end
  end

  @spec ensure_generated(Project.t()) :: :ok | {:error, Types.resource_error()}
  def ensure_generated(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with :ok <- migrate_resource_ctor_names(workspace) do
      write_generated_module(workspace)
    end
  end

  @spec ensure_generated_workspace(String.t()) :: :ok | {:error, Types.resource_error()}
  def ensure_generated_workspace(workspace) when is_binary(workspace) do
    with :ok <- migrate_resource_ctor_names(workspace) do
      write_generated_module(workspace)
    end
  end

  @spec update_bitmap_base_name(Project.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Types.resource_error()}
  def update_bitmap_base_name(%Project{} = project, old_ctor, new_base)
      when is_binary(old_ctor) and is_binary(new_base) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with {:ok, manifest} <- read_bitmap_manifest(workspace),
         %{} = row <- existing_row(manifest, old_ctor),
         new_ctor <-
           {:ok,
            CtorNaming.unique_ctor(
              :bitmap_static,
              new_base,
              manifest["entries"] || [],
              exclude_ctor: old_ctor
            )},
         migrated_row <- {:ok, migrate_bitmap_row_files(assets_dir, row, old_ctor, new_ctor)} do
      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == old_ctor))
        |> Kernel.++([migrated_row])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      with :ok <- write_manifest(manifest_path, %{"schema_version" => 1, "entries" => entries}),
           :ok <- write_generated_module(workspace) do
        {:ok, %{entry: migrated_row, entries: entries}}
      end
    else
      nil -> {:error, :bitmap_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_vector_base_name(Project.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Types.resource_error()}
  def update_vector_base_name(%Project{} = project, old_ctor, new_base)
      when is_binary(old_ctor) and is_binary(new_base) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)
    manifest_path = Path.join(workspace, @vector_manifest_rel_path)

    with {:ok, manifest} <- read_vector_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == old_ctor)),
         kind <- {:ok, CtorNaming.vector_kind_from_row(row)},
         new_ctor <-
           {:ok,
            CtorNaming.unique_ctor(kind, new_base, manifest["entries"] || [], exclude_ctor: old_ctor)},
         migrated_row <- {:ok, migrate_vector_row_files(assets_dir, row, old_ctor, new_ctor, kind)} do
      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == old_ctor))
        |> Kernel.++([migrated_row])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      with :ok <- write_manifest(manifest_path, %{"schema_version" => 1, "entries" => entries}),
           :ok <- write_generated_module(workspace) do
        {:ok, %{entry: migrated_row, entries: entries}}
      end
    else
      nil -> {:error, :vector_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec bitmap_file_path(Project.t(), String.t()) :: {:ok, String.t()} | {:error, Types.resource_error()}
  def bitmap_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    bitmap_file_path(project, ctor, nil)
  end

  @spec bitmap_file_path(Project.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def bitmap_file_path(%Project{} = project, ctor, color_mode)
      when is_binary(ctor) and (is_binary(color_mode) or is_nil(color_mode)) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_bitmap_manifest(workspace),
         %{} = row <- existing_row(manifest, ctor),
         filename when is_binary(filename) and filename != "" <-
           bitmap_preview_filename(row, color_mode) do
      {:ok, Path.join(assets_dir, filename)}
    else
      _ -> {:error, :bitmap_not_found}
    end
  end

  @spec list_fonts(Project.t()) :: {:ok, [font_entry()]} | {:error, Types.resource_error()}
  def list_fonts(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_font_manifest(workspace) do
      entries = manifest["entries"] || []

      {:ok,
       Enum.map(entries, fn row ->
         %{
           id: to_string(Map.get(row, "id", "")),
           ctor: to_string(Map.get(row, "ctor", "")),
           source_id: to_string(Map.get(row, "source_id", "")),
           filename: to_string(Map.get(row, "filename", "")),
           mime: to_string(Map.get(row, "mime", "font/ttf")),
           bytes: integer_or_zero(Map.get(row, "bytes", 0)),
           height: positive_integer_or_default(Map.get(row, "height", 0), 0),
           characters: to_string(Map.get(row, "characters", "")),
           tracking_adjust: integer_or_default(Map.get(row, "tracking_adjust", 0), 0),
           compatibility: to_string(Map.get(row, "compatibility", "2.7")),
           target_platforms: string_list(Map.get(row, "target_platforms", []))
         }
       end)}
    end
  end

  @spec list_font_sources(Project.t()) :: {:ok, [font_source()]} | {:error, Types.resource_error()}
  def list_font_sources(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_font_manifest(workspace) do
      sources = manifest["sources"] || []

      {:ok,
       Enum.map(sources, fn row ->
         %{
           id: to_string(Map.get(row, "id", "")),
           filename: to_string(Map.get(row, "filename", "")),
           mime: to_string(Map.get(row, "mime", "font/ttf")),
           bytes: integer_or_zero(Map.get(row, "bytes", 0))
         }
       end)}
    end
  end

  @spec import_font(Project.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Types.resource_error()}
  def import_font(%Project{} = project, upload_path, original_name)
      when is_binary(upload_path) and is_binary(original_name) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @font_assets_rel_dir)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_font_manifest(workspace),
         {:ok, bytes} <- File.read(upload_path),
         {:ok, safe_name, mime} <- normalized_font_filename_and_mime(original_name),
         nil <- duplicate_asset_entry(manifest["sources"] || [], assets_dir, bytes),
         source_id <- unique_source_id(Path.rootname(safe_name), manifest["sources"] || []),
         basename <- "#{source_id}#{Path.extname(safe_name)}",
         asset_path <- Path.join(assets_dir, basename),
         :ok <- File.write(asset_path, bytes) do
      source = %{
        "id" => source_id,
        "filename" => basename,
        "mime" => mime,
        "bytes" => byte_size(bytes)
      }

      sources =
        (manifest["sources"] || [])
        |> Enum.reject(&(Map.get(&1, "id") == source_id))
        |> Kernel.++([source])
        |> Enum.sort_by(&Map.get(&1, "filename", ""))

      payload = font_manifest_payload(sources, manifest["entries"] || [])

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, %{source: source, entries: payload["entries"]}}
      end
    else
      %{} = duplicate ->
        {:ok,
         %{
           duplicate: true,
           source: duplicate
         }}

      other ->
        other
    end
  end

  @spec add_font_variant(Project.t(), map()) :: {:ok, map()} | {:error, Types.resource_error()}
  def add_font_variant(%Project{} = project, params) when is_map(params) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)
    params = default_font_variant_target_platforms(project, params)

    with {:ok, manifest} <- read_font_manifest(workspace),
         {:ok, source} <- font_source_from_params(manifest, params),
         {:ok, variant} <- font_variant_from_params(source, params, manifest["entries"] || []) do
      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == Map.fetch!(variant, "ctor")))
        |> Kernel.++([variant])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      payload = font_manifest_payload(manifest["sources"] || [], entries)

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, %{entry: variant, entries: entries}}
      end
    end
  end

  @spec update_font_variant(Project.t(), String.t(), map()) :: {:ok, map()} | {:error, Types.resource_error()}
  def update_font_variant(%Project{} = project, ctor, params)
      when is_binary(ctor) and is_map(params) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)

    with {:ok, manifest} <- read_font_manifest(workspace),
         %{} = existing <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)),
         {:ok, source} <- font_source_by_id(manifest, Map.get(existing, "source_id", "")),
         params <- Map.put_new(params, "source_id", Map.get(existing, "source_id", "")),
         {:ok, variant} <-
           font_variant_from_params(source, params, manifest["entries"] || [], ctor) do
      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == ctor))
        |> Kernel.++([variant])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      payload = font_manifest_payload(manifest["sources"] || [], entries)

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, %{entry: variant, entries: entries}}
      end
    else
      nil -> {:error, :font_variant_not_found}
      error -> error
    end
  end

  @spec delete_font(Project.t(), String.t()) :: {:ok, [map()]} | {:error, Types.resource_error()}
  def delete_font(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)

    with {:ok, manifest} <- read_font_manifest(workspace) do
      entries = manifest["entries"] || []
      kept = Enum.reject(entries, &(Map.get(&1, "ctor") == ctor))
      payload = font_manifest_payload(manifest["sources"] || [], kept)

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, kept}
      end
    end
  end

  @spec delete_font_source(Project.t(), String.t()) :: {:ok, map()} | {:error, Types.resource_error()}
  def delete_font_source(%Project{} = project, source_id) when is_binary(source_id) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)
    assets_dir = Path.join(workspace, @font_assets_rel_dir)

    with {:ok, manifest} <- read_font_manifest(workspace) do
      sources = manifest["sources"] || []
      entries = manifest["entries"] || []

      {to_remove, kept_sources} = Enum.split_with(sources, &(Map.get(&1, "id") == source_id))
      kept_entries = Enum.reject(entries, &(Map.get(&1, "source_id") == source_id))

      Enum.each(to_remove, fn row ->
        filename = Map.get(row, "filename", "")
        if filename != "", do: File.rm(Path.join(assets_dir, filename))
      end)

      payload = font_manifest_payload(kept_sources, kept_entries)

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, %{sources: kept_sources, entries: kept_entries}}
      end
    end
  end

  @spec font_file_path(Project.t(), String.t()) :: {:ok, String.t()} | {:error, Types.resource_error()}
  def font_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @font_assets_rel_dir)

    with {:ok, manifest} <- read_font_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)),
         {:ok, source} <- font_source_by_id(manifest, Map.get(row, "source_id", "")),
         filename when is_binary(filename) and filename != "" <- Map.get(source, "filename") do
      {:ok, Path.join(assets_dir, filename)}
    else
      _ -> {:error, :font_not_found}
    end
  end

  @spec bitmap_file_path_by_id(Project.t(), integer()) :: {:ok, String.t()} | {:error, Types.resource_error()}
  def bitmap_file_path_by_id(%Project{} = project, id) when is_integer(id) and id >= 1 do
    with {:ok, entries} <- list(project),
         %{} = row <- Enum.at(entries, id - 1) do
      bitmap_file_path(project, row.ctor)
    else
      _ -> {:error, :bitmap_not_found}
    end
  end

  def bitmap_file_path_by_id(_project, _), do: {:error, :bitmap_not_found}

  @spec vector_file_path_by_id(Project.t(), integer()) :: {:ok, String.t()} | {:error, Types.resource_error()}
  def vector_file_path_by_id(%Project{} = project, id) when is_integer(id) and id >= 1 do
    with {:ok, entries} <- list_vectors(project),
         %{} = row <- Enum.at(entries, id - 1) do
      vector_file_path(project, row.ctor)
    else
      _ -> {:error, :vector_not_found}
    end
  end

  def vector_file_path_by_id(_project, _), do: {:error, :vector_not_found}

  @spec animation_file_path_by_id(Project.t(), integer()) :: {:ok, String.t()} | {:error, Types.resource_error()}
  def animation_file_path_by_id(%Project{} = project, id) when is_integer(id) and id >= 1 do
    with {:ok, entries} <- AnimationStore.list(project),
         %{} = row <- Enum.at(entries, id - 1) do
      AnimationStore.animation_file_path(project, row.ctor)
    else
      _ -> {:error, :not_found}
    end
  end

  def animation_file_path_by_id(_project, _), do: {:error, :not_found}

  @spec read_bitmap_manifest(Types.workspace_path()) :: {:ok, Types.manifest()} | {:error, Types.resource_error()}
  defp read_bitmap_manifest(workspace) do
    path = Path.join(workspace, @manifest_rel_path)
    read_manifest(path, strict: true)
  end

  @spec read_font_manifest(Types.workspace_path()) :: {:ok, Types.manifest()} | {:error, Types.resource_error()}
  defp read_font_manifest(workspace) do
    path = Path.join(workspace, @font_manifest_rel_path)

    case read_manifest(path) do
      {:ok, manifest} -> {:ok, normalize_font_manifest(manifest)}
      error -> error
    end
  end

  @spec read_manifest(Path.t(), keyword()) :: {:ok, Types.manifest()} | {:error, Types.manifest_io_error()}
  defp read_manifest(path, opts \\ []) do
    path = Path.expand(path)
    strict? = Keyword.get(opts, :strict, false)

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, decoded} when is_map(decoded) ->
            {:ok, Map.put_new(decoded, "entries", [])}

          _ ->
            if strict?, do: {:error, :invalid_manifest}, else: {:ok, %{"schema_version" => 1, "entries" => []}}
        end

      {:error, :enoent} ->
        {:ok, %{"schema_version" => 1, "entries" => []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec write_manifest(Path.t(), Types.manifest()) :: :ok | {:error, Types.manifest_io_error()}
  defp write_manifest(path, payload) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, json} <- Jason.encode(payload, pretty: true),
         :ok <- File.write(path, json <> "\n") do
      :ok
    end
  end

  @spec write_generated_module(Types.workspace_path()) :: :ok | {:error, Types.resource_error()}
  defp write_generated_module(workspace) do
    bitmap_entries =
      case read_bitmap_manifest(workspace) do
        {:ok, manifest} -> manifest["entries"] || []
        _ -> []
      end

    font_entries =
      case read_font_manifest(workspace) do
        {:ok, manifest} -> manifest["entries"] || []
        _ -> []
      end

    vector_entries =
      case read_vector_manifest(workspace) do
        {:ok, manifest} -> file_backed_vector_entries(workspace, manifest["entries"] || [])
        _ -> []
      end

    animation_entries =
      case read_animation_manifest(workspace) do
        {:ok, manifest} -> file_backed_animation_entries(workspace, manifest["entries"] || [])
        _ -> []
      end

    path = Path.join(workspace, @generated_module_rel_path)
    legacy = Path.join(workspace, @legacy_generated_module_rel_path)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <-
           File.write(
             path,
             generated_module_source(bitmap_entries, font_entries, vector_entries, animation_entries)
           ) do
      _ = File.rm(legacy)
      :ok
    end
  end

  defp read_animation_manifest(workspace) do
    path = Path.join(workspace, @animation_manifest_rel_path)

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, manifest} when is_map(manifest) -> {:ok, manifest}
          _ -> {:error, :invalid_manifest}
        end

      {:error, :enoent} ->
        {:ok, %{"schema_version" => 1, "entries" => []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp file_backed_animation_entries(workspace, entries) when is_list(entries) do
    assets_root = Path.join(workspace, "watch/resources/animations")

    Enum.filter(entries, fn row ->
      filename = to_string(Map.get(row, "filename", ""))
      filename != "" and File.exists?(Path.join(assets_root, filename))
    end)
  end

  @spec generated_module_source(
          [Types.manifest_entry()],
          [Types.manifest_entry()],
          [Types.manifest_entry()],
          [Types.manifest_entry()]
        ) :: String.t()
  defp generated_module_source(bitmap_entries, font_entries, vector_entries, animation_entries) do
    bitmap_rows =
      bitmap_entries
      |> Enum.map(&normalize_bitmap_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:bitmap)

    font_rows =
      font_entries
      |> Enum.map(&normalize_font_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:font)

    {static_vector_entries, animated_vector_entries} =
      Enum.split_with(vector_entries, &(CtorNaming.vector_kind_from_row(&1) == :vector_static))

    static_vector_rows =
      static_vector_entries
      |> Enum.map(&normalize_vector_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:vector)

    animated_vector_rows =
      animated_vector_entries
      |> Enum.map(&normalize_vector_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:vector)

    animated_bitmap_rows =
      animation_entries
      |> Enum.map(&normalize_animation_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:animation)

    {static_bitmap_type_decl, static_bitmap_all_decl, static_bitmap_info_decl} =
      generated_named_resource_section(
        type_name: "StaticBitmap",
        nil_ctor: "NoStaticBitmap",
        all_name: "allStaticBitmaps",
        info_type: "StaticBitmapInfo",
        info_fn: "staticBitmapInfo",
        record_field: "staticBitmap",
        rows: bitmap_rows,
        dimension_fields: true
      )

    {animated_bitmap_type_decl, animated_bitmap_all_decl, animated_bitmap_info_decl} =
      generated_named_resource_section(
        type_name: "AnimatedBitmap",
        nil_ctor: "NoAnimatedBitmap",
        all_name: "allAnimatedBitmaps",
        info_type: "AnimatedBitmapInfo",
        info_fn: "animatedBitmapInfo",
        record_field: "animatedBitmap",
        rows: animated_bitmap_rows,
        dimension_fields: true,
        animation_fields: true
      )

    {static_vector_type_decl, static_vector_all_decl, static_vector_info_decl} =
      generated_named_resource_section(
        type_name: "StaticVector",
        nil_ctor: "NoStaticVector",
        all_name: "allStaticVectors",
        info_type: "StaticVectorInfo",
        info_fn: "staticVectorInfo",
        record_field: "staticVector",
        rows: static_vector_rows
      )

    {animated_vector_type_decl, animated_vector_all_decl, animated_vector_info_decl} =
      generated_named_resource_section(
        type_name: "AnimatedVector",
        nil_ctor: "NoAnimatedVector",
        all_name: "allAnimatedVectors",
        info_type: "AnimatedVectorInfo",
        info_fn: "animatedVectorInfo",
        record_field: "animatedVector",
        rows: animated_vector_rows
      )

    {font_type_decl, font_all_decl} =
      case Enum.map(font_rows, & &1.ctor) do
        [] ->
          {"type Font\n    = DefaultFont",
           "allFonts : List Font\nallFonts =\n    [ DefaultFont ]"}

        list ->
          type_rows = Enum.map_join(list, "\n    | ", & &1)
          all_rows = Enum.map_join(list, ", ", & &1)

          {"type Font\n    = #{type_rows}",
           "allFonts : List Font\nallFonts =\n    [ #{all_rows} ]"}
      end

    font_info_decl =
      case font_rows do
        [] ->
          """
          type alias FontInfo =
              { font : Font
              , name : String
              , height : Int
              }

          fontInfo : Font -> FontInfo
          fontInfo font =
              case font of
                  DefaultFont ->
                      { font = DefaultFont, name = "DefaultFont", height = 0 }
          """

        rows ->
          cases =
            Enum.map_join(rows, "\n", fn row ->
              """
                  #{row.ctor} ->
                      { font = #{row.ctor}, name = "#{elm_string(row.name)}", height = #{row.height} }
              """
            end)

          """
          type alias FontInfo =
              { font : Font
              , name : String
              , height : Int
              }

          fontInfo : Font -> FontInfo
          fontInfo font =
              case font of
          #{cases}
          """
      end

    """
    module Pebble.Ui.Resources exposing
        ( AnimatedBitmap(..)
        , AnimatedBitmapInfo
        , AnimatedVector(..)
        , AnimatedVectorInfo
        , Font(..)
        , FontInfo
        , StaticBitmap(..)
        , StaticBitmapInfo
        , StaticVector(..)
        , StaticVectorInfo
        , allAnimatedBitmaps
        , allAnimatedVectors
        , allFonts
        , allStaticBitmaps
        , allStaticVectors
        , animatedBitmapInfo
        , animatedVectorInfo
        , fontInfo
        , staticBitmapInfo
        , staticVectorInfo
        )

    {-| Generated from the resources configured on the project settings Resources page.
    Edit bitmap, vector, and font assets there instead of editing this read-only file.
    -}

    #{static_bitmap_type_decl}

    #{static_bitmap_all_decl}

    #{static_bitmap_info_decl}

    #{animated_bitmap_type_decl}

    #{animated_bitmap_all_decl}

    #{animated_bitmap_info_decl}

    #{font_type_decl}

    #{font_all_decl}

    #{font_info_decl}

    #{static_vector_type_decl}

    #{static_vector_all_decl}

    #{static_vector_info_decl}

    #{animated_vector_type_decl}

    #{animated_vector_all_decl}

    #{animated_vector_info_decl}
    """
  end

  defp generated_named_resource_section(opts) do
    type_name = Keyword.fetch!(opts, :type_name)
    nil_ctor = Keyword.fetch!(opts, :nil_ctor)
    all_name = Keyword.fetch!(opts, :all_name)
    info_type = Keyword.fetch!(opts, :info_type)
    info_fn = Keyword.fetch!(opts, :info_fn)
    record_field = Keyword.fetch!(opts, :record_field)
    rows = Keyword.fetch!(opts, :rows)
    dimension_fields? = Keyword.get(opts, :dimension_fields, false)
    animation_fields? = Keyword.get(opts, :animation_fields, false)

    ctors = Enum.map(rows, & &1.ctor)

    {type_decl, all_decl} =
      case ctors do
        [] ->
          {"""
           type #{type_name}
               = #{nil_ctor}
           """,
           """
           #{all_name} : List #{type_name}
           #{all_name} =
               [ #{nil_ctor} ]
           """}

        list ->
          type_rows = Enum.map_join(list, "\n    | ", & &1)
          all_rows = Enum.map_join(list, ", ", & &1)

          {"""
           type #{type_name}
               = #{type_rows}
           """,
           """
           #{all_name} : List #{type_name}
           #{all_name} =
               [ #{all_rows} ]
           """}
      end

    info_decl =
      case rows do
        [] ->
          empty_info_decl(type_name, nil_ctor, info_type, info_fn, record_field, dimension_fields?, animation_fields?)

        row_list ->
          cases =
            Enum.map_join(row_list, "\n", fn row ->
              info_case_row(row, record_field, dimension_fields?, animation_fields?)
            end)

          populated_info_decl(type_name, info_type, info_fn, record_field, dimension_fields?, animation_fields?, cases)
      end

    {type_decl, all_decl, info_decl}
  end

  defp empty_info_decl(type_name, nil_ctor, info_type, info_fn, record_field, dimension_fields?, animation_fields?) do
    record_fields = info_record_fields(type_name, record_field, dimension_fields?, animation_fields?)
    nil_record = info_record_literal(record_field, nil_ctor, nil_ctor, 0, 0, 0, 0, dimension_fields?, animation_fields?)

    """
    type alias #{info_type} =
        { #{record_fields}
        }

    #{info_fn} : #{type_name} -> #{info_type}
    #{info_fn} #{record_field} =
        case #{record_field} of
            #{nil_ctor} ->
                #{nil_record}
    """
  end

  defp populated_info_decl(type_name, info_type, info_fn, record_field, dimension_fields?, animation_fields?, cases) do
    record_fields = info_record_fields(type_name, record_field, dimension_fields?, animation_fields?)

    """
    type alias #{info_type} =
        { #{record_fields}
        }

    #{info_fn} : #{type_name} -> #{info_type}
    #{info_fn} #{record_field} =
        case #{record_field} of
    #{cases}
    """
  end

  defp info_record_fields(type_name, record_field, dimension_fields?, animation_fields?) do
    parts =
      ["#{record_field} : #{type_name}", "name : String"]
      |> maybe_add_info_field(dimension_fields?, "width : Int")
      |> maybe_add_info_field(dimension_fields?, "height : Int")
      |> maybe_add_info_field(animation_fields?, "frameCount : Int")
      |> maybe_add_info_field(animation_fields?, "durationMs : Int")

    Enum.join(parts, "\n    , ")
  end

  defp maybe_add_info_field(parts, true, field), do: parts ++ [field]
  defp maybe_add_info_field(parts, false, _field), do: parts

  defp info_case_row(row, record_field, dimension_fields?, animation_fields?) do
    literal =
      info_record_literal(
        record_field,
        row.ctor,
        row.ctor,
        Map.get(row, :width, 0),
        Map.get(row, :height, 0),
        Map.get(row, :frame_count, 0),
        Map.get(row, :duration_ms, 0),
        dimension_fields?,
        animation_fields?
      )

    """
            #{row.ctor} ->
                #{literal}
    """
  end

  defp info_record_literal(record_field, value_ctor, name, width, height, frame_count, duration_ms, dimension_fields?, animation_fields?) do
    parts =
      ["#{record_field} = #{value_ctor}", ~s(name = "#{elm_string(name)}")]
      |> maybe_add_info_literal(dimension_fields?, "width = #{width}")
      |> maybe_add_info_literal(dimension_fields?, "height = #{height}")
      |> maybe_add_info_literal(animation_fields?, "frameCount = #{frame_count}")
      |> maybe_add_info_literal(animation_fields?, "durationMs = #{duration_ms}")

    "{ " <> Enum.join(parts, ", ") <> " }"
  end

  defp maybe_add_info_literal(parts, true, field), do: parts ++ [field]
  defp maybe_add_info_literal(parts, false, _field), do: parts

  @spec sort_generated_resource_rows([map()], :bitmap | :font | :vector | :animation) :: [map()]
  defp sort_generated_resource_rows(rows, kind) when is_list(rows) and kind in [:bitmap, :font, :vector, :animation] do
    Enum.sort_by(rows, &resource_row_sort_key(&1, kind))
  end

  defp resource_row_sort_key(%{ctor: ctor}, :font), do: {0, ctor}

  defp resource_row_sort_key(%{ctor: ctor}, :bitmap) do
    {resource_prefix_rank(ctor, CtorNaming.prefix(:bitmap_static)), ctor}
  end

  defp resource_row_sort_key(%{ctor: ctor}, :animation) do
    {resource_prefix_rank(ctor, CtorNaming.prefix(:bitmap_animated)), ctor}
  end

  defp resource_row_sort_key(%{ctor: ctor}, :vector) do
    rank =
      cond do
        String.starts_with?(ctor, CtorNaming.prefix(:vector_static)) -> 0
        String.starts_with?(ctor, CtorNaming.prefix(:vector_animated)) -> 1
        true -> 2
      end

    {rank, ctor}
  end

  defp resource_prefix_rank(ctor, expected_prefix) when is_binary(ctor) and is_binary(expected_prefix) do
    if String.starts_with?(ctor, expected_prefix), do: 0, else: 1
  end

  defp normalize_animation_row(row) when is_map(row) do
    normalized = CtorNaming.ensure_row!(row, :bitmap_animated)
    ctor = to_string(Map.get(normalized, "ctor", ""))

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor)),
      width: Map.get(row, "width", 0),
      height: Map.get(row, "height", 0),
      frame_count: Map.get(row, "frame_count", 0),
      duration_ms: Map.get(row, "duration_ms", 0)
    }
  end

  @spec normalize_bitmap_row(map()) :: map()
  defp normalize_bitmap_row(row) do
    normalized = row |> BitmapVariants.normalize_row() |> CtorNaming.ensure_row!(:bitmap_static)
    {width, height} = BitmapVariants.primary_dimensions(normalized)
    ctor = Map.get(normalized, "ctor", "")

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor)),
      width: width,
      height: height
    }
  end

  @spec normalize_font_row(map()) :: map()
  defp normalize_font_row(row) do
    ctor = to_string(Map.get(row, "ctor", ""))

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor)),
      height: positive_integer_or_default(Map.get(row, "height", 0), 0)
    }
  end

  @spec normalize_vector_row(map()) :: map()
  defp normalize_vector_row(row) do
    normalized = CtorNaming.ensure_row!(row, CtorNaming.vector_kind_from_row(row))
    ctor = to_string(Map.get(normalized, "ctor", ""))

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor))
    }
  end

  @spec read_vector_manifest(Types.workspace_path()) :: {:ok, Types.manifest()} | {:error, Types.resource_error()}
  defp read_vector_manifest(workspace) do
    path = Path.join(workspace, @vector_manifest_rel_path)
    read_manifest(path)
  end

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
          {:ok, binary(), map()} | {:error, Types.resource_error()}
  defp vector_bytes_from_upload(upload_path, _safe_name, "pdc", _opts) do
    case File.read(upload_path) do
      {:ok, bytes} ->
        extras = %{
          kind: vector_kind_from_bytes(bytes),
          preview_svg: preview_svg_for_bytes(bytes)
        }

        {:ok, bytes, extras}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp vector_bytes_from_upload(upload_path, _safe_name, "svg", opts) do
    case File.read(upload_path) do
      {:ok, svg} ->
        with {:ok, result} <- SvgConverter.convert(svg, opts),
             :ok <- SvgConverter.validate_pdc_bytes(result.bytes),
             {:ok, preview_svg} <- PdcDecoder.preview_svg(result.bytes) do
          {:ok, result.bytes,
           %{report: result.report, preview_svg: preview_svg, kind: "image"}}
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

  defp duplicate_asset_entry(entries, assets_dir, bytes) when is_list(entries) do
    Enum.find(entries, fn row ->
      Enum.any?(BitmapVariants.filenames_for_row(row), fn filename ->
        match?({:ok, ^bytes}, File.read(Path.join(assets_dir, filename)))
      end)
    end)
  end

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

    with :ok <- write_manifest(manifest_path, payload),
         :ok <- write_generated_module(workspace) do
      {:ok, %{entry: entry, entries: entries}}
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
           bytes: integer_or_zero(Map.get(variant, "bytes", 0)),
           width: integer_or_zero(Map.get(variant, "width", 0)),
           height: integer_or_zero(Map.get(variant, "height", 0))
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
      bytes: integer_or_zero(Map.get(normalized, "bytes", 0)),
      width: width,
      height: height,
      variants: variants
    }
  end

  @spec normalize_font_manifest(map()) :: map()
  defp normalize_font_manifest(manifest) when is_map(manifest) do
    entries = manifest["entries"] || []
    sources = manifest["sources"] || []

    if is_list(sources) and sources != [] do
      %{
        "schema_version" => 2,
        "sources" => Enum.map(sources, &normalize_font_source_row/1),
        "entries" => Enum.map(entries, &normalize_font_variant_row/1)
      }
    else
      normalized_sources =
        entries
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn row ->
          ctor =
            to_string(Map.get(row, "ctor", constructor_from_name(Map.get(row, "filename", ""))))

          filename = to_string(Map.get(row, "filename", ""))
          source_id = to_string(Map.get(row, "source_id", String.downcase(ctor)))

          %{
            "id" => source_id,
            "filename" => filename,
            "mime" => to_string(Map.get(row, "mime", "font/ttf")),
            "bytes" => integer_or_zero(Map.get(row, "bytes", 0))
          }
        end)
        |> Enum.uniq_by(&Map.get(&1, "id"))

      normalized_entries =
        entries
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn row ->
          ctor =
            to_string(Map.get(row, "ctor", constructor_from_name(Map.get(row, "filename", ""))))

          filename = to_string(Map.get(row, "filename", ""))
          source_id = to_string(Map.get(row, "source_id", String.downcase(ctor)))

          normalize_font_variant_row(%{
            "id" => to_string(Map.get(row, "id", "font_" <> String.downcase(ctor))),
            "source_id" => source_id,
            "ctor" => ctor,
            "name" => to_string(Map.get(row, "name", ctor)),
            "filename" => filename,
            "mime" => to_string(Map.get(row, "mime", "font/ttf")),
            "bytes" => integer_or_zero(Map.get(row, "bytes", 0)),
            "height" => positive_integer_or_default(Map.get(row, "height", 0), 24),
            "characters" => to_string(Map.get(row, "characters", "")),
            "tracking_adjust" => integer_or_default(Map.get(row, "tracking_adjust", 0), 0),
            "compatibility" => to_string(Map.get(row, "compatibility", "2.7")),
            "target_platforms" => string_list(Map.get(row, "target_platforms", []))
          })
        end)

      %{"schema_version" => 2, "sources" => normalized_sources, "entries" => normalized_entries}
    end
  end

  @spec normalize_font_source_row(map() | list() | nil) :: map()
  defp normalize_font_source_row(row) when is_map(row) do
    %{
      "id" => safe_resource_id(Map.get(row, "id", Map.get(row, "filename", "font"))),
      "filename" => to_string(Map.get(row, "filename", "")),
      "mime" => to_string(Map.get(row, "mime", "font/ttf")),
      "bytes" => integer_or_zero(Map.get(row, "bytes", 0))
    }
  end

  defp normalize_font_source_row(_), do: normalize_font_source_row(%{})

  @spec normalize_font_variant_row(map() | list() | nil) :: map()
  defp normalize_font_variant_row(row) when is_map(row) do
    ctor = row |> Map.get("ctor", "Font") |> to_string() |> valid_constructor_name()
    height = positive_integer_or_default(Map.get(row, "height", 0), 24)

    %{
      "id" => to_string(Map.get(row, "id", "font_" <> String.downcase(ctor))),
      "source_id" => safe_resource_id(Map.get(row, "source_id", "")),
      "ctor" => ctor,
      "name" => to_string(Map.get(row, "name", ctor)),
      "filename" => to_string(Map.get(row, "filename", "")),
      "mime" => to_string(Map.get(row, "mime", "font/ttf")),
      "bytes" => integer_or_zero(Map.get(row, "bytes", 0)),
      "height" => height,
      "characters" => to_string(Map.get(row, "characters", "")),
      "tracking_adjust" => integer_or_default(Map.get(row, "tracking_adjust", 0), 0),
      "compatibility" => to_string(Map.get(row, "compatibility", "2.7")),
      "target_platforms" => string_list(Map.get(row, "target_platforms", []))
    }
  end

  defp normalize_font_variant_row(_), do: normalize_font_variant_row(%{})

  @spec font_manifest_payload([map()], [map()]) :: map()
  defp font_manifest_payload(sources, entries) do
    %{
      "schema_version" => 2,
      "sources" => Enum.map(sources, &normalize_font_source_row/1),
      "entries" => Enum.map(entries, &normalize_font_variant_row/1)
    }
  end

  @spec elm_string(String.t()) :: String.t()
  defp elm_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  @spec normalized_filename_and_mime(String.t()) ::
          {:ok, String.t(), String.t()} | {:error, Types.asset_type_error()}
  defp normalized_filename_and_mime(original_name) do
    ext =
      original_name
      |> Path.extname()
      |> String.downcase()

    mime =
      case ext do
        ".png" -> "image/png"
        ".bmp" -> "image/bmp"
        ".jpg" -> "image/jpeg"
        ".jpeg" -> "image/jpeg"
        ".gif" -> "image/gif"
        ".webp" -> "image/webp"
        _ -> nil
      end

    if is_binary(mime) do
      base =
        original_name
        |> Path.basename()
        |> Path.rootname()
        |> String.replace(~r/[^A-Za-z0-9_-]+/, "_")
        |> String.trim("_")
        |> case do
          "" -> "bitmap"
          value -> value
        end

      {:ok, String.downcase(base) <> ext, mime}
    else
      {:error, :unsupported_bitmap_type}
    end
  end

  @spec normalized_font_filename_and_mime(String.t()) ::
          {:ok, String.t(), String.t()} | {:error, Types.asset_type_error()}
  defp normalized_font_filename_and_mime(original_name) do
    ext =
      original_name
      |> Path.extname()
      |> String.downcase()

    mime =
      case ext do
        ".ttf" -> "font/ttf"
        ".otf" -> "font/otf"
        ".pfo" -> "application/octet-stream"
        _ -> nil
      end

    if is_binary(mime) do
      base =
        original_name
        |> Path.basename()
        |> Path.rootname()
        |> String.replace(~r/[^A-Za-z0-9_-]+/, "_")
        |> String.trim("_")
        |> case do
          "" -> "font"
          value -> value
        end

      {:ok, String.downcase(base) <> ext, mime}
    else
      {:error, :unsupported_font_type}
    end
  end

  @spec constructor_from_name(String.t()) :: String.t()
  defp constructor_from_name(filename) do
    filename
    |> Path.rootname()
    |> String.split(~r/[^A-Za-z0-9]+/, trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
    |> case do
      "" -> "Resource"
      value -> value
    end
  end

  @spec unique_ctor(String.t(), [map()]) :: String.t()
  defp unique_ctor(ctor, entries, ctor_hint \\ nil)

  defp unique_ctor(_ctor, _entries, ctor_hint) when is_binary(ctor_hint) and ctor_hint != "" do
    ctor_hint
  end

  defp unique_ctor(ctor, entries, _ctor_hint) do
    used =
      entries
      |> Enum.map(&Map.get(&1, "ctor", ""))
      |> MapSet.new()

    if MapSet.member?(used, ctor) do
      Stream.iterate(2, &(&1 + 1))
      |> Enum.find_value(fn idx ->
        candidate = "#{ctor}#{idx}"
        if MapSet.member?(used, candidate), do: nil, else: candidate
      end)
    else
      ctor
    end
  end

  @spec unique_source_id(Types.wire_input(), [map()]) :: String.t()
  defp unique_source_id(value, sources) do
    base = safe_resource_id(value)

    used =
      sources
      |> Enum.map(&Map.get(&1, "id", ""))
      |> MapSet.new()

    if MapSet.member?(used, base) do
      Stream.iterate(2, &(&1 + 1))
      |> Enum.find_value(fn idx ->
        candidate = "#{base}_#{idx}"
        if MapSet.member?(used, candidate), do: nil, else: candidate
      end)
    else
      base
    end
  end

  @spec safe_resource_id(Types.wire_input()) :: String.t()
  defp safe_resource_id(value) do
    value
    |> to_string()
    |> Path.rootname()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/, "_")
    |> String.trim("_")
    |> case do
      "" -> "font"
      id -> id
    end
  end

  @spec valid_constructor_name(Types.wire_input()) :: String.t()
  defp valid_constructor_name(value) do
    value
    |> to_string()
    |> String.split(~r/[^A-Za-z0-9]+/, trim: true)
    |> Enum.map(fn
      <<first::binary-size(1), rest::binary>> -> String.upcase(first) <> rest
      other -> other
    end)
    |> Enum.join()
    |> case do
      "" ->
        "Font"

      <<first::binary-size(1), rest::binary>> ->
        String.upcase(first) <> rest
    end
  end

  @spec font_source_by_id(Types.manifest(), String.t()) ::
          {:ok, map()} | {:error, font_lookup_error()}
  defp font_source_by_id(manifest, source_id) do
    case Enum.find(manifest["sources"] || [], &(Map.get(&1, "id") == source_id)) do
      %{} = source -> {:ok, source}
      _ -> {:error, :font_source_not_found}
    end
  end

  @spec font_source_from_params(Types.manifest(), form_params()) ::
          {:ok, map()} | {:error, font_lookup_error()}
  defp font_source_from_params(manifest, params) do
    source_id =
      params
      |> Map.get("source_id", Map.get(params, :source_id, ""))
      |> to_string()

    font_source_by_id(manifest, source_id)
  end

  defp default_font_variant_target_platforms(%Project{} = project, params) when is_map(params) do
    target_platforms =
      params
      |> Map.get("target_platforms", Map.get(params, :target_platforms, []))
      |> string_list()

    if target_platforms == [] do
      Map.put(params, "target_platforms", project_target_platforms(project))
    else
      params
    end
  end

  defp project_target_platforms(%Project{} = project) do
    defaults = Map.get(project, :release_defaults, %{}) || %{}
    allowed = PebbleToolchain.supported_emulator_targets()
    allowed_set = MapSet.new(allowed)

    defaults
    |> Map.get("target_platforms", allowed)
    |> string_list()
    |> Enum.filter(&MapSet.member?(allowed_set, &1))
    |> Enum.uniq()
    |> case do
      [] -> allowed
      platforms -> platforms
    end
  end

  @spec font_variant_from_params(map(), map(), [map()], String.t() | nil) ::
          {:ok, map()} | {:error, Types.asset_type_error()}
  defp font_variant_from_params(source, params, entries, existing_ctor \\ nil) do
    raw_ctor =
      params
      |> Map.get("ctor", Map.get(params, :ctor, ""))
      |> to_string()
      |> String.trim()

    ctor_source =
      if raw_ctor == "" do
        source
        |> Map.get("filename", "Font")
        |> Path.rootname()
      else
        raw_ctor
      end

    ctor = valid_constructor_name(ctor_source)

    used_entries =
      if existing_ctor do
        Enum.reject(entries, &(Map.get(&1, "ctor") == existing_ctor))
      else
        entries
      end

    ctor =
      if Enum.any?(used_entries, &(Map.get(&1, "ctor") == ctor)) do
        unique_ctor(ctor, used_entries)
      else
        ctor
      end

    height =
      params
      |> Map.get("height", Map.get(params, :height, nil))
      |> positive_integer_or_default(next_font_height_for_source(source, used_entries))

    if height <= 0 do
      {:error, :invalid_font_height}
    else
      variant = %{
        "id" => "font_" <> String.downcase(ctor),
        "source_id" => Map.fetch!(source, "id"),
        "ctor" => ctor,
        "name" => params |> Map.get("name", Map.get(params, :name, ctor)) |> to_string(),
        "filename" => Map.get(source, "filename", ""),
        "mime" => Map.get(source, "mime", "font/ttf"),
        "bytes" => integer_or_zero(Map.get(source, "bytes", 0)),
        "height" => height,
        "characters" =>
          params |> Map.get("characters", Map.get(params, :characters, "")) |> to_string(),
        "tracking_adjust" =>
          params
          |> Map.get("tracking_adjust", Map.get(params, :tracking_adjust, 0))
          |> integer_or_default(0),
        "compatibility" =>
          params
          |> Map.get("compatibility", Map.get(params, :compatibility, "latest"))
          |> to_string(),
        "target_platforms" =>
          params
          |> Map.get("target_platforms", Map.get(params, :target_platforms, []))
          |> string_list()
      }

      {:ok, normalize_font_variant_row(variant)}
    end
  end

  @spec next_font_height_for_source(map(), [map()]) :: pos_integer()
  defp next_font_height_for_source(source, entries) do
    source_id = Map.get(source, "id", "")

    max_height =
      entries
      |> Enum.filter(&(Map.get(&1, "source_id") == source_id))
      |> Enum.map(&(Map.get(&1, "height", 0) |> positive_integer_or_default(0)))
      |> Enum.max(fn -> 23 end)

    max_height + 1
  end

  @spec bitmap_dimensions(binary(), String.t()) :: {non_neg_integer(), non_neg_integer()}
  defp bitmap_dimensions(
         <<0x89, "PNG\r\n", 0x1A, "\n", _len::32, "IHDR", width::32, height::32, _::binary>>,
         "image/png"
       ),
       do: {width, height}

  defp bitmap_dimensions(_bytes, _mime), do: {0, 0}

  @spec positive_integer_or_default(Types.wire_input(), integer()) :: integer()
  defp positive_integer_or_default(value, _default) when is_integer(value) and value > 0,
    do: value

  defp positive_integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp positive_integer_or_default(_value, default), do: default

  @spec integer_or_zero(Types.wire_input()) :: non_neg_integer()
  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value
  defp integer_or_zero(_), do: 0

  @spec integer_or_default(Types.wire_input(), integer()) :: integer()
  defp integer_or_default(value, _default) when is_integer(value), do: value

  defp integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp integer_or_default(_value, default), do: default

  @spec string_list(list() | String.t() | nil) :: [String.t()]
  defp string_list(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp string_list(value) when is_binary(value) do
    value
    |> String.split([",", " ", "\n", "\t"], trim: true)
    |> string_list()
  end

  defp string_list(_), do: []

  @spec migrate_resource_ctor_names(Types.workspace_path()) :: :ok | {:error, Types.resource_error()}
  defp migrate_resource_ctor_names(workspace) do
    with :ok <- migrate_bitmap_manifest(workspace),
         :ok <- migrate_vector_manifest(workspace),
         :ok <- AnimationStore.migrate_manifest(workspace) do
      :ok
    end
  end

  defp migrate_bitmap_manifest(workspace) do
    manifest_path = Path.join(workspace, @manifest_rel_path)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    case read_bitmap_manifest(workspace) do
      {:ok, manifest} ->
        {entries, changed?} =
          Enum.map_reduce(manifest["entries"] || [], false, fn row, changed ->
            migrated = migrate_bitmap_row_files(assets_dir, row)
            {migrated, changed or migrated != row}
          end)

        if changed? do
          write_manifest(manifest_path, %{"schema_version" => 1, "entries" => entries})
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp migrate_vector_manifest(workspace) do
    manifest_path = Path.join(workspace, @vector_manifest_rel_path)
    assets_dir = Path.join(workspace, @vector_assets_rel_dir)

    case read_vector_manifest(workspace) do
      {:ok, manifest} ->
        {entries, changed?} =
          Enum.map_reduce(manifest["entries"] || [], false, fn row, changed ->
            kind = CtorNaming.vector_kind_from_row(row)
            migrated = migrate_vector_row_files(assets_dir, row, Map.get(row, "ctor"), nil, kind)
            {migrated, changed or migrated != row}
          end)

        if changed? do
          write_manifest(manifest_path, %{"schema_version" => 1, "entries" => entries})
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp migrate_bitmap_row_files(assets_dir, row, old_ctor \\ nil, new_ctor \\ nil) do
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
    end
  end

  defp migrate_vector_row_files(assets_dir, row, old_ctor, new_ctor, kind) do
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

  defp vector_import_kind(extras) do
    case Map.get(extras, :kind) do
      "sequence" -> :vector_animated
      _ -> :vector_static
    end
  end
end
