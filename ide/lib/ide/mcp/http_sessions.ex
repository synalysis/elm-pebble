defmodule Ide.Mcp.HttpSessions do
  @moduledoc false

  use GenServer

  alias Ide.Mcp.WireTypes

  @type session_id :: String.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec create_session() :: session_id()
  def create_session, do: GenServer.call(__MODULE__, :create_session)

  @spec register_listener(session_id(), pid()) :: :ok
  def register_listener(session_id, pid) when is_binary(session_id) and is_pid(pid) do
    GenServer.call(__MODULE__, {:register_listener, session_id, pid})
  end

  @spec unregister_listener(session_id(), pid()) :: :ok
  def unregister_listener(session_id, pid) when is_binary(session_id) and is_pid(pid) do
    GenServer.cast(__MODULE__, {:unregister_listener, session_id, pid})
  end

  @spec deliver(session_id(), WireTypes.sse_message()) :: :ok
  def deliver(session_id, payload) when is_binary(session_id) and is_map(payload) do
    GenServer.cast(__MODULE__, {:deliver, session_id, payload})
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{listeners: %{}}}

  @impl GenServer
  def handle_call(:create_session, _from, state) do
    {:reply, new_session_id(), state}
  end

  def handle_call({:register_listener, session_id, pid}, _from, state) do
    ref = Process.monitor(pid)

    listeners =
      Map.update(state.listeners, session_id, %{pid => ref}, fn session_listeners ->
        Map.put(session_listeners, pid, ref)
      end)

    {:reply, :ok, %{state | listeners: listeners}}
  end

  @impl GenServer
  def handle_cast({:unregister_listener, session_id, pid}, state) do
    {:noreply, drop_listener(state, session_id, pid)}
  end

  def handle_cast({:deliver, session_id, payload}, state) do
    state.listeners
    |> Map.get(session_id, %{})
    |> Map.keys()
    |> Enum.each(fn pid ->
      send(pid, {:mcp_sse_message, payload})
    end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    listeners =
      Enum.reduce(state.listeners, state.listeners, fn {session_id, session_listeners}, acc ->
        if Map.has_key?(session_listeners, pid) do
          Map.put(acc, session_id, Map.delete(session_listeners, pid))
        else
          acc
        end
      end)

    {:noreply, %{state | listeners: listeners}}
  end

  defp drop_listener(state, session_id, pid) do
    listeners =
      Map.update(state.listeners, session_id, %{}, fn session_listeners ->
        case Map.pop(session_listeners, pid) do
          {ref, rest} when is_reference(ref) ->
            Process.demonitor(ref, [:flush])
            rest

          {_, rest} ->
            rest
        end
      end)
      |> Enum.reject(fn {_session_id, session_listeners} -> session_listeners == %{} end)
      |> Map.new()

    %{state | listeners: listeners}
  end

  defp new_session_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
