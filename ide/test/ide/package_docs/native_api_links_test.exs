defmodule Ide.PackageDocs.NativeApiLinksTest do
  use ExUnit.Case, async: true

  alias Ide.PackageDocs.NativeApiLinks

  test "maps watch modules to repebble.com native API docs" do
    assert NativeApiLinks.links_for_module("Pebble.UnobstructedArea") == [
             %{
               "label" => "UnobstructedArea",
               "url" => "https://developer.repebble.com/docs/c/User_Interface/UnobstructedArea/"
             }
           ]

    assert [%{"label" => "HealthService", "url" => health_url}] =
             NativeApiLinks.links_for_module("Pebble.Health")

    assert health_url ==
             "https://developer.repebble.com/docs/c/Foundation/Event_Service/HealthService/"

    assert [%{"label" => "Speaker", "url" => speaker_url}] =
             NativeApiLinks.links_for_module("Pebble.Speaker")

    assert speaker_url ==
             "https://developer.repebble.com/docs/c/User_Interface/Speaker/"
  end

  test "returns empty list for modules without native API bindings" do
    assert NativeApiLinks.links_for_module("Pebble.Game.Math") == []
  end
end
