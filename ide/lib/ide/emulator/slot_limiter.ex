defmodule Ide.Emulator.SlotLimiter do
  @moduledoc """
  Limits how many embedded and external emulator processes may run at once.

  Callers acquire a slot before starting QEMU (embedded session or SDK external
  emulator) and release it when the emulator stops. When all slots are in use,
  additional acquire requests wait in a FIFO queue until a slot is released or
  the caller's timeout expires.
  """

  use GenServer

  @name __MODULE__

  @type kind :: :embedded | :external
  @type slot_meta :: %{
          kind: kind(),
          platform: String.t() | nil,
          acquired_at: integer()
        }

  @type status :: %{
          max_slots: pos_integer(),
          used_slots: non_neg_integer(),
          available_slots: non_neg_integer(),
          queued: non_neg_integer(),
          slots: [%{owner: String.t(), kind: kind(), platform: String.t() | nil}]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec external_owner(String.t()) :: String.t()
  def external_owner(platform) when is_binary(platform), do: "external:#{platform}"

  @spec acquire(String.t(), keyword()) :: {:ok, String.t()} | {:error, :timeout}
  def acquire(owner_id, opts \\ []) when is_binary(owner_id) do
    timeout = Keyword.get(opts, :timeout, config(:acquire_timeout_ms, 600_000))
    ref = make_ref()

    :ok = GenServer.cast(@name, {:request, self(), ref, owner_id, slot_meta(opts)})

    receive do
      {:emulator_slot_granted, ^ref} -> {:ok, owner_id}
    after
      timeout ->
        GenServer.cast(@name, {:cancel, ref})
        {:error, :timeout}
    end
  end

  @spec release(String.t()) :: :ok
  def release(owner_id) when is_binary(owner_id) do
    GenServer.cast(@name, {:release, owner_id})
    :ok
  end

  @spec release_external(String.t()) :: :ok
  def release_external(platform) when is_binary(platform) do
    release(external_owner(platform))
  end

  @spec release_all_external() :: :ok
  def release_all_external do
    GenServer.cast(@name, :release_all_external)
    :ok
  end

  @spec status() :: status()
  def status, do: GenServer.call(@name, :status)

  @impl true
  def init(_opts) do
    max_slots = config(:max_slots, 8) |> max(1)

    {:ok,
     %{
       max_slots: max_slots,
       slots: %{},
       queue: :queue.new()
     }}
  end

  @impl true
  def handle_cast({:request, pid, ref, owner_id, meta}, state) do
    cond do
      Map.has_key?(state.slots, owner_id) ->
        send(pid, {:emulator_slot_granted, ref})
        {:noreply, state}

      map_size(state.slots) < state.max_slots ->
        state = put_slot(state, owner_id, meta)
        send(pid, {:emulator_slot_granted, ref})
        {:noreply, grant_queued(state)}

      true ->
        waiter = %{pid: pid, ref: ref, owner_id: owner_id, meta: meta}
        {:noreply, %{state | queue: :queue.in(waiter, state.queue)}}
    end
  end

  def handle_cast({:cancel, ref}, state) do
    {:noreply, %{state | queue: drop_waiter(state.queue, ref)}}
  end

  def handle_cast({:release, owner_id}, state) do
    state =
      if Map.has_key?(state.slots, owner_id) do
        %{state | slots: Map.delete(state.slots, owner_id)}
      else
        state
      end

    {:noreply, grant_queued(state)}
  end

  def handle_cast(:release_all_external, state) do
    slots =
      state.slots
      |> Enum.reject(fn {_owner, %{kind: kind}} -> kind == :external end)
      |> Map.new()

    {:noreply, grant_queued(%{state | slots: slots})}
  end

  @impl true
  def handle_call(:status, _from, state) do
    slots =
      state.slots
      |> Enum.map(fn {owner, meta} ->
        %{owner: owner, kind: meta.kind, platform: meta.platform}
      end)
      |> Enum.sort_by(& &1.owner)

    used = map_size(state.slots)

    {:reply,
     %{
       max_slots: state.max_slots,
       used_slots: used,
       available_slots: max(state.max_slots - used, 0),
       queued: :queue.len(state.queue),
       slots: slots
     }, state}
  end

  defp grant_queued(state) do
    grant_queued_loop(state)
  end

  defp grant_queued_loop(state) do
    if map_size(state.slots) >= state.max_slots or :queue.is_empty(state.queue) do
      state
    else
      {{:value, waiter}, queue} = :queue.out(state.queue)
      state = %{state | queue: queue, slots: Map.put(state.slots, waiter.owner_id, waiter.meta)}
      send(waiter.pid, {:emulator_slot_granted, waiter.ref})
      grant_queued_loop(state)
    end
  end

  defp put_slot(state, owner_id, meta) do
    %{state | slots: Map.put(state.slots, owner_id, meta)}
  end

  defp drop_waiter(queue, ref) do
    queue
    |> :queue.to_list()
    |> Enum.reject(&(&1.ref == ref))
    |> :queue.from_list()
  end

  defp slot_meta(opts) do
    %{
      kind: Keyword.get(opts, :kind, :embedded),
      platform: Keyword.get(opts, :platform),
      acquired_at: System.monotonic_time(:millisecond)
    }
  end

  defp config(key, default) do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
