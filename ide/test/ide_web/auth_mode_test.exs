defmodule IdeWeb.AuthModeTest do
  use IdeWeb.ConnCase, async: false

  alias Ide.Auth.User
  alias Ide.Repo

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])
    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original) end)
    :ok
  end

  test "local mode allows anonymous project access", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :local)

    conn = get(conn, ~p"/projects")

    assert html_response(conn, 200) =~ "Projects"
  end

  test "public mode redirects anonymous project access to login", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public)

    conn = get(conn, ~p"/projects")

    assert redirected_to(conn) == "/login"
  end

  test "public mode allows authenticated project access", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public)

    {:ok, user} =
      %User{}
      |> User.changeset(%{firebase_uid: "auth-mode-user", email: "user@example.test"})
      |> Repo.insert()

    conn =
      conn
      |> Plug.Test.init_test_session(user_id: user.id)
      |> get(~p"/projects")

    assert html_response(conn, 200) =~ "Projects"
  end
end
