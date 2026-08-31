defmodule IdeWeb.SessionTest do
  use ExUnit.Case, async: false

  alias IdeWeb.Session

  setup do
    original = Application.get_env(:ide, Session, [])
    on_exit(fn -> Application.put_env(:ide, Session, original) end)
    :ok
  end

  test "session cookies are http-only and omit secure in local config" do
    Application.put_env(:ide, Session, secure: false)
    opts = Session.options()

    assert Keyword.fetch!(opts, :http_only) == true
    assert Keyword.fetch!(opts, :secure) == false
    assert Keyword.fetch!(opts, :same_site) == "Lax"
  end

  test "session cookies can be marked secure" do
    Application.put_env(:ide, Session, secure: true)
    assert Keyword.fetch!(Session.options(), :secure) == true
  end
end
