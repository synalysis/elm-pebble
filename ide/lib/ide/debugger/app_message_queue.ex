defmodule Ide.Debugger.AppMessageQueue do
  @moduledoc """
  Per-surface inbound protocol (AppMessage) queues for the debugger.

  On device, AppMessage packets are held until the Elm runtime is ready. The
  debugger mirrors that: inbound AppMessages are queued until the recipient surface
  has finished `init` (not merely parsed introspect).
  """

  alias Ide.Debugger.Types

  @queue_targets [:watch, :companion, :phone]

  @type queue_entry :: Types.protocol_tx_rx_payload() | map()
  @type queues :: %{optional(:watch) => [queue_entry()], optional(:companion) => [queue_entry()], optional(:phone) => [queue_entry()]}

  @spec empty() :: queues()
  def empty do
    %{watch: [], companion: [], phone: []}
  end

  @spec ensure(Types.runtime_state()) :: {Types.runtime_state(), queues()}
  def ensure(state) when is_map(state) do
    queues =
      state
      |> Map.get(:app_message_queues, empty())
      |> normalize()

    {Map.put(state, :app_message_queues, queues), queues}
  end

  @spec enqueue(Types.runtime_state(), Types.surface_target(), queue_entry()) :: Types.runtime_state()
  def enqueue(state, target, payload)
      when is_map(state) and target in @queue_targets and is_map(payload) do
    {state, queues} = ensure(state)

    Map.put(state, :app_message_queues, Map.update!(queues, target, &(&1 ++ [payload])))
  end

  @spec pending?(Types.runtime_state(), Types.surface_target()) :: boolean()
  def pending?(state, target) when is_map(state) and target in @queue_targets do
    state
    |> Map.get(:app_message_queues, empty())
    |> normalize()
    |> Map.get(target, [])
    |> case do
      [_ | _] -> true
      _ -> false
    end
  end

  @spec drain_entries(Types.runtime_state(), Types.surface_target()) ::
          {Types.runtime_state(), [queue_entry()]}
  def drain_entries(state, target) when is_map(state) and target in @queue_targets do
    {state, queues} = ensure(state)
    {entries, rest} = {Map.get(queues, target, []), Map.put(queues, target, [])}
    {Map.put(state, :app_message_queues, rest), entries}
  end

  @spec normalize(Types.wire_map()) :: queues()
  defp normalize(queues) when is_map(queues) do
    Enum.reduce(@queue_targets, empty(), fn target, acc ->
      entries =
        case Map.get(queues, target) || Map.get(queues, to_string(target)) do
          list when is_list(list) -> Enum.filter(list, &is_map/1)
          _ -> []
        end

      Map.put(acc, target, entries)
    end)
  end
end
