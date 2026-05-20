defmodule Ide.ProjectBundleTest do
  use ExUnit.Case, async: true

  alias Ide.ProjectBundle

  test "latest_pbw_path finds newest pbw under a directory" do
    dir = Path.join(System.tmp_dir!(), "pbw-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    older = Path.join(dir, "old.pbw")
    newer = Path.join(dir, "new.pbw")
    File.write!(older, "old")
    File.write!(newer, "new")
    File.touch!(older, {{2020, 1, 1}, {0, 0, 0}})
    File.touch!(newer, {{2025, 1, 1}, {0, 0, 0}})

    assert ProjectBundle.latest_pbw_path(dir) == newer
  end

  test "workspace_latest_pbw_path prefers pebble-sdk build output" do
    root = Path.join(System.tmp_dir!(), "pbw-ws-#{System.unique_integer([:positive])}")
    build_dir = Path.join(root, ".pebble-sdk/app/build")
    publish_dir = Path.join(root, ".elm-pebble-publish")
    File.mkdir_p!(build_dir)
    File.mkdir_p!(publish_dir)
    on_exit(fn -> File.rm_rf!(root) end)

    build_pbw = Path.join(build_dir, "game.pbw")
    publish_pbw = Path.join(publish_dir, "stale.pbw")
    File.write!(build_pbw, "build")
    File.write!(publish_pbw, "publish")
    File.touch!(publish_pbw, {{2026, 1, 1}, {0, 0, 0}})

    assert ProjectBundle.workspace_latest_pbw_path(root) == build_pbw
  end
end
