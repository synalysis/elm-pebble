defmodule Elmx.TimeQualifiedRewriteTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.QualifiedRewrite
  alias Elmx.Runtime.Pebble

  test "QualifiedRewrite lowers Time.now and Time.getZoneName" do
    assert {:ok, %{op: :runtime_call, function: "elmx_time_now", args: []}} =
             QualifiedRewrite.rewrite("Time.now", [])

    assert {:ok, %{op: :runtime_call, function: "elmx_time_get_zone_name", args: []}} =
             QualifiedRewrite.rewrite("Time.getZoneName", [])
  end

  test "runtime dispatch for Time.now returns Ok posix millis" do
    assert {:Ok, ms} = Pebble.runtime_dispatch("elmx_time_now", [])
    assert is_integer(ms) and ms > 0
  end

  test "runtime dispatch for Time.getZoneName returns Offset ctor" do
    assert {:Ok, %{"ctor" => "Offset", "args" => [offset]}} =
             Pebble.runtime_dispatch("elmx_time_get_zone_name", [])

    assert is_integer(offset)
  end
end
