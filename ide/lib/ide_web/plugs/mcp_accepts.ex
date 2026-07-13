defmodule IdeWeb.Plugs.McpAccepts do
  @moduledoc false

  import Plug.Conn

  alias Ide.Mcp.StreamableHttp

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if StreamableHttp.acceptable_request?(conn) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(406, Jason.encode!(not_acceptable_body(conn)))
      |> halt()
    end
  end

  defp not_acceptable_body(conn) do
    %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{
        "code" => -32000,
        "message" =>
          "MCP HTTP endpoint accepts application/json and text/event-stream Accept values."
      },
      "meta" => %{"accept" => get_req_header(conn, "accept")}
    }
  end
end
