defmodule Ide.Handheld.FlipperSdk do
  @moduledoc """
  Keeps the uFBT SDK on the same API as the connected Flipper Zero.

  A FAP built with a newer API is rejected at launch with `ApiTooNew`.
  """

  @type firmware :: %{version: String.t(), api: String.t()}

  @spec ensure(keyword()) :: {:ok, String.t()} | {:skip, nil} | {:error, String.t()}
  def ensure(opts \\ []) do
    firmware_fun = Keyword.get(opts, :firmware, &read_firmware/0)
    sdk_fun = Keyword.get(opts, :sdk_api, &read_sdk_api/0)
    updater = Keyword.get(opts, :updater, &update_sdk/1)

    with {:ok, firmware} <- firmware_fun.(),
         {:ok, sdk_api} <- sdk_fun.() do
      if sdk_api == firmware.api do
        {:ok, match_message(firmware)}
      else
        switch_sdk(firmware, sdk_api, updater, sdk_fun)
      end
    else
      :skip -> {:skip, nil}
      {:error, message} when is_binary(message) -> {:error, message}
    end
  end

  defp switch_sdk(firmware, sdk_api, updater, sdk_fun) do
    case updater.(firmware.version) do
      :ok ->
        case sdk_fun.() do
          {:ok, ^sdk_api} ->
            {:error, still_on_old_sdk(firmware, sdk_api)}

          {:ok, api} when api == firmware.api ->
            {:ok, switched_message(firmware, sdk_api)}

          {:ok, api} ->
            {:error,
             "The #{firmware.version} SDK speaks API #{api}. The Flipper speaks API #{firmware.api}."}

          :skip ->
            {:error, still_on_old_sdk(firmware, sdk_api)}
        end

      {:error, output} ->
        {:error, "Switching the SDK to Flipper firmware #{firmware.version} failed.\n#{output}"}
    end
  end

  defp match_message(firmware) do
    "The connected Flipper is firmware #{firmware.version} (API #{firmware.api}). The SDK matches that API."
  end

  defp switched_message(firmware, previous) do
    "The connected Flipper is firmware #{firmware.version} (API #{firmware.api}). The installed SDK was API #{previous}, so it was switched to the #{firmware.version} SDK."
  end

  defp still_on_old_sdk(firmware, sdk_api) do
    "The Flipper is firmware #{firmware.version} (API #{firmware.api}). The SDK is still API #{sdk_api}."
  end

  defp read_firmware do
    with python when is_binary(python) <- ufbt_python(),
         scripts when is_binary(scripts) <- scripts_dir(),
         {output, 0} <-
           System.cmd(python, ["-c", firmware_script(), scripts], stderr_to_stdout: true) do
      parse_firmware(output)
    else
      nil -> :skip
      {output, 2} -> if String.contains?(output, "no-flipper"), do: :skip, else: :skip
      {_output, _status} -> :skip
    end
  end

  defp parse_firmware(output) do
    values =
      output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> [{String.trim(key), String.trim(value)}]
          _ -> []
        end
      end)
      |> Map.new()

    version = values["firmware_version"]
    major = values["firmware_api_major"]
    minor = values["firmware_api_minor"]

    if is_binary(version) and version != "" and is_binary(major) and is_binary(minor) do
      {:ok, %{version: version, api: major <> "." <> minor}}
    else
      :skip
    end
  end

  defp firmware_script do
    """
    import logging, sys
    sys.path.insert(0, sys.argv[1])
    logging.basicConfig(level=logging.ERROR)
    from flipper.utils.cdc import resolve_port
    from flipper.storage import FlipperStorage
    port = resolve_port(logging.getLogger("flipper"), "auto")
    if not port:
        print("no-flipper")
        sys.exit(2)
    with FlipperStorage(port) as storage:
        storage.send("device_info\\r")
        data = storage.read.until(FlipperStorage.CLI_PROMPT)
    text = data.decode("utf-8", "replace")
    wanted = {"firmware_version", "firmware_api_major", "firmware_api_minor"}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key in wanted:
            print(f"{key}={value.strip()}")
    """
  end

  defp read_sdk_api do
    path = sdk_api_csv()

    if is_binary(path) and File.regular?(path) do
      api =
        path
        |> File.stream!()
        |> Enum.find_value(fn line ->
          case String.split(line, ",") do
            ["Version", "+", api | _] -> String.trim(api)
            _ -> nil
          end
        end)

      if is_binary(api) and api != "", do: {:ok, api}, else: :skip
    else
      :skip
    end
  end

  defp update_sdk(version) when is_binary(version) do
    case System.find_executable("ufbt") do
      nil ->
        {:error, "ufbt is not on PATH."}

      ufbt ->
        case System.cmd(ufbt, ["update", "--branch", version, "-t", "f7"],
               stderr_to_stdout: true,
               env: [{"NO_COLOR", "1"}, {"TERM", "dumb"}]
             ) do
          {_output, 0} -> :ok
          {output, status} -> {:error, "ufbt update exited #{status}.\n#{output}"}
        end
    end
  end

  defp ufbt_home do
    System.get_env("UFBT_HOME") || Path.join(System.user_home!(), ".ufbt")
  end

  defp ufbt_python do
    path = Path.join(ufbt_home(), "toolchain/x86_64-linux/bin/python3")
    if File.regular?(path), do: path, else: System.find_executable("python3")
  end

  defp scripts_dir do
    path = Path.join(ufbt_home(), "current/scripts")
    if File.dir?(path), do: path, else: nil
  end

  defp sdk_api_csv do
    Path.join(ufbt_home(), "current/sdk_headers/f7_sdk/targets/f7/api_symbols.csv")
  end
end
