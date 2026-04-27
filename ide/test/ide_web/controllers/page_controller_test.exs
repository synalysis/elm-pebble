defmodule IdeWeb.PageControllerTest do
  use IdeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/projects"
  end
end
