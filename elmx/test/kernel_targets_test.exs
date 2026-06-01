defmodule Elmx.KernelTargetsTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.KernelTargets

  test "Elm.Kernel.PebbleWatch.onBatteryChange maps to subscription mask" do
    assert {:ok, %{op: :int_literal, value: 32}} =
             KernelTargets.rewrite("Elm.Kernel.PebbleWatch.onBatteryChange", [])
  end

  test "Elm.Kernel.PebblePhone.httpGet lowers to runtime call" do
    assert {:ok, %{op: :runtime_call, function: "elmx_kernel_pebble_phone_http_get"}} =
             KernelTargets.rewrite("Elm.Kernel.PebblePhone.httpGet", [
               %{op: :string_literal, value: "https://example.com"}
             ])
  end
end
