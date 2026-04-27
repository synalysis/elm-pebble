defmodule IdeWeb.McpController do
  use IdeWeb, :controller

  alias Ide.Mcp.Protocol
  alias Ide.Settings

  @doc """
  Handles MCP JSON-RPC over HTTP.
  """
  def create(conn, %{"_json" => request_body}) when is_list(request_body) do
    create(conn, request_body)
  end

  def create(conn, request_body) when is_list(request_body) do
    with {:ok, capabilities} <- http_capabilities(conn) do
      responses = Protocol.batch_response(request_body, capabilities)

      if responses == [] do
        send_resp(conn, 202, "")
      else
        json(conn, responses)
      end
    else
      {:error, :disabled} -> disabled_response(conn)
    end
  end

  def create(conn, request_body) when is_map(request_body) do
    with {:ok, capabilities} <- http_capabilities(conn) do
      case Protocol.response(request_body, capabilities) do
        nil -> send_resp(conn, 202, "")
        response -> json(conn, response)
      end
    else
      {:error, :disabled} -> disabled_response(conn)
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

  defp http_capabilities(conn) do
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
end
