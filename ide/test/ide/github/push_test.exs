defmodule Ide.GitHub.PushTest do
  use ExUnit.Case, async: true

  alias Ide.GitHub.Push
  alias Ide.Projects.Project

  test "push mirror gitignore excludes sdk and publish staging dirs" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_github_push_test_#{System.unique_integer([:positive])}"
      )

    workspace = Path.join(root, "workspace")
    File.mkdir_p!(Path.join(workspace, ".pebble-sdk/app"))
    File.mkdir_p!(Path.join(workspace, ".elm-pebble-publish/screenshots"))
    File.mkdir_p!(Path.join(workspace, "screenshots/basalt"))
    File.mkdir_p!(Path.join(workspace, "src"))
    File.write!(Path.join(workspace, "screenshots/basalt/basalt_shot_1.png"), "png")
    File.write!(Path.join(workspace, "src/Main.elm"), "module Main exposing (..)\n")

    on_exit(fn -> File.rm_rf(root) end)

    project = %Project{name: "Demo", target_type: "watchface"}
    mirror = Path.join(workspace, Push.mirror_dir())

    assert {:ok, ^mirror, true} = Push.mirror_sync_and_commit(workspace)
    assert {:ok, true} = Push.mirror_write_readme_and_commit(mirror, project)

    {output, 0} = System.cmd("git", ["ls-files"], cd: mirror, stderr_to_stdout: true)
    tracked = String.split(output, "\n", trim: true)

    assert "src/Main.elm" in tracked
    assert "README.md" in tracked
    readme = File.read!(Path.join(mirror, "README.md"))
    assert readme =~ "https://elm-pebble.dev"
    assert Enum.any?(tracked, &String.starts_with?(&1, "screenshots/"))
    refute Enum.any?(tracked, &String.starts_with?(&1, ".pebble-sdk/"))
    refute Enum.any?(tracked, &String.starts_with?(&1, ".elm-pebble-publish/"))
    refute Enum.any?(tracked, &String.starts_with?(&1, ".elm-pebble-github/"))
  end

  test "mirror adds commits for changes only and skips empty commits" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_github_push_mirror_#{System.unique_integer([:positive])}"
      )

    workspace = Path.join(root, "workspace")
    File.mkdir_p!(Path.join(workspace, "src"))
    File.write!(Path.join(workspace, "src/Main.elm"), "module Main exposing (..)\n\na = 1\n")
    File.write!(Path.join(workspace, "src/Other.elm"), "module Other exposing (..)\n")

    on_exit(fn -> File.rm_rf(root) end)

    assert {:ok, mirror, true} =
             Push.mirror_sync_and_commit(workspace, commit_message: "first")

    {count_after_first, 0} =
      System.cmd("git", ["rev-list", "--count", "HEAD"], cd: mirror, stderr_to_stdout: true)

    assert String.trim(count_after_first) == "1"

    assert {:ok, ^mirror, false} =
             Push.mirror_sync_and_commit(workspace, commit_message: "unchanged")

    {count_after_unchanged, 0} =
      System.cmd("git", ["rev-list", "--count", "HEAD"], cd: mirror, stderr_to_stdout: true)

    assert String.trim(count_after_unchanged) == "1"

    File.write!(Path.join(workspace, "src/Main.elm"), "module Main exposing (..)\n\na = 2\n")

    assert {:ok, ^mirror, true} =
             Push.mirror_sync_and_commit(workspace, commit_message: "second")

    {stat, 0} =
      System.cmd("git", ["diff", "--stat", "HEAD~1", "HEAD"], cd: mirror, stderr_to_stdout: true)

    assert stat =~ "Main.elm"
    refute stat =~ "Other.elm"

    {log, 0} = System.cmd("git", ["log", "--oneline"], cd: mirror, stderr_to_stdout: true)
    assert log =~ "first"
    assert log =~ "second"
    refute log =~ "unchanged"
  end
end
