defmodule Ide.Packages.ElmSourceDocsTest do
  use Ide.DataCase, async: true

  alias Ide.InternalPackages
  alias Ide.Packages
  alias Ide.Packages.ElmSourceDocs

  test "builds module markdown from internal Pebble source docs" do
    assert {:ok, markdown} =
             ElmSourceDocs.module_doc_markdown(
               InternalPackages.pebble_elm_src_abs(),
               "Pebble.Cmd"
             )

    assert markdown =~ "# `Pebble.Cmd`"
    assert markdown =~ "## Functions and values"
    assert markdown =~ "### `timerAfter`"
    assert markdown =~ "Run a command after"
  end

  test "lists module names from internal Pebble source root" do
    assert {:ok, modules} = ElmSourceDocs.list_modules(InternalPackages.pebble_elm_src_abs())
    assert "Pebble.Cmd" in modules
    assert "Pebble.Events" in modules
    assert "Pebble.Platform" in modules
    assert "Pebble.Ui" in modules
    refute Enum.any?(modules, &String.starts_with?(&1, "Elm.Kernel."))
  end

  test "Packages.module_doc_markdown serves builtin Pebble docs from source" do
    assert {:ok, markdown} =
             Packages.module_doc_markdown(
               "elm-pebble/elm-watch",
               "latest",
               "Pebble.Platform"
             )

    assert markdown =~ "# `Pebble.Platform`"
    assert markdown =~ "## Union types"
    assert markdown =~ "### `LaunchReason`"
    assert markdown =~ "### `application`"
  end
end
