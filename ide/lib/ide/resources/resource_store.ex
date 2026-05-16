defmodule Ide.Resources.ResourceStore do
  @moduledoc """
  Project-local resource storage and generated Elm resources module management.
  """

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.PebbleToolchain

  @manifest_rel_path "watch/resources/bitmaps.json"
  @assets_rel_dir "watch/resources/bitmaps"
  @font_manifest_rel_path "watch/resources/fonts.json"
  @font_assets_rel_dir "watch/resources/fonts"
  @generated_module_rel_path "watch/src/Pebble/Ui/Resources.elm"
  @legacy_generated_module_rel_path "watch/src/Pebble/Ui/Bitmap.elm"

  @type bitmap_entry :: %{
          id: String.t(),
          ctor: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer()
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

  @type font_source :: %{
          id: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer()
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

  @spec list(Project.t()) :: {:ok, [bitmap_entry()]} | {:error, term()}
  def list(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_bitmap_manifest(workspace) do
      entries = manifest["entries"] || []

      {:ok,
       Enum.map(entries, fn row ->
         %{
           id: to_string(Map.get(row, "id", "")),
           ctor: to_string(Map.get(row, "ctor", "")),
           filename: to_string(Map.get(row, "filename", "")),
           mime: to_string(Map.get(row, "mime", "image/png")),
           bytes: integer_or_zero(Map.get(row, "bytes", 0))
         }
       end)}
    end
  end

  @spec import_bitmap(Project.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def import_bitmap(%Project{} = project, upload_path, original_name)
      when is_binary(upload_path) and is_binary(original_name) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_bitmap_manifest(workspace),
         {:ok, bytes} <- File.read(upload_path),
         {:ok, safe_name, mime} <- normalized_filename_and_mime(original_name),
         nil <- duplicate_asset_entry(manifest["entries"] || [], assets_dir, bytes),
         ctor <- constructor_from_name(safe_name),
         unique_ctor <- unique_ctor(ctor, manifest["entries"] || []),
         basename <- "#{unique_ctor}#{Path.extname(safe_name)}",
         asset_path <- Path.join(assets_dir, basename),
         :ok <- File.write(asset_path, bytes) do
      {width, height} = bitmap_dimensions(bytes, mime)

      entry = %{
        "id" => "bitmap_" <> String.downcase(unique_ctor),
        "ctor" => unique_ctor,
        "filename" => basename,
        "mime" => mime,
        "bytes" => byte_size(bytes),
        "width" => width,
        "height" => height
      }

      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == unique_ctor))
        |> Kernel.++([entry])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      payload = %{"schema_version" => 1, "entries" => entries}

      with :ok <- write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, %{entry: entry, entries: entries}}
      end
    else
      %{} = duplicate ->
        {:ok,
         %{
           duplicate: true,
           entry: duplicate
         }}

      other ->
        other
    end
  end

  @spec delete_bitmap(Project.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def delete_bitmap(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @manifest_rel_path)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_bitmap_manifest(workspace) do
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

  @spec ensure_generated(Project.t()) :: :ok | {:error, term()}
  def ensure_generated(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)
    write_generated_module(workspace)
  end

  @spec ensure_generated_workspace(String.t()) :: :ok | {:error, term()}
  def ensure_generated_workspace(workspace) when is_binary(workspace) do
    write_generated_module(workspace)
  end

  @spec bitmap_file_path(Project.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def bitmap_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)

    with {:ok, manifest} <- read_bitmap_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)),
         filename when is_binary(filename) and filename != "" <- Map.get(row, "filename") do
      {:ok, Path.join(assets_dir, filename)}
    else
      _ -> {:error, :bitmap_not_found}
    end
  end

  @spec list_fonts(Project.t()) :: {:ok, [font_entry()]} | {:error, term()}
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

  @spec list_font_sources(Project.t()) :: {:ok, [font_source()]} | {:error, term()}
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

  @spec import_font(Project.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
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

  @spec add_font_variant(Project.t(), map()) :: {:ok, map()} | {:error, term()}
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

  @spec update_font_variant(Project.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
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

  @spec delete_font(Project.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
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

  @spec delete_font_source(Project.t(), String.t()) :: {:ok, map()} | {:error, term()}
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

  @spec font_file_path(Project.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
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

  @spec bitmap_file_path_by_id(Project.t(), integer()) :: {:ok, String.t()} | {:error, term()}
  def bitmap_file_path_by_id(%Project{} = project, id) when is_integer(id) and id >= 1 do
    with {:ok, entries} <- list(project),
         %{} = row <- Enum.at(entries, id - 1) do
      bitmap_file_path(project, row.ctor)
    else
      _ -> {:error, :bitmap_not_found}
    end
  end

  def bitmap_file_path_by_id(_project, _), do: {:error, :bitmap_not_found}

  @spec read_bitmap_manifest(term()) :: term()
  defp read_bitmap_manifest(workspace) do
    path = Path.join(workspace, @manifest_rel_path)
    read_manifest(path)
  end

  @spec read_font_manifest(term()) :: term()
  defp read_font_manifest(workspace) do
    path = Path.join(workspace, @font_manifest_rel_path)

    case read_manifest(path) do
      {:ok, manifest} -> {:ok, normalize_font_manifest(manifest)}
      error -> error
    end
  end

  @spec read_manifest(term()) :: term()
  defp read_manifest(path) do
    path = Path.expand(path)

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, decoded} when is_map(decoded) ->
            {:ok, Map.put_new(decoded, "entries", [])}

          _ ->
            {:ok, %{"schema_version" => 1, "entries" => []}}
        end

      {:error, :enoent} ->
        {:ok, %{"schema_version" => 1, "entries" => []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec write_manifest(term(), term()) :: term()
  defp write_manifest(path, payload) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, json} <- Jason.encode(payload, pretty: true),
         :ok <- File.write(path, json <> "\n") do
      :ok
    end
  end

  @spec write_generated_module(term()) :: term()
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

    path = Path.join(workspace, @generated_module_rel_path)
    legacy = Path.join(workspace, @legacy_generated_module_rel_path)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, generated_module_source(bitmap_entries, font_entries)) do
      _ = File.rm(legacy)
      :ok
    end
  end

  @spec generated_module_source(term(), term()) :: term()
  defp generated_module_source(bitmap_entries, font_entries) do
    bitmap_rows =
      bitmap_entries
      |> Enum.map(&normalize_bitmap_row/1)
      |> Enum.reject(&(&1.ctor == ""))

    font_rows =
      font_entries
      |> Enum.map(&normalize_font_row/1)
      |> Enum.reject(&(&1.ctor == ""))

    {bitmap_type_decl, bitmap_all_decl} =
      case Enum.map(bitmap_rows, & &1.ctor) do
        [] ->
          {"type Bitmap\n    = NoBitmap",
           "allBitmaps : List Bitmap\nallBitmaps =\n    [ NoBitmap ]"}

        list ->
          type_rows = Enum.map_join(list, "\n    | ", & &1)
          all_rows = Enum.map_join(list, ", ", & &1)

          {"type Bitmap\n    = #{type_rows}",
           "allBitmaps : List Bitmap\nallBitmaps =\n    [ #{all_rows} ]"}
      end

    bitmap_info_decl =
      case bitmap_rows do
        [] ->
          """
          type alias BitmapInfo =
              { bitmap : Bitmap
              , name : String
              , width : Int
              , height : Int
              }

          bitmapInfo : Bitmap -> BitmapInfo
          bitmapInfo bitmap =
              case bitmap of
                  NoBitmap ->
                      { bitmap = NoBitmap, name = "NoBitmap", width = 0, height = 0 }
          """

        rows ->
          cases =
            Enum.map_join(rows, "\n", fn row ->
              """
                  #{row.ctor} ->
                      { bitmap = #{row.ctor}, name = "#{elm_string(row.name)}", width = #{row.width}, height = #{row.height} }
              """
            end)

          """
          type alias BitmapInfo =
              { bitmap : Bitmap
              , name : String
              , width : Int
              , height : Int
              }

          bitmapInfo : Bitmap -> BitmapInfo
          bitmapInfo bitmap =
              case bitmap of
          #{cases}
          """
      end

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
    module Pebble.Ui.Resources exposing (Bitmap(..), BitmapInfo, Font(..), FontInfo, allBitmaps, allFonts, bitmapInfo, fontInfo)

    {-| Generated from the resources configured on the project settings Resources page.
    Edit bitmap and font assets there instead of editing this read-only file.
    -}

    #{bitmap_type_decl}

    #{bitmap_all_decl}

    #{bitmap_info_decl}

    #{font_type_decl}

    #{font_all_decl}

    #{font_info_decl}
    """
  end

  @spec normalize_bitmap_row(map()) :: map()
  defp normalize_bitmap_row(row) do
    ctor = to_string(Map.get(row, "ctor", ""))

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor)),
      width: integer_or_zero(Map.get(row, "width", 0)),
      height: integer_or_zero(Map.get(row, "height", 0))
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

  defp duplicate_asset_entry(entries, assets_dir, bytes) when is_list(entries) do
    Enum.find(entries, fn row ->
      filename = Map.get(row, "filename", "")

      is_binary(filename) and filename != "" and
        match?({:ok, ^bytes}, File.read(Path.join(assets_dir, filename)))
    end)
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

  @spec normalize_font_source_row(term()) :: map()
  defp normalize_font_source_row(row) when is_map(row) do
    %{
      "id" => safe_resource_id(Map.get(row, "id", Map.get(row, "filename", "font"))),
      "filename" => to_string(Map.get(row, "filename", "")),
      "mime" => to_string(Map.get(row, "mime", "font/ttf")),
      "bytes" => integer_or_zero(Map.get(row, "bytes", 0))
    }
  end

  defp normalize_font_source_row(_), do: normalize_font_source_row(%{})

  @spec normalize_font_variant_row(term()) :: map()
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

  @spec normalized_filename_and_mime(term()) :: term()
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

  @spec normalized_font_filename_and_mime(term()) :: term()
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

  @spec constructor_from_name(term()) :: term()
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

  @spec unique_ctor(term(), term()) :: term()
  defp unique_ctor(ctor, entries) do
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

  @spec unique_source_id(term(), [map()]) :: String.t()
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

  @spec safe_resource_id(term()) :: String.t()
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

  @spec valid_constructor_name(term()) :: String.t()
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

  @spec font_source_by_id(map(), String.t()) :: {:ok, map()} | {:error, term()}
  defp font_source_by_id(manifest, source_id) do
    case Enum.find(manifest["sources"] || [], &(Map.get(&1, "id") == source_id)) do
      %{} = source -> {:ok, source}
      _ -> {:error, :font_source_not_found}
    end
  end

  @spec font_source_from_params(map(), map()) :: {:ok, map()} | {:error, term()}
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
          {:ok, map()} | {:error, term()}
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

  @spec positive_integer_or_default(term(), integer()) :: integer()
  defp positive_integer_or_default(value, _default) when is_integer(value) and value > 0,
    do: value

  defp positive_integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp positive_integer_or_default(_value, default), do: default

  @spec integer_or_zero(term()) :: term()
  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value
  defp integer_or_zero(_), do: 0

  @spec integer_or_default(term(), integer()) :: integer()
  defp integer_or_default(value, _default) when is_integer(value), do: value

  defp integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp integer_or_default(_value, default), do: default

  @spec string_list(term()) :: [String.t()]
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
end
