defmodule Ide.Debugger.GeolocationResponsesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.RuntimeSurfaces

  test "apply_after_step skips geolocation sources" do
    state = RuntimeSurfaces.default_watch()
    ctx = %{}

    assert GeolocationResponses.apply_after_step(state, :watch, "Tick", %{}, "geolocation", ctx) ==
             state
  end

  test "update_branch_requests_command? is false without introspect cmd calls" do
    refute GeolocationResponses.update_branch_requests_command?(%{}, "Tick")
  end
end
