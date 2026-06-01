defmodule Ide.Debugger.DeviceDataHintsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CompileContract
  alias Ide.Debugger.DeviceDataHints
  alias Ide.Debugger.RuntimeModelNormalize
  alias Ide.Debugger.RuntimeSurfaces

  defp introspect do
    dir = Path.expand("../../../priv/project_templates/watchface_poke_battle", __DIR__)
    {:ok, contract} = CompileContract.build_for_project_dir(dir)
    contract
  end

  defp base_state(runtime_model) do
    contract = introspect()

    RuntimeSurfaces.default_watch()
    |> Map.put(:watch, RuntimeSurfaces.default_watch())
    |> Map.put_new(:companion, RuntimeSurfaces.default_companion())
    |> Map.put_new(:phone, RuntimeSurfaces.default_phone())
    |> update_in([:watch, :model], fn model ->
      model
      |> Map.put("runtime_model", runtime_model)
      |> Map.put("debugger_contract", contract)
    end)
    |> update_in([:watch, :shell], fn shell ->
      Map.put(shell || %{}, "debugger_contract", contract)
    end)
  end

  test "clock_style_24h maps to declared use24Hour field, not clock_style_24h" do
    runtime_model = %{
      "use24Hour" => false,
      "screenW" => 144,
      "screenH" => 168
    }

    req = %{
      kind: "clock_style_24h",
      response_message: "ClockStyle24h",
      preview: true
    }

    updated = DeviceDataHints.apply_to_state(base_state(runtime_model), :watch, req)

    rm = get_in(updated, [:watch, :model, "runtime_model"])
    assert rm["use24Hour"] == true
    refute Map.has_key?(rm, "clock_style_24h")
  end

  test "against_introspect drops fields not in init_model" do
    model = %{"debugger_contract" => introspect()}

    runtime_model = %{
      "use24Hour" => true,
      "clock_style_24h" => true,
      "screenW" => 144
    }

    normalized = RuntimeModelNormalize.against_introspect(runtime_model, model)
    assert normalized["use24Hour"] == true
    refute Map.has_key?(normalized, "clock_style_24h")
  end
end
