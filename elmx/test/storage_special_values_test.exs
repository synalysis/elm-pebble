defmodule Elmx.StorageSpecialValuesTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.SpecialValues

  test "storage readString targets rewrite to runtime call" do
    key = %{op: :int_literal, value: 42}
    to_msg = %{op: :var, name: "StorageStringLoaded"}

    for target <- [
          "Pebble.Storage.readString",
          "Pebble.Cmd.storageReadString",
          "Elm.Kernel.PebbleWatch.storageReadString"
        ] do
      assert {:ok, %{op: :runtime_call, function: "elmx_storage_read_string", args: [^key, ^to_msg]}} =
               SpecialValues.rewrite(target, [key, to_msg])
    end
  end

  test "runtime storage read string cmd shape" do
    to_msg = %{op: :var, name: "Loaded"}

    cmd =
      Pebble.runtime_dispatch("elmx_storage_read_string", [
        100,
        to_msg
      ])

    assert cmd["kind"] == "cmd.storage.read_string"
    assert cmd["key"] == 100
  end

  test "backlight rewrites to no-op runtime cmd" do
    mode = %{op: :int_literal, value: 1}

    assert {:ok, %{op: :runtime_call, function: "elmx_cmd_backlight", args: [^mode]}} =
             SpecialValues.rewrite("Pebble.Cmd.backlight", [mode])

    assert Cmd.none() == Pebble.runtime_dispatch("elmx_cmd_backlight", [mode])
  end
end
