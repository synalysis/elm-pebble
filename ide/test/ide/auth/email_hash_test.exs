defmodule Ide.Auth.EmailHashTest do
  use ExUnit.Case, async: true

  alias Ide.Auth.EmailHash
  alias Ide.Auth.User

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])
    Application.put_env(:ide, Ide.Auth, email_hash_pepper: "test-email-hash-pepper")
    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original) end)
    :ok
  end

  test "hash is deterministic for normalized email" do
    assert EmailHash.hash(" Dev@Example.Test ") == EmailHash.hash("dev@example.test")
  end

  test "hash changes when pepper changes" do
    first = EmailHash.hash("dev@example.test")

    Application.put_env(:ide, Ide.Auth, email_hash_pepper: "other-pepper")

    assert EmailHash.hash("dev@example.test") != first
  end

  test "normalize_email trims and lowercases" do
    assert User.normalize_email("  Foo@BAR.com ") == "foo@bar.com"
  end
end
