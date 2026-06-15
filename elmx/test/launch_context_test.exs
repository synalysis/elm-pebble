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
end
