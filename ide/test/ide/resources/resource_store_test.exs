defmodule Ide.Resources.ResourceStoreTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.ResourceStore

  test "generated modules are read-only across editor path variants" do
    assert ResourceStore.read_only_generated_module?("watch", "src/Pebble/Ui/Resources.elm")
    assert ResourceStore.read_only_generated_module?("watch", "Pebble/Ui/Resources.elm")
    assert ResourceStore.read_only_generated_module?("watch", "Pebble/Ui/Resources")
    assert ResourceStore.read_only_generated_module?("/phone/", "/Companion/GeneratedPreferences")

    refute ResourceStore.read_only_generated_module?("watch", "src/Main.elm")
    refute ResourceStore.read_only_generated_module?("protocol", "src/Companion/Types.elm")
  end
end
