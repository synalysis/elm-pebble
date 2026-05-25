defmodule Ide.WasmEmulator.FirmwareSync do
  @moduledoc false

  require Logger

  alias Ide.WasmEmulator

  @sdk_platforms ~w(aplite basalt chalk diorite emery flint gabbro)

  @spec sync_sdk_firmware_if_needed() :: :ok
  def sync_sdk_firmware_if_needed do
    if WasmEmulator.sdk_firmware_available?() do
      :ok
    else
      sync_sdk_firmware()
    end
  end

  @doc """
  Copies QEMU firmware images from the active Pebble SDK into the WASM emulator root.
  """
  @spec sync_sdk_firmware() :: :ok
  def sync_sdk_firmware do
    sdk_root = sdk_pebble_root()

    if is_binary(sdk_root) and File.dir?(sdk_root) do
      copied =
        sdk_root
        |> list_platform_qemu_dirs()
        |> Enum.count(&copy_platform_firmware/1)

      if copied > 0 do
        Logger.info("[WasmEmulator] synced SDK firmware for #{copied} platform(s) into #{WasmEmulator.asset_root()}")
      else
        Logger.warning("[WasmEmulator] no SDK firmware found under #{sdk_root}")
      end
    else
      Logger.warning("[WasmEmulator] SDK firmware sync skipped; Pebble SDK pebble root not found")
    end

    :ok
  end

  @spec list_platform_qemu_dirs(String.t()) :: [{String.t(), String.t()}]
  defp list_platform_qemu_dirs(sdk_root) do
    sdk_root
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(fn platform_dir ->
      platform = Path.basename(platform_dir)
      qemu_dir = Path.join(platform_dir, "qemu")

      if platform in @sdk_platforms and File.dir?(qemu_dir) do
        [{platform, qemu_dir}]
      else
        []
      end
    end)
  end

  @spec copy_platform_firmware({String.t(), String.t()}) :: boolean()
  defp copy_platform_firmware({platform, qemu_dir}) do
    micro_src = Path.join(qemu_dir, "qemu_micro_flash.bin")

    if File.regular?(micro_src) do
      dest_dir = Path.join([WasmEmulator.asset_root(), "firmware", "sdk", platform])
      File.mkdir_p!(dest_dir)

      micro_dest = Path.join(dest_dir, "qemu_micro_flash.bin")
      spi_dest = Path.join(dest_dir, "qemu_spi_flash.bin")

      with :ok <- copy_micro_flash(micro_src, micro_dest),
           :ok <- copy_spi_flash(qemu_dir, spi_dest),
           :ok <- write_manifest(platform, dest_dir, spi_dest) do
        maybe_copy_legacy_firmware(platform, dest_dir, micro_dest, spi_dest)
        true
      else
        _ -> false
      end
    else
      false
    end
  end

  @spec maybe_copy_legacy_firmware(String.t(), String.t(), String.t(), String.t()) :: :ok
  defp maybe_copy_legacy_firmware(_platform, dest_dir, micro_dest, spi_dest) do
    legacy_dir = Path.join([WasmEmulator.asset_root(), "firmware", "sdk"])
    File.mkdir_p!(legacy_dir)

    legacy_micro = Path.join(legacy_dir, "qemu_micro_flash.bin")
    legacy_spi = Path.join(legacy_dir, "qemu_spi_flash.bin")
    legacy_manifest = Path.join(legacy_dir, "manifest.json")

    if not File.regular?(legacy_micro) do
      File.cp!(micro_dest, legacy_micro)
      File.cp!(spi_dest, legacy_spi)
      File.cp!(Path.join(dest_dir, "manifest.json"), legacy_manifest)
    end

    :ok
  end

  @type firmware_error ::
          :objcopy_unavailable
          | :spi_flash_missing
          | {:objcopy_failed, String.t()}
          | {:bunzip2_failed, String.t()}
          | File.posix()

  @spec copy_micro_flash(String.t(), String.t()) :: :ok | {:error, firmware_error()}
  defp copy_micro_flash(src, dest) do
    cond do
      raw_micro_flash?(src) ->
        File.cp!(src, dest)
        :ok

      true ->
        case arm_objcopy_bin() do
          nil ->
            {:error, :objcopy_unavailable}

          objcopy ->
            case System.cmd(objcopy, ["-O", "binary", src, dest], stderr_to_stdout: true) do
              {_output, 0} -> :ok
              {output, _} -> {:error, {:objcopy_failed, output}}
            end
        end
    end
  end

  @spec copy_spi_flash(String.t(), String.t()) :: :ok | {:error, firmware_error()}
  defp copy_spi_flash(qemu_dir, dest) do
    plain = Path.join(qemu_dir, "qemu_spi_flash.bin")
    compressed = Path.join(qemu_dir, "qemu_spi_flash.bin.bz2")

    cond do
      File.regular?(plain) ->
        File.cp!(plain, dest)
        :ok

      File.regular?(compressed) ->
        case System.cmd("bunzip2", ["-ck", compressed], stderr_to_stdout: true) do
          {output, 0} -> File.write!(dest, output); :ok
          {output, _} -> {:error, {:bunzip2_failed, output}}
        end

      true ->
        {:error, :spi_flash_missing}
    end
  end

  @spec write_manifest(String.t(), String.t(), String.t()) :: :ok | {:error, firmware_error()}
  defp write_manifest(platform, dest_dir, spi_dest) do
    spi_size =
      case File.stat(spi_dest) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    payload = %{
      "platform" => platform,
      "machine" => machine_for_platform(platform),
      "cpu" => cpu_for_platform(platform),
      "storage" => storage_for_platform(platform),
      "spi_flash_size" => spi_size
    }

    path = Path.join(dest_dir, "manifest.json")

    case Jason.encode(payload) do
      {:ok, json} -> File.write!(path, json <> "\n"); :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec raw_micro_flash?(String.t()) :: boolean()
  defp raw_micro_flash?(path) do
    case File.read(path) do
      {:ok, <<0x7F, 0x45, 0x4C, 0x46, _rest::binary>>} -> false
      {:ok, _} -> true
      _ -> false
    end
  end

  @spec arm_objcopy_bin() :: String.t() | nil
  defp arm_objcopy_bin do
    sdk_root = sdk_toolchain_root()

    [
      sdk_root && Path.join(sdk_root, "arm-none-eabi/bin/arm-none-eabi-objcopy"),
      System.find_executable("arm-none-eabi-objcopy"),
      System.find_executable("llvm-objcopy")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.find_value(fn candidate ->
      if File.regular?(candidate), do: candidate
    end)
  end

  @spec sdk_pebble_root() :: String.t() | nil
  defp sdk_pebble_root do
    env_root = System.get_env("ELM_PEBBLE_QEMU_IMAGE_ROOT")

    cond do
      is_binary(env_root) and env_root != "" and File.dir?(env_root) ->
        env_root

      true ->
        default_sdk_pebble_root()
    end
  end

  @spec default_sdk_pebble_root() :: String.t() | nil
  defp default_sdk_pebble_root do
    data_root = System.get_env("IDE_DATA_ROOT") || "/var/lib/ide"

    Path.join([
      data_root,
      ".pebble-sdk/SDKs/current/sdk-core/pebble"
    ])
    |> then(fn path -> if File.dir?(path), do: path end)
  end

  @spec sdk_toolchain_root() :: String.t() | nil
  defp sdk_toolchain_root do
    data_root = System.get_env("IDE_DATA_ROOT") || "/var/lib/ide"
    path = Path.join(data_root, ".pebble-sdk/SDKs/current/toolchain")

    if File.dir?(path), do: path
  end

  @spec machine_for_platform(String.t()) :: String.t()
  defp machine_for_platform("aplite"), do: "pebble-bb2"
  defp machine_for_platform("emery"), do: "pebble-snowy-emery-sdk-bb"
  defp machine_for_platform("basalt"), do: "pebble-snowy-bb"
  defp machine_for_platform("chalk"), do: "pebble-s4-bb"
  defp machine_for_platform(platform) when platform in ["diorite", "flint"], do: "pebble-silk-bb"
  defp machine_for_platform("gabbro"), do: "pebble-snowy-emery-bb"
  defp machine_for_platform(_), do: "pebble-snowy-bb"

  @spec cpu_for_platform(String.t()) :: String.t()
  defp cpu_for_platform("aplite"), do: "cortex-m3"
  defp cpu_for_platform(_), do: "cortex-m4"

  @spec storage_for_platform(String.t()) :: String.t()
  defp storage_for_platform(platform) when platform in ["aplite", "diorite", "flint"], do: "mtdblock"
  defp storage_for_platform(_), do: "pflash"
end
