defmodule IdeWeb.EmulatorVncChannel.State do
  @moduledoc false

  @type t :: %{
          required(:session_id) => String.t(),
          required(:session_pid) => pid(),
          required(:tcp) => port()
        }

  @spec from_socket(Phoenix.Socket.t()) :: t()
  def from_socket(%Phoenix.Socket{assigns: assigns}) do
    %{
      session_id: Map.fetch!(assigns, :session_id),
      session_pid: Map.fetch!(assigns, :session_pid),
      tcp: Map.fetch!(assigns, :tcp)
    }
  end

  @spec assign(Phoenix.Socket.t(), t()) :: Phoenix.Socket.t()
  def assign(socket, %{} = state) do
    socket
    |> Phoenix.Socket.assign(:session_id, state.session_id)
    |> Phoenix.Socket.assign(:session_pid, state.session_pid)
    |> Phoenix.Socket.assign(:tcp, state.tcp)
  end
end
