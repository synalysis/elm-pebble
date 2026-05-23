defmodule Ide.Emulator.StartupCheck do
  @moduledoc false

  require Logger

  alias Ide.Emulator

  @spec log() :: :ok
  def log do
    target = default_emulator_target()
    status = Emulator.runtime_status(target)

    Logger.info(
      "[embedded-emulator] startup check for #{status.platform}: #{summary(status)}"
    )

    for component <- status.components do
      Logger.info(
        "[embedded-emulator]   #{component.label}: #{component_status(component.status)} (#{component.detail})"
      )
    end

    :ok
  end

  @spec default_emulator_target() :: String.t()
  defp default_emulator_target do
    Application.get_env(:ide, Ide.Emulator.Session, [])
    |> Keyword.get(:emulator_target, "basalt")
    |> to_string()
  end

  @spec summary(map()) :: String.t()
  defp summary(%{status: :ok, platform: platform}),
    do: "all dependencies present for #{platform}"

  defp summary(%{status: :warning, platform: platform, missing: missing}) do
    labels = Enum.map_join(missing, ", ", & &1.label)
    "missing dependencies for #{platform}: #{labels}"
  end

  @spec component_status(atom()) :: String.t()
  defp component_status(:ok), do: "ok"
  defp component_status(:missing), do: "missing"
  defp component_status(status), do: to_string(status || "unknown")
end
