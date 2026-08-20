defmodule IdeWeb.Plugs.CanonicalLoopbackHostTest do
  use ExUnit.Case, async: true

  alias IdeWeb.Plugs.CanonicalLoopbackHost

  defp html_conn(host, path \\ "/projects") do
    :get
    |> Plug.Test.conn(path)
    |> Map.put(:host, host)
    |> Map.put(:port, 4000)
    |> Map.put(:scheme, :http)
    |> Plug.Conn.put_req_header("accept", "text/html")
  end

  test "redirects 127.0.0.1 browser GET to localhost" do
    conn = CanonicalLoopbackHost.call(html_conn("127.0.0.1"), [])

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["http://localhost:4000/projects"]
    assert conn.halted
  end

  test "redirects IPv6 loopback browser GET to localhost" do
    conn = CanonicalLoopbackHost.call(html_conn("::1", "/login"), [])

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["http://localhost:4000/login"]
  end

  test "leaves localhost browser requests unchanged" do
    conn = CanonicalLoopbackHost.call(html_conn("localhost"), [])

    assert conn.status == nil
    refute conn.halted
  end

  test "does not redirect JSON API clients on 127.0.0.1" do
    conn =
      :get
      |> Plug.Test.conn("/api/mcp")
      |> Map.put(:host, "127.0.0.1")
      |> Map.put(:port, 4000)
      |> Plug.Conn.put_req_header("accept", "application/json")

    conn = CanonicalLoopbackHost.call(conn, [])

    assert conn.status == nil
    refute conn.halted
  end

  test "does not redirect POST on 127.0.0.1" do
    conn =
      :post
      |> Plug.Test.conn("/auth/firebase")
      |> Map.put(:host, "127.0.0.1")
      |> Plug.Conn.put_req_header("accept", "text/html")

    conn = CanonicalLoopbackHost.call(conn, [])

    assert conn.status == nil
    refute conn.halted
  end
end
