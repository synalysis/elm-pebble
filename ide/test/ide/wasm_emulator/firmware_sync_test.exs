defmodule Ide.WasmEmulator.FirmwareSyncTest do
  use ExUnit.Case, async: false

  alias Ide.WasmEmulator
  alias Ide.WasmEmulator.FirmwareSync

  setup do
    root = Path.join(System.tmp_dir!(), "wasm-firmware-sync-#{System.unique_integer([:positive])}")
    sdk_root = Path.join(root, "sdk-pebble")
    wasm_root = Path.join(root, "wasm")
    qemu_dir = Path.join(sdk_root, "basalt/qemu")
    File.mkdir_p!(qemu_dir)

    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), <<0, 1, 2, 3>>)
    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin"), <<4, 5, 6, 7>>)

    previous_wasm = Application.get_env(:ide, Ide.WasmEmulator, [])
    Application.put_env(:ide, Ide.WasmEmulator, asset_root: wasm_root)

    on_exit(fn ->
      Application.put_env(:ide, Ide.WasmEmulator, previous_wasm)
      File.rm_rf(root)
    end)

    System.put_env("ELM_PEBBLE_QEMU_IMAGE_ROOT", sdk_root)

    on_exit(fn -> System.delete_env("ELM_PEBBLE_QEMU_IMAGE_ROOT") end)

    {:ok, wasm_root: wasm_root}
  end

  test "sync_sdk_firmware copies SDK images into the wasm root", %{wasm_root: wasm_root} do
    assert :ok = FirmwareSync.sync_sdk_firmware()
    assert WasmEmulator.sdk_firmware_available?()

    assert File.regular?(Path.join(wasm_root, "firmware/sdk/basalt/qemu_micro_flash.bin"))
    assert File.regular?(Path.join(wasm_root, "firmware/sdk/basalt/qemu_spi_flash.bin"))
    assert File.regular?(Path.join(wasm_root, "firmware/sdk/manifest.json"))
  end

  test "sync_sdk_firmware converts ELF micro flash using the SDK objcopy", %{wasm_root: wasm_root} do
    data_root = Path.join(System.tmp_dir!(), "wasm-firmware-elf-#{System.unique_integer([:positive])}")
    sdk_pebble_root = Path.join(data_root, ".pebble-sdk/SDKs/current/sdk-core/pebble")
    qemu_dir = Path.join(sdk_pebble_root, "chalk/qemu")
    objcopy = Path.join(data_root, ".pebble-sdk/SDKs/current/toolchain/arm-none-eabi/bin/arm-none-eabi-objcopy")

    File.mkdir_p!(Path.dirname(objcopy))
    File.mkdir_p!(qemu_dir)

    File.write!(objcopy, "#!/bin/sh\nprintf 'raw' > \"$4\"\n")
    File.chmod!(objcopy, 0o755)
    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), <<0x7F, 0x45, 0x4C, 0x46, 0>>)
    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin"), <<4, 5, 6, 7>>)

    previous_data_root = System.get_env("IDE_DATA_ROOT")
    previous_image_root = System.get_env("ELM_PEBBLE_QEMU_IMAGE_ROOT")
    System.put_env("IDE_DATA_ROOT", data_root)
    System.put_env("ELM_PEBBLE_QEMU_IMAGE_ROOT", sdk_pebble_root)

    on_exit(fn ->
      if previous_data_root, do: System.put_env("IDE_DATA_ROOT", previous_data_root), else: System.delete_env("IDE_DATA_ROOT")

      if previous_image_root,
        do: System.put_env("ELM_PEBBLE_QEMU_IMAGE_ROOT", previous_image_root),
        else: System.delete_env("ELM_PEBBLE_QEMU_IMAGE_ROOT")

      File.rm_rf(data_root)
    end)

    assert :ok = FirmwareSync.sync_sdk_firmware()
    assert File.read!(Path.join(wasm_root, "firmware/sdk/chalk/qemu_micro_flash.bin")) == "raw"
  end
end
