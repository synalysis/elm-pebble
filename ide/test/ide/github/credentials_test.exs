defmodule Ide.GitHub.CredentialsTest do
  use ExUnit.Case, async: true

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
end
