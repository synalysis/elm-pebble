defmodule Ide.Emulator.PBWInstaller.AppFetch do
  @moduledoc false

  require Logger

  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Emulator.PebbleProtocol.Router
  alias Ide.Emulator.Types

  @type fetch_result :: %{required(:uuid) => String.t(), required(:app_id) => non_neg_integer()}

  @spec request_app_fetch(pid(), String.t(), timeout()) ::
          {:ok, fetch_result()} | {:error, Types.install_error()}
  def request_app_fetch(router, uuid, timeout) do
    {endpoint, payload} = Packets.app_run_state_start(uuid)
    Logger.debug("native pbw install request app_fetch uuid=#{uuid}")

    with {:ok, frame} <-
           Router.send_and_await(
             router,
             endpoint,
             payload,
             &(&1.endpoint == Packets.endpoint(:app_fetch)),
             timeout
           ) do
      Packets.decode_app_fetch_request(frame.payload)
    end
  end

  @spec verify_fetch_uuid(String.t(), String.t()) :: :ok | {:error, Types.install_error()}
  def verify_fetch_uuid(uuid, uuid), do: :ok

  def verify_fetch_uuid(actual, expected),
    do: {:error, {:wrong_app_fetch_uuid, expected, actual}}
end
