defmodule Elmx.SpecialValuesCmdTest do
  use ExUnit.Case

  alias Elmx.Runtime.Pebble.SpecialValues

  test "Pebble.Cmd.getCurrentTimeString rewrites to device time cmd" do
    assert {:ok, %{op: :runtime_call, function: "elmx_time_current_time_string", args: [_]}} =
             SpecialValues.rewrite("Pebble.Cmd.getCurrentTimeString", [
               %{op: :constructor_call, ctor: "CurrentTimeString", args: []}
             ])
  end
end
