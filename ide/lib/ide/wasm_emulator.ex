defmodule Ide.WasmEmulator do
  @moduledoc """
  Local asset boundary for the browser-hosted Pebble QEMU WASM emulator.
  """

  @runtime_assets [
    "qemu-system-arm.js",
    "qemu-system-arm.wasm",
    "qemu-system-arm.worker.js"
  ]

  @sdk_platforms ~w(aplite basalt chalk diorite emery flint gabbro)

  @firmware_assets [
    "firmware/sdk/qemu_micro_flash.bin",
    "firmware/sdk/qemu_spi_flash.bin",
    "firmware/sdk/manifest.json"
  ]

  @required_assets @runtime_assets ++ @firmware_assets

  @optional_assets [
    "firmware/full/qemu_micro_flash.bin",
    "firmware/full/qemu_spi_flash.bin",
    "firmware/full/manifest.json"
  ]

  @spec asset_root() :: String.t()
  def asset_root do
    case System.get_env("ELM_PEBBLE_WASM_EMULATOR_ROOT") do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        Application.get_env(:ide, __MODULE__, [])
        |> Keyword.get(:asset_root, Path.expand("../../priv/wasm_emulator", __DIR__))
    end
  end

  @spec status() :: map()
  def status do
    root = asset_root()
    runtime_missing = Enum.reject(@runtime_assets, &File.regular?(Path.join(root, &1)))
    firmware_missing = Enum.reject(@firmware_assets, &File.regular?(Path.join(root, &1)))
    sdk_firmware_available? = sdk_firmware_available?(root)
    effective_firmware_missing = if sdk_firmware_available?, do: [], else: firmware_missing
    missing = runtime_missing ++ effective_firmware_missing
    optional_missing = Enum.reject(@optional_assets, &File.regular?(Path.join(root, &1)))
    install_bridge = install_bridge_status(root)
    firmware = firmware_status(root)

    %{
      available?: missing == [],
      root: root,
      required: @required_assets,
      missing: missing,
      runtime_missing: runtime_missing,
      firmware_missing: effective_firmware_missing,
      optional_missing: optional_missing,
      firmware: firmware,
      asset_base: "/wasm-emulator/assets/",
      install_bridge: install_bridge,
      setup: setup(root)
    }
  end

  defp firmware_status(root) do
    %{
      sdk: sdk_firmware_status(root),
      full: full_firmware_status(root)
    }
  end

  defp sdk_firmware_status(root) do
    legacy = firmware_manifest(Path.join([root, "firmware", "sdk", "manifest.json"]))

    platforms =
      @sdk_platforms
      |> Enum.reduce(%{}, fn platform, acc ->
        manifest_path = Path.join([root, "firmware", "sdk", platform, "manifest.json"])

        case firmware_manifest(manifest_path) do
          nil -> acc
          manifest -> Map.put(acc, platform, manifest)
        end
      end)

    cond do
      map_size(platforms) > 0 ->
        %{"platforms" => platforms, "legacy" => legacy}

      legacy ->
        legacy

      true ->
        nil
    end
  end

  defp sdk_firmware_available?(root) do
    legacy_dir = Path.join([root, "firmware", "sdk"])

    legacy? =
      File.regular?(Path.join(legacy_dir, "qemu_micro_flash.bin")) and
        File.regular?(Path.join(legacy_dir, "qemu_spi_flash.bin")) and
        File.regular?(Path.join(legacy_dir, "manifest.json"))

    platform? =
      Enum.any?(@sdk_platforms, fn platform ->
        dir = Path.join([root, "firmware", "sdk", platform])

        File.regular?(Path.join(dir, "qemu_micro_flash.bin")) and
          File.regular?(Path.join(dir, "qemu_spi_flash.bin")) and
          File.regular?(Path.join(dir, "manifest.json"))
      end)

    legacy? or platform?
  end

  defp full_firmware_status(root) do
    manifest_path = Path.join([root, "firmware", "full", "manifest.json"])

    case firmware_manifest(manifest_path) do
      nil -> fallback_full_firmware_status(root)
      manifest -> manifest
    end
  end

  defp fallback_full_firmware_status(root) do
    full_dir = Path.join([root, "firmware", "full"])

    if File.regular?(Path.join(full_dir, "qemu_micro_flash.bin")) and
         File.regular?(Path.join(full_dir, "qemu_spi_flash.bin")) do
      %{
        "platform" => "emery",
        "machine" => "pebble-snowy-emery-bb",
        "spi_flash_size" => nil,
        "manifest" => "fallback"
      }
    end
  end

  defp firmware_manifest(path) do
    with {:ok, data} <- File.read(path),
         {:ok, decoded} <- Jason.decode(data) do
      decoded
    else
      _ -> nil
    end
  end

  defp setup(root) do
    %{
      upstream_url: "https://github.com/ericmigi/pebble-qemu-wasm",
      runtime_target: root,
      sdk_firmware_target: Path.join([root, "firmware", "sdk"]),
      full_firmware_target: Path.join([root, "firmware", "full"]),
      build_command: "docker compose run --rm wasm-emulator-builder",
      auto_build_command: "COMPOSE_PROFILES=wasm-emulator docker compose up -d",
      notes: [
        "Copy qemu-system-arm.js, qemu-system-arm.wasm, and qemu-system-arm.worker.js from the upstream web/ directory into the runtime target.",
        "To build those runtime files locally, run scripts/build_wasm_emulator_runtime.sh, or use docker compose run --rm wasm-emulator-builder.",
        "Copy qemu_micro_flash.bin and decompressed qemu_spi_flash.bin into firmware/sdk/<platform>. The legacy firmware/sdk path is still supported for a single SDK image. Firmware binaries are not committed by this project.",
        "For app install, the WASM runtime must expose Module.pebbleInstallPbw(plan), Module.pebbleControlSend(bytes) and Module.pebbleControlRecv(), or the patched _pebble_control_wasm_send/_pebble_control_wasm_recv exports.",
        "Optional full firmware can be copied into firmware/full with the same filenames."
      ]
    }
  end

  defp install_bridge_status(root) do
    loader = Path.join(root, "qemu-system-arm.js")

    %{
      required_api:
        "Module.pebbleInstallPbw(plan), Module.pebbleControlSend(bytes) + Module.pebbleControlRecv(), or _pebble_control_wasm_send/_pebble_control_wasm_recv",
      available?: install_bridge_available?(loader)
    }
  end

  defp install_bridge_available?(loader) do
    case File.read(loader) do
      {:ok, source} ->
        String.contains?(source, "pebbleInstallPbw") or
          (String.contains?(source, "pebbleControlSend") and
             String.contains?(source, "pebbleControlRecv")) or
          (String.contains?(source, "pebble_control_wasm_send") and
             String.contains?(source, "pebble_control_wasm_recv"))

      {:error, _reason} ->
        false
    end
  end

  @spec asset_path(String.t()) :: {:ok, String.t()} | {:error, term()}
  def asset_path(path) when is_binary(path) do
    root = Path.expand(asset_root())
    requested = Path.expand(Path.join(root, path))
    root_with_sep = root <> "/"

    cond do
      not String.starts_with?(requested, root_with_sep) ->
        {:error, :invalid_asset_path}

      File.regular?(requested) ->
        {:ok, requested}

      true ->
        {:error, :not_found}
    end
  end

  def asset_path(_), do: {:error, :invalid_asset_path}

  @spec content_type(String.t()) :: String.t()
  def content_type(path) do
    case Path.extname(path) do
      ".html" -> "text/html"
      ".js" -> "application/javascript"
      ".wasm" -> "application/wasm"
      ".worker" -> "application/javascript"
      ".json" -> "application/json"
      ".bin" -> "application/octet-stream"
      ".png" -> "image/png"
      _ -> "application/octet-stream"
    end
  end
end
