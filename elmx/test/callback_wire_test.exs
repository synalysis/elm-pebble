defmodule Elmx.CallbackWireTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Cmd.Wire

  test "message_wire resolves curried Msg constructor callback" do
    callback = fn payload -> {:GotHeading, payload} end

    assert {"GotHeading", %{"ctor" => "GotHeading", "args" => []}} =
             Wire.message_wire(callback)
  end

  test "callback_ctor_name returns nil for unrelated functions" do
    assert Wire.callback_ctor_name(fn x -> x + 1 end) == nil
  end
end
