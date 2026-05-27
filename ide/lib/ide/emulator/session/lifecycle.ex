defmodule Ide.Emulator.Session.Lifecycle do
  @moduledoc false

  alias Ide.Emulator.Types

  @spec now_ms() :: integer()
  def now_ms, do: System.monotonic_time(:millisecond)

  @spec random_id() :: String.t()
  def random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  @spec random_token() :: String.t()
  def random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  @spec schedule_idle_check(Types.session_state()) :: reference()
  def schedule_idle_check(state),
    do: Process.send_after(self(), :idle_check, min(state.idle_timeout_ms, 60_000))

  @spec handle_idle_check(Types.session_state()) ::
          {:noreply, Types.session_state()}
          | {:stop, {:shutdown, :idle_timeout}, Types.session_state()}
  def handle_idle_check(state) do
    if now_ms() - state.last_ping_ms > state.idle_timeout_ms do
      {:stop, {:shutdown, :idle_timeout}, state}
    else
      schedule_idle_check(state)
      {:noreply, state}
    end
  end
end
