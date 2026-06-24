defmodule Elmx.KernelTargetsTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.KernelTargets

  test "Elm.Kernel.PebbleWatch.onBatteryChange maps to subscription register call" do
    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_subscription_call",
              args: [%{op: :string_literal, value: "Elm.Kernel.PebbleWatch.onBatteryChange"}]
            }} =
             KernelTargets.rewrite("Elm.Kernel.PebbleWatch.onBatteryChange", [])
  end

  test "Elm.Kernel.PebblePhone.httpGet lowers to runtime call" do
    assert {:ok, %{op: :runtime_call, function: "elmx_kernel_pebble_phone_http_get"}} =
             KernelTargets.rewrite("Elm.Kernel.PebblePhone.httpGet", [
               %{op: :string_literal, value: "https://example.com"}
             ])
  end
end
