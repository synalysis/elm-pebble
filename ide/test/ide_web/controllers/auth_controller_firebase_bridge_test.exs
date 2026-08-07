defmodule IdeWeb.AuthControllerFirebaseBridgeTest do
  use IdeWeb.ConnCase, async: true

  test "firebase bridge renders for github provider", %{conn: conn} do
    conn =
      get(conn, ~p"/auth/firebase/bridge", %{
        "provider" => "github",
        "return_to" => "/projects/demo/publish"
      })

    assert html_response(conn, 200) =~ "firebase-oauth-bridge"
    assert html_response(conn, 200) =~ "GitHub"
    assert html_response(conn, 200) =~ "/projects/demo/publish"
  end

  test "firebase bridge rejects open redirects in return_to", %{conn: conn} do
    conn =
      get(conn, ~p"/auth/firebase/bridge", %{
        "provider" => "github",
        "return_to" => "https://evil.example/phish"
      })

    html = html_response(conn, 200)
    assert html =~ "firebase-oauth-bridge"
    refute html =~ "evil.example"
    assert html =~ ~s(data-return-to="/projects")
  end
end
