defmodule IdeWeb.McpControllerTest do
  use IdeWeb.ConnCase, async: false

  setup do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "ide_mcp_controller_test_#{System.unique_integer([:positive])}.json"
      )

    previous = Application.get_env(:ide, Ide.Settings, [])
    previous_auth = Application.get_env(:ide, Ide.Auth, [])

    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)
    Application.put_env(:ide, Ide.Auth, Keyword.put(previous_auth, :mode, :local))

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, previous)
      Application.put_env(:ide, Ide.Auth, previous_auth)
      File.rm(temp_path)
    end)

    {:ok, user: insert_mcp_test_user!()}
  end

  defp insert_mcp_test_user! do
    {:ok, user} =
      %Ide.Auth.User{}
      |> Ide.Auth.User.changeset(%{firebase_uid: "mcp-test-user"})
      |> Ide.Repo.insert()

    user
  end

  defp authenticated_conn(conn, user) do
    conn
    |> Plug.Test.init_test_session(user_id: user.id)
  end

  test "GET /api/mcp reports POST-only HTTP transport", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/mcp")

    body = json_response(conn, 405)
    assert get_resp_header(conn, "allow") == ["POST"]
    assert body["transport"] == "http"
    assert body["methods"] == ["POST"]
  end

  test "GET /api/mcp tolerates event-stream probes", %{conn: _conn} do
    conn =
      build_conn()
      |> put_req_header("accept", "text/event-stream, application/json")
      |> get(~p"/api/mcp")

    body = json_response(conn, 405)
    assert get_resp_header(conn, "allow") == ["POST"]
    assert body["methods"] == ["POST"]
  end

  test "POST /api/mcp handles initialize over HTTP", %{conn: conn, user: user} do
    conn =
      conn
      |> authenticated_conn(user)
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

  test "POST /api/mcp supports JSON-RPC batch requests", %{conn: conn, user: user} do
    conn =
      conn
      |> authenticated_conn(user)
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
    assert Enum.any?(tools_list["result"]["tools"], &(&1["name"] == "projects_list"))
  end

  test "capability query parameter cannot escalate beyond configured HTTP scope", %{
    conn: conn,
    user: user
  } do
    conn =
      conn
      |> authenticated_conn(user)
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

    assert "projects_list" in tool_names
    refute "files_write" in tool_names
    refute "compiler_compile" in tool_names
  end

  test "public modes disable MCP HTTP endpoint", %{conn: _conn, user: user} do
    original_auth = Application.get_env(:ide, Ide.Auth, [])

    for mode <- [:public_pebble, :public_custom] do
      Application.put_env(:ide, Ide.Auth, Keyword.put(original_auth, :mode, mode))

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/mcp")

      body = json_response(conn, 403)
      assert body["error"]["message"] =~ "disabled"

      conn =
        build_conn()
        |> authenticated_conn(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/mcp", Jason.encode!(%{"id" => 1, "method" => "tools/list"}))

      body = json_response(conn, 403)
      assert body["error"]["message"] =~ "disabled"
    end
  end

  test "disabled MCP HTTP setting returns forbidden", %{conn: conn, user: user} do
    assert :ok = Ide.Settings.set_mcp_http_enabled(false)

    conn =
      conn
      |> authenticated_conn(user)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/mcp", Jason.encode!(%{"id" => 1, "method" => "tools/list"}))

    body = json_response(conn, 403)
    assert body["error"]["message"] =~ "disabled"
  end
end
