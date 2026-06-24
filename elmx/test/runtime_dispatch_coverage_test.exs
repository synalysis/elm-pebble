defmodule Elmx.RuntimeDispatchCoverageTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.Dispatch
  alias Elmx.Runtime.Pebble.Registry

  @special_values_glob Path.expand("../lib/elmx/runtime/pebble/special_values/**/*.ex", __DIR__)

  @ui_call_re ~r/ui_call\("(elmx_[a-z0-9_]+)"/
  @runtime_call_re ~r/function: "(elmx_[a-z0-9_]+)"/

  test "static SpecialValues runtime functions are handled by runtime_dispatch" do
    emitted = emitted_runtime_functions()
    handled = Registry.handlers() |> Map.keys() |> MapSet.new()

    missing =
      emitted
      |> Enum.reject(&(&1 in handled))
      |> Enum.reject(&Dispatch.kernel_runtime_function?/1)

    assert missing == [],
           """
           runtime_dispatch/2 is missing #{length(missing)} function(s) emitted by SpecialValues:
           #{Enum.join(missing, "\n")}
           """
  end

  test "companion connectivity bridge dispatch returns companion bridge cmd" do
    cmd =
      Pebble.runtime_dispatch("elmx_companion_bridge_cmd", [
        "network",
        "status",
        "GotConnectivity"
      ])

    assert cmd["kind"] == "cmd.companion.bridge"
    assert cmd["api"] == "network"
    assert cmd["op"] == "status"
    assert cmd["callback_constructor"] == "GotConnectivity"
  end

  test "registry handlers apply without raising for a sample of symbols" do
    assert Registry.apply("elmx_light_enable", [])["kind"] == "cmd.effect.light"
    assert Registry.apply("elmx_math_clamp", [0, 10, 20]) == 10
    assert is_map(Registry.apply("elmx_ui_window_stack", [[]]))
  end

  defp emitted_runtime_functions do
    @special_values_glob
    |> Path.wildcard()
    |> Enum.flat_map(&extract_runtime_functions/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_runtime_functions(path) do
    path
    |> File.read!()
    |> then(fn text ->
      Regex.scan(@ui_call_re, text, capture: :all_but_first) ++
        Regex.scan(@runtime_call_re, text, capture: :all_but_first)
    end)
    |> List.flatten()
  end
end
