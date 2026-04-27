defmodule IdeWeb.McpControllerTest do
  use IdeWeb.ConnCase, async: false

  setup do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "ide_mcp_controller_test_#{System.unique_integer([:positive])}.json"
      )

    previous = Application.get_env(:ide, Ide.Settings, [])
    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, previous)
      File.rm(temp_path)
    end)

    :ok
  end

  test "POST /api/mcp handles initialize over HTTP", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/mcp",
        Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})
      )

    body = json_response(conn, 200)
    assert body["id"] == 1
    assert body["result"]["serverInfo"]["name"] == "elm-pebble-ide-mcp"
    assert body["result"]["meta"]["capabilities_scope"] == ["read"]
  end

  test "POST /api/mcp supports JSON-RPC batch requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/mcp",
        Jason.encode!([
          %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"},
          %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}
        ])
      )

    [initialize, tools_list] = json_response(conn, 200)

    assert initialize["id"] == 1
    assert tools_list["id"] == 2
    assert Enum.any?(tools_list["result"]["tools"], &(&1["name"] == "projects.list"))
  end

  test "capability query parameter cannot escalate beyond configured HTTP scope", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/mcp?capabilities=read,edit,build",
        Jason.encode!(%{"id" => 1, "method" => "tools/list"})
      )

    tool_names =
      conn
      |> json_response(200)
      |> get_in(["result", "tools"])
      |> Enum.map(& &1["name"])

    assert "projects.list" in tool_names
    refute "files.write" in tool_names
    refute "compiler.compile" in tool_names
  end

  test "disabled MCP HTTP setting returns forbidden", %{conn: conn} do
    assert :ok = Ide.Settings.set_mcp_http_enabled(false)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/mcp", Jason.encode!(%{"id" => 1, "method" => "tools/list"}))

    body = json_response(conn, 403)
    assert body["error"]["message"] =~ "disabled"
  end
end
