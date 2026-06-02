defmodule IdeWeb.EmulatorVncChannel do
  @moduledoc """
  Relays RFB between the browser (noVNC) and QEMU over a Phoenix channel.

  Production embedded emulator display uses this channel only; see
  `ide/docs/embedded-emulator.md` (VNC policy). `/api/emulator/:id/ws/vnc` remains for
  tools, tests, and local proxy — do not point the browser host at raw VNC without re-validation.
  """

  use IdeWeb, :channel

  require Logger

  alias Ide.Emulator
  alias Ide.Emulator.{Session, VncReady}
  alias IdeWeb.EmulatorVncChannel.State, as: ChannelState

  @vnc_connect_timeout 250
  @read_banner_ms 1_000

  @type channel_state :: ChannelState.t()
  @type join_reply :: %{required(:initial) => String.t()}

  @type join_error :: %{required(:reason) => String.t()}

  @impl true
  @spec join(String.t(), map(), Phoenix.Socket.t()) ::
          {:ok, join_reply(), Phoenix.Socket.t()}
          | {:error, join_error()}
          | {:ok, Phoenix.Socket.t()}
  def join("emulator_vnc:" <> session_id, _payload, socket) do
    Logger.info("emulator vnc channel join session_id=#{session_id}")

    with {:ok, pid} <- Emulator.lookup(session_id),
         {:ok, banner} <- Session.vnc_rfb_banner(pid),
         port when is_integer(port) and port > 0 <- Session.local_port(pid, :vnc),
         :ok <- Session.discard_vnc_tcp(pid),
         {:ok, tcp} <- connect_vnc(port),
         {:ok, initial} <- read_initial(tcp, banner) do
      :inet.setopts(tcp, active: true, nodelay: true, packet: :raw)

      Logger.debug(
        "emulator vnc channel join opened fresh tcp (#{byte_size(initial)} initial byte(s))"
      )

      channel =
        %{
          session_id: session_id,
          session_pid: pid,
          tcp: tcp
        }

      {:ok, %{initial: Base.encode64(initial)}, ChannelState.assign(socket, channel)}
    else
      {:error, reason} ->
        Logger.warning(
          "emulator vnc channel join failed session_id=#{session_id}: #{inspect(reason)}"
        )

        {:error, %{reason: "emulator_vnc_unavailable"}}

      other ->
        Logger.warning(
          "emulator vnc channel join failed session_id=#{session_id}: #{inspect(other)}"
        )

        {:error, %{reason: "emulator_vnc_unavailable"}}
    end
  end

  @impl true
  @spec handle_in(String.t(), map() | {:binary, binary()}, Phoenix.Socket.t()) ::
          {:reply, {:ok, map()}, Phoenix.Socket.t()}
          | {:stop, term(), Phoenix.Socket.t()}
          | {:noreply, Phoenix.Socket.t()}
  def handle_in("frame", %{"b64" => encoded}, socket) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, data} -> handle_in("frame", {:binary, data}, socket)
      :error -> {:stop, :invalid_frame, socket}
    end
  end

  def handle_in("frame", {:binary, data}, socket) when is_binary(data) do
    %{tcp: tcp} = ChannelState.from_socket(socket)

    Logger.debug("emulator vnc channel recv #{byte_size(data)} byte(s) from client")

    case :gen_tcp.send(tcp, data) do
      :ok -> {:reply, {:ok, %{}}, socket}
      {:error, reason} -> {:stop, {:tcp_send_failed, reason}, socket}
    end
  end

  @impl true
  @spec handle_info(term(), Phoenix.Socket.t()) ::
          {:noreply, Phoenix.Socket.t()} | {:stop, term(), Phoenix.Socket.t()}
  def handle_info({:tcp, tcp, data}, socket) when is_binary(data) do
    %{tcp: expected} = ChannelState.from_socket(socket)
    true = tcp == expected
    Logger.debug("emulator vnc channel push #{byte_size(data)} byte(s) to client")
    push_frame(socket, data)
    {:noreply, socket}
  end

  def handle_info({:tcp_closed, tcp}, socket) do
    %{tcp: expected} = ChannelState.from_socket(socket)
    true = tcp == expected
    {:stop, :normal, socket}
  end

  def handle_info({:tcp_error, tcp, reason}, socket) do
    %{tcp: expected} = ChannelState.from_socket(socket)
    true = tcp == expected
    Logger.warning("emulator vnc channel tcp error: #{inspect(reason)}")
    {:stop, {:tcp_error, reason}, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns[:tcp] do
      tcp when is_port(tcp) -> :gen_tcp.close(tcp)
      _ -> :ok
    end

    :ok
  end

  defp push_frame(socket, data) when is_binary(data) do
    push(socket, "frame", %{b64: Base.encode64(data)})
  end

  defp connect_vnc(port) do
    case :gen_tcp.connect(
           ~c"127.0.0.1",
           port,
           [:binary, active: false, nodelay: true, packet: :raw],
           @vnc_connect_timeout
         ) do
      {:ok, tcp} -> {:ok, tcp}
      {:error, reason} -> {:error, {:vnc_connect_failed, reason}}
    end
  end

  defp read_initial(tcp, fallback_banner) do
    deadline = System.monotonic_time(:millisecond) + @read_banner_ms

    case read_until_banner_complete(tcp, deadline, <<>>) do
      {:ok, initial} when byte_size(initial) > 0 -> {:ok, initial}
      _ -> {:ok, fallback_banner}
    end
  end

  defp read_until_banner_complete(tcp, deadline, acc) do
    cond do
      VncReady.version_line_complete?(acc) ->
        {:ok, acc}

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :banner_timeout}

      true ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        case :gen_tcp.recv(tcp, 0, min(remaining, 50)) do
          {:ok, data} -> read_until_banner_complete(tcp, deadline, acc <> data)
          {:error, :timeout} -> read_until_banner_complete(tcp, deadline, acc)
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
