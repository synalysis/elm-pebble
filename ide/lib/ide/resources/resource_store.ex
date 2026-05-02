defmodule Ide.Resources.ResourceStore do
  @moduledoc """
  Project-local resource storage and generated Elm resources module management.
  """

  alias Ide.Projects
  alias Ide.Projects.Project

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
    {source_root, rel_path} in [
      {"watch", "src/Pebble/Ui/Resources.elm"},
      {"watch", "src/Pebble/Ui/Bitmap.elm"},
      {"phone", "src/Companion/GeneratedPreferences.elm"}
    ]
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
         ctor <- constructor_from_name(safe_name),
         unique_ctor <- unique_ctor(ctor, manifest["entries"] || []),
         basename <- "#{unique_ctor}#{Path.extname(safe_name)}",
         asset_path <- Path.join(assets_dir, basename),
         :ok <- File.write(asset_path, bytes) do
      entry = %{
        "id" => "bitmap_" <> String.downcase(unique_ctor),
        "ctor" => unique_ctor,
        "filename" => basename,
        "mime" => mime,
        "bytes" => byte_size(bytes)
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
         ctor <- constructor_from_name(safe_name),
         unique_ctor <- unique_ctor(ctor, manifest["entries"] || []),
         basename <- "#{unique_ctor}#{Path.extname(safe_name)}",
         asset_path <- Path.join(assets_dir, basename),
         :ok <- File.write(asset_path, bytes) do
      entry = %{
        "id" => "font_" <> String.downcase(unique_ctor),
        "ctor" => unique_ctor,
        "filename" => basename,
        "mime" => mime,
        "bytes" => byte_size(bytes)
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
    end
  end

  @spec delete_font(Project.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def delete_font(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)
    assets_dir = Path.join(workspace, @font_assets_rel_dir)

    with {:ok, manifest} <- read_font_manifest(workspace) do
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

  @spec font_file_path(Project.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def font_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @font_assets_rel_dir)

    with {:ok, manifest} <- read_font_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)),
         filename when is_binary(filename) and filename != "" <- Map.get(row, "filename") do
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
    read_manifest(path)
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
    bitmap_ctors =
      bitmap_entries
      |> Enum.map(&Map.get(&1, "ctor", ""))
      |> Enum.filter(&(&1 != ""))

    font_ctors =
      font_entries
      |> Enum.map(&Map.get(&1, "ctor", ""))
      |> Enum.filter(&(&1 != ""))

    {bitmap_type_decl, bitmap_all_decl} =
      case bitmap_ctors do
        [] ->
          {"type Bitmap\n    = NoBitmap",
           "allBitmaps : List Bitmap\nallBitmaps =\n    [ NoBitmap ]"}

        list ->
          type_rows = Enum.map_join(list, "\n    | ", & &1)
          all_rows = Enum.map_join(list, ", ", & &1)

          {"type Bitmap\n    = #{type_rows}",
           "allBitmaps : List Bitmap\nallBitmaps =\n    [ #{all_rows} ]"}
      end

    {font_type_decl, font_all_decl} =
      case font_ctors do
        [] ->
          {"type Font\n    = DefaultFont",
           "allFonts : List Font\nallFonts =\n    [ DefaultFont ]"}

        list ->
          type_rows = Enum.map_join(list, "\n    | ", & &1)
          all_rows = Enum.map_join(list, ", ", & &1)

          {"type Font\n    = #{type_rows}",
           "allFonts : List Font\nallFonts =\n    [ #{all_rows} ]"}
      end

    """
    module Pebble.Ui.Resources exposing (Bitmap(..), Font(..), allBitmaps, allFonts)

    #{bitmap_type_decl}

    #{bitmap_all_decl}

    #{font_type_decl}

    #{font_all_decl}
    """
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

  @spec integer_or_zero(term()) :: term()
  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value
  defp integer_or_zero(_), do: 0
end
