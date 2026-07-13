defmodule Ide.Mcp.StreamableHttpTest do
  use ExUnit.Case, async: true

  alias Ide.Mcp.StreamableHttp

  test "accepts json and event-stream accept headers" do
    conn =
      Plug.Test.conn(:get, "/api/mcp")
      |> Plug.Conn.put_req_header("accept", "text/event-stream")

    assert StreamableHttp.acceptable_request?(conn)
    assert StreamableHttp.wants_event_stream?(conn)
  end

  test "rejects unsupported accept headers" do
    conn =
      Plug.Test.conn(:get, "/api/mcp")
      |> Plug.Conn.put_req_header("accept", "text/plain")

    refute StreamableHttp.acceptable_request?(conn)
  end

  test "allows missing origin and localhost origins" do
    conn = Plug.Test.conn(:get, "/api/mcp")
    assert StreamableHttp.valid_origin?(conn)

    conn =
      Plug.Test.conn(:get, "/api/mcp")
      |> Plug.Conn.put_req_header("origin", "http://localhost:4000")

    assert StreamableHttp.valid_origin?(conn)
  end

  test "rejects remote origin headers" do
    conn =
      Plug.Test.conn(:get, "/api/mcp")
      |> Plug.Conn.put_req_header("origin", "https://evil.example")

    refute StreamableHttp.valid_origin?(conn)
  end
end
