defmodule Elmx.DispatchModulesTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.Dispatch
  alias Elmx.Runtime.Pebble.Dispatch.Basics
  alias Elmx.Runtime.Pebble.Dispatch.Companion
  alias Elmx.Runtime.Pebble.Dispatch.Effects
  alias Elmx.Runtime.Pebble.Dispatch.Json
  alias Elmx.Runtime.Pebble.Dispatch.Platform
  alias Elmx.Runtime.Pebble.Dispatch.Storage

  test "Basics math and list helpers" do
    assert Basics.math_clamp([0, 10, 20]) == 10
    assert Basics.list_cons([1, [2, 3]]) == [1, 2, 3]
    assert Basics.collision_rect_rect([%{"x" => 0, "y" => 0, "w" => 2, "h" => 2}, %{"x" => 1, "y" => 1, "w" => 2, "h" => 2}])
  end

  test "Effects produce wire commands" do
    assert %{"kind" => "none"} = Effects.events_batch([])
    assert %{"kind" => _} = Effects.light_enable([])
  end

  test "Storage read cmd" do
    cmd = Storage.read_int_cmd([1, "Loaded", 0])
    assert %{"kind" => "cmd.storage.read_int", "key" => 1} = cmd
  end

  test "Companion send cmd" do
    assert %{"kind" => "protocol"} = Companion.send_cmd(["msg"])
  end

  test "Companion send cmd encodes tag+value watch wire" do
    assert %{
             "kind" => "protocol",
             "direction" => "watch_to_phone",
             "message" => "tag:2",
             "message_value" => %{"tag" => 2, "value" => 5}
           } = Companion.send_cmd([2, 5])
  end

  test "Platform launch reason" do
    assert is_integer(Platform.launch_reason([%{"ctor" => "LaunchUser", "args" => []}]))
  end

  test "Json encode object" do
    assert Json.encode_object([[{"a", 1}]]) == {:elmx_json_object, [{"a", 1}]}
    assert Json.encode_encode([0, Json.encode_object([[{"a", 1}]])]) == ~s({"a":1})
  end

  test "Dispatch defdelegates preserve registry entry points" do
    assert %{"kind" => "none"} = Dispatch.events_batch([])
    assert Dispatch.math_clamp([0, 1, 2]) == 1
    assert %{"kind" => _} = Dispatch.companion_send_cmd(["x"])
  end
end
