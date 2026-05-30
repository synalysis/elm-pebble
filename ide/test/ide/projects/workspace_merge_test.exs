defmodule Ide.Projects.WorkspaceMergeTest do
  use ExUnit.Case, async: true

  alias Ide.Projects.WorkspaceMerge

  test "merge_tree adds files without removing existing siblings" do
    target = Path.join(System.tmp_dir!(), "merge_target_#{System.unique_integer([:positive])}")
    source = Path.join(System.tmp_dir!(), "merge_source_#{System.unique_integer([:positive])}")

    on_exit(fn ->
      File.rm_rf(target)
      File.rm_rf(source)
    end)

    File.mkdir_p!(Path.join(target, "src"))
    File.write!(Path.join(target, "src/Main.elm"), "existing")
    File.write!(Path.join(target, "keep.txt"), "stay")

    File.mkdir_p!(Path.join(source, "src"))
    File.write!(Path.join(source, "src/Battle.elm"), "new")
    File.write!(Path.join(source, "src/Main.elm"), "overwrite")

    assert :ok = WorkspaceMerge.merge_tree(source, target)

    assert File.read!(Path.join(target, "src/Main.elm")) == "overwrite"
    assert File.read!(Path.join(target, "src/Battle.elm")) == "new"
    assert File.read!(Path.join(target, "keep.txt")) == "stay"
  end
end
