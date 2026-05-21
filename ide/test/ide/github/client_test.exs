defmodule Ide.GitHub.ClientTest do
  use ExUnit.Case, async: true

  alias Ide.GitHub.Client

  test "oauth_scope requests public repository access only" do
    assert Client.oauth_scope() == "public_repo"
  end
end
