defmodule Elmx.PebbleRegistryCompileTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Pebble.Registry

  test "Registry.compile_call emits list-wrapped Dispatch helpers" do
    assert {:ok, code} = Registry.compile_call("elmx_math_clamp", ["0", "10", "20"])
    assert code == "Elmx.Runtime.Pebble.Dispatch.math_clamp([0, 10, 20])"
  end

  test "Registry.compile_call emits splatted Ui helpers" do
    assert {:ok, code} = Registry.compile_call("elmx_ui_window_stack", ["windows"])
    assert code == "Elmx.Runtime.Pebble.Ui.window_stack(windows)"
  end

  test "Registry.compile_call emits keyed context settings" do
    assert {:ok, code} = Registry.compile_call("elmx_ui_stroke_width", ["2"])
    assert code ==
             "Elmx.Runtime.Pebble.Dispatch.ui_context_setting(\"stroke_width\", [2])"
  end

  test "Generator.compile_call resolves elmx symbols before stdlib fallback" do
    assert {:ok, code} = Generator.compile_call("elmx_light_enable", [])
    assert code == "Elmx.Runtime.Pebble.Dispatch.light_enable([])"
  end

  test "Generator.known? includes elmx registry symbols" do
    assert Generator.known?("elmx_http_get")
    assert Generator.known?("elmc_list_map")
  end
end
