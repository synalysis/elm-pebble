defmodule Ide.Debugger.DeviceDataHintsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.DeviceDataHints
  alias Ide.Debugger.RuntimeSurfaces

  defp base_state do
    RuntimeSurfaces.default_watch()
    |> Map.put(:watch, RuntimeSurfaces.default_watch())
    |> Map.put_new(:companion, RuntimeSurfaces.default_companion())
    |> Map.put_new(:phone, RuntimeSurfaces.default_phone())
    |> update_in([:watch, :model, "runtime_model"], fn rm ->
      Map.merge(rm || %{}, %{"clock_style_24h" => false})
    end)
  end

  test "apply_to_state stores boolean preview values on runtime model" do
    req = %{
      kind: "clock_style_24h",
      response_message: "ClockStyleChanged",
      preview: true
    }

    updated = DeviceDataHints.apply_to_state(base_state(), :watch, req)

    assert get_in(updated, [:watch, :model, "runtime_model", "clock_style_24h"]) == true
    assert get_in(updated, [:watch, :model, "debugger_device_clock_style_24h"]) == true
  end
end
