defmodule Ide.Emulator.PebbleProtocol.Router do
  @moduledoc false

  use GenServer

  require Logger

  alias Ide.Emulator.PebbleProtocol.{Frame, Trace}

  @qemu_header 0xFEED
  @qemu_footer 0xBEEF
  @qemu_protocol_spp 1

  @type frame :: Frame.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec send_and_await(pid(), non_neg_integer(), binary(), (frame() -> boolean()), timeout()) ::
          {:ok, frame()} | {:error, term()}
  def send_and_await(pid, endpoint, payload, matcher, timeout \\ 20_000)
      when is_pid(pid) and is_function(matcher, 1) do
    GenServer.call(pid, {:send_and_await, endpoint, payload, matcher, timeout}, timeout + 1_000)
  end

  @spec await_frame(pid(), (frame() -> boolean()), timeout()) :: {:ok, frame()} | {:error, term()}
  def await_frame(pid, matcher, timeout \\ 5_000) when is_pid(pid) and is_function(matcher, 1) do
    GenServer.call(pid, {:await_frame, matcher, timeout}, timeout + 1_000)
  end

  @spec send_packet(pid(), non_neg_integer(), binary()) :: :ok
  def send_packet(pid, endpoint, payload),
    do: GenServer.call(pid, {:send_packet, endpoint, payload})

  @spec acquire(pid(), timeout()) :: :ok | {:error, term()}
  def acquire(pid, timeout \\ 5_000), do: GenServer.call(pid, :acquire, timeout)

  @spec release(pid()) :: :ok
  def release(pid), do: GenServer.call(pid, :release)

  @impl true
  def init(opts) do
    qemu_port = Keyword.fetch!(opts, :qemu_port)
    proxy_port = Keyword.fetch!(opts, :proxy_port)

    with {:ok, qemu} <- connect_qemu(qemu_port),
         {:ok, listener} <- listen_proxy(proxy_port) do
      :inet.setopts(qemu, active: :once)
      send(self(), :accept_proxy)

      {:ok,
       %{
         qemu: qemu,
         listener: listener,
         pypkjs: nil,
         qemu_buffer: <<>>,
         pypkjs_buffer: <<>>,
         waiters: [],
         locked?: false,
         pypkjs_queue: :queue.new()
       }}
    end
  end

  @impl true
  def handle_call({:send_and_await, endpoint, payload, matcher, timeout}, from, state) do
    trace_outbound(endpoint, payload)
    :ok = :gen_tcp.send(state.qemu, qemu_spp_packet(Frame.encode(endpoint, payload)))
    timer = Process.send_after(self(), {:waiter_timeout, from}, timeout)
    waiter = %{from: from, matcher: matcher, timer: timer, observed: []}
    {:noreply, %{state | waiters: [waiter | state.waiters]}}
  end

  def handle_call({:await_frame, matcher, timeout}, from, state) do
    timer = Process.send_after(self(), {:waiter_timeout, from}, timeout)
    waiter = %{from: from, matcher: matcher, timer: timer, observed: []}
    {:noreply, %{state | waiters: [waiter | state.waiters]}}
  end

  def handle_call({:send_packet, endpoint, payload}, _from, state) do
    trace_outbound(endpoint, payload)
    :ok = :gen_tcp.send(state.qemu, qemu_spp_packet(Frame.encode(endpoint, payload)))
    {:reply, :ok, state}
  end

  def handle_call(:acquire, _from, %{locked?: false} = state) do
    {:reply, :ok, %{state | locked?: true}}
  end

  def handle_call(:acquire, _from, state), do: {:reply, {:error, :busy}, state}

  def handle_call(:release, _from, state) do
    state = %{state | locked?: false} |> flush_pypkjs_queue()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:accept_proxy, state) do
    case :gen_tcp.accept(state.listener, 0) do
      {:ok, socket} ->
        if state.pypkjs, do: :gen_tcp.close(state.pypkjs)
        :inet.setopts(socket, active: :once)
        {:noreply, %{state | pypkjs: socket, pypkjs_buffer: <<>>}}

      {:error, :timeout} ->
        Process.send_after(self(), :accept_proxy, 100)
        {:noreply, state}

      {:error, reason} ->
        {:stop, {:proxy_accept_failed, reason}, state}
    end
  end

  def handle_info({:tcp, socket, data}, %{qemu: socket} = state) do
    {packets, buffer} = parse_qemu_packets(state.qemu_buffer <> data)
    state = Enum.reduce(packets, %{state | qemu_buffer: buffer}, &handle_qemu_packet/2)
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp, socket, data}, %{pypkjs: socket} = state) do
    state =
      if state.locked? do
        %{state | pypkjs_queue: :queue.in(data, state.pypkjs_queue)}
      else
        :ok = :gen_tcp.send(state.qemu, data)
        state
      end

    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, socket}, %{qemu: socket} = state),
    do: {:stop, :qemu_closed, state}

  def handle_info({:tcp_closed, socket}, %{pypkjs: socket} = state) do
    send(self(), :accept_proxy)
    {:noreply, %{state | pypkjs: nil, pypkjs_buffer: <<>>}}
  end

  def handle_info({:waiter_timeout, from}, state) do
    {timed_out, waiters} = Enum.split_with(state.waiters, &(&1.from == from))

    Enum.each(timed_out, fn waiter ->
      Process.cancel_timer(waiter.timer)
      GenServer.reply(waiter.from, {:error, timeout_reason(waiter)})
    end)

    {:noreply, %{state | waiters: waiters}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    close_socket(state[:qemu])
    close_socket(state[:pypkjs])
    close_socket(state[:listener])
    :ok
  end

  defp connect_qemu(port) do
    :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw], 10_000)
  end

  defp listen_proxy(port) do
    :gen_tcp.listen(port, [
      :binary,
      active: false,
      packet: :raw,
      reuseaddr: true,
      ip: {127, 0, 0, 1}
    ])
  end

  defp handle_qemu_packet(%{raw: raw, protocol: @qemu_protocol_spp, payload: payload}, state) do
    if state.pypkjs && !state.locked?, do: :gen_tcp.send(state.pypkjs, raw)

    {frames, frame_buffer} = Frame.parse_many(payload)

    state =
      Enum.reduce(frames, state, fn frame, acc ->
        handle_qemu_frame(frame, acc)
      end)

    if frame_buffer == <<>> do
      state
    else
      Logger.debug(
        "embedded emulator ignored partial SPP payload: #{byte_size(frame_buffer)} bytes"
      )

      state
    end
  end

  defp handle_qemu_packet(%{raw: raw}, state) do
    if state.pypkjs && !state.locked?, do: :gen_tcp.send(state.pypkjs, raw)
    state
  end

  defp handle_qemu_frame(frame, state) do
    trace_inbound(frame)

    {matched, waiters} = Enum.split_with(state.waiters, fn waiter -> waiter.matcher.(frame) end)
    waiters = Enum.map(waiters, &observe_waiter_frame(&1, frame))

    case matched do
      [] ->
        %{state | waiters: waiters}

      [waiter | extra] ->
        Process.cancel_timer(waiter.timer)
        GenServer.reply(waiter.from, {:ok, frame})

        Enum.each(extra, fn extra_waiter ->
          Process.cancel_timer(extra_waiter.timer)
          GenServer.reply(extra_waiter.from, {:error, :superseded})
        end)

        %{state | waiters: waiters}
    end
  end

  defp observe_waiter_frame(waiter, frame) do
    observed =
      [frame_summary(frame) | Map.get(waiter, :observed, [])]
      |> Enum.take(20)

    %{waiter | observed: observed}
  end

  defp timeout_reason(%{observed: []}), do: :timeout
  defp timeout_reason(%{observed: observed}), do: {:timeout, Enum.reverse(observed)}

  defp frame_summary(frame) do
    payload = Map.get(frame, :payload, <<>>)

    %{
      endpoint: Map.get(frame, :endpoint),
      payload_bytes: byte_size(payload),
      payload_prefix:
        payload
        |> binary_part(0, min(byte_size(payload), 48))
        |> Base.encode16(case: :lower)
    }
  end

  defp flush_pypkjs_queue(state) do
    case :queue.out(state.pypkjs_queue) do
      {{:value, data}, queue} ->
        :ok = :gen_tcp.send(state.qemu, data)
        flush_pypkjs_queue(%{state | pypkjs_queue: queue})

      {:empty, _queue} ->
        state
    end
  end

  defp close_socket(nil), do: :ok
  defp close_socket(socket), do: :gen_tcp.close(socket)

  defp qemu_spp_packet(payload), do: qemu_packet(@qemu_protocol_spp, payload)

  defp qemu_packet(protocol, payload) do
    <<@qemu_header::16, protocol::16, byte_size(payload)::16, payload::binary, @qemu_footer::16>>
  end

  defp trace_outbound(endpoint, payload) do
    if Trace.enabled?(), do: Trace.emit("host->watch", %{endpoint: endpoint, payload: payload})
  end

  defp trace_inbound(frame) do
    if Trace.enabled?(), do: Trace.emit("watch->host", frame)
  end

  defp parse_qemu_packets(buffer), do: parse_qemu_packets(buffer, [])

  defp parse_qemu_packets(
         <<@qemu_header::16, protocol::16, length::16, _rest::binary>> = buffer,
         packets
       ) do
    total = 8 + length

    cond do
      byte_size(buffer) < total ->
        {Enum.reverse(packets), buffer}

      true ->
        <<raw::binary-size(total), remaining::binary>> = buffer

        <<@qemu_header::16, ^protocol::16, ^length::16, payload::binary-size(length),
          @qemu_footer::16>> =
          raw

        packet = %{protocol: protocol, payload: payload, raw: raw}
        parse_qemu_packets(remaining, [packet | packets])
    end
  end

  defp parse_qemu_packets(buffer, packets), do: {Enum.reverse(packets), buffer}
end
