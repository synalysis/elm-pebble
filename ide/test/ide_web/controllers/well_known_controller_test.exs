defmodule IdeWeb.WellKnownControllerTest do
  use IdeWeb.ConnCase, async: true

  test "oauth-protected-resource root returns clean JSON 404", %{conn: conn} do
    conn = get(conn, "/.well-known/oauth-protected-resource")

    body = json_response(conn, 404)
    assert body["error"] == "not_found"
    assert body["error_description"] =~ "does not publish OAuth"
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    refute conn.resp_body =~ "Phoenix.Router.NoRouteError"
  end

  test "oauth-protected-resource path suffix returns clean JSON 404", %{conn: conn} do
    conn = get(conn, "/.well-known/oauth-protected-resource/api/mcp")

    body = json_response(conn, 404)
    assert body["error"] == "not_found"
    refute conn.resp_body =~ "<!DOCTYPE html>"
  end
end
