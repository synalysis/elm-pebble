defmodule Elmx.LaunchContextTest do
  use ExUnit.Case

  alias Elmx.Runtime.LaunchContext

  test "launch_reason_to_int matches Pebble.Platform.launchReasonToInt" do
    assert LaunchContext.launch_reason_to_int(%{"ctor" => "LaunchUser", "args" => []}) == 1
    assert LaunchContext.launch_reason_to_int(%{"ctor" => "LaunchSystem", "args" => []}) == 0
    assert LaunchContext.launch_reason_to_int("LaunchPhone") == 2
    assert LaunchContext.launch_reason_to_int({:LaunchWakeup, []}) == 3
    assert LaunchContext.launch_reason_to_int(%{"ctor" => "LaunchUnknown", "args" => []}) == -1
  end

  test "normalize maps launch_reason string to reason ctor" do
    normalized =
      LaunchContext.normalize(%{
        "launch_reason" => "LaunchUser",
        "watch_profile_id" => "basalt"
      })

    assert normalized["reason"] == %{"ctor" => "LaunchUser", "args" => []}
    assert normalized["watchProfileId"] == "basalt"
    assert Map.get(normalized, "configurationResponse") == nil
  end

  test "normalize is idempotent for round screen shape ctors" do
    once =
      LaunchContext.normalize(%{
        "launch_reason" => "LaunchUser",
        "watch_profile_id" => "gabbro",
        "screen" => %{
          "width" => 260,
          "height" => 260,
          "shape" => "Round",
          "color_mode" => "Color"
        }
      })

    twice = LaunchContext.normalize(once)

    assert once["screen"]["shape"] == %{"ctor" => "Round", "args" => []}
    assert twice["screen"]["shape"] == %{"ctor" => "Round", "args" => []}
    assert twice["screen"]["width"] == 260
    assert twice["screen"]["is_round"] == true
  end

  test "normalize preserves round shape when screen shape is already a ctor map" do
    normalized =
      LaunchContext.normalize(%{
        "launch_reason" => "LaunchUser",
        "screen" => %{
          "width" => 260,
          "height" => 260,
          "shape" => %{"ctor" => "Round", "args" => []}
        }
      })

    assert normalized["screen"]["shape"] == %{"ctor" => "Round", "args" => []}
    assert normalized["screen"]["is_round"] == true
  end
end
