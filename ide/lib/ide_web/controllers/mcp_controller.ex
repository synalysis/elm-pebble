defmodule IdeWeb.McpController do
  use IdeWeb, :controller

  alias Ide.Mcp.Protocol
  alias Ide.Mcp.HttpSessions
  alias Ide.Mcp.StreamableHttp
  alias Ide.Auth
  alias Ide.Settings

  @doc """
  Handles MCP Streamable HTTP GET requests.

  Clients that include `Accept: text/event-stream` receive a long-lived SSE
  listener stream. JSON-only probes receive HTTP 405.
  """
  def show(conn, _params) do
    cond do
      not Auth.mcp_enabled?() ->
        disabled_response(conn)

      not valid_origin?(conn) ->
        invalid_origin_response(conn)

      match?({:error, :disabled}, http_capabilities(conn)) ->
        disabled_response(conn)

      StreamableHttp.wants_event_stream?(conn) ->
        session_id = StreamableHttp.session_id(conn)

        conn
        |> StreamableHttp.sse_response_headers()
        |> send_chunked(200)
        |> StreamableHttp.listen_loop(session_id)

      true ->
        conn
        |> put_resp_header("allow", "GET, POST")
        |> put_status(:method_not_allowed)
        |> json(%{
          "error" => "MCP HTTP endpoint accepts Streamable HTTP GET (SSE) and JSON-RPC POST.",
          "transport" => "streamable-http",
          "methods" => ["GET", "POST"]
        })
    end
  end

  @doc """
  Handles MCP JSON-RPC over Streamable HTTP POST requests.
  """
  def create(conn, %{"_json" => request_body}) when is_list(request_body) do
    create(conn, request_body)
  end

  def create(conn, request_body) when is_list(request_body) do
    with :ok <- ensure_post_acceptable(conn),
         {:ok, capabilities} <- http_capabilities(conn) do
      responses =
        with_current_user(conn, fn -> Protocol.batch_response(request_body, capabilities) end)

      if responses == [] do
        send_resp(conn, 202, "")
      else
        conn
        |> maybe_attach_initialize_session(request_body)
        |> json(responses)
      end
    else
      {:error, :disabled} -> disabled_response(conn)
      {:error, :invalid_origin} -> invalid_origin_response(conn)
      {:error, :not_acceptable} -> not_acceptable_response(conn)
    end
  end

  def create(conn, request_body) when is_map(request_body) do
    with :ok <- ensure_post_acceptable(conn),
         {:ok, capabilities} <- http_capabilities(conn) do
      case with_current_user(conn, fn -> Protocol.response(request_body, capabilities) end) do
        nil ->
          send_resp(conn, 202, "")

        response ->
          conn
          |> maybe_attach_initialize_session(request_body)
          |> json(response)
      end
    else
      {:error, :disabled} -> disabled_response(conn)
      {:error, :invalid_origin} -> invalid_origin_response(conn)
      {:error, :not_acceptable} -> not_acceptable_response(conn)
    end
  end

  def create(conn, _request_body) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32600, "message" => "invalid request"}
    })
  end

  defp ensure_post_acceptable(conn) do
    cond do
      not valid_origin?(conn) ->
        {:error, :invalid_origin}

      not StreamableHttp.acceptable_request?(conn) ->
        {:error, :not_acceptable}

      true ->
        :ok
    end
  end

  defp valid_origin?(conn), do: StreamableHttp.valid_origin?(conn)

  defp maybe_attach_initialize_session(conn, request_body) when is_list(request_body) do
    if Enum.any?(request_body, &initialize_request?/1) do
      put_resp_header(conn, "mcp-session-id", HttpSessions.create_session())
    else
      conn
    end
  end

  defp maybe_attach_initialize_session(conn, request_body) do
    if initialize_request?(request_body) do
      put_resp_header(conn, "mcp-session-id", HttpSessions.create_session())
    else
      conn
    end
  end

  defp initialize_request?(%{"method" => "initialize"}), do: true
  defp initialize_request?(_request), do: false

  defp http_capabilities(conn) do
    if Auth.mcp_enabled?() do
      settings = Settings.current()

      if settings.mcp_http_enabled do
        configured_capabilities = Protocol.normalize_capabilities(settings.mcp_http_capabilities)

        requested_capabilities =
          conn.params
          |> Map.get("capabilities", configured_capabilities)
          |> Protocol.normalize_capabilities()

        {:ok, Enum.filter(requested_capabilities, &(&1 in configured_capabilities))}
      else
        {:error, :disabled}
      end
    else
      {:error, :disabled}
    end
  end

  defp disabled_response(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32000, "message" => "MCP HTTP endpoint is disabled in IDE settings"}
    })
  end

  defp invalid_origin_response(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32000, "message" => "invalid Origin header for MCP HTTP endpoint"}
    })
  end

  defp not_acceptable_response(conn) do
    conn
    |> put_status(:not_acceptable)
    |> json(%{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{
        "code" => -32000,
        "message" =>
          "MCP HTTP POST requests must include Accept: application/json and/or text/event-stream."
      }
    })
  end

  defp with_current_user(conn, fun) do
    previous = Process.get(:ide_current_user)
    Process.put(:ide_current_user, conn.assigns[:current_user])

    try do
      fun.()
    after
      if is_nil(previous) do
        Process.delete(:ide_current_user)
      else
        Process.put(:ide_current_user, previous)
      end
    end
  end
end
