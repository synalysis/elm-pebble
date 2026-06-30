defmodule Ide.Auth.LoginDefenseTest do
  use IdeWeb.ConnCase, async: false

  import Swoosh.TestAssertions

  alias Ide.Auth.EmailHash
  alias Ide.Auth.LoginBotDefense
  alias Ide.Auth.LoginRateLimit
  alias Ide.Auth.LoginToken
  alias Ide.Auth.User
  alias Ide.Repo

  setup do
    original_auth = Application.get_env(:ide, Ide.Auth, [])
    original_limits = Application.get_env(:ide, Ide.Auth.LoginRateLimit, [])

    Application.put_env(:ide, Ide.Auth, mode: :public_custom, login_link_ttl_days: 30)
    LoginRateLimit.reset()

    on_exit(fn ->
      Application.put_env(:ide, Ide.Auth, original_auth)
      Application.put_env(:ide, Ide.Auth.LoginRateLimit, original_limits)
      LoginRateLimit.reset()
    end)

    :ok
  end

  test "honeypot submissions show sent screen without sending mail", %{conn: conn} do
    conn =
      post(conn, ~p"/auth/email/continue", %{
        "email" => "bot@example.test",
        LoginBotDefense.honeypot_field() => "Acme Corp"
      })

    assert html_response(conn, 200) =~ "Check your email"
    refute_email_sent()
    refute Repo.get_by(User, email_hash: EmailHash.hash("bot@example.test"))
    assert Repo.all(LoginToken) == []
  end

  test "turnstile is required when configured", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth,
      mode: :public_custom,
      turnstile_site_key: "site-key",
      turnstile_secret_key: "secret-key"
    )

    conn =
      post(conn, ~p"/auth/email/continue", %{
        "email" => "missing-token@example.test"
      })

    assert html_response(conn, 200) =~ "Check your email"
    refute_email_sent()
    assert Repo.all(LoginToken) == []
  end

  test "rate limit blocks additional login emails for the same address", %{conn: _conn} do
    Application.put_env(:ide, Ide.Auth.LoginRateLimit,
      ip: [limit: 100, period_ms: 3_600_000],
      email: [limit: 1, period_ms: 3_600_000]
    )

    LoginRateLimit.reset()

    assert post(build_conn(), ~p"/auth/email/continue", %{"email" => "limited@example.test"})
           |> html_response(200) =~ "Check your email"

    assert_email_sent()

    assert post(build_conn(), ~p"/auth/email/continue", %{"email" => "limited@example.test"})
           |> html_response(200) =~ "Check your email"

    refute_email_sent()
    assert length(Repo.all(LoginToken)) == 1
  end

  test "magic link verify creates user after deferred token issue", %{conn: conn} do
    conn =
      post(conn, ~p"/auth/email/continue", %{
        "email" => "deferred@example.test"
      })

    assert html_response(conn, 200) =~ "Check your email"
    refute Repo.get_by(User, email_hash: EmailHash.hash("deferred@example.test"))

    token =
      assert_email_sent(fn email ->
        [_, token] = Regex.run(~r/token=([^&\s"]+)/, email.html_body)
        token
      end)

    conn = get(build_conn(), ~p"/auth/email/verify?token=#{token}")

    assert redirected_to(conn) == "/projects"
    assert %User{} = Repo.get_by(User, email_hash: EmailHash.hash("deferred@example.test"))
  end
end
