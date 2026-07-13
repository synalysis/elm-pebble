defmodule Ide.Mcp.StreamableHttp do
  @moduledoc false

  import Plug.Conn

  alias Ide.Mcp.{HttpSessions, Sse}

  @keepalive_ms 15_000

  @spec acceptable_request?(Plug.Conn.t()) :: boolean()
  def acceptable_request?(conn) do
    accept_header(conn) == "" or
      String.contains?(accept_header(conn), "application/json") or
      String.contains?(accept_header(conn), "text/event-stream")
  end

  @spec wants_event_stream?(Plug.Conn.t()) :: boolean()
  def wants_event_stream?(conn) do
    conn.method == "GET" and String.contains?(accept_header(conn), "text/event-stream")
  end

  @spec valid_origin?(Plug.Conn.t()) :: boolean()
  def valid_origin?(conn) do
    case get_req_header(conn, "origin") do
      [] ->
        true

      [origin | _] ->
        localhost_origin?(origin, conn.host)
    end
  end

  @spec session_id(Plug.Conn.t()) :: String.t()
  def session_id(conn) do
    case get_req_header(conn, "mcp-session-id") do
      [session_id | _] when is_binary(session_id) and session_id != "" ->
        session_id

      _ ->
        HttpSessions.create_session()
    end
  end

  @spec sse_response_headers(Plug.Conn.t()) :: Plug.Conn.t()
  def sse_response_headers(conn) do
    conn
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-accel-buffering", "no")
    |> put_resp_content_type("text/event-stream")
  end

  @spec listen_loop(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def listen_loop(conn, session_id) do
    HttpSessions.register_listener(session_id, self())

    try do
      conn
      |> run_listen_loop(session_id)
    after
      HttpSessions.unregister_listener(session_id, self())
    end
  end

  defp run_listen_loop(conn, session_id) do
    case stream_loop_override() do
      fun when is_function(fun, 2) -> fun.(conn, session_id)
      _ -> default_listen_loop(conn, session_id)
    end
  end

  defp default_listen_loop(conn, session_id) do
    receive do
      {:mcp_sse_message, payload} ->
        default_listen_loop(chunk!(conn, Sse.message_event(payload)), session_id)

      {:DOWN, _ref, :process, _pid, _reason} ->
        conn
    after
      @keepalive_ms ->
        default_listen_loop(chunk!(conn, Sse.comment("keepalive")), session_id)
    end
  end

  defp stream_loop_override do
    Application.get_env(:ide, IdeWeb.McpController, [])[:stream_loop]
  end

  defp chunk!(conn, data) do
    case chunk(conn, data) do
      {:ok, conn} -> conn
      {:error, _} -> conn
    end
  end

  defp accept_header(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.join(",")
    |> String.downcase()
  end

  defp localhost_origin?(origin, host) do
    case URI.parse(origin) do
      %URI{host: origin_host} when origin_host in ["localhost", "127.0.0.1", "::1"] ->
        true

      %URI{host: origin_host} when is_binary(origin_host) and is_binary(host) ->
        String.downcase(origin_host) == String.downcase(host)

      _ ->
        false
    end
  end
end
