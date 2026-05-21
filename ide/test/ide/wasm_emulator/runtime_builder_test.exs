defmodule Ide.WasmEmulator.RuntimeBuilderTest do
  use ExUnit.Case, async: false

  alias Ide.WasmEmulator
  alias Ide.WasmEmulator.RuntimeBuilder

  @runtime_assets ~w(qemu-system-arm.js qemu-system-arm.wasm qemu-system-arm.worker.js)

  setup do
    previous_wasm = Application.get_env(:ide, Ide.WasmEmulator, [])
    previous_build = Application.get_env(:ide, :wasm_emulator_build_on_start)

    root =
      Path.join(System.tmp_dir!(), "elm-pebble-wasm-builder-#{System.unique_integer([:positive])}")

    assets = Path.join(root, "assets")
    File.mkdir_p!(assets)

    Application.put_env(:ide, Ide.WasmEmulator, asset_root: assets)
    Application.put_env(:ide, :wasm_emulator_build_on_start, false)

    on_exit(fn ->
      Application.put_env(:ide, Ide.WasmEmulator, previous_wasm)
      Application.put_env(:ide, :wasm_emulator_build_on_start, previous_build)
      File.rm_rf(root)
    end)

    {:ok, assets: assets}
  end

  test "build_status reports missing runtime assets", %{assets: assets} do
    status = RuntimeBuilder.build_status()

    assert status.status == "missing"
    assert status.in_progress? == false
    assert status.log_path == Path.join(assets, "build.log")
  end

  test "build_status reports ready when runtime assets exist", %{assets: assets} do
    for asset <- @runtime_assets do
      File.write!(Path.join(assets, asset), asset)
    end

    status = RuntimeBuilder.build_status()

    assert status.status == "ready"
    assert status.in_progress? == false
  end

  test "wasm emulator status includes runtime_build", %{assets: assets} do
    for asset <- @runtime_assets do
      File.write!(Path.join(assets, asset), asset)
    end

    status = WasmEmulator.status()

    assert status.runtime_build.status == "ready"
    assert status.runtime_build.in_progress? == false
  end
end
