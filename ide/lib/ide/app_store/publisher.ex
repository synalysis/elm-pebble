defmodule Ide.AppStore.Publisher do
  @moduledoc """
  Native App Store publisher using the same dashboard API as `pebble publish`.
  """

  alias Ide.Auth
  alias Ide.StoreAssets
  alias Ide.StoreListingUrls

  @type command_result :: %{
          status: :ok | :error,
          command: String.t(),
          output: String.t(),
          exit_code: integer(),
          cwd: String.t()
        }

  @spec publish(map(), keyword()) :: {:ok, command_result()} | {:error, term()}
  def publish(project, opts) when is_map(project) do
    app_root = Keyword.get(opts, :app_root, "")
    api_base = Keyword.get(opts, :api_base, Auth.appstore_api_base()) |> String.trim_trailing("/")
    token = Keyword.get(opts, :firebase_id_token, "") |> to_string() |> String.trim()
    artifact_path = Keyword.get(opts, :artifact_path) || default_pbw_path(app_root)
    release_notes = Keyword.get(opts, :release_notes, "") |> to_string()
    screenshots = normalize_paths(Keyword.get(opts, :screenshots, []))
    version_override = Keyword.get(opts, :version, "") |> to_string() |> String.trim()
    description = Keyword.get(opts, :description, "") |> to_string() |> String.trim()
    is_published = Keyword.get(opts, :is_published, true) == true

    run =
      case prepare_upload_artifact(artifact_path) do
        {:ok, upload_artifact_path, temp_artifact_path} ->
          result =
            with :ok <- require_token(token),
                 :ok <- require_file(upload_artifact_path, "PBW"),
                 {:ok, metadata} <- pbw_metadata(upload_artifact_path, app_root),
                 version <- choose_version(version_override, metadata, app_root),
                 {:ok, output} <-
                   publish_with_context(project, %{
                     api_base: api_base,
                     token: token,
                     artifact_path: upload_artifact_path,
                     release_notes: release_notes,
                     screenshots: screenshots,
                     version: version,
                     description: description,
                     is_published: is_published,
                     metadata: metadata,
                     opts: opts
                   }) do
              {:ok, output}
            else
              {:error, reason} -> {:error, reason}
              other -> {:error, other}
            end

          maybe_remove_temp_artifact(temp_artifact_path)
          result

        {:error, reason} ->
          {:error, reason}
      end

    case run do
      {:ok, output} ->
        {:ok, command_result(:ok, app_root, Enum.join(output, "\n"))}

      {:error, reason} ->
        {:ok, command_result(:error, app_root, error_output(reason))}
    end
  rescue
    error -> {:error, error}
  end

  def publish(_project, _opts), do: {:error, :invalid_project}

  defp publish_with_context(project, ctx) do
    output = [
      "Appstore auth preflight...",
      "API base: #{ctx.api_base}"
    ]

    with {:ok, me} <- ensure_developer(ctx),
         metadata = ctx.metadata,
         app_id <- lookup_app_id(me, metadata.app_uuid),
         {:ok, response, action_output} <- publish_app(project, ctx, metadata, me, app_id) do
      uploaded_output = upload_summary(response)

      {:ok,
       output ++
         [
           "Developer link check successful.",
           "PBW Metadata",
           "Using PBW: #{ctx.artifact_path}",
           "PBW app UUID: #{metadata.app_uuid}",
           "Name: #{metadata.app_name}",
           "PBW Version: #{metadata.version}",
           "Publish Version: #{ctx.version}",
           publish_version_warning(metadata.version, ctx.version),
           visibility_line(ctx.is_published),
           release_notes_line(ctx.release_notes),
           store_icons_line(ctx),
           "Platforms: #{Enum.join(metadata.platforms, ", ")}"
         ]
         |> Enum.reject(&is_nil/1)
         |> Kernel.++(action_output ++ uploaded_output)}
    end
  end

  defp publish_app(_project, ctx, _metadata, _me, app_id)
       when is_binary(app_id) and app_id != "" do
    with {:ok, payload} <- upload_release(ctx, app_id) do
      {:ok, payload,
       [
         "Resolved existing appstore app ID: #{app_id}",
         "Publishing release to Pebble Appstore..."
       ]}
    end
  end

  defp publish_app(project, ctx, metadata, me, _app_id) do
    with :ok <- require_description(ctx.description),
         {:ok, payload} <- create_app(project, ctx, metadata, me) do
      {:ok, payload,
       [
         "No existing app mapping for UUID #{metadata.app_uuid}. Creating a new app...",
         "Publishing new app to Pebble Appstore..."
       ]}
    end
  end

  defp ensure_developer(ctx) do
    case get_me(ctx) do
      {:ok, me} ->
        if linked_developer?(me), do: {:ok, me}, else: create_and_fetch_developer(ctx)

      {:error, :developer_not_linked} ->
        create_and_fetch_developer(ctx)

      error ->
        error
    end
  end

  defp create_and_fetch_developer(ctx) do
    with {:ok, _payload} <-
           request_json(
             :post,
             "#{ctx.api_base}/api/v1/developer/create",
             ctx.token,
             %{},
             ctx.opts
           ),
         {:ok, me} <- get_me(ctx),
         true <- linked_developer?(me) do
      {:ok, me}
    else
      false -> {:error, "Developer account is not linked on #{ctx.api_base}."}
      error -> error
    end
  end

  defp get_me(ctx) do
    case request_json(:get, "#{ctx.api_base}/api/v1/developer/me", ctx.token, nil, ctx.opts) do
      {:ok, payload} ->
        {:ok, payload}

      {:error, {403, %{"code" => "DEVELOPER_NOT_LINKED"}}} ->
        {:error, :developer_not_linked}

      {:error, {status, payload}} ->
        {:error, "Failed to call /api/v1/developer/me (#{status}): #{payload_error(payload)}"}

      error ->
        error
    end
  end

  defp upload_release(ctx, app_id) do
    fields = %{
      "version" => ctx.version,
      "releaseNotes" => ctx.release_notes,
      "isPublished" => bool_string(ctx.is_published),
      "replaceScreenshots" => replace_screenshots_string(ctx.screenshots)
    }

    files = [{"pbwFile", ctx.artifact_path}] ++ screenshot_files(ctx.screenshots)

    multipart_request(
      :post,
      "#{ctx.api_base}/api/dashboard/apps/#{URI.encode(app_id)}/releases",
      ctx.token,
      fields,
      files,
      ctx.opts
    )
    |> handle_upload_response("Release upload failed")
  end

  defp create_app(project, ctx, metadata, me) do
    fields =
      %{
        "name" => metadata.app_name || Map.get(project, :name, "Untitled App"),
        "type" => metadata.app_type,
        "version" => ctx.version,
        "expectedUuid" => metadata.app_uuid,
        "description" => ctx.description,
        "website" => website_url(ctx.opts),
        "source" => source_url(ctx.opts),
        "releaseNotes" => ctx.release_notes,
        "visible" => "true",
        "isPublished" => bool_string(ctx.is_published)
      }
      |> maybe_put_category(default_category(me, metadata.app_type))

    files =
      [{"pbwFile", ctx.artifact_path}]
      |> Kernel.++(icon_files(ctx))
      |> Kernel.++(screenshot_files(ctx.screenshots))

    fields = maybe_put_icon_prompt(fields, ctx)

    multipart_request(
      :post,
      "#{ctx.api_base}/api/dashboard/apps",
      ctx.token,
      fields,
      files,
      ctx.opts
    )
    |> handle_upload_response("App create failed")
  end

  defp handle_upload_response({:ok, payload}, _label), do: {:ok, payload}

  defp handle_upload_response({:error, {status, payload}}, label) do
    {:error, "#{label} (#{status}): #{payload_error(payload)}"}
  end

  defp handle_upload_response({:error, reason}, label),
    do: {:error, "#{label}: #{inspect(reason)}"}

  defp request_json(method, url, token, body, opts) do
    request_fun = request_fun(opts)
    headers = [{"authorization", "Bearer #{token}"}, {"accept", "application/json"}]
    headers = if is_nil(body), do: headers, else: [{"content-type", "application/json"} | headers]
    encoded = if is_nil(body), do: nil, else: Jason.encode!(body)

    request_fun.(method, url, headers, encoded, 60_000)
    |> normalize_response()
  end

  defp multipart_request(method, url, token, fields, files, opts) do
    boundary = "elm-pebble-#{System.unique_integer([:positive])}"

    with {:ok, body} <- multipart_body(boundary, fields, files) do
      headers = [
        {"authorization", "Bearer #{token}"},
        {"accept", "application/json"},
        {"content-type", "multipart/form-data; boundary=#{boundary}"}
      ]

      request_fun(opts).(method, url, headers, body, 300_000)
      |> normalize_response()
    end
  end

  @doc false
  @spec multipart_body(String.t(), map(), [{String.t(), String.t()}]) ::
          {:ok, iodata()} | {:error, term()}
  def multipart_body(boundary, fields, files) do
    field_parts =
      Enum.map(fields, fn {name, value} ->
        [
          "--",
          boundary,
          "\r\ncontent-disposition: form-data; name=\"",
          name,
          "\"\r\n\r\n",
          to_string(value || ""),
          "\r\n"
        ]
      end)

    with {:ok, file_parts} <- multipart_file_parts(boundary, files) do
      {:ok, [field_parts, file_parts, "--", boundary, "--\r\n"]}
    end
  end

  defp multipart_file_parts(boundary, files) do
    Enum.reduce_while(files, {:ok, []}, fn {field, path}, {:ok, parts} ->
      if File.regular?(path) do
        part = [
          "--",
          boundary,
          "\r\ncontent-disposition: form-data; name=\"",
          field,
          "\"; filename=\"",
          Path.basename(path),
          "\"\r\ncontent-type: ",
          mime_type(path),
          "\r\n\r\n",
          File.read!(path),
          "\r\n"
        ]

        {:cont, {:ok, [part | parts]}}
      else
        {:halt, {:error, {:file_not_found, path}}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
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

  defp pbw_metadata(pbw_path, app_root) do
    package_metadata = package_metadata(app_root)

    case read_zip_metadata(pbw_path) do
      {:ok, zip_metadata} -> {:ok, Map.merge(package_metadata, zip_metadata)}
      :error -> {:ok, package_metadata}
    end
  end

  defp package_metadata(app_root) do
    with {:ok, source} <- File.read(Path.join(app_root, "package.json")),
         {:ok, package} <- Jason.decode(source) do
      pebble = package["pebble"] || %{}
      watchapp = pebble["watchapp"] || %{}

      %{
        app_uuid: to_string(pebble["uuid"] || ""),
        app_name: pebble["displayName"] || package["name"] || "Untitled App",
        version: to_string(package["version"] || "1.0.0"),
        platforms: pebble["targetPlatforms"] || [],
        app_type: if(watchapp["watchface"] == true, do: "watchface", else: "watchapp")
      }
    else
      _ ->
        %{
          app_uuid: "",
          app_name: "Untitled App",
          version: "1.0.0",
          platforms: [],
          app_type: "watchapp"
        }
    end
  end

  defp read_zip_metadata(pbw_path) do
    with {:ok, files} <- :zip.extract(String.to_charlist(pbw_path), [:memory]),
         {_name, data} <-
           Enum.find(files, fn {name, _} ->
             to_string(name) in ["appinfo.json", "manifest.json"]
           end),
         {:ok, metadata} <- Jason.decode(data) do
      watchapp = metadata["watchapp"] || %{}

      {:ok,
       %{
         app_uuid: to_string(metadata["uuid"] || ""),
         app_name:
           metadata["longName"] || metadata["shortName"] || metadata["displayName"] ||
             "Untitled App",
         version: to_string(metadata["versionLabel"] || metadata["version"] || "1.0.0"),
         platforms: metadata["targetPlatforms"] || [],
         app_type: if(watchapp["watchface"] == true, do: "watchface", else: "watchapp")
       }}
    else
      _ -> :error
    end
  end

  defp screenshot_files(paths) do
    Enum.map(paths, fn path -> {"screenshots_#{platform_from_capture_path(path)}", path} end)
  end

  defp icon_files(ctx) do
    icons = Keyword.get(ctx.opts, :store_icons, %{})

    [
      {:icon_small, Map.get(icons, :icon_small)},
      {:icon_large, Map.get(icons, :icon_large)}
    ]
    |> Enum.flat_map(fn
      {field, path} when is_binary(path) and path != "" ->
        [{icon_field_name(field), path}]

      _ ->
        []
    end)
  end

  defp icon_field_name(key), do: StoreAssets.api_field_name(key)

  defp maybe_put_icon_prompt(fields, ctx) do
    icons = Keyword.get(ctx.opts, :store_icons, %{})
    metadata = ctx.metadata
    generate? = Keyword.get(ctx.opts, :generate_store_graphics, false) == true

    if metadata.app_type == "watchapp" and map_size(icons) == 0 and generate? do
      prompt =
        "#{metadata.app_name || "Pebble app"}: #{String.trim(ctx.description || "")}"
        |> String.trim()

      Map.put(fields, "iconPrompt", prompt)
    else
      fields
    end
  end

  defp store_icons_line(ctx) do
    icons = Keyword.get(ctx.opts, :store_icons, %{})

    cond do
      map_size(icons) == 2 ->
        "Store icons: uploaded #{StoreAssets.required_sizes_summary()}"

      map_size(icons) == 1 ->
        parts =
          Enum.map_join(icons, ", ", fn {key, _} ->
            "#{StoreAssets.api_field_name(key)} (#{StoreAssets.size_label(key)})"
          end)

        "Store icons: uploaded #{parts}"

      ctx.metadata.app_type == "watchapp" and Keyword.get(ctx.opts, :generate_store_graphics, false) ->
        "Store icons: will request Rebble AI icon generation (iconPrompt) on create"

      ctx.metadata.app_type == "watchapp" ->
        "Store icons: none uploaded (enable AI generation in Project Settings or on Publish)"

      true ->
        nil
    end
  end

  defp platform_from_capture_path(path) do
    path
    |> Path.basename()
    |> String.split("_", parts: 2)
    |> hd()
  end

  defp lookup_app_id(me, uuid) do
    lookup = get_in(me, ["app_lookup", "by_app_uuid"]) || %{}
    uuid = uuid |> to_string() |> String.trim() |> String.downcase()

    lookup
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(to_string(key)) == uuid, do: to_string(value)
    end)
  end

  defp linked_developer?(me) do
    developer = me["developer"] || %{}
    is_map(developer) and Enum.any?(["id", "_id", "firebase_uid"], &present?(developer[&1]))
  end

  defp default_category(_me, "watchface"), do: nil

  defp default_category(me, _app_type) do
    me
    |> Map.get("app_category_options", [])
    |> Enum.find_value(fn item ->
      value = item["key"] || item["id"]
      if value in ["tools", "tools-utilities"], do: "tools"
    end) || "tools"
  end

  defp maybe_put_category(fields, nil), do: fields
  defp maybe_put_category(fields, category), do: Map.put(fields, "category", category)

  defp website_url(opts) do
    opts
    |> Keyword.get(:website, StoreListingUrls.default_website_url())
    |> to_string()
    |> String.trim()
  end

  defp source_url(opts) do
    opts
    |> Keyword.get(:source, StoreListingUrls.default_source_repo_url())
    |> to_string()
    |> String.trim()
  end

  defp upload_summary(payload) do
    results = payload["screenshotResults"] || %{}
    uploaded = results["uploaded"] || []
    failed = results["failed"] || []
    app_id = extract_app_id(payload)

    [
      payload["message"] || "Publish completed successfully",
      if(app_id, do: "App page: https://apps.rePebble.com/#{app_id}", else: nil),
      if(uploaded != [], do: "Uploaded screenshots: #{length(uploaded)}", else: nil),
      if(failed != [], do: "Screenshot upload warnings: #{length(failed)}", else: nil)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp extract_app_id(payload) do
    payload["appId"] || payload["app_id"] || get_in(payload, ["app", "id"]) ||
      get_in(payload, ["data", "appId"]) || get_in(payload, ["data", "app_id"]) ||
      get_in(payload, ["data", "app", "id"])
  end

  defp choose_version("", metadata, app_root) do
    package_json_version(app_root)
    |> case do
      "" -> metadata.version
      version -> version
    end
  end

  defp choose_version(version, _metadata, _app_root), do: version

  defp package_json_version(app_root) when is_binary(app_root) do
    with {:ok, source} <- File.read(Path.join(app_root, "package.json")),
         {:ok, %{"version" => version}} <- Jason.decode(source) do
      version |> to_string() |> String.trim()
    else
      _ -> ""
    end
  end

  defp package_json_version(_), do: ""

  defp publish_version_warning(pbw_version, publish_version)
       when is_binary(pbw_version) and is_binary(publish_version) do
    if String.trim(pbw_version) != "" and String.trim(pbw_version) != String.trim(publish_version) do
      "Warning: PBW embedded version (#{pbw_version}) differs from publish version (#{publish_version}). Run Prepare Release before submit."
    end
  end

  defp publish_version_warning(_, _), do: nil

  defp visibility_line(true), do: "Release visibility: published (visible on the store listing)"

  defp visibility_line(false),
    do:
      "Release visibility: draft (not public yet — enable “Make release visible immediately” or publish from the developer dashboard)"

  defp release_notes_line(notes) do
    trimmed = notes |> to_string() |> String.trim()

    if trimmed == "" do
      "Release notes: (empty — add changelog text on the Publish page before submit)"
    else
      preview =
        trimmed
        |> String.split("\n", parts: 2)
        |> hd()
        |> String.slice(0, 80)

      suffix = if String.length(trimmed) > String.length(preview), do: "…", else: ""
      "Release notes: #{String.length(trimmed)} characters (#{preview}#{suffix})"
    end
  end

  defp prepare_upload_artifact(artifact_path) do
    case normalize_pbw_uuid(artifact_path) do
      {:ok, path, nil} ->
        {:ok, path, nil}

      {:ok, path, temp_path} ->
        {:ok, path, temp_path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_remove_temp_artifact(nil), do: :ok

  defp maybe_remove_temp_artifact(path) when is_binary(path) do
    _ = File.rm(path)
    :ok
  end

  defp normalize_pbw_uuid(artifact_path) do
    with {:ok, files} <- :zip.list_dir(artifact_path),
         metadata_name <- metadata_entry(files),
         true <- not is_nil(metadata_name),
         {:ok, metadata} <- read_zip_json(artifact_path, metadata_name),
         uuid when is_binary(uuid) and uuid != "" <- to_string(metadata["uuid"] || ""),
         lower = String.downcase(uuid),
         true <- uuid != lower,
         {:ok, temp_path} <- rewrite_pbw_uuid(artifact_path, lower) do
      {:ok, temp_path, temp_path}
    else
      false -> {:ok, artifact_path, nil}
      _ -> {:ok, artifact_path, nil}
    end
  end

  defp metadata_entry(files) do
    names = Enum.map(files, fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

    cond do
      "appinfo.json" in names -> "appinfo.json"
      "manifest.json" in names -> "manifest.json"
      true -> nil
    end
  end

  defp read_zip_json(artifact_path, entry) do
    charlist_path = String.to_charlist(artifact_path)
    charlist_entry = String.to_charlist(entry)

    with {:ok, [{_, data}]} <- :zip.extract(charlist_path, [{:file, charlist_entry}, :memory]) do
      Jason.decode(data)
    end
  end

  defp rewrite_pbw_uuid(artifact_path, lower_uuid) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "ide_publish_#{System.unique_integer([:positive])}.pbw"
      )

    charlist_path = String.to_charlist(artifact_path)

    with {:ok, files} <- :zip.extract(charlist_path, [:memory]),
         {:ok, zip_binary} <-
           :zip.create(~c"upload.pbw", rewrite_zip_entries(files, lower_uuid), [:memory]) do
      File.write!(temp_path, :erlang.iolist_to_binary(zip_binary))
      {:ok, temp_path}
    end
  end

  defp rewrite_zip_entries(files, lower_uuid) do
    Enum.map(files, fn {name, data} ->
      name_str = to_string(name)

      data =
        if name_str in ["appinfo.json", "manifest.json"] do
          case Jason.decode(data) do
            {:ok, %{"uuid" => _} = metadata} ->
              Jason.encode!(Map.put(metadata, "uuid", lower_uuid))

            _ ->
              data
          end
        else
          data
        end

      {name, data}
    end)
  end

  defp default_pbw_path(app_root),
    do: Path.join([app_root, "build", "#{Path.basename(app_root)}.pbw"])

  defp require_token(""), do: {:error, "App Store login required."}
  defp require_token(_token), do: :ok

  defp require_description(""),
    do: {:error, "Creating a new app requires an App Store description."}

  defp require_description(_description), do: :ok

  defp require_file(path, label) do
    if is_binary(path) and File.regular?(path),
      do: :ok,
      else: {:error, "#{label} file not found: #{path}"}
  end

  defp normalize_paths(paths) when is_list(paths), do: Enum.filter(paths, &is_binary/1)
  defp normalize_paths(_), do: []

  defp bool_string(true), do: "true"
  defp bool_string(false), do: "false"

  defp replace_screenshots_string([]), do: "false"
  defp replace_screenshots_string(paths) when is_list(paths), do: "true"
  defp replace_screenshots_string(_), do: "false"

  defp mime_type(path) do
    case Path.extname(path) |> String.downcase() do
      ".gif" -> "image/gif"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      _ -> "application/octet-stream"
    end
  end

  defp payload_error(%{"error" => error}), do: error
  defp payload_error(%{"message" => message}), do: message
  defp payload_error(payload), do: inspect(payload)

  defp error_output(reason) when is_binary(reason), do: reason
  defp error_output(reason), do: inspect(reason)

  defp command_result(status, cwd, output) do
    %{
      status: status,
      command: "native appstore publish",
      output: output,
      exit_code: if(status == :ok, do: 0, else: 1),
      cwd: cwd
    }
  end

  defp present?(value), do: not is_nil(value) and String.trim(to_string(value)) != ""
end
