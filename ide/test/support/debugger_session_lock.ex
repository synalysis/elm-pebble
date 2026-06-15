defmodule Ide.TestSupport.DebuggerSessionLock do
  @moduledoc false

  use GenServer

  @name __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :queue.new(), Keyword.put_new(opts, :name, @name))
  end

  @spec setup(keyword()) :: :ok
  def setup(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 300_000)
    :ok = acquire(timeout)
    ExUnit.Callbacks.on_exit(fn -> release() end)
    :ok
  end

  @spec acquire(timeout()) :: :ok
  def acquire(timeout \\ 300_000) do
    GenServer.call(@name, {:acquire, self()}, timeout)
  end

  @spec release() :: :ok
  def release do
    GenServer.cast(@name, {:release, self()})
  end

  @impl true
  def init(queue), do: {:ok, %{owner: nil, queue: queue}}

  @impl true
  def handle_call({:acquire, pid}, _from, %{owner: nil} = state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | owner: pid}}
  end

  @impl true
  def handle_call({:acquire, pid}, _from, %{owner: pid} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:acquire, pid}, from, %{owner: owner, queue: queue}) when owner != pid do
    {:noreply, %{owner: owner, queue: :queue.in({pid, from}, queue)}}
  end

  @impl true
  def handle_cast({:release, pid}, %{owner: pid} = state) do
    {:noreply, handoff_or_clear(state)}
  end

  @impl true
  def handle_cast({:release, _pid}, state), do: {:noreply, state}

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{owner: pid} = state) do
    {:noreply, handoff_or_clear(state)}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp handoff_or_clear(%{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {next_pid, next_from}}, rest} ->
        Process.monitor(next_pid)
        GenServer.reply(next_from, :ok)
        %{state | owner: next_pid, queue: rest}

      {:empty, _} ->
        %{state | owner: nil}
    end
  end
end
