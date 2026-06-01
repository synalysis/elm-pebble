defmodule ElmExecutor.PebbleWatchPeekBuiltinTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package

  defp mock_ops do
    %{
      call: fn to_msg, [payload] ->
        case to_msg do
          %{"ctor" => ctor} when is_binary(ctor) ->
            {:ok, %{"ctor" => ctor, "args" => [payload]}}

          %{ctor: ctor} when is_binary(ctor) ->
            {:ok, %{ctor: ctor, args: [payload]}}
        end
      end,
      normalize_union_value: fn message, _union -> message end,
      debug_to_string: fn value -> inspect(value) end,
      launch_context: %{}
    }
  end

  test "Elm.Kernel.PebbleWatch.compassCurrent emits compass_peek device command" do
    to_msg = %{"ctor" => "GotHeading", "args" => []}

    assert {:ok,
            %{
              "kind" => "cmd.device.compass_peek",
              "message" => "GotHeading",
              "message_value" => %{
                "ctor" => "GotHeading",
                "args" => [%{"ctor" => "Ok", "args" => [heading]}]
              }
            }} = Package.eval("elm.kernel.pebblewatch", "compasscurrent", [to_msg], mock_ops())

    assert heading["degrees"] == 180.0
    assert heading["isValid"] == true
  end

  test "Elm.Kernel.PebbleWatch.unobstructedCurrentBounds emits unobstructed_bounds_peek device command" do
    to_msg = %{"ctor" => "GotBounds", "args" => []}

    assert {:ok,
            %{
              "kind" => "cmd.device.unobstructed_bounds_peek",
              "message" => "GotBounds",
              "message_value" => %{
                "ctor" => "GotBounds",
                "args" => [bounds]
              }
            }} =
             Package.eval("elm.kernel.pebblewatch", "unobstructedcurrentbounds", [to_msg], mock_ops())

    assert bounds == %{"x" => 0, "y" => 0, "w" => 144, "h" => 168}
  end

  test "Pebble.Compass.current emits compass_peek device command" do
    to_msg = %{"ctor" => "GotHeading", "args" => []}

    assert {:ok, %{"kind" => "cmd.device.compass_peek"}} =
             Package.eval("pebble.compass", "current", [to_msg], mock_ops())
  end

  test "Pebble.UnobstructedArea.currentBounds emits unobstructed_bounds_peek device command" do
    to_msg = %{"ctor" => "GotBounds", "args" => []}

    assert {:ok, %{"kind" => "cmd.device.unobstructed_bounds_peek"}} =
             Package.eval("pebble.unobstructedarea", "currentbounds", [to_msg], mock_ops())
  end
end
