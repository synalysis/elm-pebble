defmodule IdeWeb.AuthModeTest do
  use IdeWeb.ConnCase, async: false

  import Swoosh.TestAssertions

  alias Ide.Auth
  alias Ide.Auth.User
  alias Ide.EmulatorSupport
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

  test "public_pebble mode redirects anonymous project access to login", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_pebble)

    conn = get(conn, ~p"/projects")

    assert redirected_to(conn) == "/login"
  end

  test "public alias maps to public_pebble", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public)

    assert Auth.mode() == :public_pebble
    assert Auth.public_mode?()
    assert Auth.app_store_publish_enabled?()

    conn = get(conn, ~p"/projects")
    assert redirected_to(conn) == "/login"
  end

  test "public modes disable external emulator option", %{conn: _conn} do
    for mode <- [:public_pebble, :public_custom] do
      Application.put_env(:ide, Ide.Auth, mode: mode)
      refute EmulatorSupport.external_mode_enabled?()
      refute "external" in EmulatorSupport.supported_modes("basalt")
    end
  end

  test "public_custom mode redirects anonymous users and disables app store publish", %{
    conn: conn
  } do
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    assert Auth.public_custom_mode?()
    refute Auth.app_store_publish_enabled?()

    conn = get(conn, ~p"/projects")
    assert redirected_to(conn) == "/login"
  end

  test "public_pebble allows authenticated firebase user access", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_pebble)

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

  test "public_custom magic link flow", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    conn =
      post(conn, ~p"/auth/email/continue", %{
        "email" => "magic-user@example.test"
      })

    assert html_response(conn, 200) =~ "Check your email"
    assert html_response(conn, 200) =~ "magic-user@example.test"

    token =
      assert_email_sent(fn email ->
        assert email.to == [{"", "magic-user@example.test"}]
        [_, token] = Regex.run(~r/token=([^&\s"]+)/, email.html_body)
        token
      end)

    conn = get(build_conn(), ~p"/auth/email/verify?token=#{token}")

    assert redirected_to(conn) == "/projects"
    assert get_session(conn, :user_id)
  end

  test "public_custom login page starts with email only", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    conn = get(conn, ~p"/login")

    assert html_response(conn, 200) =~ "Email me a login link"
    assert html_response(conn, 200) =~ ~p"/auth/email/continue"
    refute html_response(conn, 200) =~ "password"
  end

  test "public_custom email continue always shows check your email", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    conn =
      post(conn, ~p"/auth/email/continue", %{
        "email" => "new-user@example.test"
      })

    assert html_response(conn, 200) =~ "Check your email"

    {:ok, _} =
      %User{}
      |> User.email_changeset(%{email: "existing@example.test"})
      |> Repo.insert()

    conn =
      build_conn()
      |> post(~p"/auth/email/continue", %{"email" => "existing@example.test"})

    assert html_response(conn, 200) =~ "Check your email"
    refute html_response(conn, 200) =~ "password"
  end

  test "public_pebble login page renders firebase buttons", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_pebble)

    conn = get(conn, ~p"/login")

    assert html_response(conn, 200) =~ "Log in with Google"
    refute html_response(conn, 200) =~ ~p"/auth/email/continue"
  end
end
