defmodule IdeWeb.EmulatorController do
  use IdeWeb, :controller

  require Logger

  alias Ide.Debugger.SimulatorSettings
  alias Ide.Emulator
  alias Ide.Emulator.Session
  alias Ide.Emulator.Session.ProcessHost
  alias Ide.Emulator.Workflow
  alias Ide.PebblePreferences
  alias Ide.Projects
  alias Ide.Screenshots

  @spec screenshot(Plug.Conn.t(), %{required(String.t()) => term()}) :: Plug.Conn.t()
  def screenshot(conn, %{"slug" => slug, "image" => image} = params) do
    emulator_target = Map.get(params, "platform", "basalt")

    with project when not is_nil(project) <-
           Projects.get_project_by_slug(slug, conn.assigns[:current_user]),
         {:ok, shot} <- Screenshots.store_png_data_url(project, emulator_target, image) do
      json(conn, %{status: "ok", screenshot: shot})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: screenshot_error_message(reason)})
    end
  end

  def screenshot(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Expected image data URL"})
  end

  @spec launch(Plug.Conn.t(), %{required(String.t()) => term()}) :: Plug.Conn.t()
  def launch(conn, %{"slug" => slug} = params) do
    platform = Map.get(params, "platform")

    with project when not is_nil(project) <-
           Projects.get_project_by_slug(slug, conn.assigns[:current_user]),
         {:ok, %{session: info}} <- Workflow.launch_project(project, platform) do
      json(conn, info)
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: Workflow.launch_error_message(reason)})
    end
  end

  def launch(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Expected slug and platform"})
  end

  defp qemu_protocol(protocol) when is_integer(protocol) and protocol >= 0 and protocol <= 255,
    do: {:ok, protocol}

  defp qemu_protocol(protocol) when is_binary(protocol) do
    case Integer.parse(protocol) do
      {value, ""} -> qemu_protocol(value)
      _ -> {:error, :invalid_qemu_protocol}
    end
  end

  defp qemu_protocol(_protocol), do: {:error, :invalid_qemu_protocol}

  defp qemu_payload(payload) when is_list(payload) do
    if Enum.all?(payload, &(is_integer(&1) and &1 >= 0 and &1 <= 255)) do
      {:ok, :erlang.list_to_binary(payload)}
    else
      {:error, :invalid_qemu_payload}
    end
  end

  defp qemu_payload(_payload), do: {:error, :invalid_qemu_payload}

  @spec ping(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ping(conn, %{"id" => id}) do
    case Emulator.ping(id) do
      {:ok, info} -> json(conn, Map.put(info, :alive, true))
      {:error, _reason} -> json(conn, %{alive: false})
    end
  end

  @spec kill(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def kill(conn, %{"id" => id}) do
    _ = Emulator.kill(id)
    json(conn, %{status: "ok"})
  end

  @spec install(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def install(conn, %{"id" => id}) do
    case Emulator.install(id) do
      {:ok, result} ->
        json(conn, %{status: "ok", result: result})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Emulator not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: Workflow.install_error_message(reason)})
    end
  end

  @spec request_app_logs(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def request_app_logs(conn, %{"id" => id}) do
    case Emulator.request_app_logs(id) do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Emulator not found"})

      {:error, :embedded_protocol_router_not_started} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Embedded emulator protocol router is not running."})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  @spec control(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def control(conn, %{"id" => id} = params) do
    with {:ok, protocol} <- qemu_protocol(Map.get(params, "protocol")),
         {:ok, payload} <- qemu_payload(Map.get(params, "payload", [])),
         :ok <- Emulator.control(id, protocol, payload) do
      json(conn, %{status: "ok"})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Emulator not found"})

      {:error, :embedded_protocol_router_not_started} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Embedded emulator protocol router is not running."})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  @spec simulator_settings(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def simulator_settings(conn, %{"id" => id, "settings" => settings}) when is_map(settings) do
    normalized = SimulatorSettings.normalize(settings)

    case Emulator.apply_simulator_settings(id, normalized) do
      {:ok, result} ->
        json(conn, %{status: "ok", result: result})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Emulator not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def simulator_settings(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Missing settings object"})
  end

  @spec config_return(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  @spec companion_preferences(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def companion_preferences(conn, %{"slug" => slug}) do
    with project when not is_nil(project) <-
           Projects.get_project_by_slug(slug, conn.assigns[:current_user]),
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

  @spec artifact(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  @spec ws_vnc(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ws_vnc(conn, %{"id" => id}), do: proxy(conn, id, :vnc)

  @spec ws_phone(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ws_phone(conn, %{"id" => id}), do: proxy(conn, id, :phone)

  defp proxy(conn, id, kind) do
    if websocket_upgrade?(conn) do
      do_proxy(conn, id, kind)
    else
      conn
      |> put_status(426)
      |> json(%{error: "WebSocket upgrade required"})
      |> halt()
    end
  end

  defp do_proxy(conn, id, kind) do
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
        Logger.warning(
          "embedded emulator websocket proxy failed id=#{id} kind=#{kind}: #{inspect(reason)}"
        )

        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  defp websocket_upgrade?(conn) do
    conn.method == "GET" and
      Enum.any?(get_req_header(conn, "upgrade"), fn value ->
        value |> String.downcase() |> String.contains?("websocket")
      end)
  end

  defp proxy_target(%{backend_enabled: false}, _kind),
    do: {:error, :embedded_emulator_backend_disabled}

  defp proxy_target(%{id: id}, :vnc) do
    with {:ok, pid} <- Emulator.lookup(id),
         {:ok, port} <- session_local_port(pid, :vnc),
         true <- ProcessHost.tcp_port_open?(port) do
      {:ok, {:tcp, "127.0.0.1", port}}
    else
      false -> {:error, :emulator_vnc_not_ready}
      error -> error
    end
  end

  defp proxy_target(%{id: id}, :phone) do
    with {:ok, pid} <- Emulator.lookup(id),
         {:ok, port} <- session_local_port(pid, :phone),
         true <- ProcessHost.tcp_port_open?(port) do
      {:ok, "ws://127.0.0.1:#{port}/"}
    else
      false -> {:error, :emulator_phone_not_ready}
      error -> error
    end
  end

  defp session_local_port(pid, kind) when is_pid(pid) do
    case Session.local_port(pid, kind) do
      port when is_integer(port) and port > 0 -> {:ok, port}
      other -> {:error, other}
    end
  catch
    :exit, {:noproc, _} -> {:error, :emulator_not_running}
    :exit, {:timeout, _} -> {:error, :emulator_session_timeout}
    :exit, :killed -> {:error, :emulator_not_running}
    :exit, reason -> {:error, reason}
  end

  defp screenshot_error_message(:invalid_data_url),
    do: "Expected a PNG data URL from the emulator display."

  defp screenshot_error_message(:invalid_png),
    do: "Screenshot image is not a valid PNG."

  defp screenshot_error_message(reason), do: inspect(reason)
end
