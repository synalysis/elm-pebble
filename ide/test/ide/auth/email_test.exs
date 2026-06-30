defmodule Ide.Auth.EmailTest do
  use Ide.DataCase, async: true

  import Swoosh.TestAssertions

  alias Ide.Auth
  alias Ide.Auth.Email
  alias Ide.Auth.EmailHash
  alias Ide.Auth.LoginLink
  alias Ide.Auth.LoginToken
  alias Ide.Auth.User
  alias Ide.Repo

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])
    Application.put_env(:ide, Ide.Auth, mode: :public_custom, login_link_ttl_days: 30)
    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original) end)
    :ok
  end

  test "send_login_link creates token and email but not user" do
    assert :ok = Email.send_login_link("dev@example.test")

    refute Repo.get_by(User, email_hash: EmailHash.hash("dev@example.test"))
    assert [%LoginToken{email_hash: hash, user_id: nil}] = Repo.all(LoginToken)
    assert hash == EmailHash.hash("dev@example.test")

    assert_email_sent(fn email ->
      assert email.to == [{"", "dev@example.test"}]
      assert email.subject =~ "Log in"
    end)
  end

  test "send_login_link rejects invalid punycode domain" do
    assert {:error, :invalid_email} = Email.send_login_link("test@xn--y0.net")

    refute Repo.get_by(User, email_hash: EmailHash.hash("test@xn--y0.net"))
  end

  test "verify_login_token creates user on first use" do
    assert :ok = Email.send_login_link("verify@example.test")
    refute Repo.get_by(User, email_hash: EmailHash.hash("verify@example.test"))

    token =
      assert_email_sent(fn email ->
        [_, token] = Regex.run(~r/token=([^&\s"]+)/, email.html_body)
        token
      end)

    assert {:ok, user} = Email.verify_login_token(token)
    assert user.email_hash == EmailHash.hash("verify@example.test")
    assert Repo.get_by(User, email_hash: EmailHash.hash("verify@example.test"))
    assert {:error, :used_token} = Email.verify_login_token(token)
  end

  test "expired token is rejected" do
    user =
      %User{}
      |> User.email_changeset(%{email: "expired@example.test"})
      |> Repo.insert!()

    {raw, hash} = LoginLink.generate()

    expires_at = DateTime.utc_now(:second) |> DateTime.add(-60, :second)

    %LoginToken{}
    |> LoginToken.changeset(%{user_id: user.id, token_hash: hash, expires_at: expires_at})
    |> Repo.insert!()

    assert {:error, :expired_token} = Email.verify_login_token(raw)
  end

  test "Auth mode helpers" do
    Application.put_env(:ide, Ide.Auth, mode: :local)
    assert Auth.app_store_publish_enabled?()
    refute Auth.public_mode?()

    Application.put_env(:ide, Ide.Auth, mode: :public_pebble)
    assert Auth.public_pebble_mode?()
    assert Auth.app_store_publish_enabled?()
    refute Auth.public_custom_mode?()

    Application.put_env(:ide, Ide.Auth, mode: :public_custom)
    assert Auth.public_custom_mode?()
    refute Auth.app_store_publish_enabled?()
  end
end
