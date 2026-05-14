defmodule Ide.Emulator.PBW do
  @moduledoc false

  @platform_fallbacks %{
    "unknown" => [""],
    "aplite" => ["aplite", ""],
    "basalt" => ["basalt", "aplite", ""],
    "chalk" => ["chalk"],
    "diorite" => ["diorite", "aplite", ""],
    "emery" => ["emery", "basalt", "diorite", "aplite", ""],
    "flint" => ["flint", "diorite", "aplite", ""],
    "gabbro" => ["gabbro", "chalk"]
  }

  @type part :: %{
          kind: atom(),
          object_type: atom(),
          name: String.t(),
          size: non_neg_integer(),
          data: binary()
        }
  @type app_metadata :: %{
          uuid: String.t(),
          flags: non_neg_integer(),
          icon_resource_id: non_neg_integer(),
          app_version_major: non_neg_integer(),
          app_version_minor: non_neg_integer(),
          sdk_version_major: non_neg_integer(),
          sdk_version_minor: non_neg_integer(),
          app_name: String.t()
        }

  @type t :: %{
          path: String.t(),
          platform: String.t(),
          variant: String.t(),
          uuid: String.t(),
          appinfo: map(),
          manifest: map(),
          app_metadata: app_metadata(),
          parts: [part()]
        }

  @spec load(String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def load(path, platform) when is_binary(path) and is_binary(platform) do
    with {:ok, entries} <- read_entries(path),
         {:ok, appinfo} <- read_json(entries, "appinfo.json"),
         {:ok, variant, manifest} <- select_manifest(entries, platform, appinfo),
         {:ok, parts} <- read_parts(entries, variant, manifest),
         {:ok, app_metadata} <- app_metadata(appinfo, parts),
         {:ok, uuid} <- validate_uuid(appinfo, app_metadata) do
      {:ok,
       %{
         path: path,
         platform: platform,
         variant: variant,
         uuid: uuid,
         appinfo: appinfo,
         manifest: manifest,
         app_metadata: app_metadata,
         parts: parts
       }}
    end
  end

  @spec prune_empty_media_resources(String.t()) :: {:ok, String.t()} | {:error, term()}
  def prune_empty_media_resources(path) when is_binary(path), do: {:ok, path}

  @spec prune_development_artifacts(String.t()) :: {:ok, String.t()} | {:error, term()}
  def prune_development_artifacts(path) when is_binary(path) do
    with {:ok, entries} <- read_entry_list(path),
         pruned <- prune_entry_list(entries) do
      if pruned == entries do
        {:ok, path}
      else
        rewrite_entries(path, pruned)
      end
    end
  end

  @spec platform_variants(String.t()) :: [String.t()]
  def platform_variants(platform), do: Map.get(@platform_fallbacks, platform, [platform])

  defp read_entries(path) do
    case read_entry_list(path) do
      {:ok, entries} ->
        {:ok,
         Map.new(entries, fn {name, data} ->
           {List.to_string(name), data}
         end)}

      {:error, reason} ->
        {:error, {:pbw_zip_error, reason}}
    end
  end

  defp read_entry_list(path), do: :zip.extract(String.to_charlist(path), [:memory])

  defp prune_entry_list(entries) do
    Enum.flat_map(entries, fn {name, data} ->
      path = List.to_string(name)

      cond do
        String.ends_with?(path, ".js.map") ->
          []

        String.ends_with?(path, ".js") ->
          [{name, strip_source_map_reference(data)}]

        true ->
          [{name, data}]
      end
    end)
  end

  defp strip_source_map_reference(data) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(&1, "//# sourceMappingURL="))
    |> Enum.join("\n")
  end

  defp rewrite_entries(path, entries) do
    temp_path = "#{path}.#{System.unique_integer([:positive])}.tmp"

    case :zip.create(String.to_charlist(temp_path), entries) do
      {:ok, _zip_path} ->
        case File.rename(temp_path, path) do
          :ok ->
            {:ok, path}

          {:error, reason} ->
            File.rm(temp_path)
            {:error, {:pbw_rewrite_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:pbw_zip_rewrite_failed, reason}}
    end
  end

  defp select_manifest(entries, platform, appinfo) do
    target_platforms = Map.get(appinfo, "targetPlatforms", [])

    platform
    |> platform_variants()
    |> Enum.filter(fn variant ->
      variant == "" or target_platforms == [] or variant in target_platforms
    end)
    |> Enum.find_value(fn variant ->
      path = entry_path(variant, "manifest.json")

      case read_json(entries, path) do
        {:ok, manifest} -> {:ok, variant, manifest}
        {:error, _reason} -> nil
      end
    end)
    |> case do
      nil -> {:error, {:manifest_not_found, platform}}
      result -> result
    end
  end

  defp read_parts(entries, variant, manifest) do
    definitions =
      [
        {:binary, :binary, get_in(manifest, ["application"])},
        {:resources, :resources, get_in(manifest, ["resources"])},
        {:worker, :worker, get_in(manifest, ["worker"])}
      ]
      |> Enum.reject(fn {_kind, _object_type, blob} -> is_nil(blob) end)

    parts =
      Enum.reduce_while(definitions, {:ok, []}, fn {kind, object_type, blob}, {:ok, acc} ->
        name = Map.fetch!(blob, "name")
        size = Map.fetch!(blob, "size")
        path = entry_path(variant, name)

        case Map.fetch(entries, path) do
          {:ok, data} ->
            part = %{kind: kind, object_type: object_type, name: name, size: size, data: data}
            {:cont, {:ok, [part | acc]}}

          :error ->
            {:halt, {:error, {:blob_not_found, kind, path}}}
        end
      end)

    case parts do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
  end

  defp read_json(entries, path) do
    with {:ok, data} <- Map.fetch(entries, path),
         {:ok, decoded} <- Jason.decode(data) do
      {:ok, decoded}
    else
      :error -> {:error, {:entry_not_found, path}}
      {:error, reason} -> {:error, {:json_decode_failed, path, reason}}
    end
  end

  defp validate_uuid(appinfo, %{uuid: metadata_uuid}) do
    with {:ok, appinfo_uuid} <- Map.fetch(appinfo, "uuid") do
      if appinfo_uuid == metadata_uuid do
        {:ok, appinfo_uuid}
      else
        {:error, {:pbw_uuid_mismatch, appinfo_uuid, metadata_uuid}}
      end
    end
  end

  # PebbleBundle reads the watchapp metadata from the application binary header
  # and stores the same subset in BlobDB before triggering AppFetch.
  defp app_metadata(_appinfo, [%{kind: :binary, data: binary} | _parts])
       when byte_size(binary) >= 126 do
    <<_sentinel::binary-size(8), _struct_version_major, _struct_version_minor, sdk_version_major,
      sdk_version_minor, app_version_major, app_version_minor, _app_size::little-16,
      _offset::little-32, _crc::little-32, app_name::binary-size(32),
      _company_name::binary-size(32), icon_resource_id::little-32, _symbol_table_addr::little-32,
      flags::little-32, _num_relocation_entries::little-32, uuid::binary-size(16), _rest::binary>> =
      binary

    {:ok,
     %{
       uuid: format_uuid(uuid),
       flags: flags,
       icon_resource_id: icon_resource_id,
       app_version_major: app_version_major,
       app_version_minor: app_version_minor,
       sdk_version_major: sdk_version_major,
       sdk_version_minor: sdk_version_minor,
       app_name: trim_c_string(app_name)
     }}
  end

  defp app_metadata(appinfo, _parts) do
    {app_version_major, app_version_minor} = version_pair(Map.get(appinfo, "versionLabel", "1.0"))
    {sdk_version_major, sdk_version_minor} = version_pair(Map.get(appinfo, "sdkVersion", "3.0"))

    {:ok,
     %{
       uuid: Map.fetch!(appinfo, "uuid"),
       flags: fallback_flags(appinfo),
       icon_resource_id: 0,
       app_version_major: app_version_major,
       app_version_minor: app_version_minor,
       sdk_version_major: sdk_version_major,
       sdk_version_minor: sdk_version_minor,
       app_name:
         Map.get(appinfo, "shortName") || Map.get(appinfo, "displayName") ||
           Map.get(appinfo, "name") ||
           "Pebble App"
     }}
  end

  defp fallback_flags(appinfo) do
    if get_in(appinfo, ["watchapp", "watchface"]) == true, do: 1, else: 0
  end

  defp version_pair(version) when is_binary(version) do
    case version |> String.split(".") |> Enum.map(&Integer.parse/1) do
      [{major, _}, {minor, _} | _] -> {major, minor}
      [{major, _} | _] -> {major, 0}
      _ -> {0, 0}
    end
  end

  defp version_pair(_version), do: {0, 0}

  defp trim_c_string(data) do
    data
    |> :binary.split(<<0>>)
    |> List.first()
  end

  defp format_uuid(
         <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
           e::binary-size(6)>>
       ) do
    [a, b, c, d, e]
    |> Enum.map(&Base.encode16(&1, case: :lower))
    |> Enum.join("-")
  end

  defp entry_path("", file), do: file
  defp entry_path(".", file), do: file
  defp entry_path(variant, file), do: Path.join(variant, file)
end
