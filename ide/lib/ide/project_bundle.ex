defmodule Ide.ProjectBundle do
  @moduledoc """
  Reads and writes project bundle metadata used for self-contained imports/exports.
  """

  alias Ide.PebbleToolchain
  alias Ide.Projects.Project

  @manifest_filename "elm-pebble.project.json"
  @default_source_roots ["watch", "protocol", "phone"]
  @default_import_path "."

  @type metadata :: %{
          name: String.t(),
          slug: String.t(),
          target_type: String.t(),
          source_roots: [String.t()],
          import_path: String.t(),
          store_app_id: String.t() | nil,
          app_uuid: String.t() | nil,
          latest_published_version: String.t() | nil,
          package_metadata_cache: map(),
          release_defaults: map(),
          github: map(),
          debugger_settings: map()
        }

  @doc """
  Returns the manifest filename stored at the project root.
  """
  @spec manifest_filename() :: String.t()
  def manifest_filename, do: @manifest_filename

  @doc """
  Writes bundle metadata for a project workspace.
  """
  @spec write_manifest(String.t(), Project.t(), keyword()) :: :ok | {:error, term()}
  def write_manifest(workspace_root, %Project{} = project, opts \\ []) do
    import_path = opts[:import_path] || @default_import_path

    payload = %{
      "schema_version" => 1,
      "name" => project.name,
      "slug" => project.slug,
      "target_type" => project.target_type,
      "source_roots" => project.source_roots || @default_source_roots,
      "import_path" => import_path,
      "store_app_id" => project.store_app_id,
      "app_uuid" => project.app_uuid,
      "latest_published_version" => project.latest_published_version,
      "package_metadata_cache" => project.package_metadata_cache || %{},
      "release_defaults" => project.release_defaults || %{},
      "github" => project.github || %{},
      "debugger_settings" => project.debugger_settings || %{}
    }

    with {:ok, encoded} <- Jason.encode(payload, pretty: true),
         :ok <- File.write(Path.join(workspace_root, @manifest_filename), encoded <> "\n") do
      :ok
    end
  end

  @doc """
  Reads and validates bundle metadata from an import root.
  """
  @spec read_manifest(String.t()) :: {:ok, metadata()} | {:error, term()}
  def read_manifest(import_root) do
    manifest_path = Path.join(import_root, @manifest_filename)

    with {:ok, json} <- File.read(manifest_path),
         {:ok, decoded} <- Jason.decode(json),
         {:ok, metadata} <- parse_metadata(decoded) do
      {:ok, metadata}
    end
  end

  @doc """
  Fills missing import attrs from bundle metadata when available.
  """
  @spec merge_attrs_from_manifest(map(), String.t()) :: map()
  def merge_attrs_from_manifest(attrs, import_root) do
    attrs = Map.new(attrs)

    case read_manifest(import_root) do
      {:ok, metadata} ->
        attrs
        |> put_if_blank("name", metadata.name)
        |> put_if_blank("slug", metadata.slug)
        |> put_if_blank("target_type", metadata.target_type)
        |> Map.put_new("source_roots", metadata.source_roots)
        |> put_if_blank("import_path", metadata.import_path)
        |> put_if_blank("store_app_id", metadata.store_app_id)
        |> put_if_blank("app_uuid", metadata.app_uuid)
        |> put_if_blank("latest_published_version", metadata.latest_published_version)
        |> Map.put_new("package_metadata_cache", metadata.package_metadata_cache)
        |> Map.put_new("release_defaults", metadata.release_defaults)
        |> Map.put_new("github", metadata.github)
        |> Map.put_new("debugger_settings", metadata.debugger_settings)

      {:error, _reason} ->
        attrs
    end
  end

  @doc """
  Reads `app_uuid` from `elm-pebble.project.json` when set.
  """
  @spec read_app_uuid(String.t()) :: String.t() | nil
  def read_app_uuid(workspace_root) when is_binary(workspace_root) do
    case read_manifest(workspace_root) do
      {:ok, %{app_uuid: uuid}} when is_binary(uuid) -> normalize_app_uuid(uuid)
      _ -> nil
    end
  end

  @doc """
  Reads the Pebble app UUID from `.pebble-sdk/app/package.json` when present.
  """
  @spec package_app_uuid(String.t()) :: String.t() | nil
  def package_app_uuid(workspace_root) when is_binary(workspace_root) do
    path = Path.join(workspace_root, ".pebble-sdk/app/package.json")

    with {:ok, source} <- File.read(path),
         {:ok, %{"pebble" => %{"uuid" => uuid}}} <- Jason.decode(source) do
      uuid |> to_string() |> String.trim() |> normalize_app_uuid()
    else
      _ -> nil
    end
  end

  @doc """
  Reads the app UUID from the newest `.pbw` under `.elm-pebble-publish/` when present.
  """
  @spec pbw_app_uuid(String.t()) :: String.t() | nil
  def pbw_app_uuid(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> Path.join(".elm-pebble-publish")
    |> latest_pbw_path()
    |> case do
      nil -> nil
      path -> uuid_from_pbw(path)
    end
  end

  @doc """
  Resolves a Pebble app UUID from manifest, package build, publish artifact, or project slug.
  """
  @spec resolve_app_uuid(String.t(), String.t() | nil) :: String.t() | nil
  def resolve_app_uuid(workspace_root, slug \\ nil) when is_binary(workspace_root) do
    read_app_uuid(workspace_root) ||
      package_app_uuid(workspace_root) ||
      pbw_app_uuid(workspace_root) ||
      slug_app_uuid(slug)
  end

  @spec slug_app_uuid(String.t() | nil) :: String.t() | nil
  defp slug_app_uuid(slug) when is_binary(slug) do
    slug = String.trim(slug)

    if slug != "" do
      slug |> PebbleToolchain.deterministic_app_uuid() |> normalize_app_uuid()
    end
  end

  defp slug_app_uuid(_), do: nil

  @spec normalize_app_uuid(term()) :: String.t() | nil
  defp normalize_app_uuid(uuid) do
    uuid = uuid |> to_string() |> String.trim()

    if uuid == "" do
      nil
    else
      String.downcase(uuid)
    end
  end

  @doc """
  Returns the newest `.pbw` path under `.elm-pebble-publish/` when present.
  """
  @spec latest_pbw_path(String.t()) :: String.t() | nil
  def latest_pbw_path(dir) do
    if File.dir?(dir) do
      dir
      |> Path.wildcard("**/*.pbw")
      |> Enum.sort_by(&File.stat!(&1).mtime, {:desc, DateTime})
      |> List.first()
    end
  end

  @spec uuid_from_pbw(String.t()) :: String.t() | nil
  defp uuid_from_pbw(path) do
    charlist_path = String.to_charlist(path)

    with {:ok, files} <- :zip.list_dir(charlist_path),
         entry when is_binary(entry) <- pbw_metadata_entry(files),
         {:ok, data} <- read_pbw_zip_entry(charlist_path, entry),
         {:ok, %{"uuid" => uuid}} <- Jason.decode(data) do
      normalize_app_uuid(uuid)
    else
      _ -> nil
    end
  end

  @spec pbw_metadata_entry(list()) :: String.t() | nil
  defp pbw_metadata_entry(files) do
    names = Enum.map(files, fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

    cond do
      "appinfo.json" in names -> "appinfo.json"
      "manifest.json" in names -> "manifest.json"
      true -> nil
    end
  end

  @spec read_pbw_zip_entry(charlist(), String.t()) :: {:ok, binary()} | {:error, term()}
  defp read_pbw_zip_entry(charlist_path, entry) do
    charlist_entry = String.to_charlist(entry)

    with {:ok, [{_, data}]} <- :zip.extract(charlist_path, [{:file, charlist_entry}, :memory]) do
      {:ok, data}
    end
  end

  @doc """
  Resolves the source directory to copy based on import root and manifest import path.
  """
  @spec resolve_import_source(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def resolve_import_source(import_root, attrs) do
    import_path =
      attrs
      |> Map.get("import_path", @default_import_path)
      |> to_string()
      |> String.trim()
      |> case do
        "" -> @default_import_path
        value -> value
      end

    cond do
      Path.type(import_path) == :absolute ->
        {:error, :import_path_must_be_relative}

      true ->
        expanded = Path.expand(import_path, import_root)
        root = Path.expand(import_root)
        allowed_prefix = root <> "/"

        cond do
          expanded == root or String.starts_with?(expanded, allowed_prefix) ->
            if File.dir?(expanded), do: {:ok, expanded}, else: {:error, :import_source_not_found}

          true ->
            {:error, :invalid_import_path}
        end
    end
  end

  @spec parse_metadata(term()) :: term()
  defp parse_metadata(decoded) when is_map(decoded) do
    with {:ok, name} <- fetch_nonempty_string(decoded, "name"),
         {:ok, slug} <- fetch_nonempty_string(decoded, "slug"),
         {:ok, target_type} <- fetch_nonempty_string(decoded, "target_type"),
         {:ok, source_roots} <- fetch_source_roots(decoded),
         {:ok, import_path} <- fetch_import_path(decoded),
         {:ok, store_app_id} <- fetch_optional_string(decoded, "store_app_id"),
         {:ok, app_uuid} <- fetch_optional_string(decoded, "app_uuid"),
         {:ok, latest_published_version} <-
           fetch_optional_string(decoded, "latest_published_version"),
         {:ok, package_metadata_cache} <- fetch_optional_map(decoded, "package_metadata_cache"),
         {:ok, release_defaults} <- fetch_optional_map(decoded, "release_defaults"),
         {:ok, github} <- fetch_optional_map(decoded, "github"),
         {:ok, debugger_settings} <- fetch_optional_map(decoded, "debugger_settings") do
      {:ok,
       %{
         name: name,
         slug: slug,
         target_type: target_type,
         source_roots: source_roots,
         import_path: import_path,
         store_app_id: store_app_id,
         app_uuid: app_uuid,
         latest_published_version: latest_published_version,
         package_metadata_cache: package_metadata_cache,
         release_defaults: release_defaults,
         github: github,
         debugger_settings: debugger_settings
       }}
    end
  end

  defp parse_metadata(_), do: {:error, :invalid_manifest}

  @spec fetch_nonempty_string(term(), term()) :: term()
  defp fetch_nonempty_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: {:error, {:invalid_manifest_field, key}}, else: {:ok, trimmed}

      _ ->
        {:error, {:invalid_manifest_field, key}}
    end
  end

  @spec fetch_source_roots(term()) :: term()
  defp fetch_source_roots(map) do
    case Map.get(map, "source_roots", @default_source_roots) do
      roots when is_list(roots) ->
        cleaned =
          roots
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        if cleaned == [],
          do: {:error, {:invalid_manifest_field, "source_roots"}},
          else: {:ok, cleaned}

      _ ->
        {:error, {:invalid_manifest_field, "source_roots"}}
    end
  end

  @spec fetch_import_path(term()) :: term()
  defp fetch_import_path(map) do
    map
    |> Map.get("import_path", @default_import_path)
    |> case do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: {:ok, @default_import_path}, else: {:ok, trimmed}

      _ ->
        {:error, {:invalid_manifest_field, "import_path"}}
    end
  end

  @spec fetch_optional_string(term(), term()) :: term()
  defp fetch_optional_string(map, key) do
    case Map.get(map, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        trimmed = String.trim(value)
        {:ok, if(trimmed == "", do: nil, else: trimmed)}

      _ ->
        {:error, {:invalid_manifest_field, key}}
    end
  end

  @spec fetch_optional_map(term(), term()) :: term()
  defp fetch_optional_map(map, key) do
    case Map.get(map, key) do
      nil -> {:ok, %{}}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_manifest_field, key}}
    end
  end

  @spec put_if_blank(term(), term(), term()) :: term()
  defp put_if_blank(attrs, key, value) do
    case Map.get(attrs, key) do
      nil ->
        Map.put(attrs, key, value)

      current when is_binary(current) ->
        if String.trim(current) == "", do: Map.put(attrs, key, value), else: attrs

      _ ->
        attrs
    end
  end
end
