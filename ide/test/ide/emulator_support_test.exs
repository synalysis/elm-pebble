defmodule Ide.EmulatorSupportTest do
  use ExUnit.Case, async: true

  alias Ide.EmulatorSupport

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])
    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original) end)
    :ok
  end

  test "local mode includes external emulator for basalt" do
    Application.put_env(:ide, Ide.Auth, mode: :local)

    assert "external" in EmulatorSupport.supported_modes("basalt")
    assert {"External Pebble emulator", "external"} in EmulatorSupport.mode_options("basalt")
  end

  test "public_pebble mode excludes external emulator" do
    Application.put_env(:ide, Ide.Auth, mode: :public_pebble)

    refute EmulatorSupport.external_mode_enabled?()
    refute EmulatorSupport.wasm_mode_enabled?()
    refute "external" in EmulatorSupport.supported_modes("basalt")
    refute "wasm" in EmulatorSupport.supported_modes("basalt")
    refute "external" in EmulatorSupport.allowed_mode_ids()
    refute "wasm" in EmulatorSupport.allowed_mode_ids()

    assert EmulatorSupport.normalize_mode("basalt", "external") == "embedded"
    assert EmulatorSupport.normalize_mode("basalt", "wasm") == "embedded"
  end

  test "public_custom mode excludes external and wasm emulators" do
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    refute "external" in EmulatorSupport.supported_modes("chalk")
    refute "wasm" in EmulatorSupport.supported_modes("emery")
    assert EmulatorSupport.normalize_mode("chalk", "external") == "embedded"
    assert EmulatorSupport.normalize_mode("emery", "wasm") == "embedded"
  end

  test "local mode includes wasm emulator for basalt" do
    Application.put_env(:ide, Ide.Auth, mode: :local)

    assert EmulatorSupport.wasm_mode_enabled?()
    assert "wasm" in EmulatorSupport.supported_modes("basalt")
    assert {"WASM in browser", "wasm"} in EmulatorSupport.mode_options("basalt")
  end
end
