defmodule IdeWeb.WorkspaceLive.PublishUncommittedTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.PublishPaneFlow

  test "does not count dirty files from a parent git repository" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_publish_uncommitted_#{System.unique_integer([:positive])}"
      )

    parent = Path.join(root, "monorepo")
    workspace = Path.join(parent, "workspace_projects/demo")
    File.mkdir_p!(workspace)
    File.write!(Path.join(parent, "toolchain.ex"), "changed\n")
    File.write!(Path.join(workspace, "Main.elm"), "module Main exposing (..)\n")

    on_exit(fn -> File.rm_rf(root) end)

    {_, 0} = System.cmd("git", ["init"], cd: parent, stderr_to_stdout: true)

    {output, 0} =
      System.cmd("git", ["status", "--porcelain"], cd: workspace, stderr_to_stdout: true)

    assert String.split(output, "\n", trim: true) != []

    assert {:error, :git_unavailable_or_not_repo} =
             PublishPaneFlow.workspace_uncommitted_changes(workspace)
  end

  test "counts porcelain lines when the workspace is its own git root" do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "ide_publish_owned_git_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace)
    File.write!(Path.join(workspace, "Main.elm"), "module Main exposing (..)\n")
    on_exit(fn -> File.rm_rf(workspace) end)

    {_, 0} = System.cmd("git", ["init"], cd: workspace, stderr_to_stdout: true)

    assert {:ok, count} = PublishPaneFlow.workspace_uncommitted_changes(workspace)
    assert count >= 1
  end
end
