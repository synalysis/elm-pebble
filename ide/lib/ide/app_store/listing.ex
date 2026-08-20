defmodule Ide.AppStore.Listing do
  @moduledoc """
  Pushes App Store listing metadata for an existing app via the developer portal API.

  Updates `description`, `website`, and `source` on the store. Tags, capabilities, and
  target platforms are written to the workspace `package.json` when present (used on the
  next PBW build); the store listing API does not accept those fields on the app record.
  """

  alias Ide.Auth
  alias Ide.ProjectBundle
  alias Ide.Projects.Types, as: ProjectsTypes
  alias Ide.StoreAssets
  alias Ide.StoreListingUrls
  alias IdeWeb.WorkspaceLive.State

  @type listing_project :: ProjectsTypes.release_defaults_carrier()

  @type icon_paths :: %{optional(StoreAssets.icon_key()) => String.t()}

  @type result :: %{
          status: :ok | :error,
          output: String.t(),
          project_attrs: ProjectsTypes.project_attrs()
        }

  @icon_sizes [{:icon_small, "small"}, {:icon_large, "large"}]

  @spec update_metadata(listing_project(), keyword()) :: {:ok, result()}
  def update_metadata(project, opts \\ []) when is_map(project) do
    api_base = Keyword.get(opts, :api_base, Auth.appstore_api_base()) |> String.trim_trailing("/")
    token = Keyword.get(opts, :firebase_id_token, "") |> to_string() |> String.trim()
    workspace_root = Keyword.get(opts, :workspace_root)

    with :ok <- require_token(token),
         {:ok, app_id, resolve_lines} <- resolve_app_id(project, api_base, token, opts),
         body <- listing_body(project),
         {:ok, _payload} <- post_listing_update(api_base, token, app_id, body, opts),
         {:ok, icon_lines, icon_hashes} <-
           upload_workspace_icons(api_base, token, app_id, workspace_root, opts),
         {:ok, package_lines} <- sync_workspace_package(project, workspace_root) do
      project_attrs = listing_project_attrs(project, app_id, workspace_root, icon_hashes)

      {:ok,
       %{
         status: :ok,
         output:
           Enum.join(
             [
               "App Store listing updated (app #{app_id}).",
               "Sent: title, description, website, source."
             ] ++
               resolve_lines ++ icon_lines ++ package_lines,
             "\n"
           ),
         project_attrs: project_attrs
       }}
    else
      {:error, reason} ->
        {:ok,
         %{
           status: :error,
           output: error_message(reason),
           project_attrs: %{}
         }}
    end
  end

  @doc """
  Uploads locker/list icons through the developer-portal replace endpoints.

  Release multipart `iconSmall`/`iconLarge` only fills `list_image`. The phone
  locker reads `icon_image` (48×48 / 28×28), which is set by
  `POST /api/dp/app/:id/icon/small` and `/icon/large` with form field `icon`.
  """
  @spec upload_icons(String.t(), String.t(), String.t(), icon_paths(), keyword()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def upload_icons(api_base, token, app_id, icons, opts \\ [])
      when is_binary(api_base) and is_binary(token) and is_binary(app_id) and is_map(icons) do
    files =
      Enum.flat_map(@icon_sizes, fn {key, size} ->
        case icon_path(icons, key) do
          path when is_binary(path) and path != "" -> [{size, path}]
          _ -> []
        end
      end)

    case files do
      [] ->
        {:ok, []}

      files ->
        Enum.reduce_while(files, {:ok, []}, fn {size, path}, {:ok, lines} ->
          case post_icon_replace(api_base, token, app_id, size, path, opts) do
            {:ok, _} ->
              {:cont, {:ok, lines ++ ["Uploaded locker icon (#{size}) from #{Path.basename(path)}."]}}

            {:error, {:icon_replace_unavailable, _size}} ->
              {:halt, {:ok, lines ++ [icon_replace_unavailable_line()]}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp listing_body(project) do
    defaults = Map.get(project, :release_defaults, %{}) || %{}
    description = defaults |> Map.get("description", "") |> to_string() |> String.trim()

    %{
      "title" => project |> Map.get(:name, "") |> to_string() |> String.trim(),
      "description" => description,
      "website" => StoreListingUrls.website_url(project),
      "source" => StoreListingUrls.source_url(project)
    }
    |> Enum.reject(fn {_key, value} -> value == "" end)
    |> Map.new()
  end

  defp resolve_app_id(project, api_base, token, opts) do
    stored =
      project
      |> Map.get(:store_app_id)
      |> to_string()
      |> String.trim()

    cond do
      stored != "" ->
        {:ok, stored, []}

      true ->
        with {:ok, me} <- get_me(api_base, token, opts),
             uuid <- app_uuid(project, Keyword.get(opts, :workspace_root)),
             :ok <- require_app_uuid(uuid),
             {:ok, app_id} <- lookup_app_id_result(me, uuid) do
          {:ok, app_id, ["Resolved app id #{app_id} from developer account (UUID #{uuid})."]}
        end
    end
  end

  @spec listing_project_attrs(listing_project(), String.t(), String.t() | nil, map()) ::
          ProjectsTypes.project_attrs()
  defp listing_project_attrs(project, app_id, workspace_root, icon_hashes) do
    attrs =
      if blank?(Map.get(project, :store_app_id)) do
        %{"store_app_id" => app_id}
      else
        %{}
      end

    uuid = app_uuid(project, workspace_root)

    attrs =
      if blank?(Map.get(project, :app_uuid)) and is_binary(uuid) and uuid != "" do
        Map.put(attrs, "app_uuid", uuid)
      else
        attrs
      end

    merge_listing_icon_cache(attrs, project, icon_hashes)
  end

  defp merge_listing_icon_cache(attrs, _project, hashes) when hashes == %{}, do: attrs

  defp merge_listing_icon_cache(attrs, project, hashes) when is_map(hashes) do
    cache =
      project
      |> Map.get(:store_metadata_cache, %{})
      |> case do
        cache when is_map(cache) -> cache
        _ -> %{}
      end

    Map.put(
      attrs,
      "store_metadata_cache",
      cache
      |> Map.put("icon_hashes", hashes)
      |> Map.put("listing_icons_synced", true)
    )
  end

  defp app_uuid(project, workspace_root) when is_binary(workspace_root) do
    db =
      project
      |> Map.get(:app_uuid)
      |> to_string()
      |> String.trim()

    slug = project |> Map.get(:slug) |> to_string() |> String.trim()

    if db != "" do
      String.downcase(db)
    else
      ProjectBundle.resolve_app_uuid(workspace_root, slug)
    end
  end

  defp app_uuid(project, _workspace_root) do
    project
    |> Map.get(:app_uuid)
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      uuid -> String.downcase(uuid)
    end
  end

  defp lookup_app_id_result(me, uuid) do
    lookup = get_in(me, ["app_lookup", "by_app_uuid"]) || %{}
    uuid = uuid |> String.downcase()

    case Enum.find_value(lookup, fn {key, value} ->
           if String.downcase(to_string(key)) == uuid, do: to_string(value)
         end) do
      id when is_binary(id) and id != "" ->
        {:ok, id}

      _ ->
        {:error,
         "No App Store listing found for this app's UUID. Publish the app first to create a listing."}
    end
  end

  defp require_app_uuid(""), do: {:error, :app_uuid_required}
  defp require_app_uuid(_), do: :ok

  defp get_me(api_base, token, opts) do
    case request_json(:get, "#{api_base}/api/v1/developer/me", token, nil, opts) do
      {:ok, payload} ->
        if linked_developer?(payload), do: {:ok, payload}, else: {:error, :developer_not_linked}

      {:error, {403, %{"code" => "DEVELOPER_NOT_LINKED"}}} ->
        {:error, :developer_not_linked}

      {:error, {status, payload}} ->
        {:error, "Failed to call /api/v1/developer/me (#{status}): #{payload_error(payload)}"}

      error ->
        error
    end
  end

  defp post_listing_update(api_base, token, app_id, body, opts) do
    url = "#{api_base}/api/dp/app/#{URI.encode(app_id)}"

    case request_json(:post, url, token, body, opts) do
      {:ok, payload} ->
        {:ok, payload}

      {:error, {status, payload}} ->
        {:error, "App Store listing update failed (#{status}): #{payload_error(payload)}"}

      {:error, reason} ->
        {:error, "App Store listing update failed: #{inspect(reason)}"}
    end
  end

  defp upload_workspace_icons(_api_base, _token, _app_id, workspace_root, _opts)
       when not is_binary(workspace_root),
       do: {:ok, [], %{}}

  defp upload_workspace_icons(api_base, token, app_id, workspace_root, opts) do
    icons = StoreAssets.publish_icon_paths(workspace_root)

    case upload_icons(api_base, token, app_id, icons, opts) do
      {:ok, []} ->
        {:ok, [], %{}}

      {:ok, lines} ->
        {:ok, lines, StoreAssets.content_hashes(icons)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_icon_replace(api_base, token, app_id, size, path, opts) do
    url = "#{api_base}/api/dp/app/#{URI.encode(app_id)}/icon/#{size}"

    with {:ok, body} <- icon_multipart_body(path) do
      headers = [
        {"authorization", "Bearer #{token}"},
        {"accept", "application/json"},
        {"content-type", "multipart/form-data; boundary=elm-pebble-icon"}
      ]

      request_fun(opts).(
        :post,
        url,
        headers,
        IO.iodata_to_binary(body),
        60_000
      )
      |> normalize_response()
      |> case do
        {:ok, payload} ->
          {:ok, payload}

        {:error, {404, _payload}} ->
          {:error, {:icon_replace_unavailable, size}}

        {:error, {status, payload}} ->
          {:error, "Locker icon upload (#{size}) failed (#{status}): #{payload_error(payload)}"}

        {:error, reason} ->
          {:error, "Locker icon upload (#{size}) failed: #{inspect(reason)}"}
      end
    end
  end

  defp icon_multipart_body(path) when is_binary(path) do
    if File.regular?(path) do
      boundary = "elm-pebble-icon"

      {:ok,
       [
         "--",
         boundary,
         "\r\ncontent-disposition: form-data; name=\"icon\"; filename=\"",
         Path.basename(path),
         "\"\r\ncontent-type: image/png\r\n\r\n",
         File.read!(path),
         "\r\n--",
         boundary,
         "--\r\n"
       ]}
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp icon_path(icons, key) do
    Map.get(icons, key) || Map.get(icons, Atom.to_string(key))
  end

  defp sync_workspace_package(project, workspace_root) when is_binary(workspace_root) do
    path = Path.join(workspace_root, ".pebble-sdk/app/package.json")

    if File.regular?(path) do
      defaults = Map.get(project, :release_defaults, %{}) || %{}

      case File.read(path) do
        {:ok, source} ->
          case Jason.decode(source) do
            {:ok, package} ->
              updated =
                package
                |> put_package_description(defaults)
                |> put_package_keywords(defaults)
                |> put_package_capabilities(defaults)
                |> put_package_target_platforms(defaults)

              :ok = File.write!(path, Jason.encode!(updated, pretty: true))

              {:ok,
               [
                 "Updated .pebble-sdk/app/package.json (description, keywords/tags, capabilities, target platforms)."
               ]}

            _ ->
              {:error, :package_json_invalid}
          end

        _ ->
          {:error, :package_json_invalid}
      end
    else
      {:ok, ["No .pebble-sdk/app/package.json yet — run Prepare Release to generate it."]}
    end
  end

  defp sync_workspace_package(_project, _workspace_root) do
    {:ok, ["Workspace path missing; skipped package.json sync."]}
  end

  defp put_package_description(package, defaults) do
    description = defaults |> Map.get("description", "") |> to_string() |> String.trim()

    case description do
      "" -> package
      trimmed -> Map.put(package, "description", trimmed)
    end
  end

  defp put_package_keywords(package, defaults) do
    tags =
      defaults
      |> Map.get("tags", "")
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    keywords =
      ["pebble-app" | tags]
      |> Enum.uniq()

    Map.put(package, "keywords", keywords)
  end

  defp put_package_capabilities(package, defaults) do
    capabilities =
      defaults
      |> Map.get("capabilities", [])
      |> normalize_capabilities()

    if capabilities == [] do
      package
    else
      put_in(package, ["pebble", "capabilities"], capabilities)
    end
  end

  defp put_package_target_platforms(package, defaults) do
    platforms = State.target_platforms_form_value(Map.get(defaults, "target_platforms"))

    put_in(package, ["pebble", "targetPlatforms"], platforms)
  end

  defp normalize_capabilities(value) when is_list(value) do
    allowed = MapSet.new(["location", "configurable", "health"])

    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&MapSet.member?(allowed, &1))
    |> Enum.uniq()
  end

  defp normalize_capabilities(_), do: []

  defp linked_developer?(me) do
    developer = me["developer"] || %{}
    is_map(developer) and Enum.any?(["id", "_id", "firebase_uid"], &present?(developer[&1]))
  end

  defp present?(value), do: not is_nil(value) and to_string(value) != ""

  defp require_token(""), do: {:error, :firebase_token_required}
  defp require_token(_), do: :ok

  defp request_json(method, url, token, body, opts) do
    request_fun = request_fun(opts)
    headers = [{"authorization", "Bearer #{token}"}, {"accept", "application/json"}]
    headers = if is_nil(body), do: headers, else: [{"content-type", "application/json"} | headers]
    encoded = if is_nil(body), do: nil, else: Jason.encode!(body)

    request_fun.(method, url, headers, encoded, 60_000)
    |> normalize_response()
  end

  defp normalize_response({:ok, %{status: status, body: body}}) when status < 400 do
    {:ok, decode_body(body)}
  end

  defp normalize_response({:ok, %{status: status, body: body}}) do
    {:error, {status, decode_body(body)}}
  end

  defp normalize_response({:error, reason}), do: {:error, reason}

  defp decode_body(body) when is_map(body), do: body

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> %{"error" => body}
    end
  end

  defp decode_body(_), do: %{}

  defp request_fun(opts) do
    Keyword.get(opts, :request_fun, fn method, url, headers, body, timeout ->
      Req.request(
        method: method,
        url: url,
        headers: headers,
        body: body,
        receive_timeout: timeout
      )
    end)
  end

  defp icon_replace_unavailable_line do
    "Locker icon listing API is not available on this App Store (POST /api/dp/app/:id/icon/…). Icons are sent with the release as iconSmall/iconLarge."
  end

  defp payload_error(%{"error" => error}), do: error
  defp payload_error(%{"message" => message}), do: message

  defp payload_error(payload) when is_binary(payload) do
    trimmed = String.trim(payload)

    if String.starts_with?(trimmed, "<!DOCTYPE") or String.contains?(trimmed, "<html") do
      "App Store returned HTML (route not found)"
    else
      String.slice(trimmed, 0, 300)
    end
  end

  defp payload_error(payload), do: inspect(payload)

  defp error_message(:firebase_token_required),
    do: "App Store login required. Log in from the Publish page, then try again."

  defp error_message(:developer_not_linked),
    do: "Developer account is not linked on the App Store. Log in from the Publish page first."

  defp error_message(:package_json_invalid),
    do: "Could not update .pebble-sdk/app/package.json (invalid or unreadable file)."

  defp error_message(:app_uuid_required),
    do:
      "App Store app id unknown. Run Prepare Release on the Publish tab (or publish once) so the app UUID is available, then try again."

  defp error_message({:file_not_found, path}),
    do: "Locker icon file not found: #{path}"

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)

  defp blank?(value), do: is_nil(value) or to_string(value) == ""
end
