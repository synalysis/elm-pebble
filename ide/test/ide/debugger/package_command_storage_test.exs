defmodule Ide.Debugger.PackageCommandStorageTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.PackageCommandHandler

  test "storage read_max_size uses profile-specific capacity" do
    row = %{
      "source" => "runtime_followup",
      "package" => "elm-pebble/elm-watch",
      "command" => %{"kind" => "cmd.storage.read_max_size"},
      "message" => "StorageMax"
    }

    assert {:handled, _state, %{response: 4096}, _} =
             PackageCommandHandler.handle(%{watch_profile_id: "aplite"}, "watch", "elm-pebble/elm-watch", row)

    assert {:handled, _state, %{response: 65_536}, _} =
             PackageCommandHandler.handle(%{watch_profile_id: "emery"}, "watch", "elm-pebble/elm-watch", row)
  end
end
