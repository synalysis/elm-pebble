defmodule Ide.Resources.ResourceStore.Fonts do
  @moduledoc false

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.PebbleToolchain

  alias Ide.Resources.ResourceStore.{Coercion, CtorDedup, Duplicates, Manifest}
  alias Ide.Resources.Types

  @font_manifest_rel_path "watch/resources/fonts.json"
  @font_assets_rel_dir "watch/resources/fonts"

  @type font_entry :: Types.font_entry()
  @type font_source :: Types.font_source()
  @type font_lookup_error :: Types.font_lookup_error()
  @type form_params :: Types.font_form_params()

  @spec list_fonts(Project.t()) :: {:ok, [font_entry()]} | {:error, Types.resource_error()}
  def list_fonts(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_manifest(workspace) do
      entries = manifest["entries"] || []

      {:ok,
       Enum.map(entries, fn row ->
         %{
           id: to_string(Map.get(row, "id", "")),
           ctor: to_string(Map.get(row, "ctor", "")),
           source_id: to_string(Map.get(row, "source_id", "")),
           filename: to_string(Map.get(row, "filename", "")),
           mime: to_string(Map.get(row, "mime", "font/ttf")),
           bytes: Coercion.integer_or_zero(Map.get(row, "bytes", 0)),
           height: Coercion.positive_integer_or_default(Map.get(row, "height", 0), 0),
           characters: to_string(Map.get(row, "characters", "")),
           tracking_adjust: Coercion.integer_or_default(Map.get(row, "tracking_adjust", 0), 0),
           compatibility: to_string(Map.get(row, "compatibility", "2.7")),
           target_platforms: Coercion.string_list(Map.get(row, "target_platforms", []))
         }
       end)}
    end
  end

  @spec list_font_sources(Project.t()) ::
          {:ok, [font_source()]} | {:error, Types.resource_error()}
  def list_font_sources(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_manifest(workspace) do
      sources = manifest["sources"] || []

      {:ok,
       Enum.map(sources, fn row ->
         %{
           id: to_string(Map.get(row, "id", "")),
           filename: to_string(Map.get(row, "filename", "")),
           mime: to_string(Map.get(row, "mime", "font/ttf")),
           bytes: Coercion.integer_or_zero(Map.get(row, "bytes", 0))
         }
       end)}
    end
  end

  @spec import_font(Project.t(), String.t(), String.t()) :: Types.font_import_result()
  def import_font(%Project{} = project, upload_path, original_name)
      when is_binary(upload_path) and is_binary(original_name) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @font_assets_rel_dir)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)

    with :ok <- File.mkdir_p(assets_dir),
         {:ok, manifest} <- read_manifest(workspace),
         {:ok, bytes} <- File.read(upload_path),
         {:ok, safe_name, mime} <- normalized_font_filename_and_mime(original_name),
         nil <- Duplicates.duplicate_asset_entry(manifest["sources"] || [], assets_dir, bytes),
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

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
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

  @spec add_font_variant(Project.t(), form_params()) :: Types.font_variant_result()
  def add_font_variant(%Project{} = project, params) when is_map(params) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)
    params = default_font_variant_target_platforms(project, params)

    with {:ok, manifest} <- read_manifest(workspace),
         {:ok, source} <- font_source_from_params(manifest, params),
         {:ok, variant} <- font_variant_from_params(source, params, manifest["entries"] || []) do
      entries =
        (manifest["entries"] || [])
        |> Enum.reject(&(Map.get(&1, "ctor") == Map.fetch!(variant, "ctor")))
        |> Kernel.++([variant])
        |> Enum.sort_by(&Map.get(&1, "ctor", ""))

      payload = font_manifest_payload(manifest["sources"] || [], entries)

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok, %{entry: variant, entries: entries}}
      end
    end
  end

  @spec update_font_variant(Project.t(), String.t(), form_params()) ::
          Types.font_variant_result()
  def update_font_variant(%Project{} = project, ctor, params)
      when is_binary(ctor) and is_map(params) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)

    with {:ok, manifest} <- read_manifest(workspace),
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

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok, %{entry: variant, entries: entries}}
      end
    else
      nil -> {:error, :font_variant_not_found}
      error -> error
    end
  end

  @spec delete_font(Project.t(), String.t()) :: Types.delete_entries_result()
  def delete_font(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)

    with {:ok, manifest} <- read_manifest(workspace) do
      entries = manifest["entries"] || []
      kept = Enum.reject(entries, &(Map.get(&1, "ctor") == ctor))
      payload = font_manifest_payload(manifest["sources"] || [], kept)

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok, kept}
      end
    end
  end

  @spec delete_font_source(Project.t(), String.t()) :: Types.font_delete_source_result()
  def delete_font_source(%Project{} = project, source_id) when is_binary(source_id) do
    workspace = Projects.project_workspace_path(project)
    manifest_path = Path.join(workspace, @font_manifest_rel_path)
    assets_dir = Path.join(workspace, @font_assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace) do
      sources = manifest["sources"] || []
      entries = manifest["entries"] || []

      {to_remove, kept_sources} = Enum.split_with(sources, &(Map.get(&1, "id") == source_id))
      kept_entries = Enum.reject(entries, &(Map.get(&1, "source_id") == source_id))

      Enum.each(to_remove, fn row ->
        filename = Map.get(row, "filename", "")
        if filename != "", do: File.rm(Path.join(assets_dir, filename))
      end)

      payload = font_manifest_payload(kept_sources, kept_entries)

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- Manifest.write_generated_module(workspace) do
        {:ok, %{sources: kept_sources, entries: kept_entries}}
      end
    end
  end

  @spec font_file_path(Project.t(), String.t()) ::
          {:ok, String.t()} | {:error, Types.resource_error()}
  def font_file_path(%Project{} = project, ctor) when is_binary(ctor) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @font_assets_rel_dir)

    with {:ok, manifest} <- read_manifest(workspace),
         %{} = row <- Enum.find(manifest["entries"] || [], &(Map.get(&1, "ctor") == ctor)),
         {:ok, source} <- font_source_by_id(manifest, Map.get(row, "source_id", "")),
         filename when is_binary(filename) and filename != "" <- Map.get(source, "filename") do
      {:ok, Path.join(assets_dir, filename)}
    else
      _ -> {:error, :font_not_found}
    end
  end
  @spec read_manifest(Types.workspace_path()) ::
          {:ok, Types.manifest()} | {:error, Types.resource_error()}
  defp read_manifest(workspace) do
    case Manifest.read_font_manifest(workspace) do
      {:ok, manifest} -> {:ok, normalize_font_manifest(manifest)}
      error -> error
    end
  end
  @spec normalize_font_manifest(Types.manifest_wire_row()) :: Types.font_manifest_payload()
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
            "bytes" => Coercion.integer_or_zero(Map.get(row, "bytes", 0))
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
            "bytes" => Coercion.integer_or_zero(Map.get(row, "bytes", 0)),
            "height" => Coercion.positive_integer_or_default(Map.get(row, "height", 0), 24),
            "characters" => to_string(Map.get(row, "characters", "")),
            "tracking_adjust" => Coercion.integer_or_default(Map.get(row, "tracking_adjust", 0), 0),
            "compatibility" => to_string(Map.get(row, "compatibility", "2.7")),
            "target_platforms" => Coercion.string_list(Map.get(row, "target_platforms", []))
          })
        end)

      %{"schema_version" => 2, "sources" => normalized_sources, "entries" => normalized_entries}
    end
  end

  @spec normalize_font_source_row(Types.manifest_wire_row() | list() | nil) ::
          Types.manifest_wire_row()
  defp normalize_font_source_row(row) when is_map(row) do
    %{
      "id" => safe_resource_id(Map.get(row, "id", Map.get(row, "filename", "font"))),
      "filename" => to_string(Map.get(row, "filename", "")),
      "mime" => to_string(Map.get(row, "mime", "font/ttf")),
      "bytes" => Coercion.integer_or_zero(Map.get(row, "bytes", 0))
    }
  end

  defp normalize_font_source_row(_), do: normalize_font_source_row(%{})

  @spec normalize_font_variant_row(Types.manifest_wire_row() | list() | nil) ::
          Types.manifest_wire_row()
  defp normalize_font_variant_row(row) when is_map(row) do
    ctor = row |> Map.get("ctor", "Font") |> to_string() |> valid_constructor_name()
    height = Coercion.positive_integer_or_default(Map.get(row, "height", 0), 24)

    %{
      "id" => to_string(Map.get(row, "id", "font_" <> String.downcase(ctor))),
      "source_id" => safe_resource_id(Map.get(row, "source_id", "")),
      "ctor" => ctor,
      "name" => to_string(Map.get(row, "name", ctor)),
      "filename" => to_string(Map.get(row, "filename", "")),
      "mime" => to_string(Map.get(row, "mime", "font/ttf")),
      "bytes" => Coercion.integer_or_zero(Map.get(row, "bytes", 0)),
      "height" => height,
      "characters" => to_string(Map.get(row, "characters", "")),
      "tracking_adjust" => Coercion.integer_or_default(Map.get(row, "tracking_adjust", 0), 0),
      "compatibility" => to_string(Map.get(row, "compatibility", "2.7")),
      "target_platforms" => Coercion.string_list(Map.get(row, "target_platforms", []))
    }
  end

  defp normalize_font_variant_row(_), do: normalize_font_variant_row(%{})

  @spec font_manifest_payload([Types.manifest_wire_row()], [Types.manifest_wire_row()]) ::
          Types.font_manifest_payload()
  defp font_manifest_payload(sources, entries) do
    %{
      "schema_version" => 2,
      "sources" => Enum.map(sources, &normalize_font_source_row/1),
      "entries" => Enum.map(entries, &normalize_font_variant_row/1)
    }
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

  @spec unique_source_id(Types.wire_input(), [Types.manifest_wire_row()]) :: String.t()
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
          {:ok, Types.manifest_wire_row()} | {:error, font_lookup_error()}
  defp font_source_by_id(manifest, source_id) do
    case Enum.find(manifest["sources"] || [], &(Map.get(&1, "id") == source_id)) do
      %{} = source -> {:ok, source}
      _ -> {:error, :font_source_not_found}
    end
  end

  @spec font_source_from_params(Types.manifest(), form_params()) ::
          {:ok, Types.manifest_wire_row()} | {:error, font_lookup_error()}
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
      |> Coercion.string_list()

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
    |> Coercion.string_list()
    |> Enum.filter(&MapSet.member?(allowed_set, &1))
    |> Enum.uniq()
    |> case do
      [] -> allowed
      platforms -> platforms
    end
  end

  @spec font_variant_from_params(
          font_source(),
          form_params(),
          [Types.manifest_wire_row()],
          String.t() | nil
        ) :: {:ok, Types.manifest_wire_row()}
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

    ctor = CtorDedup.among_entries(ctor, used_entries, nil)

    height =
      params
      |> Map.get("height", Map.get(params, :height, nil))
      |> Coercion.positive_integer_or_default(next_font_height_for_source(source, used_entries))
      |> max(1)

    variant = %{
      "id" => "font_" <> String.downcase(ctor),
      "source_id" => Map.fetch!(source, "id"),
      "ctor" => ctor,
      "name" => params |> Map.get("name", Map.get(params, :name, ctor)) |> to_string(),
      "filename" => Map.get(source, "filename", ""),
      "mime" => Map.get(source, "mime", "font/ttf"),
      "bytes" => Coercion.integer_or_zero(Map.get(source, "bytes", 0)),
      "height" => height,
      "characters" =>
        params |> Map.get("characters", Map.get(params, :characters, "")) |> to_string(),
      "tracking_adjust" =>
        params
        |> Map.get("tracking_adjust", Map.get(params, :tracking_adjust, 0))
        |> Coercion.integer_or_default(0),
      "compatibility" =>
        params
        |> Map.get("compatibility", Map.get(params, :compatibility, "latest"))
        |> to_string(),
      "target_platforms" =>
        params
        |> Map.get("target_platforms", Map.get(params, :target_platforms, []))
        |> Coercion.string_list()
    }

    {:ok, normalize_font_variant_row(variant)}
  end

  @spec next_font_height_for_source(
          Types.manifest_wire_row(),
          [Types.manifest_wire_row()]
        ) :: pos_integer()
  defp next_font_height_for_source(source, entries) do
    source_id = Map.get(source, "id", "")

    max_height =
      entries
      |> Enum.filter(&(Map.get(&1, "source_id") == source_id))
      |> Enum.map(&(Map.get(&1, "height", 0) |> Coercion.positive_integer_or_default(0)))
      |> Enum.max(fn -> 23 end)

    max_height + 1
  end

end
