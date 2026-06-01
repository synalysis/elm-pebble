defmodule Elmx.RuntimeDispatchCoverageTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble

  @special_values_glob Path.expand("../lib/elmx/runtime/pebble/special_values/**/*.ex", __DIR__)
  @pebble_ex Path.expand("../lib/elmx/runtime/pebble.ex", __DIR__)

  @ui_call_re ~r/ui_call\("(elmx_[a-z0-9_]+)"/
  @runtime_call_re ~r/function: "(elmx_[a-z0-9_]+)"/
  @dispatch_clause_re ~r/"(elmx_[a-z0-9_]+)"\s*->/

  test "static SpecialValues runtime functions are handled by runtime_dispatch" do
    emitted = emitted_runtime_functions()
    handled = explicit_dispatch_functions()
    kernel_fallback? = File.read!(@pebble_ex) =~ "kernel_runtime_function?(other)"

    missing =
      emitted
      |> Enum.reject(&(&1 in handled))
      |> Enum.reject(&(kernel_fallback? and kernel_function?(&1)))

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

  defp explicit_dispatch_functions do
    @pebble_ex
    |> File.read!()
    |> then(&Regex.scan(@dispatch_clause_re, &1, capture: :all_but_first))
    |> List.flatten()
    |> MapSet.new()
  end

  defp kernel_function?(name), do: String.starts_with?(name, "elmx_kernel_pebble_")
end
