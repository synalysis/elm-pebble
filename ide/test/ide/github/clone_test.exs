defmodule Ide.GitHub.CloneTest do
  use ExUnit.Case, async: true

  alias Ide.GitHub.Clone

  test "parse_repo_ref accepts owner/repo" do
    assert {:ok, %{owner: "pebbledev", repo: "counter", branch: "main"}} =
             Clone.parse_repo_ref("pebbledev/counter")
  end

  test "parse_repo_ref accepts https github url" do
    assert {:ok, %{owner: "my-org", repo: "my-app", branch: "main"}} =
             Clone.parse_repo_ref("https://github.com/my-org/my-app.git")
  end

  test "parse_repo_ref accepts git@github.com ssh url" do
    assert {:ok, %{owner: "my-org", repo: "my-app", branch: "main"}} =
             Clone.parse_repo_ref("git@github.com:my-org/my-app.git")
  end

  test "parse_repo_ref rejects empty input" do
    assert {:error, :empty_repo_ref} = Clone.parse_repo_ref("")
  end
end
