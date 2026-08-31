defmodule Ide.GitHub.CredentialsTest do
  use ExUnit.Case, async: false

  alias Ide.GitHub.Credentials

  test "stores and clears github credentials" do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "ide_github_credentials_test_#{System.unique_integer([:positive])}.json"
      )

    original = Application.get_env(:ide, Ide.GitHub, [])
    Application.put_env(:ide, Ide.GitHub, Keyword.put(original, :credentials_path, temp_path))

    on_exit(fn ->
      Application.put_env(:ide, Ide.GitHub, original)
      File.rm(temp_path)
    end)

    refute Credentials.connected?()

    assert :ok =
             Credentials.put(%{
               "access_token" => "token-123",
               "scope" => "repo",
               "user_login" => "octocat",
               "user_id" => 42
             })

    assert %{connected?: true, user_login: "octocat", user_id: 42, scope: "repo"} =
             Credentials.current()

    assert :ok = Credentials.clear()
    refute Credentials.connected?()
  end

  test "public mode isolates github credentials per user" do
    data_root =
      Path.join(System.tmp_dir!(), "ide_github_users_#{System.unique_integer([:positive])}")

    original_settings = Application.get_env(:ide, Ide.Settings, [])
    original_auth = Application.get_env(:ide, Ide.Auth, [])

    Application.put_env(:ide, Ide.Settings, Keyword.put(original_settings, :data_root, data_root))
    Application.put_env(:ide, Ide.Auth, Keyword.put(original_auth, :mode, :public_pebble))

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_settings)
      Application.put_env(:ide, Ide.Auth, original_auth)
      Process.delete(:ide_current_user)
      File.rm_rf(data_root)
    end)

    assert {:error, :no_credentials_scope} =
             Credentials.put(%{"access_token" => "orphan-token"})

    Process.put(:ide_current_user, %{id: 1})

    assert :ok = Credentials.put(%{"access_token" => "alice-token", "user_login" => "alice"})
    assert %{connected?: true, access_token: "alice-token"} = Credentials.current()

    Process.put(:ide_current_user, %{id: 2})
    refute Credentials.connected?()

    assert :ok = Credentials.put(%{"access_token" => "bob-token", "user_login" => "bob"})
    assert %{connected?: true, access_token: "bob-token"} = Credentials.current()

    Process.put(:ide_current_user, %{id: 1})
    assert %{connected?: true, access_token: "alice-token"} = Credentials.current()

    assert File.exists?(Path.join(data_root, "users/1/github_credentials.json"))
    assert File.exists?(Path.join(data_root, "users/2/github_credentials.json"))
  end
end
