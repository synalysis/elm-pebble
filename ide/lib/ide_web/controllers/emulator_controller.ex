defmodule IdeWeb.EmulatorController do
  use IdeWeb, :controller

  alias Ide.Emulator
  alias Ide.PebblePreferences
  alias Ide.Projects
  alias Ide.WatchModels
  alias IdeWeb.WorkspaceLive.BuildFlow

  @spec launch(term(), term()) :: term()
  def launch(conn, %{"slug" => slug} = params) do
    platform = Map.get(params, "platform")

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         workspace_root <- Projects.project_workspace_path(project),
         {:ok, package_result, launch_platform} <-
           package_for_launch(project, workspace_root, platform),
         {:ok, info} <-
           Emulator.launch(
             project_slug: project.slug,
             platform: launch_platform,
             artifact_path: package_result.artifact_path,
             has_phone_companion: package_result.has_phone_companion
           ) do
      json(conn, info)
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: launch_error_message(reason)})
    end
  end

  def launch(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Expected slug and platform"})
  end

  defp package_for_launch(project, workspace_root, platform) do
    case BuildFlow.package_for_emulator_session(project, workspace_root, platform) do
      {:ok, package_result} ->
        {:ok, package_result, platform}

      {:error, reason} ->
        fallback_platform = WatchModels.default_id()

        if aplite_app_overflow?(platform, reason) and platform != fallback_platform do
          with {:ok, package_result} <-
                 BuildFlow.package_for_emulator_session(project, workspace_root, fallback_platform) do
            {:ok, package_result, fallback_platform}
          end
        else
          {:error, reason}
        end
    end
  end

  defp aplite_app_overflow?("aplite", {:pebble_build_failed, %{output: output}})
       when is_binary(output) do
    String.contains?(output, "region `APP' overflowed")
  end

  defp aplite_app_overflow?(_platform, _reason), do: false

  @spec ping(term(), term()) :: term()
  def ping(conn, %{"id" => id}) do
    case Emulator.ping(id) do
      {:ok, info} -> json(conn, Map.put(info, :alive, true))
      {:error, _reason} -> json(conn, %{alive: false})
    end
  end

  @spec kill(term(), term()) :: term()
  def kill(conn, %{"id" => id}) do
    _ = Emulator.kill(id)
    json(conn, %{status: "ok"})
  end

  @spec install(term(), term()) :: term()
  def install(conn, %{"id" => id}) do
    case Emulator.install(id) do
      {:ok, result} ->
        json(conn, %{status: "ok", result: result})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Emulator not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: install_error_message(reason)})
    end
  end

  @spec config_return(term(), term()) :: term()
  def config_return(conn, _params) do
    html(conn, """
    <!doctype html>
    <html>
      <body style="font-family: sans-serif; padding: 1rem;">
        <p>Configuration response received. You can close this window.</p>
      </body>
    </html>
    """)
  end

  @spec companion_preferences(term(), term()) :: term()
  def companion_preferences(conn, %{"slug" => slug}) do
    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         phone_root <- Path.join(Projects.project_workspace_path(project), "phone"),
         true <- File.exists?(Path.join(phone_root, "elm.json")),
         {:ok, schema} when is_map(schema) <- PebblePreferences.extract(phone_root) do
      html(conn, PebblePreferences.render_html(schema))
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      false ->
        conn |> put_status(:not_found) |> json(%{error: "This project has no companion app."})

      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "This companion app does not declare preferences."})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not render companion preferences: #{inspect(reason)}"})
    end
  end

  @spec artifact(term(), term()) :: term()
  def artifact(conn, %{"id" => id}) do
    with {:ok, pid} <- Emulator.lookup(id),
         path when is_binary(path) <- Ide.Emulator.Session.artifact_file_path(pid),
         true <- File.exists?(path) do
      send_download(conn, {:file, path},
        filename: Path.basename(path),
        content_type: "application/octet-stream"
      )
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "Artifact not found"})
    end
  end

  @spec ws_vnc(term(), term()) :: term()
  def ws_vnc(conn, %{"id" => id}), do: proxy(conn, id, :vnc)

  @spec ws_phone(term(), term()) :: term()
  def ws_phone(conn, %{"id" => id}), do: proxy(conn, id, :phone)

  defp proxy(conn, id, kind) do
    with {:ok, info} <- Emulator.info(id),
         {:ok, target} <- proxy_target(info, kind) do
      conn
      |> WebSockAdapter.upgrade(IdeWeb.EmulatorProxySocket, %{target: target},
        timeout: 86_400_000
      )
      |> halt()
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Emulator not found"})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  defp proxy_target(%{backend_enabled: false}, _kind),
    do: {:error, :embedded_emulator_backend_disabled}

  defp proxy_target(%{id: id}, :vnc) do
    with {:ok, pid} <- Emulator.lookup(id),
         port <- Ide.Emulator.Session.local_port(pid, :vnc),
         true <- Ide.Emulator.Session.tcp_port_open?(port) do
      {:ok, {:tcp, "127.0.0.1", port}}
    else
      false -> {:error, :emulator_vnc_not_ready}
      error -> error
    end
  end

  defp proxy_target(%{id: id}, :phone) do
    with {:ok, pid} <- Emulator.lookup(id),
         port <- Ide.Emulator.Session.local_port(pid, :phone),
         true <- Ide.Emulator.Session.tcp_port_open?(port) do
      {:ok, "ws://127.0.0.1:#{port}/"}
    else
      false -> {:error, :emulator_phone_not_ready}
      error -> error
    end
  end

  defp launch_error_message({:embedded_emulator_unavailable, missing}) when is_list(missing) do
    "Embedded emulator dependencies are missing: #{Enum.join(missing, ", ")}. " <>
      "Install Pebble QEMU/pypkjs or set ELM_PEBBLE_QEMU_BIN, ELM_PEBBLE_PYPKJS_BIN, and ELM_PEBBLE_QEMU_IMAGE_ROOT."
  end

  defp launch_error_message(:embedded_emulator_disabled) do
    "Embedded emulator is disabled by ELM_PEBBLE_EMBEDDED_EMULATOR."
  end

  defp launch_error_message({:embedded_emulator_image_download_failed, reason}) do
    "Could not download Pebble QEMU flash images: #{inspect(reason)}. " <>
      "Check network access or set ELM_PEBBLE_QEMU_IMAGE_ROOT to a directory that already contains <platform>/qemu images."
  end

  defp launch_error_message(reason), do: inspect(reason)

  defp install_error_message(:artifact_not_found),
    do: "PBW artifact not found for this emulator session."

  defp install_error_message(:embedded_protocol_router_not_started),
    do: "Embedded emulator protocol router is not running."

  defp install_error_message(reason), do: inspect(reason)
end
