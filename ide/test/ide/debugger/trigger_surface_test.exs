defmodule Ide.Debugger.TriggerSurfaceTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.TriggerSurface

  test "display_for falls back when introspect is empty" do
    assert TriggerSurface.display_for(
             %{},
             "on_tick",
             "watch",
             fn _st, _t -> %{} end,
             fn "watch" -> :watch end
           ) =~ "Tick"
  end

  test "candidates returns empty list for unknown target" do
    assert TriggerSurface.candidates(%{}, :watch, %{}) == []
  end
end
