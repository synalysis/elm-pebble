defmodule Ide.Emulator.PBWInstaller.PostInstall do
  @moduledoc false

  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Emulator.PebbleProtocol.Router

  @type observed_frame :: %{
          required(:endpoint) => String.t(),
          required(:payload_bytes) => non_neg_integer(),
          required(:payload_prefix) => String.t(),
          optional(:data_logging_tag_hex) => String.t(),
          optional(:error) => String.t()
        }

  @spec probe_post_install_state(pid(), timeout()) :: :ok
  def probe_post_install_state(_router, timeout) when timeout <= 0, do: :ok

  def probe_post_install_state(router, timeout) do
    {endpoint, payload} = Packets.app_run_state_request()

    _ =
      Router.send_and_await(
        router,
        endpoint,
        payload,
        &(&1.endpoint == Packets.endpoint(:app_run_state)),
        timeout
      )

    observe_post_install_any_frames(router, timeout, 40, [])
  end

  @spec observe_post_install_frame(pid(), atom()) :: :ok
  def observe_post_install_frame(router, _kind) do
    matcher = fn frame ->
      frame.endpoint in [
        Packets.endpoint(:app_fetch),
        Packets.endpoint(:app_run_state),
        Packets.endpoint(:put_bytes)
      ]
    end

    _ = Router.await_frame(router, matcher, 250)
    :ok
  end

  defp observe_post_install_any_frames(_router, _timeout, 0, _frames), do: :ok

  defp observe_post_install_any_frames(router, timeout, remaining, frames) do
    case Router.await_frame(router, fn _frame -> true end, timeout) do
      {:ok, frame} ->
        observed =
          %{
            endpoint: frame.endpoint,
            payload_bytes: byte_size(frame.payload),
            payload_prefix:
              frame.payload
              |> binary_part(0, min(byte_size(frame.payload), 48))
              |> Base.encode16(case: :lower)
          }
          |> enrich_observed_frame(frame.payload)

        observe_post_install_any_frames(router, timeout, remaining - 1, [observed | frames])

      {:error, reason} ->
        observe_post_install_any_frames(router, timeout, 0, [%{error: inspect(reason)} | frames])
    end
  end

  @doc false
  @spec enrich_observed_frame(observed_frame(), binary()) :: observed_frame()
  def enrich_observed_frame(
        observed,
        <<1, _session, _uuid::binary-size(16), _timestamp::little-32, tag::little-32,
          _rest::binary>>
      ) do
    Map.put(
      observed,
      :data_logging_tag_hex,
      "0x" <> String.pad_leading(Integer.to_string(tag, 16), 8, "0")
    )
  end

  def enrich_observed_frame(observed, _payload), do: observed
end
