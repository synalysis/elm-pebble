defmodule IdeWeb.Plugs.RemoteIpTest do
  use ExUnit.Case, async: false

  alias IdeWeb.Plugs.RemoteIp

  setup do
    original = Application.get_env(:ide, RemoteIp, [])
    on_exit(fn -> Application.put_env(:ide, RemoteIp, original) end)
    :ok
  end

  test "leaves remote_ip unchanged when untrusted" do
    Application.put_env(:ide, RemoteIp, trust: false)

    conn =
      Plug.Test.conn(:get, "/")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> Plug.Conn.put_req_header("x-forwarded-for", "8.8.8.8")
      |> RemoteIp.call([])

    assert conn.remote_ip == {127, 0, 0, 1}
  end

  test "rewrites remote_ip from X-Forwarded-For when trusted" do
    Application.put_env(:ide, RemoteIp, trust: true)

    conn =
      Plug.Test.conn(:get, "/")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> Plug.Conn.put_req_header("x-forwarded-for", "8.8.8.8, 10.0.0.1")
      |> RemoteIp.call([])

    assert conn.remote_ip == {8, 8, 8, 8}
  end
end
