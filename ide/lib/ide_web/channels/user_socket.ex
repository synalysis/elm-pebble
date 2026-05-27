defmodule IdeWeb.UserSocket do
  use Phoenix.Socket

  require Logger

  channel "lsp:*", IdeWeb.LspChannel
  channel "emulator_vnc:*", IdeWeb.EmulatorVncChannel

  @impl true
  def connect(params, socket, connect_info) do
    Logger.info(
      "user socket connect transport=#{inspect(Map.get(connect_info, :transport))} params_keys=#{inspect(Map.keys(params || %{}))}"
    )

    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
